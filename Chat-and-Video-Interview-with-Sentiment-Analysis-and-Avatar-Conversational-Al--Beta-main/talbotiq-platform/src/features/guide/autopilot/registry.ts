import { useEffect } from 'react'
import { create } from 'zustand'
import type { ActionDescriptor, ParamSpec } from '@shared/autopilot'

export interface RegisteredAction {
  descriptor: ActionDescriptor
  run: (args: Record<string, unknown>) => void | Promise<void>
}
/** What a screen passes per action (name is the map key; screen prefixes it). */
export interface ActionDef {
  description: string
  sideEffect?: boolean
  params?: ParamSpec[]
  run: (args: Record<string, unknown>) => void | Promise<void>
}
interface ScreenReg { actions: Record<string, RegisteredAction>; getState: () => Record<string, unknown> }
interface RegistryState {
  byScreen: Record<string, ScreenReg>
  registerScreen: (screen: string, defs: Record<string, ActionDef>, getState?: () => Record<string, unknown>) => void
  unregisterScreen: (screen: string) => void
}

export const useAutopilotRegistry = create<RegistryState>((set) => ({
  byScreen: {},
  registerScreen: (screen, defs, getState) =>
    set((s) => {
      const actions: Record<string, RegisteredAction> = {}
      for (const [key, def] of Object.entries(defs)) {
        const name = `${screen}.${key}`
        actions[name] = {
          descriptor: { name, description: def.description, screen, sideEffect: def.sideEffect ?? false, params: def.params ?? [] },
          run: def.run,
        }
      }
      return { byScreen: { ...s.byScreen, [screen]: { actions, getState: getState ?? (() => ({})) } } }
    }),
  unregisterScreen: (screen) =>
    set((s) => {
      const next = { ...s.byScreen }
      delete next[screen]
      return { byScreen: next }
    }),
}))

/* ── Pure selectors (unit-tested) ── */
export function listDescriptors(state: RegistryState): ActionDescriptor[] {
  return Object.values(state.byScreen).flatMap((sc) => Object.values(sc.actions).map((a) => a.descriptor))
}
export function snapshotState(state: RegistryState): Record<string, unknown> {
  return Object.values(state.byScreen).reduce<Record<string, unknown>>((acc, sc) => ({ ...acc, ...sc.getState() }), {})
}
export function findAction(state: RegistryState, name: string): RegisteredAction | undefined {
  for (const sc of Object.values(state.byScreen)) if (sc.actions[name]) return sc.actions[name]
  return undefined
}

/** Screens call this while mounted to expose their real handlers to Autopilot. */
export function useAutopilotActions(
  screen: string,
  defs: Record<string, ActionDef>,
  opts?: { getState?: () => Record<string, unknown> },
): void {
  const register = useAutopilotRegistry((s) => s.registerScreen)
  const unregister = useAutopilotRegistry((s) => s.unregisterScreen)
  // Re-register whenever defs identity changes; callers should memoize defs/getState.
  useEffect(() => {
    register(screen, defs, opts?.getState)
    return () => unregister(screen)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [screen, defs, opts?.getState])
}

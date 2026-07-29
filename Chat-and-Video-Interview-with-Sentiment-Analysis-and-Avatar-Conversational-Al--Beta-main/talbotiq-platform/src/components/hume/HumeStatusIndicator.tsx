import { useAppStore } from '@/store/useAppStore'

export function HumeStatusIndicator() {
  const { humeStreamActive, humeKey } = useAppStore()

  if (!humeKey) {
    return (
      <span className="flex items-center gap-1.5 text-2xs font-mono text-hume-muted">
        <span className="w-1.5 h-1.5 rounded-full bg-hume-amber" />
        HUME KEY MISSING
      </span>
    )
  }

  if (!humeStreamActive) {
    return (
      <span className="flex items-center gap-1.5 text-2xs font-mono text-hume-amber">
        <span className="w-1.5 h-1.5 rounded-full bg-hume-amber animate-pulse" />
        HUME CONNECTING…
      </span>
    )
  }

  return (
    <span className="flex items-center gap-1.5 text-2xs font-mono text-hume-live">
      <span className="w-1.5 h-1.5 rounded-full bg-hume-live animate-pulse-live" />
      HUME LIVE
    </span>
  )
}

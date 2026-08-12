import { useCallback, useEffect, useState } from 'react'
import toast from 'react-hot-toast'
import { sessionsApi } from '@/lib/api'
import type { IntegrityConfig, IntegrityEvent } from '@shared/types'

/**
 * Client-side integrity monitoring. Detects tab/window switches and fullscreen
 * exits, posts them to the server, and surfaces calm, professional warnings.
 * Paste/copy blocking is enforced at the input; this exposes `post` so those
 * attempts can be logged too.
 */
export function useIntegrityMonitor(
  sessionId: string,
  integrity: IntegrityConfig | undefined,
  active: boolean,
) {
  const [warnings, setWarnings] = useState(0)

  const post = useCallback(
    (type: IntegrityEvent['type'], notify?: string) => {
      if (!integrity?.logEvents) return
      sessionsApi
        .integrityEvent(sessionId, { type })
        .then((r) => {
          if (typeof r.tabSwitchWarnings === 'number') setWarnings(r.tabSwitchWarnings)
          if (notify) {
            const max = r.maxTabSwitchWarnings
            toast(max ? `${notify} (${r.tabSwitchWarnings}/${max})` : notify, { icon: '⚠️' })
          }
        })
        .catch(() => {})
    },
    [sessionId, integrity?.logEvents],
  )

  // Tab / window switching
  useEffect(() => {
    if (!active || !integrity?.detectTabSwitch) return
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') post('tab_switch', 'Please stay on this tab — switching away is recorded')
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [active, integrity?.detectTabSwitch, post])

  // Fullscreen enforcement (best-effort; entered via user gesture in enterFullscreen)
  useEffect(() => {
    if (!active || !integrity?.enforceFullscreen) return
    const onFsChange = () => {
      if (!document.fullscreenElement) post('fullscreen_exit', 'Please return to fullscreen for the interview')
    }
    document.addEventListener('fullscreenchange', onFsChange)
    return () => document.removeEventListener('fullscreenchange', onFsChange)
  }, [active, integrity?.enforceFullscreen, post])

  const enterFullscreen = useCallback(() => {
    if (integrity?.enforceFullscreen) {
      document.documentElement.requestFullscreen?.().catch(() => {})
    }
  }, [integrity?.enforceFullscreen])

  return { warnings, post, enterFullscreen }
}

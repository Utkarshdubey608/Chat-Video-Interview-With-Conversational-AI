import { useEffect, useRef } from 'react'

import { useReplicas } from '@/hooks/useTavus'
import { getIdTokenOrNull } from '@/lib/firebase'
import { CACHE_VERSION, getSyncMeta, syncReplicaFaces } from './lib/replicaFaceCache'

const STALE_MS = 7 * 24 * 60 * 60 * 1000 // re-sync at most weekly

/**
 * Populates the intro's real-replica face cache — ONCE, in the background, from
 * an authenticated recruiter context (where the replica list is already loaded
 * by React Query, so no extra Tavus call is made). Extraction reads the
 * server's same-origin preview cache, not Tavus. Renders nothing.
 *
 * Mounted inside the recruiter shell. A manual re-sync can be triggered via the
 * `mimic:sync-faces` window event, `window.mimicSyncFaces()`, or `?introSync=1`.
 */
export function IntroFaceSync() {
  const { data: replicas } = useReplicas()
  const running = useRef(false)
  const replicasRef = useRef(replicas)
  replicasRef.current = replicas

  const run = useRef(async (force: boolean) => {
    if (running.current) return
    // Never decode preview MP4s while a live interview call could be on screen —
    // 4 parallel video decodes + canvas grabs would compete with the WebRTC call.
    if (window.location.pathname.startsWith('/interview') || window.location.pathname.startsWith('/take/')) return
    const list = replicasRef.current
    if (!list || list.length === 0) return
    if (!force) {
      const meta = await getSyncMeta()
      // Re-sync when stale, empty, or extracted by an older cache version
      // (e.g. before this higher-resolution capture).
      if (meta && meta.version === CACHE_VERSION && Date.now() - meta.syncedAt < STALE_MS && meta.count > 0) return
    }
    running.current = true
    try {
      const token = await getIdTokenOrNull().catch(() => null)
      await syncReplicaFaces(list, { token })
    } finally {
      running.current = false
    }
  }).current

  // Auto-sync once the replica list is known (deferred so it never competes
  // with first paint / interaction).
  useEffect(() => {
    if (!replicas || replicas.length === 0) return
    const force = new URLSearchParams(window.location.search).get('introSync') === '1'
    const id = window.setTimeout(() => void run(force), force ? 0 : 4000)
    return () => window.clearTimeout(id)
  }, [replicas, run])

  // Manual re-sync hooks.
  useEffect(() => {
    const onEvent = () => void run(true)
    window.addEventListener('mimic:sync-faces', onEvent)
    const w = window as Window & { mimicSyncFaces?: () => void }
    w.mimicSyncFaces = () => void run(true)
    return () => {
      window.removeEventListener('mimic:sync-faces', onEvent)
      if (w.mimicSyncFaces) delete w.mimicSyncFaces
    }
  }, [run])

  return null
}

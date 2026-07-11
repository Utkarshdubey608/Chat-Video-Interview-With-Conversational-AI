import { useCallback, useEffect, useRef, useState } from 'react'
import DailyIframe, { type DailyCall } from '@daily-co/daily-js'
import { tavus } from '@/services/tavus'
import { useAppStore } from '@/store/useAppStore'

type Status = 'idle' | 'connecting' | 'live' | 'ended' | 'error'

/**
 * Runs a Tavus conversation in ECHO mode (the avatar speaks only what we send —
 * no Tavus LLM), embeds the Daily room, and reports the candidate's speech via
 * `onTranscript`. Our conversation engine still decides the questions; this hook
 * just makes the avatar say them and returns what the candidate said.
 */
export function useTavusConversation(opts: {
  enabled: boolean
  container: HTMLElement | null
  defaultReplicaId?: string
  conversationalContext?: string
  onTranscript?: (text: string) => void
}) {
  const tavusKey = useAppStore((s) => s.tavusKey)
  const [status, setStatus] = useState<Status>('idle')
  const [error, setError] = useState<string | null>(null)

  const callRef = useRef<DailyCall | null>(null)
  const convIdRef = useRef<string | null>(null)
  const startedRef = useRef(false)
  const onTx = useRef(opts.onTranscript)
  onTx.current = opts.onTranscript

  useEffect(() => {
    if (!opts.enabled || !opts.container || startedRef.current) return
    if (!tavusKey) {
      setStatus('error')
      setError('No Tavus API key configured — add one in Settings to enable the video avatar.')
      return
    }
    startedRef.current = true
    setStatus('connecting')

    ;(async () => {
      try {
        tavus.setKey(tavusKey)
        let replicaId = opts.defaultReplicaId
        if (!replicaId) {
          const reps = await tavus.listReplicas()
          replicaId = reps.find((r) => r.status === 'ready')?.replica_id ?? reps[0]?.replica_id
        }
        if (!replicaId) throw new Error('No Tavus replica available on this account')

        const conv = await tavus.createConversation({
          replica_id: replicaId,
          conversation_name: 'TalbotIQ interview',
          conversational_context: opts.conversationalContext,
          properties: {
            pipeline_mode: 'echo',            // avatar speaks ONLY our echoed text
            enable_transcription: true,
            max_call_duration: 1800,
            participant_left_timeout: 60,
          },
        })
        convIdRef.current = conv.conversation_id

        const call = DailyIframe.createFrame(opts.container!, {
          showLeaveButton: false,
          showFullscreenButton: false,
          iframeStyle: { width: '100%', height: '100%', border: '0' },
        })
        callRef.current = call

        // Tavus emits the candidate's speech as app-messages; shapes vary, so match defensively.
        call.on('app-message', (ev) => {
          const d = (ev?.data ?? {}) as Record<string, unknown>
          const et = String(d.event_type ?? d.type ?? '')
          if (!/transcription|utterance/i.test(et)) return
          const p = (d.properties ?? d) as Record<string, unknown>
          const role = String(p.role ?? p.speaker ?? '')
          const text = (p.text ?? p.speech ?? p.transcript ?? p.utterance) as string | undefined
          if (text && (!role || /user|participant|candidate/i.test(role))) onTx.current?.(String(text))
        })

        await call.join({ url: conv.conversation_url })
        setStatus('live')
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not start the video avatar')
        setStatus('error')
      }
    })()

    return () => {
      const call = callRef.current
      if (call) { call.leave().catch(() => {}); call.destroy().catch(() => {}); callRef.current = null }
      if (convIdRef.current) { tavus.endConversation(convIdRef.current).catch(() => {}); convIdRef.current = null }
      startedRef.current = false
    }
  }, [opts.enabled, opts.container, tavusKey, opts.defaultReplicaId, opts.conversationalContext])

  /** Make the avatar speak the given text (Tavus echo interaction). */
  const speak = useCallback((text: string) => {
    const call = callRef.current
    const cid = convIdRef.current
    if (!call || !cid || !text.trim()) return
    call.sendAppMessage(
      { message_type: 'conversation', event_type: 'conversation.echo', conversation_id: cid, properties: { text } },
      '*',
    )
  }, [])

  const end = useCallback(() => {
    const call = callRef.current
    const cid = convIdRef.current
    if (call) { call.leave().catch(() => {}); call.destroy().catch(() => {}); callRef.current = null }
    if (cid) { tavus.endConversation(cid).catch(() => {}); convIdRef.current = null }
    setStatus('ended')
  }, [])

  return { status, error, speak, end }
}

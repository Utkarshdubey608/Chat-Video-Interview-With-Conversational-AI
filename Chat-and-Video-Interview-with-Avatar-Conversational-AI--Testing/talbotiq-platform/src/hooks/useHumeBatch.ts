import { useEffect, useRef } from 'react'
import toast from 'react-hot-toast'
import { humeService } from '@/services/hume'
import { audioStore as _audioStore } from '@/services/audioStore'
import { useAppStore } from '@/store/useAppStore'

const POLL_INTERVAL = 4000
const MAX_POLLS = 150 // ~10 min

// ── Called in InterviewPage on interview end — submits the batch job only ────
export function useHumeSubmit(trigger: boolean) {
  const store = useAppStore()

  useEffect(() => {
    const humeKey = store.humeKey || humeService.getKey()
    if (!trigger || !humeKey) return
    if (!_audioStore.hasData) return

    if (humeKey) humeService.setKey(humeKey)
    _audioStore.seal()
    const blob = _audioStore.blob
    if (!blob) return

    async function submit() {
      try {
        const jobId = await humeService.submitBatchJob(blob!)
        store.setHumeJobId(jobId)
        store.setHumeJobStatus('QUEUED')
      } catch (err) {
        console.error('[HumeSubmit] submit error:', err)
        store.setHumeJobStatus('FAILED')
      }
    }

    submit()
  }, [trigger]) // eslint-disable-line react-hooks/exhaustive-deps
}

// ── Called in ResultsPage — picks up a pending jobId and polls to completion ─
export function useHumePoll() {
  const store = useAppStore()
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const countRef = useRef(0)
  const activeJobRef = useRef<string | null>(null)

  useEffect(() => {
    const jobId = store.humeJobId
    const status = store.humeJobStatus

    // Nothing to poll
    if (!jobId) return
    const humeKey = store.humeKey || humeService.getKey()
    if (!humeKey) return
    if (humeKey) humeService.setKey(humeKey)
    if (status === 'COMPLETED' || status === 'FAILED') return
    // Already polling this job
    if (activeJobRef.current === jobId) return

    activeJobRef.current = jobId
    countRef.current = 0

    pollRef.current = setInterval(async () => {
      countRef.current += 1
      if (countRef.current > MAX_POLLS) {
        clearInterval(pollRef.current!)
        store.setHumeJobStatus('FAILED')
        return
      }
      try {
        const job = await humeService.pollBatchJob(jobId)
        console.log('[HumePoll] status:', job.status, 'job_id:', jobId)
        store.setHumeJobStatus(job.status)

        if (job.status === 'COMPLETED') {
          clearInterval(pollRef.current!)
          const preds = await humeService.fetchBatchPredictions(jobId)
          console.log('[HumePoll] predictions received:', preds?.length ?? 0, 'items')
          const questions = useAppStore.getState().questions.filter(Boolean)
          const timestamps = useAppStore.getState().questionTimestamps
          const result = humeService.buildSessionResult(jobId, preds, timestamps, questions)
          store.setHumeResult(result)
          toast.success('Emotion analysis complete', { duration: 3000 })
        } else if (job.status === 'FAILED') {
          clearInterval(pollRef.current!)
          toast.error('Hume emotion analysis failed — see console for details', { duration: 6000 })
        }
      } catch (err) {
        console.warn('[HumePoll] transient error — will retry:', err)
      }
    }, POLL_INTERVAL)

    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
      activeJobRef.current = null
    }
  }, [store.humeJobId, store.humeJobStatus]) // eslint-disable-line react-hooks/exhaustive-deps
}

// Legacy export kept so InterviewPage import doesn't break during transition
export { useHumeSubmit as useHumeBatch }

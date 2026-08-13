// src/hooks/useFacialCapture.ts
// React hook wrapping RekognitionService for InterviewPage. Requests VIDEO only —
// audio is already captured by useAudioAnalysis (the AudioWorklet pipeline).

import { useRef, useState, useCallback } from 'react'
import { RekognitionService } from '@/services/rekognitionService'
import { facialDataStore } from '@/services/facialDataStore'
import { useAppStore } from '@/store/useAppStore'
import type { FacialFrame } from '@/types/rekognition.types'

export interface FacialCaptureState {
  status: 'idle' | 'requesting_permission' | 'active' | 'error' | 'unavailable'
  frameCount: number
  lastFrameQuality: string
  permissionDenied: boolean
  startCapture: () => Promise<void>
  stopCapture: () => FacialFrame[]
  updateQuestion: (questionIdx: number) => void
  errorMessage: string | null
}

export function useFacialCapture(): FacialCaptureState {
  const awsProxyUrl = useAppStore(s => s.awsProxyUrl)
  const serviceRef = useRef<RekognitionService | null>(null)
  const videoStreamRef = useRef<MediaStream | null>(null)
  const uiIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const [status, setStatus] = useState<FacialCaptureState['status']>('idle')
  const [frameCount, setFrameCount] = useState(0)
  const [lastFrameQuality, setLastFrameQuality] = useState('')
  const [permissionDenied, setPermissionDenied] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  // Generation counter guards against React StrictMode's mount→cleanup→remount:
  // without it, two overlapping startCapture calls each open a camera stream and
  // the first one leaks (camera LED stays on, doubled Rekognition calls).
  const genRef = useRef(0)

  const startCapture = useCallback(async () => {
    if (serviceRef.current) return  // already running
    if (!awsProxyUrl) {
      setStatus('unavailable')
      setErrorMessage('AWS Rekognition is not configured on the server.')
      return
    }

    const gen = ++genRef.current
    setStatus('requesting_permission')
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user', frameRate: { ideal: 15 } },
        audio: false, // audio is handled by the existing AudioWorklet pipeline
      })
      if (gen !== genRef.current) { stream.getTracks().forEach(t => t.stop()); return } // superseded
      videoStreamRef.current = stream

      const service = new RekognitionService(awsProxyUrl)
      serviceRef.current = service
      await service.startCapture(videoStreamRef.current)
      if (gen !== genRef.current) return // stopCapture already ran during the await
      setStatus('active')

      uiIntervalRef.current = setInterval(() => {
        // Functional updates bail out when unchanged → this poll no longer
        // re-renders the live-call page every 2s (frames only land ~every 8s).
        const frames = service.getFrames()
        setFrameCount((prev) => (prev === frames.length ? prev : frames.length))
        const note = frames[frames.length - 1]?.frameQualityNote
        if (note) setLastFrameQuality((prev) => (prev === note ? prev : note))
      }, 2000)
    } catch (err: any) {
      if (err?.name === 'NotAllowedError') {
        setPermissionDenied(true)
        setStatus('unavailable')
        setErrorMessage('Camera permission denied — facial analysis disabled for this session.')
      } else {
        setStatus('error')
        setErrorMessage(`Camera error: ${err?.message ?? err}`)
      }
      serviceRef.current = null
    }
  }, [awsProxyUrl])

  const stopCapture = useCallback((): FacialFrame[] => {
    genRef.current++ // invalidate any in-flight startCapture
    if (uiIntervalRef.current) { clearInterval(uiIntervalRef.current); uiIntervalRef.current = null }
    const frames = serviceRef.current?.stopCapture() ?? []
    if (frames.length > 0) facialDataStore.setFrames(frames)
    videoStreamRef.current?.getTracks().forEach(t => t.stop())
    videoStreamRef.current = null
    serviceRef.current = null
    setStatus('idle')
    return frames
  }, [])

  const updateQuestion = useCallback((questionIdx: number) => {
    serviceRef.current?.setCurrentQuestion(questionIdx)
  }, [])

  return { status, frameCount, lastFrameQuality, permissionDenied, errorMessage, startCapture, stopCapture, updateQuestion }
}

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

  const startCapture = useCallback(async () => {
    if (serviceRef.current) return  // already running
    if (!awsProxyUrl) {
      setStatus('unavailable')
      setErrorMessage('AWS Rekognition proxy URL not configured. Add it in Settings.')
      return
    }

    setStatus('requesting_permission')
    try {
      videoStreamRef.current = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user', frameRate: { ideal: 15 } },
        audio: false, // audio is handled by the existing AudioWorklet pipeline
      })

      const service = new RekognitionService(awsProxyUrl)
      serviceRef.current = service
      await service.startCapture(videoStreamRef.current)
      setStatus('active')

      uiIntervalRef.current = setInterval(() => {
        const frames = service.getFrames()
        setFrameCount(frames.length)
        const last = frames[frames.length - 1]
        if (last) setLastFrameQuality(last.frameQualityNote)
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

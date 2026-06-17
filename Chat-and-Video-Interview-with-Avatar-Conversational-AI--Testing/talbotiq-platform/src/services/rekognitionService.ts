// src/services/rekognitionService.ts
// Captures video frames during the interview and sends them to the AWS Rekognition
// proxy (Lambda or local Express). Browser → proxy → Rekognition (never direct, so the
// AWS secret never enters the browser bundle).

import type {
  FacialFrame,
  FacialSessionSummary,
  QuestionFacialSummary,
  RekognitionFaceDetail,
  RekognitionEmotionType,
} from '@/types/rekognition.types'

// Minimum standards for a frame to be USED in analysis. Frames below these are discarded.
const QUALITY_THRESHOLDS = {
  minBrightness: 30,
  maxBrightness: 95,
  minSharpness: 20,
  minFaceConfidence: 90,
  minEmotionConfidence: 60,
  maxYawForAttention: 20,
  maxPitchForAttention: 20,
}

// Capture cadence — 8s balances coverage vs API cost.
const CAPTURE_INTERVAL_MS = 8000

export class RekognitionService {
  private proxyUrl: string
  private captureInterval: ReturnType<typeof setInterval> | null = null
  private videoElement: HTMLVideoElement | null = null
  private canvasElement: HTMLCanvasElement | null = null
  private frames: FacialFrame[] = []
  private currentQuestionIdx = 0
  private sessionStartMs = 0
  private isCapturing = false

  constructor(proxyUrl: string) {
    this.proxyUrl = proxyUrl
  }

  async startCapture(videoStream: MediaStream): Promise<void> {
    this.frames = []
    this.sessionStartMs = Date.now()
    this.isCapturing = true

    this.videoElement = document.createElement('video')
    this.videoElement.srcObject = videoStream
    this.videoElement.autoplay = true
    this.videoElement.muted = true
    this.videoElement.playsInline = true
    this.videoElement.style.display = 'none'
    document.body.appendChild(this.videoElement)

    this.canvasElement = document.createElement('canvas')
    this.canvasElement.width = 640
    this.canvasElement.height = 480
    this.canvasElement.style.display = 'none'
    document.body.appendChild(this.canvasElement)

    await this.videoElement.play().catch(err => {
      console.warn('[Rekognition] video play failed:', err)
    })

    await new Promise<void>(resolve => {
      if (this.videoElement!.readyState >= 3) resolve()
      else this.videoElement!.addEventListener('canplay', () => resolve(), { once: true })
    })

    await this._captureAndAnalyzeFrame()
    this.captureInterval = setInterval(() => this._captureAndAnalyzeFrame(), CAPTURE_INTERVAL_MS)
  }

  setCurrentQuestion(questionIdx: number): void {
    this.currentQuestionIdx = questionIdx
  }

  stopCapture(): FacialFrame[] {
    this.isCapturing = false
    if (this.captureInterval) { clearInterval(this.captureInterval); this.captureInterval = null }
    this._cleanup()
    return [...this.frames]
  }

  getFrames(): FacialFrame[] {
    return [...this.frames]
  }

  private _cleanup(): void {
    if (this.videoElement) { this.videoElement.srcObject = null; this.videoElement.remove(); this.videoElement = null }
    if (this.canvasElement) { this.canvasElement.remove(); this.canvasElement = null }
  }

  private async _captureAndAnalyzeFrame(): Promise<void> {
    if (!this.isCapturing || !this.videoElement || !this.canvasElement) return
    if (this.videoElement.readyState < 2) return

    const ctx = this.canvasElement.getContext('2d')
    if (!ctx) return

    ctx.drawImage(this.videoElement, 0, 0, this.canvasElement.width, this.canvasElement.height)

    const imageBase64 = this.canvasElement
      .toDataURL('image/jpeg', 0.85)
      .replace('data:image/jpeg;base64,', '')

    const timestampMs = Date.now() - this.sessionStartMs

    try {
      const response = await fetch(this.proxyUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ imageBase64, questionIdx: this.currentQuestionIdx, timestampMs }),
      })

      if (!response.ok) { this._storeFailedFrame(timestampMs, `api_error_${response.status}`); return }

      const data = await response.json()
      if (!data.success) { this._storeFailedFrame(timestampMs, data.reason ?? 'unknown'); return }

      const faceDetailsList = data.faceDetails ?? []

      if (faceDetailsList.length === 0) {
        this.frames.push({
          timestampMs, questionIdx: this.currentQuestionIdx, faceDetail: null,
          frameQuality: 'no_face', frameQualityNote: 'No face detected in frame',
          dominantEmotion: null, isLookingAtCamera: false, attentionScore: 0, rawResponse: data,
        })
        return
      }

      if (faceDetailsList.length > 1) {
        const frame = this._processFaceDetail(faceDetailsList[0], timestampMs, data)
        frame.frameQuality = 'multiple_faces'
        frame.frameQualityNote = `WARNING: ${faceDetailsList.length} faces detected — integrity flag`
        this.frames.push(frame)
        return
      }

      this.frames.push(this._processFaceDetail(faceDetailsList[0], timestampMs, data))
    } catch (err) {
      console.warn('[Rekognition] frame capture failed:', err)
      this._storeFailedFrame(timestampMs, 'network_error')
    }
  }

  private _processFaceDetail(raw: any, timestampMs: number, rawResponse: any): FacialFrame {
    const faceDetail: RekognitionFaceDetail = {
      confidence: raw.Confidence ?? 0,
      ageRange: { low: raw.AgeRange?.Low ?? 0, high: raw.AgeRange?.High ?? 99 },
      smile: { value: raw.Smile?.Value ?? false, confidence: raw.Smile?.Confidence ?? 0 },
      eyesOpen: { value: raw.EyesOpen?.Value ?? true, confidence: raw.EyesOpen?.Confidence ?? 0 },
      mouthOpen: { value: raw.MouthOpen?.Value ?? false, confidence: raw.MouthOpen?.Confidence ?? 0 },
      emotions: (raw.Emotions ?? [])
        .map((e: any) => ({ type: e.Type as RekognitionEmotionType, confidence: e.Confidence ?? 0 }))
        .sort((a: any, b: any) => b.confidence - a.confidence),
      pose: { roll: raw.Pose?.Roll ?? 0, yaw: raw.Pose?.Yaw ?? 0, pitch: raw.Pose?.Pitch ?? 0 },
      quality: { brightness: raw.Quality?.Brightness ?? 0, sharpness: raw.Quality?.Sharpness ?? 0 },
      sunglasses: { value: raw.Sunglasses?.Value ?? false, confidence: raw.Sunglasses?.Confidence ?? 0 },
      eyeglasses: { value: raw.Eyeglasses?.Value ?? false, confidence: raw.Eyeglasses?.Confidence ?? 0 },
    }

    let frameQuality: FacialFrame['frameQuality'] = 'good'
    let frameQualityNote = 'Good quality frame'

    if (faceDetail.confidence < QUALITY_THRESHOLDS.minFaceConfidence) {
      frameQuality = 'low_confidence'
      frameQualityNote = `Face detection confidence ${faceDetail.confidence.toFixed(1)}% — below threshold`
    } else if (faceDetail.quality.brightness < QUALITY_THRESHOLDS.minBrightness) {
      frameQuality = 'low_brightness'
      frameQualityNote = `Frame too dark (brightness ${faceDetail.quality.brightness.toFixed(0)})`
    } else if (faceDetail.quality.sharpness < QUALITY_THRESHOLDS.minSharpness) {
      frameQuality = 'low_sharpness'
      frameQualityNote = `Frame too blurry (sharpness ${faceDetail.quality.sharpness.toFixed(0)})`
    }

    const dominantEmotion = faceDetail.emotions.find(e => e.confidence >= QUALITY_THRESHOLDS.minEmotionConfidence) ?? null

    const isLookingAtCamera =
      Math.abs(faceDetail.pose.yaw) < QUALITY_THRESHOLDS.maxYawForAttention &&
      Math.abs(faceDetail.pose.pitch) < QUALITY_THRESHOLDS.maxPitchForAttention

    const yawNorm = Math.max(0, 1 - Math.abs(faceDetail.pose.yaw) / 90)
    const pitchNorm = Math.max(0, 1 - Math.abs(faceDetail.pose.pitch) / 90)
    const attentionScore = (yawNorm + pitchNorm) / 2

    return {
      timestampMs, questionIdx: this.currentQuestionIdx, faceDetail,
      frameQuality, frameQualityNote, dominantEmotion, isLookingAtCamera, attentionScore, rawResponse,
    }
  }

  private _storeFailedFrame(timestampMs: number, reason: string): void {
    this.frames.push({
      timestampMs, questionIdx: this.currentQuestionIdx, faceDetail: null,
      frameQuality: 'no_face', frameQualityNote: `Frame capture failed: ${reason}`,
      dominantEmotion: null, isLookingAtCamera: false, attentionScore: 0, rawResponse: null,
    })
  }
}

// ─── Aggregation ──────────────────────────────────────────────────────────────

export function aggregateFacialData(frames: FacialFrame[], questionCount: number): FacialSessionSummary {
  const usableFrames = frames.filter(f => f.frameQuality === 'good' && f.faceDetail !== null)
  const usablePercent = frames.length > 0 ? (usableFrames.length / frames.length) * 100 : 0

  let dataQuality: FacialSessionSummary['dataQuality'] = 'insufficient'
  let dataQualityNote = ''
  if (usableFrames.length >= 10) { dataQuality = 'high'; dataQualityNote = `${usableFrames.length} high-quality frames analyzed` }
  else if (usableFrames.length >= 5) { dataQuality = 'medium'; dataQualityNote = `Only ${usableFrames.length} usable frames — moderate confidence` }
  else if (usableFrames.length >= 2) { dataQuality = 'low'; dataQualityNote = `Only ${usableFrames.length} usable frames — low confidence, treat with caution` }
  else { dataQuality = 'insufficient'; dataQualityNote = 'Insufficient facial data — facial analysis should be disregarded' }

  const emotionMap = new Map<RekognitionEmotionType, number[]>()
  for (const frame of usableFrames) {
    for (const emotion of (frame.faceDetail?.emotions ?? [])) {
      if (emotion.confidence >= 60) {
        if (!emotionMap.has(emotion.type)) emotionMap.set(emotion.type, [])
        emotionMap.get(emotion.type)!.push(emotion.confidence)
      }
    }
  }
  const sessionDominantEmotions = Array.from(emotionMap.entries())
    .map(([type, confidences]) => ({ type, avgConfidence: confidences.reduce((a, b) => a + b, 0) / confidences.length }))
    .sort((a, b) => b.avgConfidence - a.avgConfidence)

  const sessionAvgAttention = usableFrames.length > 0
    ? usableFrames.reduce((sum, f) => sum + f.attentionScore, 0) / usableFrames.length : 0
  const sessionAvgSmile = usableFrames.length > 0
    ? usableFrames.filter(f => f.faceDetail?.smile.value).length / usableFrames.length : 0
  const lookingAwayFrames = usableFrames.filter(f => !f.isLookingAtCamera)
  const overallLookingAwayPercent = usableFrames.length > 0 ? (lookingAwayFrames.length / usableFrames.length) * 100 : 0

  const perQuestion: QuestionFacialSummary[] = Array.from({ length: questionCount }, (_, idx) => {
    const qFrames = frames.filter(f => f.questionIdx === idx)
    const qUsable = qFrames.filter(f => f.frameQuality === 'good' && f.faceDetail !== null)

    if (qUsable.length === 0) {
      return {
        questionIdx: idx, frameCount: qFrames.length, usableFrameCount: 0,
        dominantEmotions: [], avgAttentionScore: 0, avgSmileScore: 0,
        lookingAwayCount: 0, lookingAwayPercent: 0, eyesClosedCount: 0,
        mouthOpenAvg: 0, headPoseVariance: 0, qualityNote: 'No usable frames for this question',
      }
    }

    const qEmotionMap = new Map<RekognitionEmotionType, number[]>()
    for (const frame of qUsable) {
      for (const e of (frame.faceDetail?.emotions ?? [])) {
        if (e.confidence >= 60) {
          if (!qEmotionMap.has(e.type)) qEmotionMap.set(e.type, [])
          qEmotionMap.get(e.type)!.push(e.confidence)
        }
      }
    }
    const dominantEmotions = Array.from(qEmotionMap.entries())
      .map(([type, confs]) => ({ type, avgConfidence: confs.reduce((a, b) => a + b, 0) / confs.length }))
      .sort((a, b) => b.avgConfidence - a.avgConfidence)

    const avgAttentionScore = qUsable.reduce((sum, f) => sum + f.attentionScore, 0) / qUsable.length
    const avgSmileScore = qUsable.filter(f => f.faceDetail?.smile.value).length / qUsable.length
    const lookingAway = qUsable.filter(f => !f.isLookingAtCamera)
    const lookingAwayPercent = (lookingAway.length / qUsable.length) * 100
    const eyesClosed = qUsable.filter(f => f.faceDetail?.eyesOpen.value === false && (f.faceDetail?.eyesOpen.confidence ?? 0) > 80).length
    const mouthOpenAvg = qUsable.filter(f => f.faceDetail?.mouthOpen.value).length / qUsable.length

    const yaws = qUsable.map(f => f.faceDetail?.pose.yaw ?? 0)
    const yawMean = yaws.reduce((a, b) => a + b, 0) / yaws.length
    const headPoseVariance = yaws.reduce((sum, y) => sum + Math.pow(y - yawMean, 2), 0) / yaws.length

    return {
      questionIdx: idx, frameCount: qFrames.length, usableFrameCount: qUsable.length,
      dominantEmotions, avgAttentionScore, avgSmileScore,
      lookingAwayCount: lookingAway.length, lookingAwayPercent,
      eyesClosedCount: eyesClosed, mouthOpenAvg, headPoseVariance,
      qualityNote: qUsable.length < 2 ? `Only ${qUsable.length} usable frame(s) — low confidence` : '',
    }
  })

  const integrityFlags: string[] = []
  const engagementFlags: string[] = []
  const concernFlags: string[] = []

  if (overallLookingAwayPercent > 40) {
    integrityFlags.push(`Candidate looked away from camera in ${overallLookingAwayPercent.toFixed(0)}% of frames`)
  }
  const multipleFaceFrames = frames.filter(f => f.frameQuality === 'multiple_faces')
  if (multipleFaceFrames.length > 0) {
    integrityFlags.push(`Multiple faces detected in ${multipleFaceFrames.length} frame(s) — possible coaching`)
  }

  for (const q of perQuestion) {
    if (q.lookingAwayPercent > 60 && q.usableFrameCount >= 2) {
      integrityFlags.push(`Q${q.questionIdx + 1}: Looking away ${q.lookingAwayPercent.toFixed(0)}% of the time`)
    }
    if (q.headPoseVariance > 200) {
      concernFlags.push(`Q${q.questionIdx + 1}: High head-movement variance — possible anxiety or distraction`)
    }
    const top = q.dominantEmotions[0]
    if (top?.type === 'CALM' && top.avgConfidence > 75) {
      engagementFlags.push(`Q${q.questionIdx + 1}: Consistent calm expression (${top.avgConfidence.toFixed(0)}% confidence)`)
    }
    if (top?.type === 'CONFUSED' && top.avgConfidence > 65) {
      concernFlags.push(`Q${q.questionIdx + 1}: Facial confusion signal (${top.avgConfidence.toFixed(0)}% confidence)`)
    }
  }

  if (sessionAvgAttention > 0.85) {
    engagementFlags.push(`High camera attention throughout — avg ${(sessionAvgAttention * 100).toFixed(0)}%`)
  }

  return {
    totalFrames: frames.length,
    usableFrames: usableFrames.length,
    usableFramePercent: usablePercent,
    frames,
    perQuestion,
    sessionDominantEmotions,
    sessionAvgAttention,
    sessionAvgSmile,
    overallLookingAwayPercent,
    dataQuality,
    dataQualityNote,
    integrityFlags,
    engagementFlags,
    concernFlags,
  }
}

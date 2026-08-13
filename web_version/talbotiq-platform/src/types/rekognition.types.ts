// src/types/rekognition.types.ts
// Full TypeScript coverage of the AWS Rekognition DetectFaces response we use.

export type RekognitionEmotionType =
  | 'HAPPY' | 'SAD' | 'ANGRY' | 'CONFUSED'
  | 'DISGUSTED' | 'SURPRISED' | 'CALM' | 'FEAR'

export interface RekognitionEmotion {
  type: RekognitionEmotionType
  confidence: number  // 0–100 (AWS uses 0-100, not 0-1)
}

export interface RekognitionPose {
  roll: number   // head tilt left/right (-90..90)
  yaw: number    // head turn left/right (-90..90, 0 = facing camera)
  pitch: number  // head tilt up/down (-90..90, 0 = level)
}

export interface RekognitionQuality {
  brightness: number   // 0–100
  sharpness: number    // 0–100
}

export interface RekognitionBooleanAttribute {
  value: boolean
  confidence: number
}

export interface RekognitionAgeRange {
  low: number
  high: number
}

export interface RekognitionFaceDetail {
  confidence: number
  ageRange: RekognitionAgeRange
  smile: RekognitionBooleanAttribute
  eyesOpen: RekognitionBooleanAttribute
  mouthOpen: RekognitionBooleanAttribute
  emotions: RekognitionEmotion[]
  pose: RekognitionPose
  quality: RekognitionQuality
  sunglasses: RekognitionBooleanAttribute
  eyeglasses: RekognitionBooleanAttribute
}

export type FrameQuality =
  | 'good' | 'low_brightness' | 'low_sharpness' | 'no_face' | 'multiple_faces' | 'low_confidence'

export interface FacialFrame {
  timestampMs: number
  questionIdx: number
  faceDetail: RekognitionFaceDetail | null
  frameQuality: FrameQuality
  frameQualityNote: string
  dominantEmotion: RekognitionEmotion | null
  isLookingAtCamera: boolean       // derived: |yaw| < 15 && |pitch| < 15
  attentionScore: number           // 0–1, derived from pose angles
  rawResponse: any
}

export interface QuestionFacialSummary {
  questionIdx: number
  frameCount: number
  usableFrameCount: number
  dominantEmotions: Array<{ type: RekognitionEmotionType; avgConfidence: number }>
  avgAttentionScore: number
  avgSmileScore: number
  lookingAwayCount: number
  lookingAwayPercent: number
  eyesClosedCount: number
  mouthOpenAvg: number
  headPoseVariance: number
  qualityNote: string
}

export interface FacialSessionSummary {
  totalFrames: number
  usableFrames: number
  usableFramePercent: number
  frames: FacialFrame[]
  perQuestion: QuestionFacialSummary[]
  sessionDominantEmotions: Array<{ type: RekognitionEmotionType; avgConfidence: number }>
  sessionAvgAttention: number
  sessionAvgSmile: number
  overallLookingAwayPercent: number
  dataQuality: 'high' | 'medium' | 'low' | 'insufficient'
  dataQualityNote: string
  integrityFlags: string[]
  engagementFlags: string[]
  concernFlags: string[]
}

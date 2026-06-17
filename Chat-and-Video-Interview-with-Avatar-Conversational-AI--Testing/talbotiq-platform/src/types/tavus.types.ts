// ── Replicas ──────────────────────────────────────────────────────────────────
export type ReplicaStatus = 'ready' | 'training' | 'error' | 'deleted'

export interface TavusReplica {
  replica_id: string
  replica_name: string
  status: ReplicaStatus
  thumbnail_video_url?: string
  training_progress?: number
  created_at: string
  updated_at?: string
  replica_type?: 'personal' | 'custom' | 'stock'
  callback_url?: string
}

export interface CreateReplicaInput {
  train_video_url?: string
  replica_name: string
  callback_url?: string
  replica_type?: 'personal' | 'custom'
}

// ── Personas ──────────────────────────────────────────────────────────────────
export type TTSEngine = 'cartesia' | 'eleven_labs' | 'tavus'
export type STTEngine = 'tavus' | 'deepgram' | 'custom'
export type LLMModel = 'gpt-4o' | 'gpt-4o-mini' | 'claude-3-5-sonnet' | 'gemini-1.5-pro' | 'custom'
export type EmotionTag = 'anger' | 'positivity' | 'surprise' | 'sadness' | 'curiosity'

export interface PersonaLLMLayer {
  model?: LLMModel
  base_url?: string
  api_key?: string
  max_tokens?: number
  temperature?: number
}

export interface PersonaTTSLayer {
  api_key?: string
  tts_engine?: TTSEngine
  external_voice_id?: string
  voice_settings?: {
    speed?: number
    emotion?: EmotionTag[]
  }
}

export interface PersonaSTTLayer {
  stt_engine?: STTEngine
  participant_pause_sensitivity?: number
  smart_turn_detection?: boolean
}

export interface PersonaPerceptionLayer {
  ambient_awareness_queries?: string[]
  perception_model?: string
}

export interface PersonaVQALayer {
  enable_camera?: boolean
}

export interface PersonaLayers {
  llm?: PersonaLLMLayer
  tts?: PersonaTTSLayer
  stt?: PersonaSTTLayer
  perception?: PersonaPerceptionLayer
  vqa?: PersonaVQALayer
}

export interface TavusPersona {
  persona_id: string
  persona_name: string
  system_prompt: string
  context?: string
  default_replica_id?: string
  layers?: PersonaLayers
  created_at: string
  updated_at?: string
}

export interface CreatePersonaInput {
  persona_name: string
  system_prompt: string
  context?: string
  default_replica_id?: string
  layers?: PersonaLayers
}

// ── Conversations ─────────────────────────────────────────────────────────────
export type ConversationStatus = 'active' | 'ended' | 'error'
export type PipelineMode = 'full' | 'echo' | 'no_audio' | 'video_only'
// Tavus requires full language names, NOT ISO codes
export type SupportedLanguage = 'English' | 'Spanish' | 'French' | 'German' | 'Italian' | 'Portuguese' | 'Japanese' | 'Korean' | 'Chinese' | 'Hindi' | 'Arabic'

export interface ConversationProperties {
  max_call_duration?: number
  participant_left_timeout?: number
  participant_absent_timeout?: number
  enable_recording?: boolean
  enable_transcription?: boolean
  language?: SupportedLanguage
  recording_s3_bucket_name?: string
  recording_s3_bucket_region?: string
  aws_assume_role_arn?: string
  apply_conversation_override?: boolean
  apply_greenscreen?: boolean
  background_url?: string
  pipeline_mode?: PipelineMode
}

export interface TavusConversation {
  conversation_id: string
  conversation_name?: string
  status: ConversationStatus
  conversation_url: string
  replica_id: string
  persona_id?: string
  created_at: string
  ended_at?: string
  properties?: ConversationProperties
  callback_url?: string
  conversational_context?: string
  custom_greeting?: string
}

export interface CreateConversationInput {
  replica_id: string
  persona_id?: string
  conversation_name?: string
  conversational_context?: string
  custom_greeting?: string
  callback_url?: string
  properties?: ConversationProperties
}

export interface ConversationFilters {
  status?: ConversationStatus
  replica_id?: string
  persona_id?: string
  page?: number
  limit?: number
}

// ── Conversation Events ────────────────────────────────────────────────────────
export type ConversationEventType =
  | 'conversation.started'
  | 'conversation.ended'
  | 'conversation.transcription'
  | 'conversation.replica.started_speaking'
  | 'conversation.replica.stopped_speaking'
  | 'conversation.participant.joined'
  | 'conversation.participant.left'
  | 'conversation.error'

export interface ConversationEvent {
  event_type: ConversationEventType
  timestamp: string
  conversation_id: string
  payload?: Record<string, unknown>
}

// ── Videos ─────────────────────────────────────────────────────────────────────
export type VideoStatus = 'queued' | 'processing' | 'ready' | 'error'

export interface TavusVideo {
  video_id: string
  status: VideoStatus
  video_url?: string
  download_url?: string
  thumbnail_url?: string
  replica_id: string
  script?: string
  created_at: string
  duration?: number
  progress?: number
}

export interface GenerateVideoInput {
  replica_id: string
  script: string
  video_name?: string
  callback_url?: string
}

// ── API response wrappers ──────────────────────────────────────────────────────
export interface TavusListResponse<T> {
  data: T[]
  total?: number
  page?: number
  limit?: number
}

export interface TavusError {
  message: string
  code?: string
  status?: number
}

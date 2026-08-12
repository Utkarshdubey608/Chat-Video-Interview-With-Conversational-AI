import type {
  TavusReplica, CreateReplicaInput,
  TavusPersona, CreatePersonaInput,
  TavusConversation, CreateConversationInput, ConversationFilters,
  TavusVideo, GenerateVideoInput,
  TavusListResponse,
} from '@/types/tavus.types'

const BASE = 'https://tavusapi.com/v2'

class TavusAPI {
  private key = ''

  setKey(k: string) { this.key = k }
  getKey() { return this.key }

  private headers(extra?: Record<string, string>) {
    return {
      'x-api-key': this.key,
      'Content-Type': 'application/json',
      ...extra,
    }
  }

  private async req<T>(
    method: string,
    path: string,
    body?: unknown,
    formData?: FormData,
  ): Promise<T> {
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: formData ? { 'x-api-key': this.key } : this.headers(),
      body: formData ?? (body !== undefined ? JSON.stringify(body) : undefined),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => null)
      // Surface the actual Tavus error — could be nested in different shapes
      const msg = err?.message ?? err?.error ?? err?.detail ?? `HTTP ${res.status}`
      throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg))
    }
    if (res.status === 204) return undefined as T
    return res.json()
  }

  // ── Replicas ──────────────────────────────────────────────────────────────
  // Fetches custom replicas + stock replicas, merges and deduplicates by id
  listReplicas = async (): Promise<TavusReplica[]> => {
    const [custom, stock] = await Promise.allSettled([
      this.req<TavusListResponse<TavusReplica>>('GET', '/replicas')
        .then(r => (r.data ?? (r as unknown as TavusReplica[])).map(x => ({ ...x, replica_type: x.replica_type ?? 'personal' }))),
      this.req<TavusListResponse<TavusReplica>>('GET', '/replicas?replica_type=stock')
        .then(r => (r.data ?? (r as unknown as TavusReplica[])).map(x => ({ ...x, replica_type: 'stock' as const }))),
    ])
    const customList = custom.status === 'fulfilled' ? custom.value : []
    const stockList  = stock.status  === 'fulfilled' ? stock.value  : []
    // Merge: custom first, then stock — deduplicate by replica_id
    const seen = new Set(customList.map(r => r.replica_id))
    const merged = [...customList, ...stockList.filter(r => !seen.has(r.replica_id))]
    return merged
  }

  getReplica = (id: string) =>
    this.req<TavusReplica>('GET', `/replicas/${id}`)

  createReplica = (data: CreateReplicaInput) =>
    this.req<TavusReplica>('POST', '/replicas', data)

  updateReplica = (id: string, data: Partial<TavusReplica>) =>
    this.req<TavusReplica>('PATCH', `/replicas/${id}`, data)

  deleteReplica = (id: string) =>
    this.req<void>('DELETE', `/replicas/${id}`)

  // ── Personas ──────────────────────────────────────────────────────────────
  listPersonas = () =>
    this.req<TavusListResponse<TavusPersona>>('GET', '/personas')
      .then(r => r.data ?? (r as unknown as TavusPersona[]))

  getPersona = (id: string) =>
    this.req<TavusPersona>('GET', `/personas/${id}`)

  createPersona = (data: CreatePersonaInput) =>
    this.req<TavusPersona>('POST', '/personas', data)

  updatePersona = (id: string, data: Partial<CreatePersonaInput>) =>
    this.req<TavusPersona>('PATCH', `/personas/${id}`, data)

  deletePersona = (id: string) =>
    this.req<void>('DELETE', `/personas/${id}`)

  // ── Conversations ─────────────────────────────────────────────────────────
  listConversations = (filters?: ConversationFilters) => {
    const params = new URLSearchParams()
    if (filters?.status) params.set('status', filters.status)
    if (filters?.replica_id) params.set('replica_id', filters.replica_id)
    if (filters?.persona_id) params.set('persona_id', filters.persona_id)
    if (filters?.page) params.set('page', String(filters.page))
    if (filters?.limit) params.set('limit', String(filters.limit))
    const qs = params.toString()
    return this.req<TavusListResponse<TavusConversation>>('GET', `/conversations${qs ? `?${qs}` : ''}`)
      .then(r => r.data ?? (r as unknown as TavusConversation[]))
  }

  getConversation = (id: string) =>
    this.req<TavusConversation>('GET', `/conversations/${id}`)

  createConversation = (data: CreateConversationInput) =>
    this.req<TavusConversation>('POST', '/conversations', data)

  updateConversation = (id: string, data: Partial<CreateConversationInput>) =>
    this.req<TavusConversation>('PATCH', `/conversations/${id}`, data)

  endConversation = (id: string) =>
    this.req<void>('DELETE', `/conversations/${id}`)

  getConversationTranscript = (id: string) =>
    this.req<{ transcript?: Array<{ role: string; content: string; timestamp?: string }> }>(
      'GET', `/conversations/${id}/transcript`
    )

  // ── Videos ────────────────────────────────────────────────────────────────
  listVideos = () =>
    this.req<TavusListResponse<TavusVideo>>('GET', '/videos')
      .then(r => r.data ?? (r as unknown as TavusVideo[]))

  getVideo = (id: string) =>
    this.req<TavusVideo>('GET', `/videos/${id}`)

  generateVideo = (data: GenerateVideoInput) =>
    this.req<TavusVideo>('POST', '/videos', data)
}

export const tavus = new TavusAPI()
export type { TavusAPI }

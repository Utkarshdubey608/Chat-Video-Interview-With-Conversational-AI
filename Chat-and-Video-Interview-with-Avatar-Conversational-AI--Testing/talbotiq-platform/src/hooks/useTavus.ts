import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { tavus } from '@/services/tavus'
import type {
  CreateReplicaInput, CreatePersonaInput,
  CreateConversationInput, ConversationFilters, GenerateVideoInput,
} from '@/types/tavus.types'

// ── Query keys ────────────────────────────────────────────────────────────────
export const QK = {
  replicas:      ['replicas'] as const,
  replica:       (id: string) => ['replicas', id] as const,
  personas:      ['personas'] as const,
  persona:       (id: string) => ['personas', id] as const,
  conversations: (f?: ConversationFilters) => ['conversations', f] as const,
  conversation:  (id: string) => ['conversations', id] as const,
  videos:        ['videos'] as const,
  video:         (id: string) => ['videos', id] as const,
}

// ── Replicas ──────────────────────────────────────────────────────────────────
export function useReplicas() {
  return useQuery({
    queryKey: QK.replicas,
    queryFn: tavus.listReplicas,
    staleTime: 30_000,
  })
}

export function useReplica(id: string) {
  return useQuery({
    queryKey: QK.replica(id),
    queryFn: () => tavus.getReplica(id),
    enabled: !!id,
    refetchInterval: (q) => {
      const status = q.state.data?.status
      return status === 'training' ? 3000 : false
    },
  })
}

export function useCreateReplica() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: CreateReplicaInput) => tavus.createReplica(data),
    onSuccess: () => qc.invalidateQueries({ queryKey: QK.replicas }),
  })
}

export function useUpdateReplica() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof tavus.updateReplica>[1] }) =>
      tavus.updateReplica(id, data),
    onSuccess: (_, { id }) => {
      qc.invalidateQueries({ queryKey: QK.replicas })
      qc.invalidateQueries({ queryKey: QK.replica(id) })
    },
  })
}

export function useDeleteReplica() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => tavus.deleteReplica(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: QK.replicas }),
  })
}

// ── Personas ──────────────────────────────────────────────────────────────────
export function usePersonas() {
  return useQuery({
    queryKey: QK.personas,
    queryFn: tavus.listPersonas,
    staleTime: 30_000,
  })
}

export function usePersona(id: string) {
  return useQuery({
    queryKey: QK.persona(id),
    queryFn: () => tavus.getPersona(id),
    enabled: !!id,
  })
}

export function useCreatePersona() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: CreatePersonaInput) => tavus.createPersona(data),
    onSuccess: () => qc.invalidateQueries({ queryKey: QK.personas }),
  })
}

export function useUpdatePersona() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<CreatePersonaInput> }) =>
      tavus.updatePersona(id, data),
    onSuccess: (_, { id }) => {
      qc.invalidateQueries({ queryKey: QK.personas })
      qc.invalidateQueries({ queryKey: QK.persona(id) })
    },
  })
}

export function useDeletePersona() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => tavus.deletePersona(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: QK.personas }),
  })
}

// ── Conversations ─────────────────────────────────────────────────────────────
export function useConversations(filters?: ConversationFilters) {
  return useQuery({
    queryKey: QK.conversations(filters),
    queryFn: () => tavus.listConversations(filters),
    staleTime: 10_000,
  })
}

export function useConversation(id: string, poll = false) {
  return useQuery({
    queryKey: QK.conversation(id),
    queryFn: () => tavus.getConversation(id),
    enabled: !!id,
    refetchInterval: poll ? 3000 : false,
  })
}

export function useCreateConversation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: CreateConversationInput) => tavus.createConversation(data),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['conversations'] }),
  })
}

export function useUpdateConversation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<CreateConversationInput> }) =>
      tavus.updateConversation(id, data),
    onSuccess: (_, { id }) => qc.invalidateQueries({ queryKey: QK.conversation(id) }),
  })
}

export function useConversationTranscript(id: string, poll = false) {
  return useQuery({
    queryKey: [...QK.conversation(id), 'transcript'],
    queryFn: () => tavus.getConversationTranscript(id),
    enabled: !!id,
    refetchInterval: poll ? 2000 : false,
    retry: false,
  })
}

export function useEndConversation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => tavus.endConversation(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['conversations'] }),
  })
}

// ── Videos ────────────────────────────────────────────────────────────────────
export function useVideos() {
  return useQuery({
    queryKey: QK.videos,
    queryFn: tavus.listVideos,
    staleTime: 30_000,
  })
}

export function useVideo(id: string) {
  return useQuery({
    queryKey: QK.video(id),
    queryFn: () => tavus.getVideo(id),
    enabled: !!id,
    refetchInterval: (q) => {
      const status = q.state.data?.status
      return status === 'processing' || status === 'queued' ? 3000 : false
    },
  })
}

export function useGenerateVideo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (data: GenerateVideoInput) => tavus.generateVideo(data),
    onSuccess: () => qc.invalidateQueries({ queryKey: QK.videos }),
  })
}

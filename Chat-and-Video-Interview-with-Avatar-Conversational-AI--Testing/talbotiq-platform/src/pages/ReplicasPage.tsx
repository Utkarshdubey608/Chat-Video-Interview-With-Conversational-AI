import { useState } from 'react'
import toast from 'react-hot-toast'
import { useReplicas, useDeleteReplica, useUpdateReplica } from '@/hooks/useTavus'
import { Button, Card, Badge, Modal, Input, Skeleton, EmptyState, PageHeader, InfoRow } from '@/components/ui'
import type { TavusReplica } from '@/types/tavus.types'
import { formatDistanceToNow } from 'date-fns'

function StatusBadge({ status }: { status: TavusReplica['status'] }) {
  const map = { ready: 'success', training: 'warning', error: 'danger', deleted: 'neutral' } as const
  return <Badge variant={map[status]}>{status}</Badge>
}

function ReplicaCard({ r, onSelect }: { r: TavusReplica; onSelect: (r: TavusReplica) => void }) {
  const del = useDeleteReplica()
  return (
    <Card hover className="overflow-hidden cursor-pointer" onClick={() => onSelect(r)}>
      {r.thumbnail_video_url
        ? <video src={r.thumbnail_video_url} className="w-full h-44 object-cover bg-neutral-100" muted loop autoPlay />
        : <div className="w-full h-44 bg-gradient-to-br from-neutral-100 to-neutral-50 flex items-center justify-center text-neutral-300">
            <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/></svg>
          </div>
      }
      <div className="p-4">
        <div className="flex items-start justify-between gap-2 mb-3">
          <div className="min-w-0">
            <p className="text-sm font-semibold text-neutral-900 truncate">{r.replica_name}</p>
            <p className="text-xs text-neutral-400 font-mono mt-0.5 truncate">{r.replica_id}</p>
          </div>
          <StatusBadge status={r.status} />
        </div>
        {r.status === 'training' && (
          <div className="mb-3">
            <div className="flex justify-between text-xs mb-1.5">
              <span className="text-neutral-500 font-medium">Training in progress</span>
              <span className="text-neutral-400 font-mono">{r.training_progress ?? 0}%</span>
            </div>
            <div className="h-1.5 bg-neutral-100 rounded-full overflow-hidden">
              <div className="h-full bg-primary-700 rounded-full transition-all" style={{ width: `${r.training_progress ?? 0}%` }} />
            </div>
          </div>
        )}
        <div className="flex items-center justify-between pt-3 border-t border-border">
          <span className="text-xs text-neutral-400">{formatDistanceToNow(new Date(r.created_at), { addSuffix: true })}</span>
          <button
            onClick={e => { e.stopPropagation(); if (confirm(`Delete "${r.replica_name}"?`)) del.mutate(r.replica_id, { onSuccess: () => toast.success('Replica deleted'), onError: (e: any) => toast.error(e.message) }) }}
            className="text-xs font-medium text-danger hover:underline"
          >Delete</button>
        </div>
      </div>
    </Card>
  )
}

export default function ReplicasPage() {
  const { data: replicas, isLoading } = useReplicas()
  const update = useUpdateReplica()
  const [selected, setSelected] = useState<TavusReplica | null>(null)
  const [editName, setEditName] = useState('')

  return (
    <div className="max-w-[1400px] mx-auto px-6 py-8">
      <PageHeader
        kicker="Avatar Management"
        title="Replicas"
        description="Manage your Tavus AI avatar replicas. Click any card to view full details or rename."
        action={
          <Button onClick={() => toast('Create replicas at platform.tavus.io → Replicas → Create. They appear here automatically once training completes (~15 min).')}>
            + New Replica
          </Button>
        }
      />

      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {[...Array(8)].map((_, i) => <Skeleton key={i} className="h-72" />)}
        </div>
      ) : !replicas?.length ? (
        <EmptyState
          icon="🎭"
          title="No replicas yet"
          description="Create a replica on the Tavus dashboard. Training takes approximately 15 minutes. Your replica will appear here automatically once it's ready."
          action={
            <Button variant="outline" onClick={() => window.open('https://platform.tavus.io', '_blank')}>
              Open Tavus Dashboard ↗
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {replicas.map(r => <ReplicaCard key={r.replica_id} r={r} onSelect={r => { setSelected(r); setEditName(r.replica_name) }} />)}
        </div>
      )}

      <Modal open={!!selected} onClose={() => setSelected(null)} title="Replica Details" description="View metadata and rename this replica.">
        {selected && (
          <div className="space-y-4">
            {selected.thumbnail_video_url && (
              <video src={selected.thumbnail_video_url} controls className="w-full rounded-xl bg-neutral-100 max-h-48 object-contain" />
            )}
            <div className="border border-border rounded-xl overflow-hidden">
              <InfoRow label="Replica ID" value={<span className="font-mono text-xs">{selected.replica_id}</span>} />
              <InfoRow label="Status" value={<StatusBadge status={selected.status} />} />
              <InfoRow label="Type" value={selected.replica_type ?? '—'} />
              <InfoRow label="Created" value={new Date(selected.created_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })} />
            </div>
            <Input label="Rename Replica" value={editName} onChange={e => setEditName(e.target.value)} />
            <div className="flex gap-2 justify-end pt-2">
              <Button variant="secondary" onClick={() => setSelected(null)}>Cancel</Button>
              <Button
                loading={update.isPending}
                onClick={() => update.mutate({ id: selected.replica_id, data: { replica_name: editName } }, { onSuccess: () => { toast.success('Replica renamed'); setSelected(null) }, onError: (e: any) => toast.error(e.message) })}
              >
                Save Changes
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}

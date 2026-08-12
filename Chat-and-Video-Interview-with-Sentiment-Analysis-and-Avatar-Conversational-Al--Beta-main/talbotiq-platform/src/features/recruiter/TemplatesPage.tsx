import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { Copy, Pencil, Trash2, FileText, Video } from 'lucide-react'
import { PageHeader, Card, Button, Badge, EmptyState, Skeleton } from '@/components/ui'
import { templatesApi } from '@/lib/api'
import type { InterviewTemplate } from '@shared/types'

export default function TemplatesPage() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const templates = useQuery({ queryKey: ['templates'], queryFn: templatesApi.list })

  const create = useMutation({
    mutationFn: () => templatesApi.create({ name: 'New template', role: 'Software Engineer' }),
    onSuccess: (t) => {
      qc.invalidateQueries({ queryKey: ['templates'] })
      navigate(`/templates/${t.id}`)
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const duplicate = useMutation({
    mutationFn: (t: InterviewTemplate) =>
      templatesApi.create({ ...t, name: `${t.name} (copy)`, id: undefined as never }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['templates'] }); toast.success('Template duplicated') },
  })

  const remove = useMutation({
    mutationFn: (id: string) => templatesApi.remove(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['templates'] }); toast.success('Template deleted') },
  })

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <PageHeader
        kicker="AI Interview"
        title="Interview Templates"
        description="Reusable configurations — questions, timing, scoring rubric, branding, and integrity rules."
        action={<Button loading={create.isPending} onClick={() => create.mutate()}>+ New template</Button>}
      />

      {templates.isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-40" />)}</div>
      ) : !templates.data?.length ? (
        <Card className="p-0">
          <EmptyState icon="🧩" title="No templates yet" description="Create your first interview template to start inviting candidates." action={<Button onClick={() => create.mutate()}>+ New template</Button>} />
        </Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {templates.data.map((t) => (
            <Card key={t.id} hover className="flex flex-col p-5">
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary-50 text-primary-700">
                    {t.track === 'video_avatar' ? <Video size={17} /> : <FileText size={17} />}
                  </span>
                  <Badge variant={t.questionSource === 'adaptive' ? 'info' : 'neutral'}>{t.questionSource}</Badge>
                </div>
              </div>
              <h3 className="mt-3 text-base font-bold text-neutral-900">{t.name}</h3>
              <p className="text-sm text-neutral-500">{t.role}{t.seniority ? ` · ${t.seniority}` : ''}</p>
              <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-neutral-400">
                <span>Prep {t.timing.prepSeconds}s</span>
                <span>Answer {t.timing.answerSeconds}s</span>
                <span>{t.rubric.kpis.filter((k) => k.enabled).length} KPIs</span>
              </div>
              <div className="mt-4 flex items-center gap-1 border-t border-border pt-3">
                <Button size="sm" variant="secondary" icon={<Pencil size={14} />} onClick={() => navigate(`/templates/${t.id}`)}>Edit</Button>
                <Button size="sm" variant="ghost" icon={<Copy size={14} />} onClick={() => duplicate.mutate(t)}>Duplicate</Button>
                <button
                  onClick={() => { if (confirm(`Delete “${t.name}”?`)) remove.mutate(t.id) }}
                  className="ml-auto rounded-lg p-2 text-neutral-400 hover:bg-danger-bg hover:text-danger"
                  aria-label="Delete template"
                >
                  <Trash2 size={15} />
                </button>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}

import { useCallback, useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import { pipelinesApi } from '@/lib/api'
import { useAutopilotActions } from '@/features/guide/autopilot/registry'
import { matchOption } from '@/features/guide/autopilot/filterMatch'
import { Card, Select, PageHeader, EmptyState, Skeleton } from '@/components/ui'
import type { Pipeline } from '@shared/types'

export default function PipelinesPage() {
  const { data: pipelines, isLoading, isError } = useQuery({ queryKey: ['pipelines'], queryFn: () => pipelinesApi.list() })
  const [role, setRole] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const navigate = useNavigate()

  const roles = useMemo(
    () => [...new Set((pipelines ?? []).map((p) => p.role).filter(Boolean))].sort(),
    [pipelines],
  )

  // ── Autopilot: open a board by role, and drive the list filters (role + date
  // range) exactly like the controls below. Filtering/navigation are read-only
  // (not side effects), so these run immediately. Live data is read through refs
  // so the memoized defs never go stale. ────────────────────────────────────
  const pipelinesRef = useRef<Pipeline[]>([])
  pipelinesRef.current = pipelines ?? []
  const filterRef = useRef({ role: '', from: '', to: '' })
  filterRef.current = { role, from, to }
  const apActions = useMemo(() => ({
    openByRole: {
      description: 'Open the progression board for a role by name (matches a pipeline role, most recent first)',
      params: [{ name: 'role', type: 'string' as const, required: true }],
      run: (args: Record<string, unknown>) => {
        const want = String(args.role ?? '').trim().toLowerCase()
        if (!want) return
        const match = pipelinesRef.current.find((p) => p.role.toLowerCase() === want)
          ?? pipelinesRef.current.find((p) => p.role.toLowerCase().includes(want))
        if (match) navigate(`/pipelines/${match.id}`)
      },
    },
    filterByRole: {
      description: 'Filter the pipelines list by role/position (matches an existing pipeline role). Say "all" to clear.',
      params: [{ name: 'role', type: 'string' as const, required: true, description: 'the role name, or "all" to clear' }],
      run: (args: Record<string, unknown>) => {
        const want = String(args.role ?? '').trim()
        if (!want || /^(all|any)$/i.test(want)) { setRole(''); return }
        const roleList = [...new Set(pipelinesRef.current.map((p) => p.role).filter(Boolean))]
        const match = matchOption(want, roleList)
        if (!match) { toast.error(`No pipeline for a role matching "${want}"`); return }
        setRole(match)
      },
    },
    setDateRange: {
      description: 'Filter the pipelines list by creation date range (YYYY-MM-DD). Omit a bound to leave it open; use clearFilters to remove dates.',
      params: [
        { name: 'from', type: 'string' as const, required: false, description: 'start date YYYY-MM-DD' },
        { name: 'to', type: 'string' as const, required: false, description: 'end date YYYY-MM-DD' },
      ],
      run: (args: Record<string, unknown>) => {
        setFrom(args.from ? String(args.from) : '')
        setTo(args.to ? String(args.to) : '')
      },
    },
    clearFilters: {
      description: 'Clear all pipelines-list filters (role and dates).',
      params: [],
      run: () => { setRole(''); setFrom(''); setTo('') },
    },
  }), [navigate])
  const apGetState = useCallback(() => {
    const all = pipelinesRef.current
    const f = filterRef.current
    const matching = all.filter((p) => {
      if (f.role && p.role !== f.role) return false
      if (f.from && (p.createdAt || '') < f.from) return false
      if (f.to && (p.createdAt || '') > `${f.to}T23:59:59.999Z`) return false
      return true
    })
    return {
      screen: 'pipelines',
      availableRoles: [...new Set(all.map((p) => p.role).filter(Boolean))].sort(),
      filters: { role: f.role || 'All roles', from: f.from || null, to: f.to || null },
      matchingCount: matching.length,
      totalCount: all.length,
    }
  }, [])
  const apOpts = useMemo(() => ({ getState: apGetState }), [apGetState])
  useAutopilotActions('pipelines', apActions, apOpts)
  const hasFilters = !!(role || from || to)
  const filtered = useMemo(() => (pipelines ?? []).filter((p) => {
    if (role && p.role !== role) return false
    if (from && (p.createdAt || '') < from) return false
    if (to && (p.createdAt || '') > `${to}T23:59:59.999Z`) return false
    return true
  }), [pipelines, role, from, to])

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <PageHeader
        kicker="Hiring Pipelines"
        title="Pipelines"
        description="Multi-round hiring flows. Pick one to see candidate progression."
      />

      <Card className="p-4 mb-6">
        <div className="flex flex-wrap items-end gap-3">
          <Select
            label="Role"
            value={role}
            onChange={(e) => setRole(e.target.value)}
            options={[{ value: '', label: 'All roles' }, ...roles.map((r) => ({ value: r, label: r }))]}
          />
          <div className="flex flex-col gap-1.5">
            <label className="field-label">From</label>
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="input-base h-9 text-sm" />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="field-label">To</label>
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="input-base h-9 text-sm" />
          </div>
          {hasFilters && (
            <button
              onClick={() => { setRole(''); setFrom(''); setTo('') }}
              className="h-9 px-3 rounded-lg text-sm font-medium text-neutral-500 hover:text-neutral-800 hover:bg-neutral-100"
            >
              Clear
            </button>
          )}
        </div>
      </Card>

      {isLoading ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[0, 1, 2].map((i) => <Skeleton key={i} className="h-24" />)}
        </div>
      ) : isError ? (
        <Card className="p-0">
          <EmptyState icon="⚠️" title="Couldn’t load pipelines" description="Please retry." />
        </Card>
      ) : filtered.length === 0 ? (
        <Card className="p-0">
          <EmptyState
            icon="🧬"
            title={hasFilters ? 'No pipelines match these filters' : 'No pipelines yet'}
            description="Create one from Sessions → Invite → Multiple Rounds."
          />
        </Card>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {filtered.map((p: Pipeline) => (
            <Link key={p.id} to={`/pipelines/${p.id}`}>
              <Card hover className="p-4">
                <div className="font-semibold text-neutral-800">{p.role}</div>
                <div className="text-sm text-neutral-500 mt-1">
                  {p.rounds.length} round{p.rounds.length === 1 ? '' : 's'} · {p.rounds.map((r) => r.name).join(' → ')}
                </div>
                <div className="mt-2 text-xs text-neutral-400">Created {new Date(p.createdAt).toLocaleDateString()}</div>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

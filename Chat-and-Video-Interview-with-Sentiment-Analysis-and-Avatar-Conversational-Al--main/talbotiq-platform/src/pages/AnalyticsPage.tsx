import { useState } from 'react'
import { useConversations } from '@/hooks/useTavus'
import { Card, Badge, Button, Skeleton, StatCard, PageHeader } from '@/components/ui'
import { cn } from '@/components/ui'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line, AreaChart, Area } from 'recharts'
import type { ConversationStatus } from '@/types/tavus.types'
import { formatDistanceToNow } from 'date-fns'

const WEEKLY = Array.from({ length: 7 }, (_, i) => ({ day: ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][i], interviews: Math.floor(Math.random() * 12) + 2, avgScore: Math.floor(Math.random() * 20) + 70 }))
const TOOLTIP = { background: '#fff', border: '1px solid #e2e8f0', borderRadius: 8, color: '#0f172a', fontSize: 12, boxShadow: '0 4px 12px rgba(0,0,0,0.08)' }

export default function AnalyticsPage() {
  const [filter, setFilter] = useState<ConversationStatus | 'all'>('all')
  const [search, setSearch] = useState('')
  const { data: all, isLoading } = useConversations()
  const [selected, setSelected] = useState<Set<string>>(new Set())

  const filtered = (all ?? []).filter(c =>
    (filter === 'all' || c.status === filter) &&
    (!search || c.conversation_name?.toLowerCase().includes(search.toLowerCase()) || c.conversation_id.includes(search)),
  )

  return (
    <div className="max-w-[1400px] mx-auto px-6 py-8">
      <PageHeader
        kicker="Platform Analytics"
        title="AI Interview Dashboard"
        description="Comprehensive candidate intelligence powered by conversational AI and behavioral analytics."
      />

      {/* KPI row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Total Candidates" value="345" sub="+12 this week" trend="up" color="#0d5c3a" />
        <StatCard label="Interviews Completed" value="218" sub="+8 today" trend="up" color="#0d5c3a" />
        <StatCard label="Average Match Score" value="84%" sub="+2.1% vs last week" trend="up" color="#d97706" />
        <StatCard label="Recommended" value="92" sub="26.7% acceptance rate" trend="up" color="#0d5c3a" />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-6">
        <Card className="p-5">
          <div className="mb-4">
            <p className="text-sm font-semibold text-neutral-800">Interviews This Week</p>
            <p className="text-xs text-neutral-400 mt-0.5">Daily session volume</p>
          </div>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={WEEKLY} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#f1f5f9" />
              <XAxis dataKey="day" tick={{ fill: '#94a3b8', fontSize: 11, fontFamily: 'Inter' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fill: '#94a3b8', fontSize: 11, fontFamily: 'Inter' }} axisLine={false} tickLine={false} />
              <Tooltip contentStyle={TOOLTIP} />
              <Bar dataKey="interviews" fill="#0d5c3a" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="p-5">
          <div className="mb-4">
            <p className="text-sm font-semibold text-neutral-800">Average Score Trend</p>
            <p className="text-xs text-neutral-400 mt-0.5">Weekly rolling average</p>
          </div>
          <ResponsiveContainer width="100%" height={180}>
            <AreaChart data={WEEKLY} margin={{ top: 0, right: 0, left: -20, bottom: 0 }}>
              <defs>
                <linearGradient id="scoreGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#0d5c3a" stopOpacity={0.12} />
                  <stop offset="95%" stopColor="#0d5c3a" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="2 4" stroke="#f1f5f9" />
              <XAxis dataKey="day" tick={{ fill: '#94a3b8', fontSize: 11, fontFamily: 'Inter' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fill: '#94a3b8', fontSize: 11, fontFamily: 'Inter' }} axisLine={false} tickLine={false} domain={[60, 100]} />
              <Tooltip contentStyle={TOOLTIP} />
              <Area type="monotone" dataKey="avgScore" stroke="#0d5c3a" strokeWidth={2} fill="url(#scoreGrad)" dot={{ fill: '#0d5c3a', r: 3, strokeWidth: 0 }} />
            </AreaChart>
          </ResponsiveContainer>
        </Card>
      </div>

      {/* Sessions table */}
      <Card>
        <div className="px-6 py-4 border-b border-border flex items-center justify-between gap-4 flex-wrap">
          <div>
            <p className="text-sm font-semibold text-neutral-800">All Sessions</p>
            <p className="text-xs text-neutral-400 mt-0.5">{(all ?? []).length} total sessions</p>
          </div>
          <div className="flex items-center gap-3 flex-wrap">
            {/* Search */}
            <div className="relative">
              <svg className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-400" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search sessions…"
                className="input-base pl-8 h-9 w-52 text-sm" />
            </div>
            {/* Filters */}
            <div className="flex bg-neutral-100 rounded-lg p-1 gap-0.5">
              {(['all', 'active', 'ended', 'error'] as const).map(s => (
                <button key={s} onClick={() => setFilter(s)}
                  className={cn('px-3 h-7 rounded-md text-xs font-semibold capitalize transition-all', filter === s ? 'bg-white text-neutral-900 shadow-xs' : 'text-neutral-500 hover:text-neutral-700')}>
                  {s}
                </button>
              ))}
            </div>
            {selected.size > 0 && <Button variant="danger" size="sm" onClick={() => setSelected(new Set())}>Delete {selected.size}</Button>}
          </div>
        </div>

        {isLoading ? (
          <div className="p-4 space-y-2">{[...Array(5)].map((_, i) => <Skeleton key={i} className="h-12" />)}</div>
        ) : !filtered.length ? (
          <div className="py-16 text-center">
            <p className="text-sm text-neutral-400">{search ? 'No results match your search.' : 'No sessions yet. Launch your first interview from Setup.'}</p>
          </div>
        ) : (
          <>
            {/* Table header */}
            <div className="px-6 py-2 border-b border-border grid grid-cols-[24px_1fr_120px_120px_120px] gap-4 bg-neutral-50">
              {['', 'Session', 'Status', 'Replica', 'Created'].map((h, i) => (
                <span key={i} className="text-xs font-semibold text-neutral-400 uppercase tracking-wide">{h}</span>
              ))}
            </div>
            <div className="divide-y divide-border">
              {filtered.map(c => (
                <div key={c.conversation_id} className={cn('px-6 py-3 grid grid-cols-[24px_1fr_120px_120px_120px] gap-4 items-center hover:bg-neutral-50 transition-colors', selected.has(c.conversation_id) && 'bg-primary-50/40')}>
                  <input type="checkbox" checked={selected.has(c.conversation_id)}
                    onChange={() => setSelected(s => { const n = new Set(s); n.has(c.conversation_id) ? n.delete(c.conversation_id) : n.add(c.conversation_id); return n })} />
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-neutral-800 truncate">{c.conversation_name ?? '(unnamed session)'}</p>
                    <p className="text-xs text-neutral-400 font-mono truncate">{c.conversation_id}</p>
                  </div>
                  <Badge variant={c.status === 'active' ? 'success' : c.status === 'error' ? 'danger' : 'neutral'}>{c.status}</Badge>
                  <p className="text-xs text-neutral-500 font-mono truncate">{c.replica_id?.slice(0, 12)}…</p>
                  <p className="text-xs text-neutral-400 whitespace-nowrap">{formatDistanceToNow(new Date(c.created_at), { addSuffix: true })}</p>
                </div>
              ))}
            </div>
          </>
        )}
      </Card>
    </div>
  )
}

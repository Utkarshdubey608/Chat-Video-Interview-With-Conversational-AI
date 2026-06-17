import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
} from 'recharts'
import type { EmotionSnapshot, EmotionCategory } from '@/types/hume.types'

const SERIES: { key: EmotionCategory; color: string; label: string }[] = [
  { key: 'positive_high', color: '#00c9a7', label: 'Energy' },
  { key: 'positive_calm', color: '#7c83fd', label: 'Calm' },
  { key: 'cognitive',     color: '#e8b84b', label: 'Focus' },
  { key: 'negative',      color: '#ff6b6b', label: 'Stress' },
]

interface Props {
  timeline: EmotionSnapshot[]
  questionTimestamps?: number[]
}

export function EmotionTimeline({ timeline }: Props) {
  if (timeline.length === 0) {
    return (
      <div className="h-80 flex items-center justify-center text-neutral-400 text-sm">
        No timeline data yet
      </div>
    )
  }

  const origin = timeline[0]?.timestamp ?? 0
  const data = timeline.map(s => ({
    t: Math.round(s.timestamp - origin),
    ...Object.fromEntries(
      SERIES.map(sr => [sr.key, Math.round(s.categoryScores[sr.key] * 100)])
    ),
  }))

  // Dynamic Y ceiling so lines are spread across the full chart height
  const maxVal = Math.max(
    ...data.flatMap(d => SERIES.map(sr => (d as Record<string, number>)[sr.key] ?? 0)),
    10,
  )
  const yMax = Math.ceil((maxVal * 1.4) / 5) * 5

  return (
    <div className="w-full h-80">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 20, left: -4, bottom: 4 }}>
          <CartesianGrid stroke="#e8ede9" strokeDasharray="4 4" vertical={false} />
          <XAxis
            dataKey="t"
            tick={{ fill: '#94a3b8', fontSize: 11 }}
            tickFormatter={v => `${v}s`}
            axisLine={{ stroke: '#dde8e0' }}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: '#94a3b8', fontSize: 11 }}
            domain={[0, yMax]}
            tickFormatter={v => `${v}%`}
            axisLine={false}
            tickLine={false}
            tickCount={6}
          />
          <Tooltip
            contentStyle={{
              background: '#ffffff',
              border: '1px solid #dde8e0',
              borderRadius: 8,
              color: '#0f172a',
              fontSize: 12,
              boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
            }}
            formatter={(v: number, name: string) => {
              const s = SERIES.find(s => s.key === name)
              return [`${v}%`, s?.label ?? name]
            }}
            labelFormatter={v => `t = ${v}s`}
          />
          <Legend
            iconType="circle"
            iconSize={8}
            wrapperStyle={{ paddingTop: 8, fontSize: 12 }}
            formatter={(value) => {
              const s = SERIES.find(s => s.key === value)
              return <span style={{ color: '#64748b' }}>{s?.label ?? value}</span>
            }}
          />
          {SERIES.map(sr => (
            <Line
              key={sr.key}
              type="monotone"
              dataKey={sr.key}
              stroke={sr.color}
              strokeWidth={2.5}
              dot={false}
              activeDot={{ r: 4, strokeWidth: 0, fill: sr.color }}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

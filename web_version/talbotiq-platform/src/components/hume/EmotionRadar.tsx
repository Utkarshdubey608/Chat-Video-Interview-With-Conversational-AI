import {
  RadarChart, PolarGrid, PolarAngleAxis, Radar, ResponsiveContainer, Tooltip,
} from 'recharts'
import type { EmotionCategory } from '@/types/hume.types'

const LABELS: Record<EmotionCategory, string> = {
  positive_high: 'Energy',
  positive_calm: 'Calm',
  cognitive: 'Focus',
  social: 'Social',
  negative: 'Stress',
  disengagement: 'Disengaged',
}

// Shared chart chrome — one grid colour, one tick colour, one tooltip shell
// across every emotion visualisation.
const GRID = '#E7E2F2'
const TICK = { fill: '#7C7595', fontSize: 11, fontFamily: 'Figtree, system-ui, sans-serif' }
const TOOLTIP_STYLE = {
  background: '#ffffff',
  border: '1px solid #E7E2F2',
  borderRadius: 10,
  color: '#1B0B3B',
  fontSize: 12,
  fontFamily: 'Figtree, system-ui, sans-serif',
  boxShadow: '0 8px 24px -4px rgb(27 11 59 / 0.10), 0 4px 10px -4px rgb(27 11 59 / 0.06)',
} as const

interface Props {
  categoryScores: Record<EmotionCategory, number>
  color?: string
}

export function EmotionRadar({ categoryScores, color = '#6B2BE0' }: Props) {
  const data = (Object.keys(LABELS) as EmotionCategory[]).map(k => ({
    subject: LABELS[k],
    score: Math.round(categoryScores[k] * 100),
    fullMark: 100,
  }))

  return (
    <div className="w-full h-56">
      <ResponsiveContainer width="100%" height="100%">
        <RadarChart data={data}>
          <PolarGrid stroke={GRID} />
          <PolarAngleAxis dataKey="subject" tick={TICK} />
          <Radar
            dataKey="score"
            stroke={color}
            fill={color}
            fillOpacity={0.16}
            strokeWidth={2}
          />
          <Tooltip
            cursor={{ stroke: GRID }}
            contentStyle={TOOLTIP_STYLE}
            labelStyle={{ color: '#1B0B3B', fontWeight: 600 }}
            formatter={(v: number) => [`${v}%`, 'Score']}
          />
        </RadarChart>
      </ResponsiveContainer>
    </div>
  )
}

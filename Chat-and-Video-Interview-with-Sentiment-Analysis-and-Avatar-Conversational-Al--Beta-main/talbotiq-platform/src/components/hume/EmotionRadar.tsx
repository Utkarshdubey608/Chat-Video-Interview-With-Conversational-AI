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

interface Props {
  categoryScores: Record<EmotionCategory, number>
  color?: string
}

export function EmotionRadar({ categoryScores, color = '#00c9a7' }: Props) {
  const data = (Object.keys(LABELS) as EmotionCategory[]).map(k => ({
    subject: LABELS[k],
    score: Math.round(categoryScores[k] * 100),
    fullMark: 100,
  }))

  return (
    <div className="w-full h-56 animate-radar-expand">
      <ResponsiveContainer width="100%" height="100%">
        <RadarChart data={data}>
          <PolarGrid stroke="#e2e8f0" />
          <PolarAngleAxis
            dataKey="subject"
            tick={{ fill: '#64748b', fontSize: 11, fontFamily: 'DM Sans' }}
          />
          <Radar
            dataKey="score"
            stroke={color}
            fill={color}
            fillOpacity={0.18}
            strokeWidth={2}
          />
          <Tooltip
            contentStyle={{
              background: '#ffffff',
              border: '1px solid #e2e8f0',
              borderRadius: 8,
              color: '#0f172a',
              fontSize: 12,
              boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
            }}
            formatter={(v: number) => [`${v}%`, 'Score']}
          />
        </RadarChart>
      </ResponsiveContainer>
    </div>
  )
}

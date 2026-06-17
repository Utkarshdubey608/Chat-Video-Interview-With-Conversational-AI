import type { EmotionCategory } from '@/types/hume.types'

const METADATA: Record<EmotionCategory, { label: string; color: string; icon: string; description: string }> = {
  positive_high: { label: 'Energy & Enthusiasm',   color: '#00c9a7', icon: '⚡', description: 'Excitement, pride, admiration' },
  positive_calm: { label: 'Calm & Contentment',    color: '#7c83fd', icon: '🌊', description: 'Serenity, satisfaction, awe' },
  cognitive:     { label: 'Cognitive Engagement',  color: '#e8b84b', icon: '🧠', description: 'Concentration, curiosity, focus' },
  social:        { label: 'Social Presence',        color: '#00c9a7', icon: '🤝', description: 'Empathy, warmth, connection' },
  negative:      { label: 'Stress & Anxiety',       color: '#ff6b6b', icon: '⚠️', description: 'Anxiety, confusion, distress' },
  disengagement: { label: 'Disengagement',          color: '#4a6080', icon: '😶', description: 'Boredom, doubt, awkwardness' },
}

interface Props {
  categoryScores: Record<EmotionCategory, number>
}

export function EmotionCategoryPanel({ categoryScores }: Props) {
  const sorted = (Object.keys(categoryScores) as EmotionCategory[])
    .sort((a, b) => categoryScores[b] - categoryScores[a])

  return (
    <div className="grid grid-cols-2 gap-3">
      {sorted.map(cat => {
        const meta = METADATA[cat]
        const pct = Math.round(categoryScores[cat] * 100)
        return (
          <div
            key={cat}
            className="rounded-xl bg-hume-card border border-hume-border p-3 flex flex-col gap-2"
          >
            <div className="flex items-center justify-between">
              <span className="text-sm text-neutral-700">{meta.icon} {meta.label}</span>
              <span
                className="text-sm font-mono font-bold animate-count-up"
                style={{ color: meta.color }}
              >
                {pct}%
              </span>
            </div>
            <div className="h-1.5 rounded-full bg-hume-border overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-700"
                style={{ width: `${pct}%`, background: meta.color }}
              />
            </div>
            <p className="text-2xs text-hume-muted">{meta.description}</p>
          </div>
        )
      })}
    </div>
  )
}

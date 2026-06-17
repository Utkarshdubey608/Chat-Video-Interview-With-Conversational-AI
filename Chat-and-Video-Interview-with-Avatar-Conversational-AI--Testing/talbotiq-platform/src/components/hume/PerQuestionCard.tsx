import type { QuestionEmotionSummary } from '@/types/hume.types'
import { EmotionRadar } from './EmotionRadar'

const DOMINANT_COLOR: Record<string, string> = {
  Energy: '#00c9a7', Excitement: '#00c9a7', Enthusiasm: '#00c9a7',
  Calm: '#7c83fd', Serenity: '#7c83fd', Contentment: '#7c83fd',
  Anxiety: '#ff6b6b', Stress: '#ff6b6b', Confusion: '#ff6b6b',
}

interface Props {
  summary: QuestionEmotionSummary
  index: number
}

export function PerQuestionCard({ summary, index }: Props) {
  const dominantColor = DOMINANT_COLOR[summary.dominant] ?? '#e8b84b'

  return (
    <div className="rounded-2xl bg-hume-card border border-hume-border p-5 space-y-4 animate-slide-in-right">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-2xs font-mono text-hume-muted mb-1">QUESTION {index + 1}</p>
          <p className="text-sm text-hume-text leading-relaxed line-clamp-2">
            {summary.questionText}
          </p>
        </div>
        <span
          className="shrink-0 px-2 py-1 rounded-lg text-2xs font-mono font-semibold"
          style={{ background: `${dominantColor}22`, color: dominantColor }}
        >
          {summary.dominant}
        </span>
      </div>

      <EmotionRadar categoryScores={summary.avgCategoryScores} color={dominantColor} />

      <div className="flex flex-wrap gap-1.5">
        {summary.topEmotions.slice(0, 4).map(e => (
          <span
            key={e.name}
            className="px-2 py-0.5 rounded-full text-2xs bg-hume-surface border border-hume-border text-hume-text"
          >
            {e.name} · {Math.round(e.score * 100)}%
          </span>
        ))}
      </div>
    </div>
  )
}

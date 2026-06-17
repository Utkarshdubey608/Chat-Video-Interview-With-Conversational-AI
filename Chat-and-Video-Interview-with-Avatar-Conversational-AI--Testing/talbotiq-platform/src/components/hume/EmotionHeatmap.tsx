import type { QuestionEmotionSummary, EmotionCategory } from '@/types/hume.types'

const CATS: EmotionCategory[] = [
  'positive_high', 'positive_calm', 'cognitive', 'social', 'negative', 'disengagement',
]
const CAT_LABELS: Record<EmotionCategory, string> = {
  positive_high: 'Energy',
  positive_calm: 'Calm',
  cognitive:     'Focus',
  social:        'Social',
  negative:      'Stress',
  disengagement: 'Disengaged',
}

function heatColor(score: number, cat: EmotionCategory): string {
  const t = score // 0..1
  if (cat === 'negative' || cat === 'disengagement') {
    // red scale
    const r = Math.round(120 + t * 135)
    const g = Math.round(40 - t * 20)
    const b = Math.round(40 - t * 10)
    return `rgba(${r},${g},${b},${0.15 + t * 0.7})`
  }
  if (cat === 'positive_high' || cat === 'positive_calm') {
    const r = Math.round(t * 20)
    const g = Math.round(100 + t * 101)
    const b = Math.round(100 + t * 67)
    return `rgba(${r},${g},${b},${0.15 + t * 0.7})`
  }
  // indigo/gold
  const r = Math.round(100 + t * 132)
  const g = Math.round(100 + t * 83)
  const b = Math.round(150 + t * 75)
  return `rgba(${r},${g},${b},${0.15 + t * 0.7})`
}

interface Props {
  perQuestion: QuestionEmotionSummary[]
}

export function EmotionHeatmap({ perQuestion }: Props) {
  if (perQuestion.length === 0) {
    return (
      <div className="h-32 flex items-center justify-center text-hume-muted text-sm">
        No data
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-2xs">
        <thead>
          <tr>
            <th className="text-left text-hume-muted font-normal pb-2 pr-3 w-28">Question</th>
            {CATS.map(c => (
              <th key={c} className="text-center text-hume-muted font-normal pb-2 px-1">
                {CAT_LABELS[c]}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {perQuestion.map((q, i) => (
            <tr key={i} className="border-t border-hume-border">
              <td className="py-2 pr-3 text-hume-text truncate max-w-[7rem]">
                Q{i + 1}
              </td>
              {CATS.map(cat => {
                const score = q.avgCategoryScores[cat]
                return (
                  <td
                    key={cat}
                    className="text-center py-1.5 px-1 font-mono rounded"
                    style={{ background: heatColor(score, cat), color: '#0f172a' }}
                  >
                    {Math.round(score * 100)}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

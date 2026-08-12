interface Props {
  score: number // 0-100
  label?: string
  size?: number
}

export function SentimentArc({ score, label = 'Sentiment Score', size = 140 }: Props) {
  const radius = size / 2 - 14
  const circumference = Math.PI * radius // semicircle
  const offset = circumference * (1 - score / 100)

  const color =
    score >= 70 ? '#00c9a7' :
    score >= 45 ? '#e8b84b' :
    '#ff6b6b'

  return (
    <div className="flex flex-col items-center gap-2">
      <svg width={size} height={size / 2 + 16} style={{ overflow: 'visible' }}>
        {/* Track */}
        <path
          d={`M ${14} ${size / 2} A ${radius} ${radius} 0 0 1 ${size - 14} ${size / 2}`}
          fill="none"
          stroke="#e2e8f0"
          strokeWidth={10}
          strokeLinecap="round"
        />
        {/* Progress */}
        <path
          d={`M ${14} ${size / 2} A ${radius} ${radius} 0 0 1 ${size - 14} ${size / 2}`}
          fill="none"
          stroke={color}
          strokeWidth={10}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 1s ease, stroke 0.5s ease' }}
        />
        {/* Score text */}
        <text
          x={size / 2}
          y={size / 2 - 4}
          textAnchor="middle"
          fill={color}
          fontSize={size / 4}
          fontWeight="700"
          fontFamily="IBM Plex Mono"
        >
          {score}
        </text>
        <text
          x={size / 2}
          y={size / 2 + 14}
          textAnchor="middle"
          fill="#94a3b8"
          fontSize={11}
          fontFamily="DM Sans"
        >
          / 100
        </text>
      </svg>
      <p className="text-xs text-hume-muted">{label}</p>
    </div>
  )
}

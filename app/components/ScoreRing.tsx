export function scoreTone(score: number) {
  if (score >= 70)
    return { stroke: 'var(--color-moss-400)', text: 'text-moss-300', word: 'Clean' }
  if (score >= 40)
    return { stroke: 'var(--color-honey-400)', text: 'text-honey-300', word: 'Moderate' }
  return { stroke: 'var(--color-clay-400)', text: 'text-clay-300', word: 'Avoid' }
}

/** Small clean-score ring used on food rows and search results. */
export default function ScoreRing({ score, size = 44 }: { score: number; size?: number }) {
  const { stroke, text } = scoreTone(score)
  const r = 15.9
  const circ = 2 * Math.PI * r
  const dash = (score / 100) * circ
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 36 36" width={size} height={size} className="-rotate-90">
        <circle
          cx="18"
          cy="18"
          r={r}
          fill="none"
          stroke="rgba(255,255,255,0.08)"
          strokeWidth="3"
        />
        <circle
          cx="18"
          cy="18"
          r={r}
          fill="none"
          stroke={stroke}
          strokeWidth="3"
          strokeDasharray={`${dash} ${circ - dash}`}
          strokeLinecap="round"
        />
      </svg>
      <span
        className={`absolute inset-0 flex items-center justify-center font-mono text-xs tabular-nums ${text}`}
      >
        {score}
      </span>
    </div>
  )
}

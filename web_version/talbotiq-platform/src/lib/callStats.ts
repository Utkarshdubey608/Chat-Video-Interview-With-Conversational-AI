/**
 * Dev-gated live-call diagnostics — activate by opening the interview with
 * `?callstats=1`. Zero cost when not enabled (no timers, no listeners).
 *
 * Two signals, both logged to the console:
 *  1. Transport health every 5s from the wrapped Daily instance
 *     (`getNetworkStats()`): quality score, round-trip time, receive
 *     bitrate/packet-loss — this is what distinguishes "network jitter"
 *     lag from "device overloaded" lag.
 *  2. Turn latency: time from the candidate's last utterance event to the
 *     interviewer's next utterance event (the app-perceived response gap).
 *
 * Read the numbers against targets: RTT < 150ms and loss < 2% is healthy;
 * turn gaps of 600-1500ms are normal for Tavus CVI; > 3s points at the
 * pipeline, sustained loss/RTT points at the network, low quality score with
 * good RTT points at local CPU/GPU contention.
 */

export function callStatsEnabled(): boolean {
  try {
    return new URLSearchParams(window.location.search).has('callstats')
  } catch {
    return false
  }
}

type DailyLikeCall = {
  getNetworkStats?: () => Promise<{
    quality?: number
    threshold?: string
    stats?: { latest?: Record<string, number> }
  }>
}

export type CallStatsHandle = {
  /** Feed utterance events; logs the candidate→interviewer response gap. */
  markUtterance: (role: 'interviewer' | 'candidate') => void
  stop: () => void
}

const NOOP: CallStatsHandle = { markUtterance: () => {}, stop: () => {} }

export function startCallStats(call: unknown, label = 'call'): CallStatsHandle {
  if (!callStatsEnabled()) return NOOP

  const c = call as DailyLikeCall
  let lastCandidateAt = 0

  const interval = window.setInterval(() => {
    c.getNetworkStats?.()
      .then((s) => {
        const l = s?.stats?.latest ?? {}
        // eslint-disable-next-line no-console
        console.info(
          `[${label}] quality=${s?.quality ?? '?'} (${s?.threshold ?? '?'}) ` +
            `rtt=${Math.round(((l.networkRoundTripTime as number) ?? 0) * 1000)}ms ` +
            `recv=${Math.round(((l.videoRecvBitsPerSecond as number) ?? 0) / 1000)}kbps ` +
            `loss(recv)=${(((l.totalRecvPacketLoss as number) ?? (l.videoRecvPacketLoss as number) ?? 0) * 100).toFixed(1)}%`,
        )
      })
      .catch(() => { /* stats are best-effort */ })
  }, 5000)

  return {
    markUtterance: (role) => {
      const now = performance.now()
      if (role === 'candidate') {
        lastCandidateAt = now
      } else if (lastCandidateAt) {
        // eslint-disable-next-line no-console
        console.info(`[${label}] turn gap (candidate→interviewer): ${Math.round(now - lastCandidateAt)}ms`)
        lastCandidateAt = 0
      }
    },
    stop: () => window.clearInterval(interval),
  }
}

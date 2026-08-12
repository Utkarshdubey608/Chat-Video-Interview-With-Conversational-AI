import { useEffect, useRef } from 'react'
import { MicOff, VideoOff } from 'lucide-react'
import type { DailyParticipant } from '@daily-co/daily-js'

interface Props {
  participant: DailyParticipant
  /** Force-mute this tile's own audio playback (independent of the
   *  participant's mic state — e.g. avoiding double-audio for a tile that's
   *  already covered by another audio element). Local tiles never get an
   *  <audio> element regardless of this prop (self-audio would echo). */
  muted?: boolean
  label?: string
}

/**
 * One video tile for the live two-way call — attaches a Daily participant's
 * persistent video (and, for remote tiles, audio) tracks to plain
 * <video>/<audio> elements. Styled like the existing CameraRecorder/
 * AvatarStage video frame so the two-way room matches the rest of the
 * interview experience.
 */
export function DailyVideoTile({ participant, muted = false, label }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const audioRef = useRef<HTMLAudioElement>(null)

  const videoTrack = participant.tracks.video.persistentTrack ?? null
  const audioTrack = participant.tracks.audio.persistentTrack ?? null
  const isLocal = participant.local

  // (Re)attach the video track whenever it changes (track-started/-stopped,
  // participant swap, subscription changes, etc).
  useEffect(() => {
    const el = videoRef.current
    if (!el) return
    el.srcObject = videoTrack ? new MediaStream([videoTrack]) : null
  }, [videoTrack])

  // Remote tiles only — the local tile never plays its own mic back out.
  useEffect(() => {
    if (isLocal) return
    const el = audioRef.current
    if (!el) return
    el.srcObject = audioTrack ? new MediaStream([audioTrack]) : null
  }, [audioTrack, isLocal])

  // Daily's persistentTrack often survives a camera toggle-off (the track
  // object sticks around even though it's not producing frames), so gating
  // on "no track" as well as state kept this stuck showing stale video
  // instead of the placeholder. 'sendable'/'loading' aren't off — only these
  // three states mean the camera itself isn't producing playable video.
  const videoState = participant.tracks.video.state
  const camOff = videoState === 'off' || videoState === 'blocked' || videoState === 'interrupted'
  const micMuted = !audioTrack || participant.tracks.audio.state === 'off'
  const name = label ?? (participant.user_name || (isLocal ? 'You' : 'Guest'))

  return (
    <div className="relative aspect-video w-full overflow-hidden rounded-xl border border-border bg-neutral-900">
      <video ref={videoRef} autoPlay muted={isLocal} playsInline className="h-full w-full object-cover" />
      {!isLocal && <audio ref={audioRef} autoPlay muted={muted} />}
      {camOff && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-neutral-900 text-white/50">
          <VideoOff size={22} />
          <span className="text-xs">Camera off</span>
        </div>
      )}
      <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-medium text-white/90">
        {name}
        {micMuted && <MicOff size={11} className="text-red-400" />}
      </span>
    </div>
  )
}

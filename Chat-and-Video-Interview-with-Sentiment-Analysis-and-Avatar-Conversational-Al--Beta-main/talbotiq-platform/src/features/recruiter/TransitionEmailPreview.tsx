import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Maximize2, X } from 'lucide-react'
import { renderTransitionEmail, type TransitionRenderVars } from '@shared/inviteEmail'
import type { EmailKind, InviteEmailTemplate } from '@shared/types'

const EMAIL_WIDTH = 600 // the fixed email layout width (matches the shell)

export type TransitionEmailKind = Exclude<EmailKind, 'invite'>

/**
 * Kind-aware sibling of `EmailPreview` (invite-only) for the transition emails —
 * advance / selected / rejection. Uses the SAME shared renderer
 * (`renderTransitionEmail`) as the server send path, so what the recruiter previews
 * is exactly what goes out. Only 'advance' carries a locked interview link + "exact
 * email" note (see `renderTransitionEmail`'s `includeLink`/`includeNote` flags); for
 * 'selected'/'rejection' no link/candidate email is needed, so the caller passes none.
 *
 * Mirrors `EmailPreview`'s scaled inline layout (CSS zoom keeps the fixed 600px email
 * legible without clipping) plus an Outlook-style "Full preview" reading pane.
 */
export function TransitionEmailPreview({
  draft,
  kind,
  vars,
  candidateEmail,
  origin,
}: {
  draft: InviteEmailTemplate
  kind: TransitionEmailKind
  vars: TransitionRenderVars
  candidateEmail?: string
  origin?: string
}) {
  const [full, setFull] = useState(false)

  // advance is the only kind whose render needs a link + candidate email; a sample
  // is used for both since the real per-candidate values don't exist until send time.
  const sampleEmail = candidateEmail || `${(vars.candidate_name || 'candidate').toLowerCase().replace(/[^a-z0-9]+/g, '.')}@example.com`
  const sampleLink = `${origin || 'https://app.talbotiq.com'}/take/sample-next-round`

  let subject = '(no subject)'
  let html = '<p style="padding:16px;color:#dc2626">Preview unavailable</p>'
  try {
    const rendered = renderTransitionEmail(
      draft, kind, vars,
      kind === 'advance' ? { interviewLink: sampleLink, candidateEmail: sampleEmail } : {},
    )
    subject = rendered.subject || '(no subject)'
    html = rendered.html
  } catch { /* keep fallback */ }

  const fromLine = draft.sender.verifiedSenderEmail
    ? `${draft.sender.fromName || ''} <${draft.sender.verifiedSenderEmail}>`.trim()
    : `${draft.sender.fromName || 'TalbotIQ'} (server default sender)`

  // Scale the fixed-width email to fit the inline column (CSS zoom keeps layout height).
  const boxRef = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(1)
  useLayoutEffect(() => {
    const el = boxRef.current
    if (!el) return
    const measure = () => setScale(Math.min(1, (el.clientWidth - 2) / EMAIL_WIDTH))
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  return (
    <>
      <div className="overflow-hidden rounded-xl border border-border">
        <div className="flex items-center justify-between border-b border-border bg-neutral-50 px-3 py-2 text-xs text-neutral-500">
          <span className="font-semibold uppercase tracking-wide">Preview</span>
          <button type="button" onClick={() => setFull(true)}
            className="inline-flex items-center gap-1.5 rounded-md px-2 py-1 font-medium text-primary-700 hover:bg-primary-50">
            <Maximize2 size={13} /> Full preview
          </button>
        </div>
        {/* Scaled-to-fit inline render — the whole email, never clipped. */}
        <div ref={boxRef} className="max-h-[420px] overflow-y-auto overflow-x-hidden bg-[#eff5f0]">
          <div style={{ zoom: scale }} dangerouslySetInnerHTML={{ __html: html }} />
        </div>
      </div>

      {full && (
        <FullPreview
          html={html}
          from={fromLine}
          to={kind === 'advance' ? sampleEmail : 'each recipient (see list above)'}
          subject={subject}
          onClose={() => setFull(false)}
        />
      )}
    </>
  )
}

/** Outlook-style reading pane: From / To / Subject header + the email at natural size. */
function FullPreview({
  html, from, to, subject, onClose,
}: { html: string; from: string; to: string; subject: string; onClose: () => void }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { window.removeEventListener('keydown', onKey); document.body.style.overflow = prev }
  }, [onClose])

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-neutral-900/50 backdrop-blur-[2px] animate-fade-in" onClick={onClose}>
      <div className="mx-auto my-4 flex h-[calc(100vh-2rem)] w-full max-w-4xl flex-col overflow-hidden rounded-2xl bg-white shadow-xl animate-slide-up"
        onClick={(e) => e.stopPropagation()}>
        {/* Email client header */}
        <div className="flex items-start justify-between gap-4 border-b border-border px-6 py-4">
          <div className="min-w-0">
            <h3 className="truncate text-lg font-bold text-neutral-900">{subject}</h3>
            <p className="mt-1 truncate text-sm text-neutral-500"><span className="font-medium text-neutral-700">From:</span> {from}</p>
            <p className="truncate text-sm text-neutral-500"><span className="font-medium text-neutral-700">To:</span> {to}</p>
          </div>
          <button type="button" onClick={onClose} aria-label="Close preview"
            className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700">
            <X size={18} />
          </button>
        </div>
        {/* Rendered email body, natural size, on the email's own canvas */}
        <div className="flex-1 overflow-auto bg-[#eff5f0]">
          <div dangerouslySetInnerHTML={{ __html: html }} />
        </div>
      </div>
    </div>
  )
}

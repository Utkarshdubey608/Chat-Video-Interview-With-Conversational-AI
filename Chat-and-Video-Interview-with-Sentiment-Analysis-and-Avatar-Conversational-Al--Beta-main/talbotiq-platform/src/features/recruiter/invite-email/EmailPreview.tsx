import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Maximize2, X } from 'lucide-react'
import { renderInviteEmail, renderTemplate, type InviteRenderVars } from '@shared/inviteEmail'
import type { InviteEmailTemplate } from '@shared/types'

const EMAIL_WIDTH = 600 // the fixed email layout width (matches the shell)

/**
 * Live preview of the invite email. Uses the SAME shared renderer as the server
 * send path, so what the recruiter sees is what goes out. The interview link shown
 * here is a representative sample — the real per-candidate link is generated at send
 * time (it doesn't exist until the interview doc is created).
 *
 * The inline preview scales the fixed 600px email down to fit its column (no
 * clipping); "Full preview" opens an Outlook-style reading pane at natural size.
 */
export function EmailPreview({
  draft,
  vars,
  candidateEmail,
  origin,
}: {
  draft: InviteEmailTemplate
  vars: InviteRenderVars
  candidateEmail: string
  origin: string
}) {
  const [full, setFull] = useState(false)

  const sampleLink = `${origin || 'https://app.talbotiq.com'}/take/sample-link-${'x'.repeat(10)}`
  let html = '<p style="padding:16px;color:#dc2626">Preview unavailable</p>'
  try {
    html = renderInviteEmail(draft, vars, { interviewLink: sampleLink, candidateEmail }).html
  } catch { /* keep fallback */ }
  const subject = renderTemplate(draft.subject, { ...vars, interview_link: sampleLink }) || '(no subject)'
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
        <div ref={boxRef} className="max-h-[520px] overflow-y-auto overflow-x-hidden bg-[#eff5f0]">
          <div style={{ zoom: scale }} dangerouslySetInnerHTML={{ __html: html }} />
        </div>
      </div>

      {full && (
        <FullPreview
          html={html}
          from={fromLine}
          to={candidateEmail}
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

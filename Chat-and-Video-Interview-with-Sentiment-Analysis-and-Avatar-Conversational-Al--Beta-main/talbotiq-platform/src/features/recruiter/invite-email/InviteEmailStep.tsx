import { useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { AlertTriangle, Send, Save, Copy, Trash2, Info, Link2, UploadCloud } from 'lucide-react'
import { Button, Input, Select, cn } from '@/components/ui'
import { inviteEmailTemplatesApi, invitesApi } from '@/lib/api'
import { useAuth } from '@/features/auth/AuthProvider'
import { validateLockedTokens, type InviteRenderVars } from '@shared/inviteEmail'
import type { InviteEmailTemplate } from '@shared/types'
import { RichTextEditor } from './RichTextEditor'
import { EmailPreview } from './EmailPreview'

const QK = ['invite-email-templates'] as const

export function sampleName(email: string): string {
  const local = (email.split('@')[0] || '').replace(/[._-]+/g, ' ').trim()
  return local ? local.replace(/\b\w/g, (c) => c.toUpperCase()) : 'there'
}

/**
 * Step 4 — configure, preview, and test the invite email before sending. The
 * per-candidate link + "use this exact email" note are injected + locked at send
 * time; this UI can restyle around them but the interview link token must remain
 * (a warning + disabled Next enforces it).
 */
export function InviteEmailStep({
  draft,
  onChange,
  role,
  sampleEmail,
  origin,
}: {
  draft: InviteEmailTemplate
  onChange: (d: InviteEmailTemplate) => void
  role: string
  sampleEmail: string
  origin: string
}) {
  const qc = useQueryClient()
  const { user, firebaseUser } = useAuth()
  const recruiterName = user?.displayName || firebaseUser?.displayName || firebaseUser?.email || 'A recruiter'

  const templates = useQuery({ queryKey: QK, queryFn: () => inviteEmailTemplatesApi.list() })
  const senders = useQuery({ queryKey: ['invite-senders'], queryFn: invitesApi.senders })
  const [selectedId, setSelectedId] = useState('')
  const [busy, setBusy] = useState(false)
  const [testing, setTesting] = useState(false)
  const [uploadingLogo, setUploadingLogo] = useState(false)
  const [logoBroken, setLogoBroken] = useState(false)
  const logoInput = useRef<HTMLInputElement>(null)

  const set = <K extends keyof InviteEmailTemplate>(key: K, val: InviteEmailTemplate[K]) =>
    onChange({ ...draft, [key]: val })
  const setSender = (patch: Partial<InviteEmailTemplate['sender']>) =>
    onChange({ ...draft, sender: { ...draft.sender, ...patch } })
  const setCta = (patch: Partial<InviteEmailTemplate['cta']>) =>
    onChange({ ...draft, cta: { ...draft.cta, ...patch } })
  const setBranding = (patch: Partial<InviteEmailTemplate['branding']>) =>
    onChange({ ...draft, branding: { ...draft.branding, ...patch } })

  const locked = validateLockedTokens(draft.subject, draft.bodyHtml)

  const vars: InviteRenderVars = {
    candidate_name: sampleName(sampleEmail),
    role: role || 'the role',
    recruiter_name: recruiterName,
    company: draft.branding.companyName || 'TalbotIQ',
    deadline: draft.deadlineText || '—',
  }

  const emailConfig = (): Partial<InviteEmailTemplate> => ({
    name: draft.name,
    sender: draft.sender,
    subject: draft.subject,
    bodyHtml: draft.bodyHtml,
    cta: draft.cta,
    branding: draft.branding,
    deadlineText: draft.deadlineText,
  })

  const loadTemplate = (id: string) => {
    const t = templates.data?.find((x) => x.id === id)
    if (t) { onChange(t); setSelectedId(id) }
  }

  const saveAsNew = async () => {
    const name = window.prompt('Save invite email as…', draft.name || 'My invite email')
    if (!name) return
    setBusy(true)
    try {
      const created = await inviteEmailTemplatesApi.create({ ...emailConfig(), name, isDefault: false })
      await qc.invalidateQueries({ queryKey: QK })
      setSelectedId(created.id)
      onChange(created)
      toast.success('Template saved')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Could not save') } finally { setBusy(false) }
  }
  const updateSaved = async () => {
    if (!selectedId) return
    setBusy(true)
    try {
      const updated = await inviteEmailTemplatesApi.update(selectedId, emailConfig())
      await qc.invalidateQueries({ queryKey: QK })
      onChange(updated)
      toast.success('Template updated')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Could not update') } finally { setBusy(false) }
  }
  const duplicate = async () => {
    if (!selectedId) return
    setBusy(true)
    try {
      const copy = await inviteEmailTemplatesApi.duplicate(selectedId)
      await qc.invalidateQueries({ queryKey: QK })
      setSelectedId(copy.id); onChange(copy)
      toast.success('Duplicated')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Could not duplicate') } finally { setBusy(false) }
  }
  const remove = async () => {
    if (!selectedId) return
    if (!window.confirm('Delete this saved invite email template?')) return
    setBusy(true)
    try {
      await inviteEmailTemplatesApi.remove(selectedId)
      await qc.invalidateQueries({ queryKey: QK })
      setSelectedId('')
      toast.success('Deleted')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Could not delete') } finally { setBusy(false) }
  }

  const sendTest = async () => {
    if (!locked.ok) { toast.error(`Add the ${locked.missing.join(', ')} token before testing`); return }
    setTesting(true)
    try {
      const res = await invitesApi.test({ role, origin, emailConfig: emailConfig() })
      if (res.sent) toast.success(`Test sent to ${res.to}`)
      else if (res.dryRun) toast(`Dry-run: mailer not configured (would send to ${res.to})`, { icon: 'ℹ️' })
      else toast.error(res.error || 'Test failed')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Test failed') } finally { setTesting(false) }
  }

  const insertLinkToken = () =>
    set('bodyHtml', `${draft.bodyHtml}<p>{{interview_link}}</p>`)

  const onUploadLogo = async (file: File | null) => {
    if (!file) return
    setUploadingLogo(true)
    try {
      const { url } = await invitesApi.uploadLogo(file)
      setLogoBroken(false)
      setBranding({ logoUrl: url })
      toast.success('Logo uploaded')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Could not upload logo')
    } finally {
      setUploadingLogo(false)
      if (logoInput.current) logoInput.current.value = ''
    }
  }

  const senderList = senders.data?.senders ?? []
  const brevoReady = senders.data?.brevoReady ?? false

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
      {/* ── Config column ── */}
      <div className="space-y-5">
        {/* Template picker */}
        <div className="rounded-xl border border-border bg-white p-4">
          <label className="field-label mb-1.5 block">Saved templates</label>
          <div className="flex flex-wrap items-center gap-2">
            <select
              className="input-base h-10 flex-1 min-w-[160px] appearance-none"
              value={selectedId}
              onChange={(e) => (e.target.value ? loadTemplate(e.target.value) : setSelectedId(''))}
            >
              <option value="">— New (unsaved) —</option>
              {templates.data?.map((t) => (
                <option key={t.id} value={t.id}>{t.name}{t.isDefault ? ' (default)' : ''}</option>
              ))}
            </select>
            {selectedId
              ? <Button size="sm" variant="secondary" icon={<Save size={14} />} loading={busy} onClick={updateSaved}>Update</Button>
              : <Button size="sm" variant="secondary" icon={<Save size={14} />} loading={busy} onClick={saveAsNew}>Save</Button>}
            <Button size="sm" variant="ghost" icon={<Copy size={14} />} disabled={!selectedId || busy} onClick={duplicate}>Duplicate</Button>
            <Button size="sm" variant="ghost" icon={<Trash2 size={14} />} disabled={!selectedId || busy} onClick={remove}>Delete</Button>
            {selectedId && <Button size="sm" variant="ghost" onClick={saveAsNew} disabled={busy}>Save as new</Button>}
          </div>
        </div>

        {/* Sender */}
        <div className="rounded-xl border border-border bg-white p-4 space-y-3">
          <p className="text-sm font-semibold text-neutral-800">Sender</p>
          {brevoReady && senderList.length > 0 ? (
            <Select
              label="From address (Brevo verified sender)"
              value={draft.sender.verifiedSenderEmail}
              onChange={(e) => setSender({ verifiedSenderEmail: e.target.value })}
              options={[{ value: '', label: 'Use server default (MAIL_FROM)' }, ...senderList.map((s) => ({ value: s.email, label: `${s.name ? s.name + ' — ' : ''}${s.email}${s.active ? '' : ' (inactive)'}` }))]}
            />
          ) : (
            <Input
              label="From address (verified sender)"
              placeholder="talent@yourco.com"
              value={draft.sender.verifiedSenderEmail}
              onChange={(e) => setSender({ verifiedSenderEmail: e.target.value })}
              hint="Must be a Brevo-verified sender. Leave blank to use the server default."
            />
          )}
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input label="From name" value={draft.sender.fromName} onChange={(e) => setSender({ fromName: e.target.value })} />
            <Input label="Reply-to (optional)" value={draft.sender.replyTo || ''} onChange={(e) => setSender({ replyTo: e.target.value })} />
          </div>
          <div className="flex items-start gap-2 rounded-lg bg-neutral-50 p-2.5 text-xs text-neutral-500">
            <Info size={14} className="mt-0.5 flex-shrink-0 text-neutral-400" />
            <span>
              You can only send from a Brevo-verified sender. Branded sending from your own domain
              (instead of the default <span className="font-mono">…@brevosend.com</span> subdomain) requires
              adding the domain + SPF/DKIM verification in Brevo → Senders, Domains.
              {!brevoReady && ' Set BREVO_API_KEY on the server to load your verified senders here.'}
            </span>
          </div>
        </div>

        {/* Subject + body */}
        <div className="rounded-xl border border-border bg-white p-4 space-y-3">
          <Input label="Subject" value={draft.subject} onChange={(e) => set('subject', e.target.value)} hint="Supports variables, e.g. {{role}}." />
          <div>
            <label className="field-label mb-1.5 block">Body</label>
            <RichTextEditor value={draft.bodyHtml} onChange={(html) => set('bodyHtml', html)} />
          </div>
          {!locked.ok && (
            <div className="flex items-center justify-between gap-2 rounded-lg border border-warning-border bg-warning-bg p-2.5 text-xs text-amber-800">
              <span className="flex items-center gap-2"><AlertTriangle size={14} /> The interview link ({locked.missing.join(', ')}) is required and can’t be removed.</span>
              <Button size="xs" variant="secondary" icon={<Link2 size={12} />} onClick={insertLinkToken}>Insert link</Button>
            </div>
          )}
        </div>

        {/* CTA + branding */}
        <div className="rounded-xl border border-border bg-white p-4 space-y-3">
          <p className="text-sm font-semibold text-neutral-800">Button & branding</p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input label="Button text" value={draft.cta.text} onChange={(e) => setCta({ text: e.target.value })} />
            <ColorField label="Button colour" value={draft.cta.color} onChange={(v) => setCta({ color: v })} />
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input label="Company name" value={draft.branding.companyName} onChange={(e) => setBranding({ companyName: e.target.value })} />
            <ColorField label="Accent colour" value={draft.branding.accentColor} onChange={(v) => setBranding({ accentColor: v })} />
          </div>
          <div>
            <label className="field-label mb-1.5 block">Logo (optional)</label>
            <div className="flex items-center gap-2">
              <input
                className="input-base h-10 flex-1"
                placeholder="https://…/logo.png"
                value={draft.branding.logoUrl || ''}
                onChange={(e) => { setLogoBroken(false); setBranding({ logoUrl: e.target.value }) }}
              />
              <input ref={logoInput} type="file" accept="image/*" className="hidden" onChange={(e) => void onUploadLogo(e.target.files?.[0] ?? null)} />
              <Button size="sm" variant="secondary" icon={<UploadCloud size={14} />} loading={uploadingLogo} onClick={() => logoInput.current?.click()}>Upload</Button>
            </div>
            {draft.branding.logoUrl && (
              <div className="mt-2 flex items-center gap-2">
                <img
                  key={draft.branding.logoUrl}
                  src={draft.branding.logoUrl}
                  alt="Logo preview"
                  className="h-8 max-w-[160px] rounded border border-border object-contain"
                  onLoad={() => setLogoBroken(false)}
                  onError={() => setLogoBroken(true)}
                />
                {logoBroken && <span className="text-xs text-danger">This URL didn’t load as an image — use a public direct image link, or Upload a file.</span>}
              </div>
            )}
            <p className="mt-1 text-xs text-neutral-400">
              Paste a <span className="font-medium">public, direct</span> image URL, or Upload a file (we host it). Google Drive/Docs links and <span className="font-mono">localhost</span> URLs won’t load in emails.
            </p>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Input label="Footer" value={draft.branding.footer || ''} onChange={(e) => setBranding({ footer: e.target.value })} />
            <Input label="Deadline text (optional)" placeholder="e.g. Please complete within 5 days" value={draft.deadlineText || ''} onChange={(e) => set('deadlineText', e.target.value)} />
          </div>
        </div>

        <div className="flex justify-end">
          <Button variant="secondary" icon={<Send size={15} />} loading={testing} onClick={sendTest}>Send test to me</Button>
        </div>
      </div>

      {/* ── Preview column ── */}
      <div className="space-y-2 lg:sticky lg:top-4 lg:self-start">
        <EmailPreview draft={draft} vars={vars} candidateEmail={sampleEmail} origin={origin} />
        <p className="px-1 text-xs text-neutral-400">
          Sample data shown. The real per-candidate link is generated per recipient at send time.
        </p>
      </div>
    </div>
  )
}

/** A small native colour picker + hex text pair styled to the design system. */
function ColorField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <label className="field-label mb-1.5 block">{label}</label>
      <div className="flex items-center gap-2">
        <input type="color" value={/^#[0-9a-fA-F]{6}$/.test(value) ? value : '#0d5c3a'} onChange={(e) => onChange(e.target.value)}
          className="h-10 w-12 cursor-pointer rounded-lg border border-border bg-white p-1" />
        <input value={value} onChange={(e) => onChange(e.target.value)} className={cn('input-base h-10 flex-1 font-mono text-xs')} />
      </div>
    </div>
  )
}

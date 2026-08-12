import { useEffect, useState } from 'react'
import toast from 'react-hot-toast'
import { Card, Button } from '@/components/ui'
import { settingsApi } from '@/lib/api'
import type { AppSettingsStatus, GeminiModel } from '@shared/types'

/**
 * Server-backed Gemini key management. Unlike the other (browser-local) keys
 * on this page, the Gemini key is stored on the server and never returned to
 * the client — we only ever show a masked hint.
 */
export function GeminiKeyCard() {
  const [status, setStatus] = useState<AppSettingsStatus | null>(null)
  const [value, setValue] = useState('')
  const [show, setShow] = useState(false)
  const [model, setModel] = useState<GeminiModel>('gemini-2.5-flash')
  const [busy, setBusy] = useState(false)

  const refresh = () => settingsApi.status().then(setStatus).catch(() => {})
  useEffect(() => { refresh() }, [])
  useEffect(() => { if (status?.model) setModel(status.model as GeminiModel) }, [status?.model])

  const save = async () => {
    if (!value.trim()) { toast.error('Enter a Gemini API key'); return }
    setBusy(true)
    try {
      setStatus(await settingsApi.saveGeminiKey(value.trim(), model))
      setValue('')
      toast.success('Gemini key saved')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Save failed')
    } finally {
      setBusy(false)
    }
  }

  const clear = async () => {
    setBusy(true)
    try {
      setStatus(await settingsApi.clearGeminiKey())
      toast.success('Saved Gemini key removed')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card className="mb-5 divide-y divide-border">
      <div className="px-6 py-4">
        <h3 className="text-sm font-semibold text-neutral-800">Gemini API Key (AI Interview)</h3>
        <p className="mt-0.5 text-xs text-neutral-400">
          Used server-side for résumé question generation &amp; scoring. Stored on the server, never sent back to the browser.
        </p>
      </div>
      <div className="space-y-4 px-6 py-5">
        <div className="flex items-center gap-2 text-xs">
          <span className="field-label">Status</span>
          {status?.geminiKeySet ? (
            <span className="flex items-center gap-1.5 font-medium text-success">
              <span className="live-dot" /> Set ({status.source}) · <span className="font-mono">{status.geminiKeyMasked}</span> · {status.model}
            </span>
          ) : (
            <span className="font-medium text-amber-600">Not configured — using heuristic fallback</span>
          )}
        </div>

        <div>
          <label className="field-label mb-1.5 block">{status?.geminiKeySet ? 'Replace key' : 'API key'}</label>
          <div className="relative">
            <input
              type={show ? 'text' : 'password'}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder="AIza…"
              className="input-base pr-14 font-mono text-xs"
            />
            <button type="button" onClick={() => setShow((s) => !s)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-medium text-neutral-400 hover:text-neutral-700">
              {show ? 'Hide' : 'Show'}
            </button>
          </div>
          <p className="mt-1 text-xs text-neutral-400">Get one at aistudio.google.com → API keys. Keys start with “AIza”.</p>
        </div>

        <div className="flex items-center justify-between">
          <div className="flex gap-1">
            {(['gemini-2.5-flash', 'gemini-2.5-pro'] as GeminiModel[]).map((m) => (
              <button key={m} onClick={() => setModel(m)}
                className={`rounded-md px-2.5 py-1 text-xs font-semibold ${model === m ? 'bg-primary-700 text-white' : 'text-neutral-500 hover:bg-neutral-100'}`}>
                {m.replace('gemini-2.5-', '')}
              </button>
            ))}
          </div>
          <div className="flex gap-2">
            {status?.source === 'saved' && (
              <Button variant="secondary" size="sm" onClick={clear} disabled={busy}>Remove</Button>
            )}
            <Button size="sm" loading={busy} onClick={save}>Save key</Button>
          </div>
        </div>
      </div>
    </Card>
  )
}

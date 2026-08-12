import { useEffect, useState } from 'react'
import toast from 'react-hot-toast'
import { Button, Card, Toggle, PageHeader, Input } from '@/components/ui'
import { useAppStore } from '@/store/useAppStore'
import { tavus } from '@/services/tavus'
import { settingsApi } from '@/lib/api'
import { GeminiKeyCard } from '@/features/recruiter/GeminiKeyCard'

/**
 * Settings — AI Avatar Screening credentials, hybrid model.
 *
 * • Tavus key: a real runtime key entered here (never compiled into the bundle).
 * • Gemini: configured via the shared GeminiKeyCard (server-side) — the same key
 *   powers both recruiter scoring and the avatar ATS analysis. (Frozen module,
 *   reused read-only.)
 * • Deepgram / Hume / AWS Rekognition: SERVER-side secrets set via the server
 *   environment (see .env.example). Shown here as read-only status — no key ever
 *   entered or tested from the browser.
 */
const SERVER_KEYS = [
  { key: 'deepgram',    label: 'Deepgram Nova-3',  env: 'DEEPGRAM_API_KEY',                      hint: 'Live transcription, speaking pace & filler analysis' },
  { key: 'hume',        label: 'Hume AI',          env: 'HUME_API_KEY',                          hint: 'Voice prosody & emotional-intelligence (batch)' },
  { key: 'rekognition', label: 'AWS Rekognition',  env: 'AWS_ACCESS_KEY_ID / SECRET / REGION',   hint: 'Facial expression & engagement analysis' },
] as const

type StatusMap = { deepgram: boolean; hume: boolean; gemini: boolean; rekognition: boolean }

export default function SettingsPage() {
  const store = useAppStore()
  const [tavusKey, setTavusKeyLocal] = useState('')
  const [showTavus, setShowTavus] = useState(false)
  const [webhook, setWebhook] = useState('')
  const [connState, setConnState] = useState<'idle' | 'testing' | 'ok' | 'fail'>('idle')
  const [status, setStatus] = useState<StatusMap | null>(null)
  const [whiteLabelMode, setWhiteLabelMode] = useState(false)
  const [gdprAuto, setGdprAuto] = useState(true)
  const [multiLang, setMultiLang] = useState(false)

  useEffect(() => {
    setTavusKeyLocal(store.tavusKey)
    setWebhook(store.webhookUrl)
    fetch('/api/avatar/status').then(r => (r.ok ? r.json() : null)).then(setStatus).catch(() => setStatus(null))
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function testConnection() {
    if (!tavusKey) { toast.error('Enter your Tavus API key first'); return }
    setConnState('testing')
    try {
      tavus.setKey(tavusKey)
      const reps = await tavus.listReplicas()
      setConnState('ok')
      toast.success(`Connected — ${Array.isArray(reps) ? reps.length : 0} replica(s) found`)
    } catch (e) {
      setConnState('fail')
      toast.error((e as Error).message ?? 'Connection failed')
    }
  }

  const [saving, setSaving] = useState(false)
  async function save() {
    setSaving(true)
    // Local (this browser): recruiter dashboard pages call Tavus with this key.
    store.setTavusKey(tavusKey)
    store.setWebhookUrl(webhook)
    tavus.setKey(tavusKey)
    // Server (single source of truth): applies the key EVERYWHERE at once —
    // candidate avatar interviews + any previously-applied Setup config.
    try {
      await settingsApi.saveTavusKey(tavusKey.trim())
      toast.success('Settings saved — Tavus key applied everywhere')
    } catch (e) {
      toast.error(`Saved locally, but the server sync failed: ${(e as Error).message}`)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="max-w-2xl mx-auto px-6 py-8">
      <PageHeader
        kicker="Platform Config"
        title="Settings"
        description="Manage API credentials, webhook endpoints, and platform behaviour."
        action={<Button onClick={() => void save()} loading={saving}>Save Settings</Button>}
      />

      {/* Tavus (runtime key) */}
      <Card className="mb-5 divide-y divide-border">
        <div className="px-6 py-4">
          <h3 className="text-sm font-semibold text-neutral-800">Tavus — Avatar</h3>
          <p className="text-xs text-neutral-400 mt-0.5">The single source of truth for your Tavus key — saving applies it everywhere at once (this browser, candidate interviews, and any applied avatar config). Never compiled into the app bundle.</p>
        </div>
        <div className="px-6 py-5 space-y-4">
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="field-label">Tavus API Key</label>
              {connState === 'ok' && <span className="text-xs font-medium text-success flex items-center gap-1.5"><span className="live-dot" />Connected</span>}
              {connState === 'fail' && <span className="text-xs font-medium text-danger">✕ Failed</span>}
              {connState === 'testing' && <span className="text-xs font-medium text-neutral-400 animate-pulse">Testing…</span>}
            </div>
            <div className="relative">
              <input
                type={showTavus ? 'text' : 'password'}
                value={tavusKey}
                onChange={e => setTavusKeyLocal(e.target.value)}
                placeholder="ta_xxxxxxxxxxxxxxxxxxxxxxxx"
                className="input-base font-mono text-xs pr-14"
              />
              <button type="button" onClick={() => setShowTavus(s => !s)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-medium text-neutral-400 hover:text-neutral-700 transition-colors">
                {showTavus ? 'Hide' : 'Show'}
              </button>
            </div>
            <p className="text-xs text-neutral-400 mt-1">Required — from tavus.io → Settings → API Keys</p>
          </div>
          <Button variant="outline" size="sm" onClick={testConnection} loading={connState === 'testing'}>
            Test Tavus Connection
          </Button>
        </div>
      </Card>

      {/* Gemini — shared server key (frozen recruiter module, reused) */}
      <div className="mb-5">
        <GeminiKeyCard />
      </div>

      {/* Server-managed analysis providers (hybrid — keys live in server env) */}
      <Card className="mb-5 divide-y divide-border">
        <div className="px-6 py-4">
          <h3 className="text-sm font-semibold text-neutral-800">Analysis Providers — Server-Side</h3>
          <p className="text-xs text-neutral-400 mt-0.5">These keys stay on the server (set in its environment) and are proxied via <span className="font-mono">/api/avatar/*</span> — never exposed to the browser.</p>
        </div>
        <div className="px-6 py-5 space-y-4">
          {SERVER_KEYS.map(f => {
            const configured = !!status?.[f.key as keyof StatusMap]
            return (
              <div key={f.key} className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-sm font-medium text-neutral-800">{f.label}</p>
                  <p className="text-xs text-neutral-400 mt-0.5">{f.hint}</p>
                  {!configured && <p className="text-[11px] text-neutral-400 mt-1">Set <span className="font-mono">{f.env}</span> in the server environment.</p>}
                </div>
                <span className={`flex-shrink-0 flex items-center gap-1.5 text-xs font-medium ${configured ? 'text-success' : 'text-neutral-400'}`}>
                  <span className={`w-2 h-2 rounded-full ${configured ? 'bg-success' : 'bg-neutral-300'}`} />
                  {status === null ? 'Checking…' : configured ? 'Configured' : 'Not configured'}
                </span>
              </div>
            )
          })}
        </div>
      </Card>

      {/* Webhook */}
      <Card className="mb-5 divide-y divide-border">
        <div className="px-6 py-4">
          <h3 className="text-sm font-semibold text-neutral-800">Webhook Configuration</h3>
          <p className="text-xs text-neutral-400 mt-0.5">Receives real-time conversation events from Tavus</p>
        </div>
        <div className="px-6 py-5">
          <Input
            label="Webhook URL"
            type="url"
            value={webhook}
            onChange={e => setWebhook(e.target.value)}
            placeholder="https://api.yourcompany.com/webhook/tavus"
            hint="Receives: conversation.started, conversation.ended, transcription, participant events, errors"
          />
        </div>
      </Card>

      {/* Multi-tenant */}
      <Card className="mb-8 divide-y divide-border">
        <div className="px-6 py-4">
          <h3 className="text-sm font-semibold text-neutral-800">Platform Settings</h3>
          <p className="text-xs text-neutral-400 mt-0.5">Multi-tenant and compliance configuration</p>
        </div>
        <div className="px-6 py-2">
          <Toggle checked={whiteLabelMode} onChange={setWhiteLabelMode} label="White-label Mode" description="Remove TalbotIQ branding from candidate-facing screens" />
          <Toggle checked={gdprAuto} onChange={setGdprAuto} label="GDPR Auto-Purge" description="Automatically delete video and biometric data after 30 days" />
          <Toggle checked={multiLang} onChange={setMultiLang} label="Multi-language Avatar" description="Enable multilingual question delivery via Tavus" />
        </div>
      </Card>

      <div className="flex gap-3">
        <Button onClick={save}>Save Settings</Button>
        <Button variant="secondary" onClick={() => { if (confirm('Reset Tavus key and local preferences?')) { localStorage.removeItem('talbotiq-store'); location.reload() } }}>
          Reset to Defaults
        </Button>
      </div>
    </div>
  )
}

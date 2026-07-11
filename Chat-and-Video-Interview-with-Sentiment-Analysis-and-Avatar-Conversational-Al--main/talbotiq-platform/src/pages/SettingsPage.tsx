import { useState, useEffect } from 'react'
import toast from 'react-hot-toast'
import { Button, Card, Toggle, PageHeader, Input } from '@/components/ui'
import { useAppStore } from '@/store/useAppStore'
import { tavus } from '@/services/tavus'
import { GeminiKeyCard } from '@/features/recruiter/GeminiKeyCard'

const API_FIELDS = [
  { key: 'tavus',     label: 'Tavus API Key',         placeholder: 'ta_xxxxxxxxxxxxxxxxxxxxxxxx', hint: 'Required — from tavus.io → Settings → API Keys' },
  { key: 'deepgram',  label: 'Deepgram API Key',       placeholder: 'Token xxxxxxxxxxxxxxxx',      hint: 'Optional — transcription & pace analysis (Nova-2)' },
  { key: 'hume',      label: 'Hume AI API Key',        placeholder: 'hume_xxxxxxxx',              hint: 'Optional — voice prosody & sentiment scoring' },
  { key: 'aws',       label: 'AWS Access Key',         placeholder: 'AKIA…',                      hint: 'Optional — Rekognition facial analysis' },
  { key: 'anthropic', label: 'Anthropic / Claude Key', placeholder: 'sk-ant-api03-…',             hint: 'Optional — AI scorecard synthesis' },
] as const

export default function SettingsPage() {
  const store = useAppStore()
  const [keys, setKeys] = useState({ tavus: '', deepgram: '', hume: '', aws: '', anthropic: '', webhook: '' })
  const [show, setShow] = useState<Record<string, boolean>>({})
  const [connState, setConnState] = useState<'idle' | 'testing' | 'ok' | 'fail'>('idle')
  const [whiteLabelMode, setWhiteLabelMode] = useState(false)
  const [gdprAuto, setGdprAuto] = useState(true)
  const [multiLang, setMultiLang] = useState(false)

  useEffect(() => {
    setKeys({ tavus: store.tavusKey, deepgram: store.deepgramKey, hume: store.humeKey, aws: store.awsKey, anthropic: store.anthropicKey, webhook: store.webhookUrl })
  }, [])

  async function testConnection() {
    if (!keys.tavus) { toast.error('Enter your Tavus API key first'); return }
    setConnState('testing')
    try {
      tavus.setKey(keys.tavus)
      const reps = await tavus.listReplicas()
      setConnState('ok')
      toast.success(`Connected — ${Array.isArray(reps) ? reps.length : 0} replica(s) found`)
    } catch (e: any) {
      setConnState('fail')
      toast.error(e.message ?? 'Connection failed')
    }
  }

  function save() {
    store.setTavusKey(keys.tavus); store.setDeepgramKey(keys.deepgram)
    store.setHumeKey(keys.hume); store.setAwsKey(keys.aws)
    store.setAnthropicKey(keys.anthropic); store.setWebhookUrl(keys.webhook)
    tavus.setKey(keys.tavus)
    toast.success('Settings saved')
  }

  return (
    <div className="max-w-2xl mx-auto px-6 py-8">
      <PageHeader
        kicker="Platform Config"
        title="Settings"
        description="Manage API credentials, webhook endpoints, and platform behaviour."
        action={<Button onClick={save}>Save Settings</Button>}
      />

      {/* API Keys */}
      <Card className="mb-5 divide-y divide-border">
        <div className="px-6 py-4">
          <h3 className="text-sm font-semibold text-neutral-800">API Credentials</h3>
          <p className="text-xs text-neutral-400 mt-0.5">Keys are stored locally in your browser and never sent to TalbotIQ servers.</p>
        </div>
        <div className="px-6 py-5 space-y-5">
          {API_FIELDS.map(f => (
            <div key={f.key}>
              <div className="flex items-center justify-between mb-1.5">
                <label className="field-label">{f.label}</label>
                {f.key === 'tavus' && connState === 'ok' && <span className="text-xs font-medium text-success flex items-center gap-1.5"><span className="live-dot" />Connected</span>}
                {f.key === 'tavus' && connState === 'fail' && <span className="text-xs font-medium text-danger">✕ Failed</span>}
                {f.key === 'tavus' && connState === 'testing' && <span className="text-xs font-medium text-neutral-400 animate-pulse">Testing…</span>}
              </div>
              <div className="relative">
                <input
                  type={show[f.key] ? 'text' : 'password'}
                  value={keys[f.key as keyof typeof keys]}
                  onChange={e => setKeys(p => ({ ...p, [f.key]: e.target.value }))}
                  placeholder={f.placeholder}
                  className="input-base font-mono text-xs pr-14"
                />
                <button type="button" onClick={() => setShow(p => ({ ...p, [f.key]: !p[f.key] }))}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-medium text-neutral-400 hover:text-neutral-700 transition-colors">
                  {show[f.key] ? 'Hide' : 'Show'}
                </button>
              </div>
              <p className="text-xs text-neutral-400 mt-1">{f.hint}</p>
            </div>
          ))}
          <Button variant="outline" size="sm" onClick={testConnection} loading={connState === 'testing'}>
            Test Tavus Connection
          </Button>
        </div>
      </Card>

      {/* Gemini key — server-side (AI Interview module) */}
      <GeminiKeyCard />

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
            value={keys.webhook}
            onChange={e => setKeys(p => ({ ...p, webhook: e.target.value }))}
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
        <Button variant="secondary" onClick={() => { if (confirm('Reset all settings and clear stored API keys?')) { localStorage.removeItem('talbotiq-store'); location.reload() } }}>
          Reset to Defaults
        </Button>
      </div>
    </div>
  )
}

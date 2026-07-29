import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { UploadCloud, FileText, Loader2, AlertTriangle, User } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  busy?: boolean
  onUpload: (file: File, fullName: string) => Promise<void> | void
}

/**
 * Pre-interview step: FIRST the candidate tells us their full name (the AI
 * interviewer addresses them by it throughout the interview), THEN they upload
 * the résumé their questions are tailored to.
 */
export function ResumeUpload({ branding, busy, onUpload }: Props) {
  const reduce = useReducedMotion()
  const [fullName, setFullName] = useState('')
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)

  const nameOk = fullName.trim().length >= 2

  const submit = async () => {
    if (!file || !nameOk) return
    setError(null)
    try {
      await onUpload(file, fullName.trim())
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed')
    }
  }

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Tell us about you</h1>
      <p className="mt-2 text-sm text-neutral-500">
        Your interviewer will address you by name, and your questions will be tailored to your experience.
      </p>

      {/* 1 — full name (asked BEFORE the résumé) */}
      <div className="mt-6">
        <label htmlFor="candidate-full-name" className="mb-1.5 flex items-center gap-1.5 text-sm font-semibold text-neutral-800">
          <User size={15} style={{ color: branding.accentColor }} /> Your full name
        </label>
        <input
          id="candidate-full-name"
          type="text"
          value={fullName}
          onChange={(e) => { setFullName(e.target.value); setError(null) }}
          placeholder="e.g. Arjun Kumar"
          autoFocus
          autoComplete="name"
          className="w-full rounded-xl border border-border bg-white px-3 py-2.5 text-sm text-neutral-900 outline-none transition-colors placeholder:text-neutral-400 focus:border-neutral-400"
        />
        <p className="mt-1 text-xs text-neutral-400">The AI interviewer uses this to address you during the interview.</p>
      </div>

      {/* 2 — résumé */}
      <div className="mt-5">
        <p className="mb-1.5 text-sm font-semibold text-neutral-800">Your résumé</p>
        <label
          className="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-border bg-neutral-50 p-8 text-center transition-colors hover:border-neutral-300"
        >
          <input
            type="file"
            accept=".pdf,.docx,.txt,application/pdf,text/plain"
            className="hidden"
            onChange={(e) => { setFile(e.target.files?.[0] ?? null); setError(null) }}
          />
          {file ? (
            <span className="flex items-center gap-2 text-sm font-medium text-neutral-800">
              <FileText size={18} style={{ color: branding.accentColor }} /> {file.name}
            </span>
          ) : (
            <>
              <UploadCloud size={28} className="text-neutral-400" />
              <span className="text-sm font-medium text-neutral-600">Click to choose a file</span>
              <span className="text-xs text-neutral-400">PDF · DOCX · TXT (max 8 MB)</span>
            </>
          )}
        </label>
      </div>

      {error && (
        <div className="mt-4 flex items-start gap-2 rounded-lg border border-danger-border bg-danger-bg p-3 text-sm text-danger">
          <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" /> {error}
        </div>
      )}

      <button
        onClick={submit}
        disabled={!file || !nameOk || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        {busy ? <><Loader2 size={18} className="animate-spin" /> Preparing your questions…</> : 'Continue'}
      </button>
      {!nameOk && file && (
        <p className="mt-2 text-center text-xs text-neutral-400">Enter your full name above to continue.</p>
      )}
    </motion.div>
  )
}

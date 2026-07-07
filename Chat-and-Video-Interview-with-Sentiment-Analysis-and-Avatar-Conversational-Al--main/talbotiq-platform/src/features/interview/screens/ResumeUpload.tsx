import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { UploadCloud, FileText, Loader2, AlertTriangle } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  busy?: boolean
  onUpload: (file: File) => Promise<void> | void
}

export function ResumeUpload({ branding, busy, onUpload }: Props) {
  const reduce = useReducedMotion()
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    if (!file) return
    setError(null)
    try {
      await onUpload(file)
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
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Upload your résumé</h1>
      <p className="mt-2 text-sm text-neutral-500">
        Your questions will be tailored to your experience. PDF, DOCX, or TXT — it’s used only to prepare your
        interview.
      </p>

      <label
        className="mt-6 flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-border bg-neutral-50 p-8 text-center transition-colors hover:border-neutral-300"
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

      {error && (
        <div className="mt-4 flex items-start gap-2 rounded-lg border border-danger-border bg-danger-bg p-3 text-sm text-danger">
          <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" /> {error}
        </div>
      )}

      <button
        onClick={submit}
        disabled={!file || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        {busy ? <><Loader2 size={18} className="animate-spin" /> Preparing your questions…</> : 'Continue'}
      </button>
    </motion.div>
  )
}

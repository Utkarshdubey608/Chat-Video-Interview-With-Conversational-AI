import type { ReactNode } from 'react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  progress?: { current: number; total: number }
  live?: boolean
  children: ReactNode
}

/** Chrome-minimal candidate layout: brand bar + progress pill + centered stage. */
export function InterviewShell({ branding, progress, live, children }: Props) {
  return (
    <div className="min-h-screen bg-background font-sans flex flex-col">
      <header className="border-b border-border bg-white/70 backdrop-blur-sm">
        <div className="mx-auto flex h-14 max-w-4xl items-center justify-between gap-4 px-5">
          <div className="flex items-center gap-2.5 min-w-0">
            {branding.logoUrl ? (
              <img src={branding.logoUrl} alt="" className="h-6 w-6 rounded object-contain" />
            ) : (
              <span
                className="flex h-6 w-6 items-center justify-center rounded text-xs font-bold text-white"
                style={{ background: branding.accentColor }}
              >
                {branding.companyName.charAt(0)}
              </span>
            )}
            <span className="truncate text-sm font-bold tracking-tight text-neutral-800">
              {branding.companyName}
            </span>
          </div>
          <div className="flex items-center gap-3">
            {live && (
              <span className="flex items-center gap-1.5 rounded-full border border-[#b3e9cd] bg-[#f0faf5] px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider text-[#0d5c3a]">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#16a34a]" />
                Live
              </span>
            )}
            {progress && progress.total > 0 && (
              <span className="rounded-full bg-neutral-100 px-3 py-1 text-xs font-semibold text-neutral-600 tabular-nums">
                Question {progress.current} of {progress.total}
              </span>
            )}
          </div>
        </div>
      </header>

      <main className="flex flex-1 items-center justify-center px-5 py-8">
        <div className="w-full max-w-2xl">{children}</div>
      </main>
    </div>
  )
}

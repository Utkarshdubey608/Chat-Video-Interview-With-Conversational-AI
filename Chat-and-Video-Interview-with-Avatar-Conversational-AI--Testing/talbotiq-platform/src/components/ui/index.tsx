import React from 'react'
import { clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export const cn = (...c: Parameters<typeof clsx>) => twMerge(clsx(c))

/* ─── Button ─────────────────────────────────────────────────────────────── */
interface BtnProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger' | 'outline'
  size?: 'xs' | 'sm' | 'md' | 'lg'
  loading?: boolean
  icon?: React.ReactNode
}
export function Button({ variant = 'primary', size = 'md', loading, icon, children, className, disabled, ...p }: BtnProps) {
  const base = [
    'inline-flex items-center justify-center gap-2 font-semibold rounded-lg',
    'transition-all duration-150 focus-visible:outline-none focus-visible:ring-2',
    'focus-visible:ring-primary-700 focus-visible:ring-offset-2',
    'disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
    'select-none whitespace-nowrap',
  ].join(' ')

  const variants = {
    primary:  'bg-primary-700 text-white hover:bg-primary-600 active:bg-primary-800 shadow-xs hover:shadow-primary-sm',
    secondary:'bg-white text-neutral-700 border border-border hover:border-neutral-300 hover:bg-neutral-50 active:bg-neutral-100',
    ghost:    'bg-transparent text-neutral-500 hover:text-neutral-800 hover:bg-neutral-100 active:bg-neutral-200',
    danger:   'bg-danger-bg text-danger border border-danger-border hover:bg-red-100',
    outline:  'bg-transparent text-primary-700 border-2 border-primary-700 hover:bg-primary-50 active:bg-primary-100',
  }
  const sizes = {
    xs: 'h-7 px-2.5 text-xs',
    sm: 'h-8 px-3.5 text-xs',
    md: 'h-10 px-5 text-sm',
    lg: 'h-12 px-7 text-base',
  }

  return (
    <button {...p} disabled={disabled || loading} className={cn(base, variants[variant], sizes[size], className)}>
      {loading
        ? <span className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin flex-shrink-0" />
        : icon && <span className="flex-shrink-0">{icon}</span>
      }
      {children}
    </button>
  )
}

/* ─── Input ──────────────────────────────────────────────────────────────── */
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string; hint?: string; error?: string
  suffix?: React.ReactNode; prefix?: React.ReactNode
}
export function Input({ label, hint, error, suffix, prefix, className, id, ...p }: InputProps) {
  const iid = id ?? label?.toLowerCase().replace(/\W+/g, '-')
  return (
    <div className="flex flex-col gap-1.5">
      {label && <label htmlFor={iid} className="field-label">{label}</label>}
      <div className="relative">
        {prefix && <span className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-400 pointer-events-none">{prefix}</span>}
        <input
          id={iid}
          className={cn(
            'input-base',
            prefix && 'pl-9',
            suffix && 'pr-9',
            error && '!border-danger !ring-0 focus:!ring-2 focus:!ring-danger/20',
            className,
          )}
          {...p}
        />
        {suffix && <span className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-400">{suffix}</span>}
      </div>
      {hint && !error && <p className="text-xs text-neutral-400">{hint}</p>}
      {error && <p className="text-xs text-danger flex items-center gap-1">⚠ {error}</p>}
    </div>
  )
}

/* ─── Textarea ───────────────────────────────────────────────────────────── */
interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string; hint?: string; error?: string; charLimit?: number
}
export function Textarea({ label, hint, error, charLimit, className, value, ...p }: TextareaProps) {
  const len = typeof value === 'string' ? value.length : 0
  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <div className="flex items-center justify-between">
          <label className="field-label">{label}</label>
          {charLimit && <span className={cn('text-xs font-mono tabular-nums', len > charLimit * 0.9 ? 'text-danger' : 'text-neutral-400')}>{len.toLocaleString()}/{charLimit.toLocaleString()}</span>}
        </div>
      )}
      <textarea
        value={value}
        className={cn('textarea-base', error && '!border-danger', className)}
        {...p}
      />
      {hint && !error && <p className="text-xs text-neutral-400">{hint}</p>}
      {error && <p className="text-xs text-danger">⚠ {error}</p>}
    </div>
  )
}

/* ─── Select ─────────────────────────────────────────────────────────────── */
interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string; hint?: string; error?: string
  options: { value: string; label: string }[]
}
export function Select({ label, hint, error, options, className, ...p }: SelectProps) {
  return (
    <div className="flex flex-col gap-1.5">
      {label && <label className="field-label">{label}</label>}
      <div className="relative">
        <select
          className={cn('input-base appearance-none pr-8 cursor-pointer', error && '!border-danger', className)}
          {...p}
        >
          {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        <svg className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none text-neutral-400" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      {hint && <p className="text-xs text-neutral-400">{hint}</p>}
      {error && <p className="text-xs text-danger">⚠ {error}</p>}
    </div>
  )
}

/* ─── Toggle ─────────────────────────────────────────────────────────────── */
interface ToggleProps { checked: boolean; onChange: (v: boolean) => void; label?: string; description?: string }
export function Toggle({ checked, onChange, label, description }: ToggleProps) {
  return (
    <div className="flex items-center justify-between gap-6 py-3">
      {(label || description) && (
        <div className="flex-1 min-w-0">
          {label && <p className="text-sm font-medium text-neutral-800 leading-tight">{label}</p>}
          {description && <p className="text-xs text-neutral-400 mt-0.5 leading-relaxed">{description}</p>}
        </div>
      )}
      <button
        type="button" role="switch" aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={cn('relative flex-shrink-0 w-10 h-[22px] rounded-full transition-colors duration-200 focus-visible:ring-2 focus-visible:ring-primary-700 focus-visible:ring-offset-1', checked ? 'bg-primary-700' : 'bg-neutral-200')}
      >
        <span className={cn('absolute top-[3px] w-4 h-4 bg-white rounded-full shadow-sm transition-all duration-200', checked ? 'left-[22px]' : 'left-[3px]')} />
      </button>
    </div>
  )
}

/* ─── Slider ─────────────────────────────────────────────────────────────── */
interface SliderProps {
  value: number; onChange: (v: number) => void
  min?: number; max?: number; step?: number
  label?: string; hint?: string; formatValue?: (v: number) => string
}
export function Slider({ value, onChange, min = 0, max = 1, step = 0.01, label, hint, formatValue }: SliderProps) {
  const pct = ((value - min) / (max - min)) * 100
  return (
    <div className="flex flex-col gap-2">
      {label && (
        <div className="flex items-center justify-between">
          <span className="field-label">{label}</span>
          <span className="text-xs font-semibold font-mono text-primary-700 tabular-nums">
            {formatValue ? formatValue(value) : value.toFixed(2)}
          </span>
        </div>
      )}
      <input
        type="range" min={min} max={max} step={step} value={value}
        onChange={e => onChange(Number(e.target.value))}
        className="w-full h-1 rounded-full appearance-none cursor-pointer"
        style={{ background: `linear-gradient(to right, #0d5c3a 0%, #0d5c3a ${pct}%, #e2e8f0 ${pct}%, #e2e8f0 100%)` }}
      />
      {hint && <p className="text-xs text-neutral-400">{hint}</p>}
    </div>
  )
}

/* ─── Badge ──────────────────────────────────────────────────────────────── */
interface BadgeProps { children: React.ReactNode; variant?: 'success' | 'warning' | 'danger' | 'neutral' | 'info'; className?: string }
export function Badge({ children, variant = 'neutral', className }: BadgeProps) {
  return <span className={cn('badge', `badge-${variant}`, className)}>{children}</span>
}

/* ─── Card ───────────────────────────────────────────────────────────────── */
export function Card({ children, className, hover, ...p }: React.HTMLAttributes<HTMLDivElement> & { hover?: boolean }) {
  return <div className={cn('card', hover && 'card-hover', className)} {...p}>{children}</div>
}

/* ─── SectionTitle ───────────────────────────────────────────────────────── */
export function SectionTitle({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn('flex items-center gap-3 mb-5', className)}>
      <span className="section-label">{children}</span>
      <div className="flex-1 h-px bg-border" />
    </div>
  )
}

/* ─── PageHeader ─────────────────────────────────────────────────────────── */
export function PageHeader({ kicker, title, description, action }: { kicker?: string; title: string; description?: string; action?: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-6 mb-8">
      <div>
        {kicker && <span className="pill mb-3 inline-flex">{kicker}</span>}
        <h1 className="text-3xl font-bold tracking-tight text-neutral-900 mt-1">{title}</h1>
        {description && <p className="text-neutral-500 mt-2 text-sm max-w-2xl leading-relaxed">{description}</p>}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  )
}

/* ─── StatCard ───────────────────────────────────────────────────────────── */
interface StatCardProps { label: string; value: string | number; sub?: string; trend?: 'up' | 'down'; color?: string }
export function StatCard({ label, value, sub, trend, color = '#0d5c3a' }: StatCardProps) {
  return (
    <Card className="p-5 flex flex-col gap-2">
      <p className="section-label">{label}</p>
      <p className="text-3xl font-bold tracking-tight" style={{ color }}>{value}</p>
      {sub && (
        <p className={cn('text-xs flex items-center gap-1 font-medium', trend === 'up' ? 'text-success' : trend === 'down' ? 'text-danger' : 'text-neutral-400')}>
          {trend === 'up' && '↑'}{trend === 'down' && '↓'}{sub}
        </p>
      )}
    </Card>
  )
}

/* ─── Modal ──────────────────────────────────────────────────────────────── */
interface ModalProps { open: boolean; onClose: () => void; title?: string; description?: string; children: React.ReactNode; width?: string }
export function Modal({ open, onClose, title, description, children, width = 'max-w-xl' }: ModalProps) {
  React.useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    if (open) { document.addEventListener('keydown', h); document.body.style.overflow = 'hidden' }
    return () => { document.removeEventListener('keydown', h); document.body.style.overflow = '' }
  }, [open, onClose])

  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" onClick={onClose}>
      <div className="absolute inset-0 bg-neutral-900/40 backdrop-blur-[2px] animate-fade-in" />
      <div
        className={cn('relative w-full bg-white rounded-2xl shadow-xl border border-border animate-slide-up max-h-[90vh] overflow-y-auto', width)}
        onClick={e => e.stopPropagation()}
      >
        {(title || description) && (
          <div className="px-6 pt-6 pb-5 border-b border-border">
            <div className="flex items-start justify-between gap-4">
              <div>
                {title && <h2 className="text-lg font-bold text-neutral-900 leading-tight">{title}</h2>}
                {description && <p className="text-sm text-neutral-500 mt-1">{description}</p>}
              </div>
              <button onClick={onClose} className="p-1.5 rounded-lg text-neutral-400 hover:text-neutral-700 hover:bg-neutral-100 transition-colors flex-shrink-0">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>
          </div>
        )}
        <div className="p-6">{children}</div>
      </div>
    </div>
  )
}

/* ─── JsonPreview ────────────────────────────────────────────────────────── */
export function JsonPreview({ data, title = 'Request Preview', method = 'POST', endpoint = '/v2/conversations' }: { data: unknown; title?: string; method?: string; endpoint?: string }) {
  return (
    <div className="rounded-xl overflow-hidden border border-neutral-200 font-mono text-xs">
      <div className="flex items-center justify-between px-4 py-2.5 bg-neutral-900 border-b border-neutral-700">
        <span className="text-neutral-400">{title}</span>
        <div className="flex items-center gap-2">
          <span className="bg-primary-700/20 text-primary-400 px-2 py-0.5 rounded text-[10px] font-bold">{method}</span>
          <span className="text-neutral-500 text-[10px]">tavusapi.com{endpoint}</span>
        </div>
      </div>
      <pre className="p-4 bg-neutral-950 text-emerald-400 overflow-x-auto max-h-80 leading-relaxed">
        {JSON.stringify(data, null, 2)}
      </pre>
    </div>
  )
}

/* ─── EmptyState ─────────────────────────────────────────────────────────── */
export function EmptyState({ icon, title, description, action }: { icon?: React.ReactNode; title: string; description?: string; action?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 gap-5 text-center">
      {icon && (
        <div className="w-14 h-14 rounded-2xl bg-neutral-100 flex items-center justify-center text-2xl">
          {icon}
        </div>
      )}
      <div>
        <p className="font-semibold text-lg text-neutral-800">{title}</p>
        {description && <p className="text-sm text-neutral-400 mt-2 max-w-sm mx-auto leading-relaxed">{description}</p>}
      </div>
      {action}
    </div>
  )
}

/* ─── Skeleton ───────────────────────────────────────────────────────────── */
export function Skeleton({ className }: { className?: string }) {
  return <div className={cn('animate-pulse bg-neutral-100 rounded-lg', className)} />
}

/* ─── Divider ────────────────────────────────────────────────────────────── */
export function Divider({ className }: { className?: string }) {
  return <div className={cn('divider my-5', className)} />
}

/* ─── InfoRow (settings / detail rows) ──────────────────────────────────── */
export function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between py-3 border-b border-border last:border-0 gap-4">
      <span className="text-xs font-semibold text-neutral-500 uppercase tracking-wide flex-shrink-0">{label}</span>
      <span className="text-sm text-neutral-800 text-right">{value}</span>
    </div>
  )
}

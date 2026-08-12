import { useEffect, useRef, useState, type ReactNode } from 'react'

/** Reusable, accessible motion for the marketing site. All effects no-op under
 *  prefers-reduced-motion. Scoped to .mimic-site via CSS. */

const prefersReduced = () =>
  typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

/** Slide-up + fade a block in when it scrolls into view. `delay` staggers siblings. */
export function Reveal({ children, delay = 0, as: Tag = 'div', className = '' }: { children: ReactNode; delay?: number; as?: 'div' | 'section' | 'li'; className?: string }) {
  const ref = useRef<HTMLElement | null>(null)
  const [inView, setInView] = useState(false)
  useEffect(() => {
    if (prefersReduced()) { setInView(true); return }
    const el = ref.current
    if (!el || typeof IntersectionObserver === 'undefined') { setInView(true); return }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { setInView(true); io.disconnect() } })
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' })
    io.observe(el)
    return () => io.disconnect()
  }, [])
  return (
    <Tag ref={ref as never} className={`reveal ${inView ? 'in' : ''} ${className}`.trim()} style={{ transitionDelay: `${delay}ms` }}>
      {children}
    </Tag>
  )
}

/** Count a stat up from zero when it enters view. Parses a leading prefix, the
 *  number (commas/decimals/sign) and a trailing suffix — so "1.3 days", "62%",
 *  "340k", "500+", "8,400", "-71%", "100%" all animate and keep their unit. */
export function CountUp({ value, className, duration = 1200 }: { value: string; className?: string; duration?: number }) {
  const ref = useRef<HTMLSpanElement | null>(null)
  const [text, setText] = useState(value)
  useEffect(() => {
    const m = /^(\D*)(-?[\d,]*\.?\d+)(.*)$/.exec(value)
    const el = ref.current
    if (!m || prefersReduced() || !el || typeof IntersectionObserver === 'undefined') { setText(value); return }
    const [, prefix, numStr, suffix] = m
    const hasComma = numStr.includes(',')
    const decimals = numStr.includes('.') ? numStr.split('.')[1].length : 0
    const target = parseFloat(numStr.replace(/,/g, ''))
    const fmt = (n: number) => {
      const base = hasComma
        ? n.toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
        : n.toFixed(decimals)
      return `${prefix}${base}${suffix}`
    }
    setText(fmt(0))
    let raf = 0
    let started = false
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting || started) return
        started = true
        io.disconnect()
        let t0 = 0
        const step = (t: number) => {
          if (!t0) t0 = t
          const p = Math.min(1, (t - t0) / duration)
          const eased = 1 - Math.pow(1 - p, 3)
          setText(fmt(target * eased))
          if (p < 1) raf = requestAnimationFrame(step)
          else setText(fmt(target))
        }
        raf = requestAnimationFrame(step)
      })
    }, { threshold: 0.5 })
    io.observe(el)
    return () => { io.disconnect(); cancelAnimationFrame(raf) }
  }, [value, duration])
  return <span ref={ref} className={className}>{text}</span>
}

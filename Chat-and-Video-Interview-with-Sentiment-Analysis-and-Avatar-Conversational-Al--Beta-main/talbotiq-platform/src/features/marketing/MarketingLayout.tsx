import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { NAV, type NavGroup } from './content'
import './mimicSite.css'

const Mark = () => (
  <svg viewBox="0 0 32 32" aria-hidden="true"><path d="M7 21V11l5 6 4-6 4 6 5-6v10" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" /></svg>
)

/** Shared marketing chrome — banner + accessible mega-menu + footer. Used by the
 *  home page and every inner marketing page so the nav is defined once. */
export function MarketingLayout({ children, seo }: { children: ReactNode; seo?: { title: string; desc: string } }) {
  const [banner, setBanner] = useState(true)
  const [open, setOpen] = useState<string | null>(null)   // desktop mega-panel
  const [mobileOpen, setMobileOpen] = useState(false)
  const [mobileGroup, setMobileGroup] = useState<string | null>(null)
  const hideTimer = useRef<number | null>(null)
  const navRef = useRef<HTMLElement | null>(null)
  const loc = useLocation()

  // Per-route SEO head (SPA shares one <head>): set on mount/route, restore after.
  useEffect(() => {
    if (!seo) return
    const prev = document.title
    document.title = seo.title
    const added: HTMLElement[] = []
    const set = (sel: string, attr: string, key: string, val: string) => {
      let el = document.head.querySelector<HTMLMetaElement>(sel)
      if (!el) { el = document.createElement('meta'); el.setAttribute(attr, key); document.head.appendChild(el); added.push(el) }
      el.setAttribute('content', val)
    }
    set('meta[name="description"]', 'name', 'description', seo.desc)
    set('meta[property="og:title"]', 'property', 'og:title', seo.title)
    set('meta[property="og:description"]', 'property', 'og:description', seo.desc)
    const canon = document.createElement('link'); canon.rel = 'canonical'
    canon.href = `https://mimic.talbotiq.com${loc.pathname}`; document.head.appendChild(canon); added.push(canon)
    return () => { document.title = prev; added.forEach((e) => e.remove()) }
  }, [seo, loc.pathname])

  // Close menus on route change.
  useEffect(() => { setOpen(null); setMobileOpen(false); setMobileGroup(null) }, [loc.pathname, loc.hash])
  // Click-outside + Escape close the desktop panel.
  useEffect(() => {
    const onDoc = (e: MouseEvent) => { if (navRef.current && !navRef.current.contains(e.target as Node)) setOpen(null) }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(null) }
    document.addEventListener('mousedown', onDoc); document.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('mousedown', onDoc); document.removeEventListener('keydown', onKey) }
  }, [])
  useEffect(() => () => { if (hideTimer.current) window.clearTimeout(hideTimer.current) }, [])

  const enter = (k: string) => { if (hideTimer.current) window.clearTimeout(hideTimer.current); hideTimer.current = window.setTimeout(() => setOpen(k), 120) }
  const leave = () => { if (hideTimer.current) window.clearTimeout(hideTimer.current); hideTimer.current = window.setTimeout(() => setOpen(null), 140) }
  const active = (g: NavGroup) => loc.pathname === g.to || loc.pathname.startsWith(g.to + '/')

  return (
    <div className="mimic-site">
      {banner && (
        <div className="banner" role="region" aria-label="Announcement">
          <span>Mimic interviews every applicant the day they apply — no scheduling, no queue. <Link to="/mimic#demo">See it live →</Link></span>
          <button type="button" aria-label="Dismiss announcement" onClick={() => setBanner(false)}>×</button>
        </div>
      )}

      <header className="nav" ref={navRef}>
        <div className="wrap nav-in">
          <Link className="brand" to="/mimic" aria-label="Mimic by TalbotIQ — home"><span className="mk"><Mark /></span>Mimic</Link>
          <nav className="navlinks" aria-label="Primary" onMouseLeave={leave}>
            {NAV.map((g) => (
              <button key={g.key} type="button" aria-expanded={open === g.key} aria-haspopup="true"
                className={active(g) ? 'is-active' : undefined}
                onMouseEnter={() => enter(g.key)} onFocus={() => setOpen(g.key)}
                onClick={() => setOpen(open === g.key ? null : g.key)}
                onKeyDown={(e) => { if (e.key === 'Escape') setOpen(null) }}>
                {g.label}
                <svg className="caret" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
              </button>
            ))}
          </nav>
          <div className="nav-right">
            <Link className="signin" to="/login">Sign in</Link>
            <Link className="btn btn-primary" to="/mimic#demo">Book a demo</Link>
            <button className="navtoggle" type="button" aria-label="Menu" aria-expanded={mobileOpen} onClick={() => setMobileOpen((o) => !o)}>Menu</button>
          </div>
        </div>

        {open && (
          <div className="mega open" onMouseEnter={() => { if (hideTimer.current) window.clearTimeout(hideTimer.current) }} onMouseLeave={leave}>
            <div className="wrap mega-in">
              {NAV.find((g) => g.key === open)!.columns.map((col) => (
                <div key={col.title}>
                  <h4>{col.title}</h4>
                  <ul>{col.links.map((l) => <li key={l.label}><Link to={l.to}>{l.label}</Link></li>)}</ul>
                </div>
              ))}
            </div>
          </div>
        )}

        {mobileOpen && (
          <div className="mmenu">
            {NAV.map((g) => (
              <div key={g.key} className="macc">
                <button type="button" aria-expanded={mobileGroup === g.key} onClick={() => setMobileGroup(mobileGroup === g.key ? null : g.key)}>
                  {g.label}<span aria-hidden="true">{mobileGroup === g.key ? '–' : '+'}</span>
                </button>
                {mobileGroup === g.key && (
                  <div className="macc-body">
                    {g.columns.map((col) => (
                      <div key={col.title}>
                        <h5>{col.title}</h5>
                        {col.links.map((l) => <Link key={l.label} to={l.to}>{l.label}</Link>)}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
            <Link to="/login" style={{ display: 'block', padding: '12px 2px', fontWeight: 700, color: 'var(--m-ink)' }}>Sign in</Link>
            <Link className="btn btn-primary" to="/mimic#demo" style={{ marginTop: 12 }}>Book a demo</Link>
          </div>
        )}
      </header>

      {children}

      <footer className="foot">
        <div className="wrap">
          <div className="foot-grid" style={{ gridTemplateColumns: '1.4fr repeat(5, 1fr)' }}>
            <div className="foot-brand"><span className="brand" style={{ color: '#fff' }}><span className="mk"><Mark /></span>Mimic</span><p>AI interviews for every candidate. A TalbotIQ product.</p></div>
            {NAV.map((g) => (
              <div key={g.key}>
                <h4>{g.label}</h4>
                <ul>{g.columns.flatMap((c) => c.links).slice(0, 6).map((l) => <li key={l.label}><Link to={l.to}>{l.label}</Link></li>)}</ul>
              </div>
            ))}
          </div>
          <div className="foot-bottom">
            <span>© 2026 TalbotIQ. Mimic is a product of TalbotIQ.</span>
            <span><Link to="/mimic/company" style={{ color: 'rgba(255,255,255,.7)' }}>Legal &amp; privacy</Link></span>
          </div>
        </div>
      </footer>
    </div>
  )
}

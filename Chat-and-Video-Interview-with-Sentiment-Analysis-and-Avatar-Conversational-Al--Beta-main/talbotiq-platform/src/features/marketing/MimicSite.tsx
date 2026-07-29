import { useEffect, useState } from 'react'
import './mimicSite.css'
import { MarketingLayout } from './MarketingLayout'
import { CountUp } from './motion'

/* Mimic marketing site — a faithful React implementation of the Claude Design
 * doc (Mimic.dc.html). Public route (pre-login). All styling is scoped under
 * `.mimic-site`. Content + figures match the design doc verbatim (per the
 * user's request); the sample stats/logos/testimonial are illustrative and
 * to be replaced with real data before public launch. */

const Mark = ({ stroke = '#fff' }: { stroke?: string }) => (
  <svg viewBox="0 0 32 32" aria-hidden="true">
    <path d="M7 21V11l5 6 4-6 4 6 5-6v10" fill="none" stroke={stroke} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
)
const Check = ({ color = 'currentColor', size = 20 }: { color?: string; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
)


const TRACKS = [
  { name: 'Conversational chat', tag: 'Async', desc: 'A text interview candidates finish on a phone in minutes. Best for hourly and high-volume reqs.', meta: ['No scheduling', 'Mobile-first'], bg: '#F0E9FD', dot: '#6B2BE0' },
  { name: 'Voice screening', tag: 'Async', desc: 'Spoken answers, transcribed and scored — tone, pacing and content assessed together.', meta: ['Transcription', 'Signal analysis'], bg: '#E6F7F2', dot: '#2FBF9F' },
  { name: 'AI video avatar', tag: 'Async', desc: 'A face-to-face round with a configured persona that reacts, follows up and probes shallow answers.', meta: ['Personas', 'Replicas'], bg: '#FCE9F4', dot: '#C42C93' },
  { name: 'Live two-way call', tag: 'Live', desc: 'A real interviewer in the room, with Mimic taking notes, scoring the rubric and recording consentfully.', meta: ['Host room', 'Star rating'], bg: '#EDE7FA', dot: '#4A1BA8' },
  { name: 'Timed Q&A', tag: 'Async', desc: 'Per-question timers for skills that need pressure — support triage, trading floors, dispatch.', meta: ['Per-Q timer', 'Integrity checks'], bg: '#FDEBE9', dot: '#D53927' },
  { name: 'Résumé-adaptive by default', tag: 'Every track', desc: "Each interview reads the candidate's résumé first and rewrites its own follow-ups around what they claim.", meta: ['Auto-tailored', 'Same rubric'], bg: '#1B0B3B', dot: '#B98CFF', dark: true },
]
const STEPS = [
  { t: 'Configure once', r: '/templates/senior-rn-nights', b: 'Pick the track, the question source, the rubric weights and the timing. Save it as a template your whole team reuses.' },
  { t: 'Invite in bulk', r: '/sessions/new', b: 'Drop in a CSV or paste an ATS export. Mimic parses every résumé, personalises the email and sends the links.' },
  { t: 'Interview on their schedule', r: '/take/:sessionId', b: 'Candidates interview at 11pm on a phone if that is what works. Questions adapt live to what the résumé claimed.' },
  { t: 'Score every answer', r: '/sessions/:id/report', b: 'One rubric, applied identically. Each dimension cites the answer it came from, with transcript and signal analysis.' },
  { t: 'Decide with a shortlist', r: '/pipelines/:id', b: 'Drag candidates through rounds, or auto-advance everyone above a threshold. Export the board when you are done.' },
]
type ClientLogo = { name: string; srcs: string[]; h?: number }
// Real client logos. Save each file (any of these formats) under /public/mimic-logos/
// and it renders automatically: total-it-global.(png|svg|jpg|webp), aisling.(…).
// `h` overrides the row height per logo so square marks read at the same visual
// size as wide wordmarks. Until a file exists the marquee falls back to text.
const withExts = (base: string) => ['png', 'svg', 'jpg', 'jpeg', 'webp'].map((e) => `${base}.${e}`)
const CLIENTS: ClientLogo[] = [
  { name: 'Total IT Global', srcs: withExts('/mimic-logos/total-it-global') },
  { name: 'Aisling', srcs: withExts('/mimic-logos/aisling'), h: 52 },
  { name: 'TalbotIQ', srcs: ['/talbotiq-logo.png'] },
]
// Repeated so the sliding row stays full; the marquee doubles this for a seamless loop.
const LOGOS: ClientLogo[] = [...CLIENTS, ...CLIENTS, ...CLIENTS]
function LogoSlot({ name, srcs, h }: ClientLogo) {
  const [i, setI] = useState(0)
  if (i >= srcs.length) return <span className="logo-slot">{name.toUpperCase()}</span>
  return <span className="logo-slot"><img src={srcs[i]} alt={name} loading="lazy" onError={() => setI(i + 1)} style={h ? { height: `${h}px`, maxWidth: 'none' } : undefined} /></span>
}
const HERO_PROOF = [
  { n: '1.3 days', l: 'Median time to shortlist' },
  { n: '62%', l: 'Recruiter hours returned' },
  { n: '340k', l: 'Interviews scored' },
]
const OUTCOMES = [
  { n: '33%', t: 'Faster time-to-fill', d: 'Screening runs the night applications land, not the week after.' },
  { n: '500+', t: 'Candidates per req, interviewed', d: 'Volume stops being a staffing question.' },
  { n: '100%', t: 'Answers scored against one rubric', d: 'Every candidate measured the same way, evidence attached.' },
  { n: '4 min', t: 'To configure a new round', d: 'Template, question set, invite list, send.' },
]
const STORY_STATS = [
  { n: '8,400', l: 'Applicants screened in one quarter' },
  { n: '-71%', l: 'Recruiter hours per hire' },
  { n: '4.6/5', l: 'Candidate experience rating' },
]
const TRUST = [
  { tag: 'Independently audited', t: 'Bias testing you can read', d: 'Adverse-impact testing is run by a third party and the results are published, not summarised. Every rubric dimension is reported separately.' },
  { tag: 'Human-in-the-loop', t: 'Mimic never rejects anyone', d: 'Scores are recommendations with evidence attached. Advancing, rejecting and overriding are recruiter actions, and every one is logged.' },
  { tag: 'Enterprise controls', t: 'Your data stays yours', d: 'Regional residency, configurable retention, GDPR purge on request, SSO and role-based access. Candidate data is never used to train models.' },
]
const BADGES = ['SOC 2 Type II', 'ISO 27001', 'ISO 42001', 'GDPR ready', 'WCAG 2.2 AA', 'EEOC-aligned']
const RESOURCES = [
  { kind: 'Benchmark report', t: 'What 340,000 scored interviews say about screening accuracy', bg: 'linear-gradient(140deg,#2A1259,#6B2BE0)' },
  { kind: 'Playbook', t: 'Designing a rubric your hiring managers will actually trust', bg: 'linear-gradient(140deg,#6B2BE0,#C42C93)' },
  { kind: "Buyer's guide", t: 'Twelve questions to ask any AI interview vendor', bg: 'linear-gradient(140deg,#38206B,#C42C93)' },
]
const HERO_ROWS = [
  { in: 'AR', name: 'Amara Reyes', tag: 'AI avatar · Scored', sc: '92', bg: '#F0E9FD', fg: '#6B2BE0', pc: '#0F7A66', pb: '#E6F7F2', scC: '#0F7A66' },
  { in: 'JT', name: 'Jonas Thiel', tag: 'Two-way · Scored', sc: '88', bg: '#E6F7F2', fg: '#0F7A66', pc: '#0F7A66', pb: '#E6F7F2', scC: '#0F7A66' },
  { in: 'PK', name: 'Priya Kaur', tag: 'Voice · In progress', sc: '—', bg: '#EDE7FA', fg: '#4A1BA8', pc: '#6B2BE0', pb: '#F0E9FD', scC: '#ADA6C0' },
  { in: 'MO', name: 'Michael Osei', tag: 'Chatbot · Invited', sc: '—', bg: '#FCE9F4', fg: '#C42C93', pc: '#7C7595', pb: '#F8F6FD', scC: '#ADA6C0' },
  { in: 'LN', name: 'Lena Novák', tag: 'Timed Q&A · Scored', sc: '71', bg: '#F0E9FD', fg: '#6B2BE0', pc: '#0F7A66', pb: '#E6F7F2', scC: '#4A1BA8' },
]
const FAQS = [
  { q: 'Does Mimic reject candidates automatically?', a: 'No. Every score is a recommendation with the evidence behind it. Advancing, rejecting and overriding are recruiter actions, and every one is logged. Mimic never rejects anyone on its own.' },
  { q: 'How do you keep scoring fair?', a: 'Every candidate is measured against one rubric, and each dimension cites the exact answer it came from. Adverse-impact testing is run by a third party and reported per dimension, and a human makes every decision.' },
  { q: 'How long does it take to go live?', a: 'You can build a reusable interview template in minutes and send your first invitations the same day. Most teams are running a live round within a week; larger rollouts scale from there.' },
  { q: 'Does Mimic work with our ATS?', a: 'Invite candidates from a CSV, an ATS export, or a single shareable link — so you can start today with no integration. Direct ATS connectors are available for enterprise plans; tell us your stack in the demo.' },
  { q: 'Is candidate data secure and compliant?', a: 'Mimic supports regional data residency, configurable retention, GDPR purge on request, SSO and role-based access, and is SOC 2 Type II and ISO 27001 aligned. Candidate data is never used to train models.' },
  { q: 'What does Mimic cost?', a: "Mimic is priced for enterprise hiring by volume — you pay for interview capacity, not per seat. Book a demo and we'll scope pricing to your req load." },
]

type FormState = { firstName: string; lastName: string; email: string; hiresPerYear: string }
const EMPTY: FormState = { firstName: '', lastName: '', email: '', hiresPerYear: '' }

export default function MimicSite() {
  const [step, setStep] = useState(0)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [errors, setErrors] = useState<Partial<Record<keyof FormState, boolean>>>({})
  const [submitting, setSubmitting] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [formError, setFormError] = useState('')

  // Per-route SEO head. A single-page app shares one <head>, so set the marketing
  // page's own title/meta/OG/canonical + JSON-LD on mount and restore on unmount.
  // (Client-rendered — fine for JS-executing crawlers; a prerender/SSR pass is the
  // follow-up for full static SEO. Tracked in the delivery notes.)
  useEffect(() => {
    const prevTitle = document.title
    document.title = 'Mimic by TalbotIQ — AI Interviews for Every Candidate'
    const desc = 'Mimic interviews and scores every applicant the day they apply — across chat, voice, AI video and live rounds — on one rubric, with the evidence attached. Book a demo.'
    const added: HTMLElement[] = []
    const meta = (sel: string, attr: string, key: string, content: string) => {
      let el = document.head.querySelector<HTMLMetaElement>(sel)
      if (!el) { el = document.createElement('meta'); el.setAttribute(attr, key); document.head.appendChild(el); added.push(el) }
      el.setAttribute('content', content)
    }
    meta('meta[name="description"]', 'name', 'description', desc)
    meta('meta[property="og:title"]', 'property', 'og:title', 'Mimic — AI interviews for every candidate')
    meta('meta[property="og:description"]', 'property', 'og:description', desc)
    meta('meta[property="og:type"]', 'property', 'og:type', 'website')
    meta('meta[name="twitter:card"]', 'name', 'twitter:card', 'summary_large_image')
    const canonical = document.createElement('link'); canonical.rel = 'canonical'; canonical.href = 'https://mimic.talbotiq.com/'; document.head.appendChild(canonical); added.push(canonical)
    const ld = document.createElement('script'); ld.type = 'application/ld+json'
    ld.textContent = JSON.stringify({ '@context': 'https://schema.org', '@graph': [
      { '@type': 'Organization', name: 'TalbotIQ', brand: { '@type': 'Brand', name: 'Mimic' }, url: 'https://mimic.talbotiq.com/' },
      { '@type': 'WebSite', name: 'Mimic by TalbotIQ', url: 'https://mimic.talbotiq.com/' },
      { '@type': 'Service', name: 'Mimic AI interview platform', serviceType: 'AI candidate screening and interviewing', description: desc },
      { '@type': 'FAQPage', mainEntity: FAQS.map((f) => ({ '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a } })) },
    ] })
    document.head.appendChild(ld); added.push(ld)
    return () => { document.title = prevTitle; added.forEach((el) => el.remove()) }
  }, [])


  const valid = (k: keyof FormState, v: string) =>
    k === 'email' ? /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.trim()) : v.trim().length > 0
  const setField = (k: keyof FormState, v: string) => {
    setForm((f) => ({ ...f, [k]: v }))
    if (errors[k]) setErrors((e) => ({ ...e, [k]: !valid(k, v) }))
  }
  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    const next: Partial<Record<keyof FormState, boolean>> = {}
    ;(Object.keys(EMPTY) as (keyof FormState)[]).forEach((k) => { if (!valid(k, form[k])) next[k] = true })
    setErrors(next)
    if (Object.keys(next).length) return
    setSubmitting(true); setFormError('')
    try {
      const res = await fetch('/api/leads', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...form, source: 'mimic-site' }),
      })
      if (!res.ok) throw new Error('bad status')
      setSubmitted(true)
    } catch {
      setFormError("Something went wrong sending that. Please try again, or email sales@talbotiq.com.")
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <MarketingLayout>
      <main id="top">
        {/* HERO */}
        <section className="hero" aria-labelledby="hero-h1">
          <div className="wrap hero-in">
            <div>
              <span className="pill">AI interviews · every candidate</span>
              <h1 id="hero-h1">Screening, decided.</h1>
              <p className="sub">Mimic interviews and scores every applicant the day they apply — across chat, voice, AI video and a live round — on one rubric, with the evidence attached.</p>
              <div className="hero-cta">
                <a className="btn btn-light" href="#demo">Book a demo</a>
                <a className="btn btn-outline-l" href="#how">See how scoring works</a>
              </div>
              <div className="proof">
                {HERO_PROOF.map((p) => (<div key={p.l}><div className="n"><CountUp value={p.n} /></div><div className="l">{p.l}</div></div>))}
              </div>
            </div>
            <div className="card-float" role="img" aria-label="Sample Mimic sessions workspace showing scored candidates">
              <div className="cf-head"><span className="t">Sessions · Senior RN · Nights</span><span className="sample">Sample data</span></div>
              {HERO_ROWS.map((r) => (
                <div className="strow" key={r.name}>
                  <span className="cand"><span className="ci" style={{ background: r.bg, color: r.fg }}>{r.in}</span><span className="nm">{r.name}</span></span>
                  <span className="pill-s" style={{ color: r.pc, background: r.pb }}>{r.tag}</span>
                  <span className="sc" style={{ color: r.scC }}>{r.sc}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* LOGOS */}
        <section className="logos" aria-label="Customers">
          <div className="wrap">
            <h2>Talent teams screening at volume already run on Mimic.</h2>
            <div className="marq" aria-hidden="true"><div className="marq-track">{LOGOS.concat(LOGOS).map((l, i) => <LogoSlot key={l.name + i} name={l.name} srcs={l.srcs} h={l.h} />)}</div></div>
          </div>
        </section>

        {/* OUTCOMES */}
        <section className="section" id="how" aria-labelledby="out-h">
          <div className="wrap">
            <div className="sec-head">
              <span className="eyebrow" style={{ color: 'var(--m-violet)' }}>The outcome</span>
              <h2 className="h2" id="out-h" style={{ marginTop: 12 }}>The first round stops being the bottleneck.</h2>
              <p className="lede">Applications arrive around the clock. Mimic interviews them as they land and hands your team a ranked, evidence-backed shortlist — not a queue.</p>
            </div>
            <div className="grid4">
              {OUTCOMES.map((o) => (<div className="ocell" key={o.t}><div className="n"><CountUp value={o.n} /></div><div className="t">{o.t}</div><div className="d">{o.d}</div></div>))}
            </div>
          </div>
        </section>

        {/* TRACKS */}
        <section className="section" id="platform" aria-labelledby="tr-h">
          <div className="wrap">
            <div className="sec-head">
              <span className="eyebrow" style={{ color: 'var(--m-violet)' }}>Interview tracks</span>
              <h2 className="h2" id="tr-h" style={{ marginTop: 12 }}>One configuration. Five ways to meet a candidate.</h2>
              <p className="lede">Pick the format that fits the role. Every track reads the résumé first and scores against the same rubric.</p>
            </div>
            <div className="grid3">
              {TRACKS.map((t) => (
                <article className={`track${t.dark ? ' dark' : ''}`} key={t.name}>
                  <div className="top"><span className="ic" style={{ background: t.dark ? 'rgba(255,255,255,.08)' : t.bg }}><i style={{ background: t.dot }} /></span><span className="tag">{t.tag}</span></div>
                  <h3>{t.name}</h3><p>{t.desc}</p>
                  <div className="meta">{t.meta.map((m) => <span key={m}>{m}</span>)}</div>
                </article>
              ))}
            </div>
          </div>
        </section>

        {/* PROCESS */}
        <section className="process" id="process" aria-labelledby="pr-h">
          <div className="wrap">
            <div className="sec-head"><span className="eyebrow" style={{ color: '#B98CFF' }}>How it works</span><h2 className="h2" id="pr-h" style={{ color: '#fff', marginTop: 12 }}>Invite. Interview. Score. Shortlist.</h2></div>
            <div className="proc-grid">
              <div className="steps" role="tablist" aria-label="How Mimic works">
                {STEPS.map((s, i) => (
                  <button className="step" role="tab" aria-selected={i === step} key={s.t} onClick={() => setStep(i)}>
                    <span className="num">0{i + 1}</span><h3>{s.t}</h3><p>{s.b}</p>
                  </button>
                ))}
              </div>
              <div className="proc-panel" role="tabpanel"><span className="route">{STEPS[step].r}</span><h3>{STEPS[step].t}</h3><p>{STEPS[step].b}</p></div>
            </div>
          </div>
        </section>

        {/* SHOWCASE */}
        <section className="section showcase" aria-labelledby="sh-h">
          <div className="wrap">
            <div className="sec-head"><span className="eyebrow" style={{ color: 'var(--m-violet)' }}>The product</span><h2 className="h2" id="sh-h" style={{ marginTop: 12 }}>Two sides of the same interview.</h2><p className="lede">The site you're reading, and the workspace your team lives in — Sessions, pipelines, reports and an avatar studio, all on one rubric.</p></div>
            <div className="two">
              <div>
                <ul className="featlist">
                  <li><Check color="var(--m-teal)" />Bulk invitations from a CSV, an ATS export, or one shareable link.</li>
                  <li><Check color="var(--m-teal)" />Multi-round pipelines with drag-to-advance and quick-advance rules.</li>
                  <li><Check color="var(--m-teal)" />One rubric across every track, so scores compare directly.</li>
                  <li><Check color="var(--m-teal)" />Analytics by role, template, track and recruiter.</li>
                </ul>
                <a className="btn btn-primary" href="#demo" style={{ marginTop: 26 }}>See the workspace in a demo</a>
              </div>
              <div className="app-mock" role="img" aria-label="Sample Mimic recruiter workspace: the Sessions screen">
                <div className="am-top">
                  <span className="brand" style={{ fontSize: 14, color: '#fff' }}><span className="mk" style={{ width: 20, height: 20, borderRadius: 6 }}><Mark /></span>Mimic</span>
                  <div className="am-tabs"><span className="on">Sessions</span><span>Pipelines</span><span>Analytics</span><span>Studio</span></div>
                </div>
                <div className="am-body">
                  <div className="strow" style={{ borderColor: '#EEE9F8' }}><span className="cand"><span className="ci" style={{ background: '#F0E9FD', color: '#6B2BE0' }}>AR</span><span className="nm">Amara Reyes</span></span><span className="pill-s" style={{ color: '#0F7A66', background: '#E6F7F2' }}>Scored</span><span className="sc" style={{ color: '#0F7A66' }}>92</span></div>
                  <div className="strow" style={{ borderColor: '#EEE9F8' }}><span className="cand"><span className="ci" style={{ background: '#E6F7F2', color: '#0F7A66' }}>DA</span><span className="nm">Devon Ako</span></span><span className="pill-s" style={{ color: '#0F7A66', background: '#E6F7F2' }}>Scored</span><span className="sc" style={{ color: '#0F7A66' }}>94</span></div>
                  <div className="strow" style={{ borderColor: '#EEE9F8' }}><span className="cand"><span className="ci" style={{ background: '#FDEBE9', color: '#D53927' }}>SW</span><span className="nm">Sam Whitaker</span></span><span className="pill-s" style={{ color: '#C42C93', background: '#FCE9F4' }}>Scheduled</span><span className="sc" style={{ color: '#ADA6C0' }}>—</span></div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* TESTIMONIAL */}
        <section className="section" aria-label="Customer story">
          <div className="wrap quote-grid">
            <div>
              <blockquote>“We were losing good people to a two-week screening queue. Now every applicant is interviewed the same day and my team reads five reports instead of ninety.”</blockquote>
              <div className="byline"><span className="ph-photo">photo</span><div><div style={{ fontSize: 14, fontWeight: 700 }}>Dana Whitfield</div><div style={{ fontSize: '12.5px', color: 'var(--m-ink2)', fontWeight: 500 }}>VP Talent Acquisition, Meridian Health</div></div></div>
            </div>
            <div className="story">
              {STORY_STATS.map((s) => (<div className="row" key={s.l}><span className="n">{s.n}</span><span className="l">{s.l}</span></div>))}
            </div>
          </div>
        </section>

        {/* TRUST */}
        <section className="section" id="trust" aria-labelledby="trust-h">
          <div className="wrap">
            <h2 className="h2" id="trust-h" style={{ maxWidth: '20ch' }}>Everyone claims responsible AI. Ours is auditable.</h2>
            <div className="trust-grid">
              {TRUST.map((t) => (<div className="tcard" key={t.t}><div className="tag">{t.tag}</div><h3>{t.t}</h3><p>{t.d}</p></div>))}
            </div>
            <div className="badges"><span style={{ fontSize: '12.5px', color: 'var(--m-muted)', fontWeight: 600, marginRight: 4 }}>Compliance:</span>{BADGES.map((b) => (<span className="badge" key={b}>{b}</span>))}</div>
          </div>
        </section>

        {/* RESOURCES */}
        <section className="section" id="resources" aria-labelledby="res-h">
          <div className="wrap">
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 30, gap: 20, flexWrap: 'wrap' }}>
              <h2 className="h2" id="res-h" style={{ fontSize: 26 }}>Resources</h2>
              <a href="#demo" style={{ fontSize: '13.5px', fontWeight: 700 }}>Talk to our team →</a>
            </div>
            <div className="res-grid">
              {RESOURCES.map((r) => (<a className="rcard" href="#demo" key={r.t} style={{ background: r.bg }}><span className="kind">{r.kind}</span><h3>{r.t}</h3></a>))}
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section className="section" id="faq" aria-labelledby="faq-h">
          <div className="wrap">
            <div className="sec-head center"><span className="eyebrow" style={{ color: 'var(--m-violet)' }}>Questions, answered</span><h2 className="h2" id="faq-h" style={{ marginTop: 12 }}>The things buyers ask us first.</h2></div>
            <div className="faq">
              {FAQS.map((f, i) => (
                <details key={f.q} open={i === 0}>
                  <summary>{f.q}</summary>
                  <p>{f.a}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        {/* CTA + FORM */}
        <section className="cta" id="demo" aria-labelledby="cta-h">
          <div className="wrap cta-in">
            <div>
              <h2 id="cta-h">Give the first round back to your recruiters.</h2>
              <p className="sub">See Mimic interview a candidate, score the answers against a rubric, and build a shortlist — on your own roles.</p>
              <div className="assure">
                <span><Check color="#B98CFF" size={16} />30-minute walkthrough</span>
                <span><Check color="#B98CFF" size={16} />Your roles, your rubric</span>
                <span><Check color="#B98CFF" size={16} />No card required</span>
              </div>
            </div>
            {submitted ? (
              <div className="thanks" role="status" aria-live="polite">
                <div className="tick"><Check color="#0F7A66" size={26} /></div>
                <h3>Thanks — you're on the list.</h3>
                <p>We'll be in touch within one business day to set up your walkthrough.</p>
              </div>
            ) : (
              <form className="demo" onSubmit={submit} noValidate>
                <h3>Book a demo</h3>
                <div className={`field${errors.firstName ? ' bad' : ''}`}><label htmlFor="fn">First name</label><input id="fn" autoComplete="given-name" value={form.firstName} aria-invalid={!!errors.firstName} onChange={(e) => setField('firstName', e.target.value)} onBlur={(e) => setErrors((x) => ({ ...x, firstName: !valid('firstName', e.target.value) }))} /><span className="err">Enter your first name.</span></div>
                <div className={`field${errors.lastName ? ' bad' : ''}`}><label htmlFor="ln">Last name</label><input id="ln" autoComplete="family-name" value={form.lastName} aria-invalid={!!errors.lastName} onChange={(e) => setField('lastName', e.target.value)} onBlur={(e) => setErrors((x) => ({ ...x, lastName: !valid('lastName', e.target.value) }))} /><span className="err">Enter your last name.</span></div>
                <div className={`field full${errors.email ? ' bad' : ''}`}><label htmlFor="em">Work email</label><input id="em" type="email" autoComplete="email" value={form.email} aria-invalid={!!errors.email} onChange={(e) => setField('email', e.target.value)} onBlur={(e) => setErrors((x) => ({ ...x, email: !valid('email', e.target.value) }))} /><span className="err">Enter a valid work email.</span></div>
                <div className={`field full${errors.hiresPerYear ? ' bad' : ''}`}><label htmlFor="hy">Hires per year</label><input id="hy" inputMode="numeric" placeholder="e.g. 500–2,000" value={form.hiresPerYear} aria-invalid={!!errors.hiresPerYear} onChange={(e) => setField('hiresPerYear', e.target.value)} onBlur={(e) => setErrors((x) => ({ ...x, hiresPerYear: !valid('hiresPerYear', e.target.value) }))} /><span className="err">Roughly how many people do you hire a year?</span></div>
                <div className="submit"><button type="submit" disabled={submitting}>{submitting ? 'Sending…' : 'Book a demo'}</button></div>
                {formError && <p className="err" style={{ display: 'block', gridColumn: '1 / -1', textAlign: 'center' }}>{formError}</p>}
                <p className="form-note">By submitting you agree to be contacted about Mimic. <a href="#trust">Privacy</a>.</p>
              </form>
            )}
          </div>
        </section>
      </main>
    </MarketingLayout>
  )
}

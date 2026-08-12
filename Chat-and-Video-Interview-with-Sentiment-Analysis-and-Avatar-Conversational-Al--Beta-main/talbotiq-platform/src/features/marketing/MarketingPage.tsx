import { Link, useParams } from 'react-router-dom'
import { MarketingLayout } from './MarketingLayout'
import { NAV, PAGE_BY_SLUG, type MktPage } from './content'
import { Reveal, CountUp } from './motion'
import { RoiCalculator } from './RoiCalculator'

function Jsonld({ page }: { page: MktPage }) {
  const graph: unknown[] = [
    { '@type': 'BreadcrumbList', itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'Mimic', item: 'https://mimic.talbotiq.com/mimic' },
      { '@type': 'ListItem', position: 2, name: page.section, item: `https://mimic.talbotiq.com${page.sectionTo}` },
      { '@type': 'ListItem', position: 3, name: page.kicker.split('·').pop()?.trim() || page.h1, item: `https://mimic.talbotiq.com/mimic/${page.slug}` },
    ] },
    { '@type': 'Service', name: `Mimic — ${page.h1}`, serviceType: 'AI candidate screening and interviewing', provider: { '@type': 'Organization', name: 'TalbotIQ' } },
  ]
  if (page.faqs?.length) graph.push({ '@type': 'FAQPage', mainEntity: page.faqs.map((f) => ({ '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a } })) })
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }) }} />
}

function Breadcrumbs({ page }: { page: MktPage }) {
  const leaf = page.kicker.includes('·') ? page.kicker.split('·').pop()!.trim() : page.h1
  return (
    <nav className="crumbs" aria-label="Breadcrumb">
      <Link to="/mimic">Mimic</Link><span>/</span>
      <Link to={page.sectionTo}>{page.section}</Link>
      {page.tier !== 'hub' && (<><span>/</span><span aria-current="page">{leaf}</span></>)}
    </nav>
  )
}

export default function MarketingPage() {
  const params = useParams()
  const slug = params['*'] || ''
  const page = PAGE_BY_SLUG[slug]

  if (!page) {
    return (
      <MarketingLayout seo={{ title: 'Page not found — Mimic', desc: 'That page could not be found.' }}>
        <main className="mkpage"><div className="wrap" style={{ padding: '96px 32px', textAlign: 'center' }}>
          <p className="eyebrow" style={{ color: 'var(--m-violet)' }}>404</p>
          <h1 className="h2" style={{ marginTop: 12 }}>We couldn’t find that page.</h1>
          <p className="lede" style={{ margin: '14px auto 26px', maxWidth: '46ch' }}>The link may be old. Try the platform overview, or book a demo and we’ll point you the right way.</p>
          <div style={{ display: 'flex', gap: 12, justifyContent: 'center', flexWrap: 'wrap' }}>
            <Link className="btn btn-primary" to="/mimic">Back to home</Link>
            <Link className="btn btn-ghost" to="/mimic/solutions">Explore solutions</Link>
          </div>
        </div></main>
      </MarketingLayout>
    )
  }

  const group = NAV.find((g) => g.to === page.sectionTo)
  const cta = page.cta ?? { title: 'See Mimic on your roles', sub: 'Book a 30-minute walkthrough — no card required.' }

  return (
    <MarketingLayout seo={{ title: page.metaTitle, desc: page.metaDesc }}>
      <Jsonld page={page} />
      <main className="mkpage">
        <div className="wrap">
          <Breadcrumbs page={page} />
          <header className="mk-hero">
            <p className="eyebrow" style={{ color: 'var(--m-violet)' }}>{page.kicker}</p>
            <h1>{page.h1}</h1>
            <p className="lede" style={{ marginTop: 16 }}>{page.intro}</p>
            <div style={{ marginTop: 24, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
              <Link className="btn btn-primary" to="/mimic#demo">Book a demo</Link>
              {page.tier !== 'hub' && <Link className="btn btn-ghost" to={page.sectionTo}>All {page.section.toLowerCase()}</Link>}
            </div>
          </header>

          {page.tier !== 'hub' && (
            <Reveal delay={60}>
              <div className="mk-proof">
                {[['1.3 days', 'Median time to shortlist'], ['62%', 'Recruiter hours returned'], ['340k', 'Interviews scored']].map(([v, l]) => (
                  <div className="cell" key={l}><div className="n"><CountUp value={v} /></div><div className="l">{l}</div></div>
                ))}
              </div>
            </Reveal>
          )}

          {page.tier === 'hub' && group ? (
            <div className="hub-cols">
              {group.columns.map((col, i) => (
                <Reveal key={col.title} as="section" className="hub-col" delay={i * 90}>
                  <h2>{col.title}</h2>
                  <ul>{col.links.map((l) => <li key={l.label}><Link to={l.to}>{l.label}<span aria-hidden="true">→</span></Link></li>)}</ul>
                </Reveal>
              ))}
            </div>
          ) : (
            <div className="mk-body">
              {page.slug === 'resources/roi-calculator' && <Reveal><RoiCalculator /></Reveal>}
              {page.sections.map((s, i) => (
                <Reveal key={s.h2} as="section" className="mk-sec" delay={i * 80}>
                  <h2>{s.h2}</h2>
                  <p>{s.body}</p>
                  {s.bullets && <ul className="mk-bullets">{s.bullets.map((b) => <li key={b}>{b}</li>)}</ul>}
                </Reveal>
              ))}
            </div>
          )}

          {page.faqs?.length ? (
            <section className="mk-faq" aria-label="FAQ">
              <h2 className="h2" style={{ fontSize: 26, marginBottom: 8 }}>Questions</h2>
              <div className="faq">
                {page.faqs.map((f, i) => (
                  <details key={f.q} open={i === 0}><summary>{f.q}</summary><p>{f.a}</p></details>
                ))}
              </div>
            </section>
          ) : null}
        </div>

        <section className="cta" style={{ marginTop: 8 }}>
          <div className="wrap cta-in" style={{ gridTemplateColumns: '1fr auto', alignItems: 'center' }}>
            <div><h2 style={{ fontSize: 34 }}>{cta.title}</h2><p className="sub">{cta.sub}</p></div>
            <Link className="btn btn-light" to="/mimic#demo" style={{ alignSelf: 'center' }}>Book a demo</Link>
          </div>
        </section>
      </main>
    </MarketingLayout>
  )
}

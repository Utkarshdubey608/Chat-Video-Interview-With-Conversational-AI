/**
 * Mimic marketing site — information architecture + page content.
 *
 * Single source of truth for the nav mega-menu, the footer, the route table and
 * every page's copy + SEO. Templates render from this, so every nav link resolves
 * to a real, populated, indexable page (zero dead ends) and the nav/footer are
 * generated once. Content is written to be honest and specific; anything we cannot
 * truthfully assert (certifications, customers, metrics we don't have) is a
 * [PLACEHOLDER] string, surfaced to the team, never fabricated.
 */

export interface NavLink { label: string; to: string }
export interface NavColumn { title: string; links: NavLink[] }
export interface NavGroup { key: string; label: string; to: string; columns: NavColumn[] }

export interface PageSection { h2: string; body: string; bullets?: string[] }
export interface FaqItem { q: string; a: string }
export interface MktPage {
  slug: string            // path under /mimic, e.g. "solutions/high-volume-hiring"
  section: string         // "Solutions" | "Trust" | ...
  sectionTo: string       // hub route, e.g. "/mimic/solutions"
  tier: 'hub' | 'A' | 'B' | 'C'
  kicker: string
  h1: string
  metaTitle: string       // ~55-60 chars
  metaDesc: string        // ~150-160 chars
  intro: string
  sections: PageSection[]
  faqs?: FaqItem[]
  cta?: { title: string; sub: string }
}

const DEMO = '/mimic#demo'

/* ─── Nav tree (drives mega-menu + footer + routes) ───────────────────────── */
export const NAV: NavGroup[] = [
  {
    key: 'Platform', label: 'Platform', to: '/mimic/platform',
    columns: [
      { title: 'Interview tracks', links: [
        { label: 'Conversational chat', to: '/mimic/platform/conversational-chat' },
        { label: 'Voice screening', to: '/mimic/platform/voice-screening' },
        { label: 'AI video avatar', to: '/mimic/platform/ai-video-avatar' },
        { label: 'Live two-way call', to: '/mimic/platform/live-two-way' },
        { label: 'Timed Q&A', to: '/mimic/platform/timed-qa' },
      ]},
      { title: 'Workflow', links: [
        { label: 'Bulk invitations', to: '/mimic/platform/bulk-invitations' },
        { label: 'Interview templates', to: '/mimic/platform/interview-templates' },
        { label: 'Question sets', to: '/mimic/platform/question-sets' },
        { label: 'Multi-round pipelines', to: '/mimic/platform/pipelines' },
        { label: 'Rubrics & scoring', to: '/mimic/platform/rubrics-scoring' },
      ]},
      { title: 'Intelligence', links: [
        { label: 'Candidate reports', to: '/mimic/platform/candidate-reports' },
        { label: 'Recruiter analytics', to: '/mimic/platform/recruiter-analytics' },
        { label: 'Signal analysis', to: '/mimic/platform/signal-analysis' },
        { label: 'Mimic Guide assistant', to: '/mimic/platform/mimic-guide' },
      ]},
    ],
  },
  {
    key: 'Solutions', label: 'Solutions', to: '/mimic/solutions',
    columns: [
      { title: 'By use case', links: [
        { label: 'High-volume hiring', to: '/mimic/solutions/high-volume-hiring' },
        { label: 'Campus & graduate', to: '/mimic/solutions/campus-graduate' },
        { label: 'Technical screening', to: '/mimic/solutions/technical-screening' },
        { label: 'Sales & customer-facing', to: '/mimic/solutions/sales-customer-facing' },
        { label: 'Frontline & hourly', to: '/mimic/solutions/frontline-hourly' },
        { label: 'Internal mobility', to: '/mimic/solutions/internal-mobility' },
      ]},
      { title: 'By team', links: [
        { label: 'Talent acquisition leaders', to: '/mimic/solutions/talent-acquisition-leaders' },
        { label: 'Recruiters', to: '/mimic/solutions/recruiters' },
        { label: 'Hiring managers', to: '/mimic/solutions/hiring-managers' },
        { label: 'RPO & staffing agencies', to: '/mimic/solutions/rpo-staffing' },
        { label: 'People analytics', to: '/mimic/solutions/people-analytics' },
      ]},
      { title: 'By industry', links: [
        { label: 'BPO & contact centres', to: '/mimic/solutions/bpo-contact-centres' },
        { label: 'IT services', to: '/mimic/solutions/it-services' },
        { label: 'Retail & hospitality', to: '/mimic/solutions/retail-hospitality' },
        { label: 'Healthcare', to: '/mimic/solutions/healthcare' },
        { label: 'Financial services', to: '/mimic/solutions/financial-services' },
      ]},
    ],
  },
  {
    key: 'Trust', label: 'Trust', to: '/mimic/trust',
    columns: [
      { title: 'Responsible AI', links: [
        { label: 'How Mimic scores', to: '/mimic/trust/how-mimic-scores' },
        { label: 'Bias testing & audits', to: '/mimic/trust/bias-testing-audits' },
        { label: 'Human-in-the-loop review', to: '/mimic/trust/human-in-the-loop' },
        { label: 'Model & data transparency', to: '/mimic/trust/model-data-transparency' },
        { label: 'Candidate rights', to: '/mimic/trust/candidate-rights' },
      ]},
      { title: 'Compliance', links: [
        { label: 'EU AI Act', to: '/mimic/trust/eu-ai-act' },
        { label: 'NYC Local Law 144', to: '/mimic/trust/nyc-local-law-144' },
        { label: 'Illinois AI Video Interview Act', to: '/mimic/trust/illinois-aivia' },
        { label: 'GDPR & India DPDP', to: '/mimic/trust/gdpr-india-dpdp' },
        { label: 'EEOC & adverse impact', to: '/mimic/trust/eeoc-adverse-impact' },
      ]},
      { title: 'Security', links: [
        { label: 'Trust Center', to: '/mimic/trust/trust-center' },
        { label: 'Certifications', to: '/mimic/trust/certifications' },
        { label: 'Data residency & retention', to: '/mimic/trust/data-residency-retention' },
        { label: 'Sub-processors', to: '/mimic/trust/sub-processors' },
        { label: 'Status page', to: '/mimic/trust/status' },
      ]},
    ],
  },
  {
    key: 'Resources', label: 'Resources', to: '/mimic/resources',
    columns: [
      { title: 'Learn', links: [
        { label: 'Blog', to: '/mimic/resources/blog' },
        { label: 'Guides & playbooks', to: '/mimic/resources/guides' },
        { label: 'Webinars', to: '/mimic/resources/webinars' },
        { label: 'Interview question library', to: '/mimic/resources/question-library' },
        { label: 'Rubric templates', to: '/mimic/resources/rubric-templates' },
        { label: 'Glossary', to: '/mimic/resources/glossary' },
      ]},
      { title: 'Proof', links: [
        { label: 'Customer stories', to: '/mimic/resources/customer-stories' },
        { label: 'ROI calculator', to: '/mimic/resources/roi-calculator' },
        { label: 'Benchmark report', to: '/mimic/resources/benchmark-report' },
      ]},
      { title: 'Build', links: [
        { label: 'Documentation', to: '/mimic/resources/documentation' },
        { label: 'API reference', to: '/mimic/resources/api-reference' },
        { label: 'ATS integrations', to: '/mimic/resources/ats-integrations' },
        { label: 'Changelog', to: '/mimic/resources/changelog' },
        { label: 'Help centre', to: '/mimic/resources/help' },
      ]},
    ],
  },
  {
    key: 'Company', label: 'Company', to: '/mimic/company',
    columns: [
      { title: 'About', links: [
        { label: 'About TalbotIQ', to: '/mimic/company/about' },
        { label: 'Careers', to: '/mimic/company/careers' },
        { label: 'Newsroom', to: '/mimic/company/newsroom' },
        { label: 'Contact', to: '/mimic/company/contact' },
      ]},
      { title: 'Connect', links: [
        { label: 'Partners', to: '/mimic/company/partners' },
        { label: 'Become a reseller', to: '/mimic/company/reseller' },
        { label: 'Events', to: '/mimic/company/events' },
        { label: 'Legal & privacy', to: '/mimic/company/legal' },
      ]},
    ],
  },
]

/* ─── Section hubs (real overview pages so every top-level item resolves) ──── */
const HUBS: MktPage[] = [
  {
    slug: 'platform', section: 'Platform', sectionTo: '/mimic/platform', tier: 'hub',
    kicker: 'Platform', h1: 'One platform. Every way to interview a candidate.',
    metaTitle: 'Mimic Platform — AI interview tracks & workflow',
    metaDesc: 'Five interview tracks, bulk invitations, templates, pipelines and one rubric — plus reports, analytics and the Mimic Guide assistant.',
    intro: 'Mimic interviews candidates five different ways, runs the whole workflow from invite to shortlist, and turns every answer into an evidence-backed score. Explore the pieces.',
    sections: [
      { h2: 'Interview tracks', body: 'Pick the format that fits the role — every track scores on the same rubric.', bullets: ['Conversational chat', 'Voice screening', 'AI video avatar', 'Live two-way call', 'Timed Q&A'] },
      { h2: 'Workflow', body: 'From a spreadsheet to interviews in inboxes, then a shortlist.', bullets: ['Bulk invitations', 'Interview templates', 'Question sets', 'Multi-round pipelines', 'Rubrics & scoring'] },
      { h2: 'Intelligence', body: 'Evidence-backed scores, analytics and an assistant that operates the product.', bullets: ['Candidate reports', 'Recruiter analytics', 'Signal analysis', 'Mimic Guide assistant'] },
    ],
    cta: { title: 'See the platform on your roles', sub: 'Book a 30-minute walkthrough — no card required.' },
  },
  {
    slug: 'solutions', section: 'Solutions', sectionTo: '/mimic/solutions', tier: 'hub',
    kicker: 'Solutions', h1: 'The right screen for every kind of hire.',
    metaTitle: 'Mimic Solutions — AI screening by use case & team',
    metaDesc: 'See how Mimic screens candidates for high-volume, campus, technical and frontline hiring — and what changes for recruiters, hiring managers and RPOs.',
    intro: 'Mimic is one platform, but the job it does looks different depending on who you are hiring and who is doing the hiring. Start with the use case closest to yours.',
    sections: [
      { h2: 'By use case', body: 'The shape of the problem changes with volume, seniority and format.', bullets: ['High-volume hiring', 'Campus & graduate', 'Technical screening', 'Sales & customer-facing', 'Frontline & hourly', 'Internal mobility'] },
      { h2: 'By team', body: 'What Mimic returns to your week depends on your seat.', bullets: ['Talent acquisition leaders', 'Recruiters', 'Hiring managers', 'RPO & staffing agencies', 'People analytics'] },
      { h2: 'By industry', body: 'Rubrics and question sets tuned to how your industry actually interviews.', bullets: ['BPO & contact centres', 'IT services', 'Retail & hospitality', 'Healthcare', 'Financial services'] },
    ],
    cta: { title: 'See Mimic on your roles', sub: 'Book a 30-minute walkthrough on your own open reqs.' },
  },
  {
    slug: 'trust', section: 'Trust', sectionTo: '/mimic/trust', tier: 'hub',
    kicker: 'Trust', h1: 'AI hiring your legal team can actually sign off.',
    metaTitle: 'Mimic Trust — responsible AI, compliance & security',
    metaDesc: 'How Mimic scores, how bias is tested, how humans stay in the loop, and how we map to the EU AI Act, NYC Local Law 144, Illinois AIVIA, GDPR and EEOC.',
    intro: 'In AI hiring, the deal-blocker is rarely price — it is the security, legal and DEI review. This section answers those questions directly, before they land in your procurement queue.',
    sections: [
      { h2: 'Responsible AI', body: 'How scoring works, how we test for adverse impact, and where a human decides.', bullets: ['How Mimic scores', 'Bias testing & audits', 'Human-in-the-loop review', 'Model & data transparency', 'Candidate rights'] },
      { h2: 'Compliance', body: 'How Mimic maps to the regulations your review will raise.', bullets: ['EU AI Act', 'NYC Local Law 144', 'Illinois AI Video Interview Act', 'GDPR & India DPDP', 'EEOC & adverse impact'] },
      { h2: 'Security', body: 'Where your data lives, who touches it, and how long it is kept.', bullets: ['Trust Center', 'Certifications', 'Data residency & retention', 'Sub-processors', 'Status page'] },
    ],
    cta: { title: 'Talk to our security team', sub: 'We will walk your legal and infosec reviewers through the controls.' },
  },
  {
    slug: 'resources', section: 'Resources', sectionTo: '/mimic/resources', tier: 'hub',
    kicker: 'Resources', h1: 'Learn how the best teams screen at volume.',
    metaTitle: 'Mimic Resources — guides, docs & customer proof',
    metaDesc: 'Playbooks, an interview question library, rubric templates, docs and an API reference — everything to run structured, fair AI screening well.',
    intro: 'Practical material for the people who run screening day to day — and the developers who wire Mimic into your stack.',
    sections: [
      { h2: 'Learn', body: 'Field-tested playbooks and reference material.', bullets: ['Blog', 'Guides & playbooks', 'Webinars', 'Interview question library', 'Rubric templates', 'Glossary'] },
      { h2: 'Proof', body: 'What Mimic changes, in numbers and in stories.', bullets: ['Customer stories', 'ROI calculator', 'Benchmark report'] },
      { h2: 'Build', body: 'For developers and RevOps wiring Mimic into your ATS.', bullets: ['Documentation', 'API reference', 'ATS integrations', 'Changelog', 'Help centre'] },
    ],
    cta: { title: 'Get the screening playbook', sub: 'Book a demo and we will share the material relevant to your team.' },
  },
  {
    slug: 'company', section: 'Company', sectionTo: '/mimic/company', tier: 'hub',
    kicker: 'Company', h1: 'Mimic is built by TalbotIQ.',
    metaTitle: 'Company — Mimic by TalbotIQ',
    metaDesc: 'Who builds Mimic, what we believe about fair AI hiring, and how to reach us for partnerships, press, careers and support.',
    intro: 'Mimic is the AI-interview product from TalbotIQ. We build screening that measures every candidate the same way and keeps a human on every decision.',
    sections: [
      { h2: 'About', body: 'Who we are and how to reach us.', bullets: ['About TalbotIQ', 'Careers', 'Newsroom', 'Contact'] },
      { h2: 'Connect', body: 'Work with us.', bullets: ['Partners', 'Become a reseller', 'Events', 'Legal & privacy'] },
    ],
    cta: { title: 'Talk to us', sub: 'Sales, partnerships or press — we will route you to the right person.' },
  },
]

/* ─── Solutions detail pages (Tier A/B) ────────────────────────────────────── */
function solution(slug: string, kicker: string, h1: string, metaTitle: string, metaDesc: string, intro: string, sections: PageSection[], faqs: FaqItem[]): MktPage {
  return { slug: `solutions/${slug}`, section: 'Solutions', sectionTo: '/mimic/solutions', tier: 'A', kicker, h1, metaTitle, metaDesc, intro, sections, faqs, cta: { title: 'See it on your roles', sub: 'A 30-minute walkthrough on your own open reqs — no card required.' } }
}

const SOLUTION_PAGES: MktPage[] = [
  solution('high-volume-hiring', 'Use case · High-volume hiring',
    'Interview 5,000 applicants without adding a single recruiter.',
    'High-Volume Hiring Software | Mimic by TalbotIQ',
    'Screen thousands of applicants the day they apply. Mimic interviews and scores every candidate on one rubric so your team reviews a shortlist, not a queue.',
    'When a req draws hundreds of applicants, the first round becomes a staffing problem: someone has to talk to everyone, and nobody has the hours. So résumés get keyword-filtered, good people fall through, and time-to-fill stretches for weeks.',
    [
      { h2: 'The problem with a phone-screen queue', body: 'Manual first-round screening does not scale linearly — it scales with headcount you do not have. Every day a candidate waits is a day a competitor calls them first.' },
      { h2: 'How Mimic handles volume', body: 'Every applicant is invited automatically and interviews on their own schedule, on a phone if that is what they have. Answers are scored against one rubric with the evidence attached.', bullets: ['Bulk-invite from a CSV, ATS export, or one link', 'Async chat, voice or video — no scheduling', 'One rubric, so 5,000 scores compare directly'] },
      { h2: 'What changes for your team', body: 'Recruiters stop being the bottleneck and start working a ranked shortlist. Hiring managers see evidence, not just a résumé.' },
    ],
    [
      { q: 'Does volume slow scoring down?', a: 'No — interviews are scored as they complete, around the clock, so your shortlist keeps filling whether it is 50 applicants or 5,000.' },
      { q: 'What about candidate experience at scale?', a: 'Candidates interview when it suits them and get a consistent, structured experience instead of waiting weeks for a callback.' },
    ]),
  solution('campus-graduate', 'Use case · Campus & graduate',
    'Give every graduate applicant a fair first interview.',
    'Campus & Graduate Recruiting Software | Mimic',
    'Interview an entire graduate cohort in days, not months. Résumé-adaptive questions and one rubric mean every student gets the same fair shot.',
    'Campus hiring compresses a year of applications into a few frantic weeks. Volume spikes, résumés look identical, and the students you want have three other offers by the time you schedule a call.',
    [
      { h2: 'Why graduate volume breaks manual screening', body: 'Thousands of near-identical résumés arrive in the same fortnight. Keyword filters cut good people; scheduling cannot keep pace.' },
      { h2: 'How Mimic runs a cohort', body: 'Invite the whole cohort at once. Each interview reads the student’s résumé and asks about what they actually did, not a generic “tell me about yourself”.', bullets: ['Same-day interviews for the whole cohort', 'Résumé-adaptive questions per student', 'Structured scores career services can defend'] },
      { h2: 'What changes', body: 'You reach strong students before your competitors, and every applicant gets a real, fair interview instead of a silent rejection.' },
    ],
    [{ q: 'Can we share results with a university?', a: 'You can export structured, evidence-backed scores — useful for career-services partnerships. [PLACEHOLDER: confirm cohort-export details]' }]),
  solution('technical-screening', 'Use case · Technical screening',
    'Screen for real skill before an engineer’s calendar gets involved.',
    'Technical Screening Software | Mimic by TalbotIQ',
    'Résumé-adaptive technical interviews that probe depth, not buzzwords — scored on one rubric so your engineers only meet candidates worth their time.',
    'Engineering interview time is your scarcest resource, and most of it is spent on candidates who will not pass. The first technical screen is where that waste starts.',
    [
      { h2: 'The cost of a shallow first screen', body: 'Keyword-matched résumés put unqualified candidates in front of senior engineers, burning the exact hours you are trying to protect.' },
      { h2: 'How Mimic screens for depth', body: 'Interviews adapt to what the résumé claims and follow up when an answer is thin — with per-question timers for skills that need pressure.', bullets: ['Résumé-adaptive follow-ups', 'Timed Q&A for pressure-testing', 'Evidence-cited scores per dimension'] },
      { h2: 'What changes for engineering', body: 'Your engineers meet a short, strong list, and every candidate is measured against the same bar.' },
    ],
    [{ q: 'Is this a coding test?', a: 'Mimic focuses on structured technical conversation and reasoning; pair it with your existing coding assessment rather than replacing it. [PLACEHOLDER: confirm coding-assessment integrations]' }]),
  solution('sales-customer-facing', 'Use case · Sales & customer-facing',
    'Hear how a candidate actually sells — before you book the panel.',
    'Sales Hiring & Screening Software | Mimic',
    'Voice and video interviews that surface communication, objection handling and presence — scored consistently so your best closers reach the shortlist.',
    'For sales and customer-facing roles, the résumé tells you almost nothing that matters. How someone communicates under a little pressure is the job — and you cannot read it off a CV.',
    [
      { h2: 'Why résumés fail sales hiring', body: 'Quota history is noisy and hard to verify; the signal you need is live communication, which manual screening only reaches after weeks of scheduling.' },
      { h2: 'How Mimic surfaces the signal', body: 'Voice and video tracks assess tone, pacing and content together, with the same rubric applied to every candidate.', bullets: ['Voice & video screening', 'Signal analysis on delivery', 'Consistent rubric across candidates'] },
      { h2: 'What changes', body: 'Managers hear real communication early and spend panel time only on candidates who can actually carry a conversation.' },
    ],
    [{ q: 'Can we score for specific competencies?', a: 'Yes — build a rubric around the competencies that matter for the role (discovery, objection handling, clarity) and Mimic scores every candidate against it.' }]),
  solution('frontline-hourly', 'Use case · Frontline & hourly',
    'Fill frontline roles before the applicant takes another job.',
    'Frontline & Hourly Hiring Software | Mimic',
    'Mobile-first chat interviews that hourly candidates finish in minutes — so you screen and shortlist the same day applications arrive.',
    'Frontline hiring is a race. Hourly candidates apply to several employers at once and take the first real offer. A screening process measured in days loses them to one measured in hours.',
    [
      { h2: 'Speed is the whole game', body: 'Every day in the queue is a candidate lost to a faster employer. Manual screening cannot move at frontline speed.' },
      { h2: 'How Mimic moves same-day', body: 'A text interview candidates finish on a phone in minutes, scored instantly so you can reach out while they are still interested.', bullets: ['Mobile-first, no scheduling', 'Finishes in minutes', 'Instant, consistent scoring'] },
      { h2: 'What changes', body: 'You contact strong candidates first, and location managers get a ready shortlist instead of a stack of applications.' },
    ],
    [{ q: 'Do candidates need an app or account?', a: 'No — they open a link and interview in the browser on their phone.' }]),
  solution('internal-mobility', 'Use case · Internal mobility',
    'Give internal candidates the same fair, structured shot.',
    'Internal Mobility & Talent Screening | Mimic',
    'Screen internal applicants against the same rubric as external ones — a defensible, consistent process that helps people grow without favouritism.',
    'Internal mobility often runs on hallway conversations and manager relationships. That is how good internal candidates get overlooked and how bias claims start.',
    [
      { h2: 'The risk of informal internal hiring', body: 'Inconsistent, undocumented internal processes are hard to defend and easy to skew toward whoever is most visible.' },
      { h2: 'How Mimic standardises it', body: 'Internal applicants take the same structured interview and are scored on the same rubric, with the evidence recorded.', bullets: ['Same rubric as external candidates', 'Documented, defensible decisions', 'A real shot for quieter high-performers'] },
      { h2: 'What changes', body: 'People see a fair path to grow, and HR has a record that stands up to scrutiny.' },
    ],
    [{ q: 'Can managers still weigh in?', a: 'Yes — scores are recommendations with evidence; the hiring manager still decides, now with a consistent baseline.' }]),
]

/* ─── Solutions "by team" + "by industry" (Tier B — real, tighter pages) ───── */
function brief(slug: string, kicker: string, h1: string, metaTitle: string, metaDesc: string, intro: string, sections: PageSection[]): MktPage {
  return { slug: `solutions/${slug}`, section: 'Solutions', sectionTo: '/mimic/solutions', tier: 'B', kicker, h1, metaTitle, metaDesc, intro, sections, cta: { title: 'See it on your roles', sub: 'Book a 30-minute walkthrough on your own open reqs.' } }
}
const SOLUTION_BRIEFS: MktPage[] = [
  brief('talent-acquisition-leaders', 'Team · TA leaders', 'Cut time-to-fill without cutting corners on fairness.', 'For Talent Acquisition Leaders | Mimic', 'Give your TA org capacity and a defensible, consistent screening process — with analytics by role, team and recruiter.', 'You are asked to hire faster, cheaper and more fairly at the same time. Mimic gives your team first-round capacity back and gives you the analytics to prove the process is consistent.', [ { h2: 'What you get', body: 'Capacity, consistency and evidence.', bullets: ['First round runs itself, at any volume', 'One rubric across every recruiter and track', 'Analytics by role, template, track and recruiter'] } ]),
  brief('recruiters', 'Team · Recruiters', 'Stop phone-screening. Start working a shortlist.', 'For Recruiters | Mimic by TalbotIQ', 'Mimic runs your first round so you spend your day on the candidates most worth your time — with evidence for every score.', 'The first round is the least strategic part of your week and the biggest time sink. Mimic takes it off your plate and hands you a ranked, evidence-backed shortlist.', [ { h2: 'What changes for you', body: 'Less scheduling, more judgement.', bullets: ['No calendar tetris for first rounds', 'Evidence behind every score', 'More time on offers and candidate care'] } ]),
  brief('hiring-managers', 'Team · Hiring managers', 'Meet a short list of people actually worth your time.', 'For Hiring Managers | Mimic', 'See evidence-backed scores, not just résumés, so your interview time goes to candidates who can do the job.', 'You do not have time to interview a long list, and a résumé does not tell you who can do the work. Mimic gives you a short list with the evidence behind each score.', [ { h2: 'What you get', body: 'Signal before you spend an hour.', bullets: ['Ranked shortlist with evidence', 'Per-question breakdowns', 'A consistent bar across candidates'] } ]),
  brief('rpo-staffing', 'Team · RPO & staffing', 'Screen more roles per recruiter, across every client.', 'RPO & Staffing Agency Screening | Mimic', 'Run structured, branded screening at agency scale — more submittals per recruiter, consistent quality across every client account.', 'Your margin is recruiter time. Manual first rounds cap how many roles each recruiter can carry and make quality uneven across clients.', [ { h2: 'What changes for your agency', body: 'More throughput, consistent quality.', bullets: ['More roles per recruiter', 'Consistent quality across accounts', 'Client-ready, evidence-backed submittals'] } ]),
  brief('people-analytics', 'Team · People analytics', 'Screening data you can actually analyse.', 'People Analytics for Hiring | Mimic', 'Every candidate scored on one rubric with the evidence recorded — structured hiring data by role, template, track and recruiter.', 'Most screening produces no usable data — just notes in inboxes. Mimic produces structured, comparable scores you can analyse and defend.', [ { h2: 'What you get', body: 'Clean, comparable hiring data.', bullets: ['One rubric = comparable scores', 'Adverse-impact reporting per dimension', 'Exportable, auditable records'] } ]),
  brief('bpo-contact-centres', 'Industry · BPO & contact centres', 'Screen contact-centre agents at the speed you lose them.', 'BPO & Contact Centre Hiring | Mimic', 'Voice-first, mobile screening for high-attrition contact-centre roles — assess communication and score consistently, same day.', 'Contact-centre hiring is high-volume and high-attrition: you are always hiring, and speed plus communication signal are everything.', [ { h2: 'Why Mimic fits BPO', body: 'Volume, speed and the right signal.', bullets: ['Voice screening for comms signal', 'Same-day, mobile-first', 'Scales to constant req volume'] } ]),
  brief('it-services', 'Industry · IT services', 'Bench-ready technical screening at project speed.', 'IT Services Hiring & Screening | Mimic', 'Résumé-adaptive technical interviews to staff projects fast without burning senior engineers on unqualified first rounds.', 'IT services hiring is bursty and skill-specific — you need qualified people bench-ready when a project lands, without wasting senior engineers on screening.', [ { h2: 'Why Mimic fits IT services', body: 'Depth, fast.', bullets: ['Résumé-adaptive technical screens', 'Scales with project demand', 'Protects senior-engineer time'] } ]),
  brief('retail-hospitality', 'Industry · Retail & hospitality', 'Staff every location before the season peaks.', 'Retail & Hospitality Hiring | Mimic', 'Mobile-first, same-day screening for seasonal and frontline retail and hospitality roles across every location.', 'Retail and hospitality hiring spikes with the season and spans many locations. Speed and a consistent bar across sites are what you need.', [ { h2: 'Why Mimic fits retail', body: 'Fast, consistent, everywhere.', bullets: ['Same-day mobile screening', 'Consistent bar across locations', 'Handles seasonal spikes'] } ]),
  brief('healthcare', 'Industry · Healthcare', 'Screen clinical staff against a defensible rubric.', 'Healthcare Hiring & Screening | Mimic', 'Structured screening for clinical and support roles — consistent, evidence-backed, and built for shift-based, high-demand hiring.', 'Healthcare hiring is high-stakes and heavily scrutinised: you need a consistent, defensible process that still moves fast enough to fill shifts.', [ { h2: 'Why Mimic fits healthcare', body: 'Consistent and defensible.', bullets: ['Rubrics tuned to clinical roles', 'Evidence-backed, auditable scores', 'Handles shift-based volume'] } ]),
  brief('financial-services', 'Industry · Financial services', 'Screen at scale with an audit trail regulators accept.', 'Financial Services Hiring | Mimic', 'Consistent, evidence-backed screening with the audit trail and controls financial-services compliance teams expect.', 'Financial-services hiring runs under real regulatory and audit scrutiny. Every screening decision needs to be consistent, evidenced and defensible.', [ { h2: 'Why Mimic fits financial services', body: 'Scale with an audit trail.', bullets: ['One rubric, fully evidenced', 'Adverse-impact reporting', 'Auditable decision records'] } ]),
]

/* ─── Trust pages ──────────────────────────────────────────────────────────
 * Legal is the deal-blocker in AI hiring, so these describe capabilities and
 * controls FACTUALLY and never assert an attestation, certification or legal
 * compliance we cannot prove — those are [PLACEHOLDER] for the team to confirm.
 * Compliance pages explain how Mimic supports a regulation; they are not legal
 * advice. */
function trust(slug: string, tier: 'A' | 'B', kicker: string, h1: string, metaTitle: string, metaDesc: string, intro: string, sections: PageSection[], faqs?: FaqItem[]): MktPage {
  return { slug: `trust/${slug}`, section: 'Trust', sectionTo: '/mimic/trust', tier, kicker, h1, metaTitle, metaDesc, intro, sections, faqs, cta: { title: 'Talk to our security team', sub: 'We will walk your legal and infosec reviewers through the controls.' } }
}
const TRUST_PAGES: MktPage[] = [
  trust('how-mimic-scores', 'A', 'Responsible AI · Scoring', 'See exactly how every score is reached.',
    'How Mimic Scores Candidates | Responsible AI',
    'A Mimic score is a recommendation with the evidence attached — measured against the rubric you set, dimension by dimension. Here is precisely how it works.',
    'A score you cannot explain is a score your legal team will not accept. Mimic is built so every number traces back to a specific answer and a rubric you defined.',
    [
      { h2: 'A score is a recommendation, not a verdict', body: 'Mimic produces a recommendation with evidence. A human reviews it and decides. Nothing is auto-rejected.' },
      { h2: 'You set the rubric', body: 'You define the dimensions and their weights. The same rubric is applied identically to every candidate for that role.', bullets: ['Dimensions and weights you control', 'Applied identically to everyone', 'Versioned, so you can show what changed'] },
      { h2: 'Every dimension cites its evidence', body: 'Each rubric dimension links to the exact answer, transcript span or signal it came from — so a reviewer can check the working, not just trust the number.' },
      { h2: 'What Mimic does not do', body: 'Mimic does not infer protected characteristics and does not use them in scoring. [PLACEHOLDER: confirm the exact model-input policy your team will publish]' },
    ],
    [{ q: 'Can a recruiter override a score?', a: 'Yes. Scores are recommendations; recruiters advance, reject or override, and every action is logged.' }, { q: 'Is the rubric the same for every candidate?', a: 'Yes — for a given role, one rubric is applied identically, which is what makes scores comparable and defensible.' }]),
  trust('bias-testing-audits', 'A', 'Responsible AI · Bias', 'Bias testing you can read, not take on faith.',
    'Bias Testing & Audits | Mimic Responsible AI',
    'Adverse-impact testing reported per rubric dimension, not summarised — so your DEI and legal teams can see the evidence, not a marketing claim.',
    '“Responsible AI” is on every vendor’s site. What your review actually needs is the adverse-impact numbers, per dimension, that you can hand to counsel.',
    [
      { h2: 'Adverse-impact testing per dimension', body: 'Selection rates are reported for each rubric dimension so disparate impact is visible where it happens, not hidden in an overall average.' },
      { h2: 'Independent review', body: '[PLACEHOLDER: confirm the third-party auditor, scope and cadence, and whether results are published].' },
      { h2: 'You can monitor it continuously', body: 'Analytics let you watch selection rates across groups over time, so a drift is caught early rather than in a lawsuit.' },
    ],
    [{ q: 'Do you publish audit results?', a: '[PLACEHOLDER: confirm what is published and where — e.g. an annual bias-audit summary.]' }]),
  trust('human-in-the-loop', 'A', 'Responsible AI · Oversight', 'A human makes every hiring decision.',
    'Human-in-the-Loop Review | Mimic',
    'Mimic recommends; people decide. Advancing, rejecting and overriding are recruiter actions — and every one is logged for a complete audit trail.',
    'Automated hiring decisions are exactly what regulators and candidates fear. Mimic is designed so the machine never makes the call.',
    [
      { h2: 'Mimic recommends, people decide', body: 'Every outcome that affects a candidate is a human action taken with the evidence in front of them.' },
      { h2: 'Every action is logged', body: 'Who advanced, rejected or overrode whom, when, and on what basis — a complete, exportable audit trail.', bullets: ['Advance / reject / override are human actions', 'Timestamped, attributed audit log', 'Exportable for review or dispute'] },
      { h2: 'Why this matters', body: 'Meaningful human oversight is a requirement under emerging AI-hiring law. Building it in is not a feature — it is the point.' },
    ],
    [{ q: 'Does Mimic ever reject a candidate on its own?', a: 'No. Rejection is always a logged human action.' }]),
  trust('model-data-transparency', 'B', 'Responsible AI · Transparency', 'Know what the model sees — and what it doesn’t.',
    'Model & Data Transparency | Mimic', 'What goes into a Mimic score, what is deliberately excluded, and where to find the model documentation your review team needs.',
    'Transparency is not a slogan; it is a list of inputs your reviewers can check.',
    [ { h2: 'What the model uses', body: 'Answers, transcripts and role-relevant signals, measured against your rubric.' }, { h2: 'What is excluded', body: 'Protected characteristics are not inferred or used. [PLACEHOLDER: confirm the exact input/exclusion list and model documentation to link here].' } ]),
  trust('candidate-rights', 'B', 'Responsible AI · Candidates', 'Candidates know they’re interviewing with AI.',
    'Candidate Rights & AI Disclosure | Mimic', 'Clear disclosure, consent, accommodation and data-access rights for every candidate Mimic interviews — the basics fair AI hiring requires.',
    'Candidate trust is part of your employer brand. Mimic makes disclosure and rights explicit, not buried.',
    [ { h2: 'Disclosure and consent', body: 'Candidates are told they are interviewing with AI and consent before starting. [PLACEHOLDER: confirm your consent-copy and jurisdictions].' }, { h2: 'Accommodation and access', body: 'Candidates can request accommodations and access or deletion of their data. [PLACEHOLDER: confirm the accommodation process].' } ]),
  trust('eu-ai-act', 'B', 'Compliance · EU AI Act', 'Built for the EU AI Act’s high-risk requirements.',
    'Mimic & the EU AI Act | Compliance', 'How Mimic supports EU AI Act obligations for hiring systems — transparency, human oversight, logging and documentation. Not legal advice.',
    'The EU AI Act classifies hiring AI as high-risk, which brings transparency, oversight, logging and documentation duties. Mimic is built to support them.',
    [ { h2: 'What the Act asks of hiring AI', body: 'Transparency to candidates, meaningful human oversight, record-keeping, and technical documentation, among others.' }, { h2: 'How Mimic supports it', body: 'AI disclosure to candidates, human-in-the-loop decisions, a complete audit log, and model documentation.', bullets: ['Candidate AI disclosure', 'Human oversight on every decision', 'Exportable audit logs', 'Model documentation [PLACEHOLDER: link]'] }, { h2: 'Not legal advice', body: 'This describes product capabilities. Your own counsel determines your obligations. [PLACEHOLDER: confirm counsel-reviewed statement].' } ]),
  trust('nyc-local-law-144', 'B', 'Compliance · NYC LL144', 'Ready for NYC Local Law 144 bias audits.',
    'Mimic & NYC Local Law 144 | Compliance', 'How Mimic supports NYC Local Law 144: the data behind an annual bias audit and the candidate notice the law requires. Not legal advice.',
    'NYC Local Law 144 requires an annual independent bias audit of automated employment decision tools and advance notice to candidates.',
    [ { h2: 'What LL144 requires', body: 'An annual third-party bias audit, publication of a summary, and notice to NYC candidates before use.' }, { h2: 'How Mimic supports it', body: 'Per-dimension selection-rate data for the audit, and candidate notice built into the flow.', bullets: ['Audit-ready selection-rate data', 'Candidate notice in the invite flow', '[PLACEHOLDER: confirm auditor + published summary]'] } ]),
  trust('illinois-aivia', 'B', 'Compliance · Illinois AIVIA', 'Supports the Illinois AI Video Interview Act.',
    'Mimic & Illinois AIVIA | Compliance', 'How Mimic supports the Illinois AI Video Interview Act: candidate notice, consent, and deletion on request. Not legal advice.',
    'For video interviews of Illinois candidates, AIVIA requires notice, consent, an explanation of how the AI works, and deletion on request.',
    [ { h2: 'What AIVIA requires', body: 'Notice before the interview, consent, a plain explanation of the AI, and deletion within 30 days of a request.' }, { h2: 'How Mimic supports it', body: 'Built-in disclosure and consent, a plain-language explanation, and data deletion controls. [PLACEHOLDER: confirm deletion SLA copy].' } ]),
  trust('gdpr-india-dpdp', 'B', 'Compliance · GDPR & DPDP', 'GDPR and India DPDP data controls, built in.',
    'GDPR & India DPDP | Mimic Compliance', 'Lawful basis, candidate data-subject rights, regional residency and configurable retention for GDPR and India’s DPDP Act. Not legal advice.',
    'Handling candidate data under GDPR and India’s DPDP Act means consent, data-subject rights, residency and retention — all first-class in Mimic.',
    [ { h2: 'Rights and consent', body: 'Consent capture, and access, rectification, erasure and portability on request.' }, { h2: 'Residency and retention', body: 'Regional data residency and configurable retention with purge on request. [PLACEHOLDER: confirm available regions and DPO contact].' } ]),
  trust('eeoc-adverse-impact', 'B', 'Compliance · EEOC', 'One rubric, applied identically — and measured.',
    'EEOC & Adverse Impact | Mimic Compliance', 'How a single, consistently-applied rubric plus per-dimension selection-rate reporting helps you monitor adverse impact under EEOC guidance. Not legal advice.',
    'US employers are expected to monitor selection procedures for adverse impact. A consistent, measured process is your best defence.',
    [ { h2: 'What adverse impact is', body: 'A selection rate for one group substantially below another (often referenced against the four-fifths rule).' }, { h2: 'How Mimic helps you monitor it', body: 'One rubric applied identically, with selection rates reported per dimension and an evidence trail for every decision.', bullets: ['Identical rubric for every candidate', 'Per-dimension selection-rate reporting', 'Evidence trail for defensibility'] } ]),
  trust('trust-center', 'A', 'Security · Trust Center', 'Everything security and legal need, in one place.',
    'Mimic Trust Center | Security & Compliance', 'Security controls, data-handling practices, sub-processors and reports — one place for your infosec and legal reviewers to get answers fast.',
    'A good Trust Center shortens your sales cycle: reviewers self-serve the answers instead of waiting on a questionnaire round-trip.',
    [ { h2: 'What’s here', body: 'An overview of security controls, data handling, residency and retention, sub-processors, and how to request reports.' }, { h2: 'Documents & reports', body: '[PLACEHOLDER: list the reports available on request — e.g. security whitepaper, pen-test summary — and how to request them].' }, { h2: 'How to get access', body: 'Reviewers can request gated documents under NDA. [PLACEHOLDER: request process / contact].' } ]),
  trust('certifications', 'B', 'Security · Certifications', 'Certifications & attestations.',
    'Certifications & Attestations | Mimic Security', 'The security and compliance attestations Mimic holds, and how to request the underlying reports for your review.',
    'We only list attestations we actually hold. Anything below marked as a placeholder is not yet claimed.',
    [ { h2: 'Attestations', body: '[PLACEHOLDER: list only certifications actually held — e.g. SOC 2 Type II, ISO 27001, ISO 42001. Do not display any that are not yet attested].' }, { h2: 'Requesting reports', body: 'Certification reports are available to qualified reviewers under NDA. [PLACEHOLDER: request process].' } ]),
  trust('data-residency-retention', 'B', 'Security · Data', 'Your data stays where you need it, only as long as you need it.',
    'Data Residency & Retention | Mimic Security', 'Choose where candidate data is stored, set how long it is kept, and purge on request — the residency and retention controls enterprise review expects.',
    'Where data lives and how long it is kept are the two questions every security review asks first.',
    [ { h2: 'Residency', body: 'Store candidate data in your required region. [PLACEHOLDER: confirm available regions].' }, { h2: 'Retention & purge', body: 'Configurable retention windows and deletion on request, including GDPR/DPDP erasure.' } ]),
  trust('sub-processors', 'B', 'Security · Sub-processors', 'Who we work with to run Mimic.',
    'Sub-processors | Mimic Security', 'The third-party sub-processors Mimic uses, what each does, and how we notify you of changes — full supply-chain transparency for your review.',
    'Your DPA review needs the sub-processor list. Here it is, with change notifications so nothing moves without your knowledge.',
    [ { h2: 'The list', body: '[PLACEHOLDER: current sub-processor list — name, purpose, region for each].' }, { h2: 'Change notifications', body: 'We notify customers before adding or changing a sub-processor. [PLACEHOLDER: notification method + notice period].' } ]),
  trust('status', 'B', 'Security · Status', 'Mimic system status.',
    'System Status | Mimic', 'Live service status, incident history and subscribe-for-updates — so your team always knows Mimic is up before a screening window opens.',
    'When you are screening at volume, uptime transparency is not optional.',
    [ { h2: 'Live status & history', body: 'Real-time component status and a public incident history. [PLACEHOLDER: status-page URL].' }, { h2: 'Subscribe', body: 'Subscribe to get notified of incidents and maintenance. [PLACEHOLDER: subscribe link].' } ]),
]

/* ─── Resources + Company (Tier C mostly; honest empty states, no fake data) ── */
function page(slug: string, tier: 'A' | 'B' | 'C', kicker: string, h1: string, metaTitle: string, metaDesc: string, intro: string, sections: PageSection[], ctaTitle: string, ctaSub: string): MktPage {
  const section = slug.startsWith('resources') ? 'Resources' : 'Company'
  return { slug, section, sectionTo: slug.startsWith('resources') ? '/mimic/resources' : '/mimic/company', tier, kicker, h1, metaTitle, metaDesc, intro, sections, cta: { title: ctaTitle, sub: ctaSub } }
}
const RESOURCE_PAGES: MktPage[] = [
  page('resources/blog', 'C', 'Learn · Blog', 'Field notes on screening at volume.', 'Mimic Blog — AI hiring & screening', 'Practical writing on structured interviews, fair AI scoring and hiring at volume from the team building Mimic.', 'Short, useful posts on running structured, fair screening — no thought-leadership filler.', [ { h2: 'What you’ll find here', body: 'Practical pieces on rubrics, adverse-impact monitoring, candidate experience and hiring at volume.' }, { h2: 'Nothing published yet', body: 'We’re just getting started. Subscribe or book a demo and we’ll share the first pieces as they land — we won’t pad this page with filler.' } ], 'Get the first posts', 'Book a demo and we’ll add you to the list.'),
  page('resources/guides', 'C', 'Learn · Guides', 'Playbooks for structured, fair screening.', 'Guides & Playbooks | Mimic', 'Step-by-step playbooks for designing rubrics, running high-volume screening and monitoring adverse impact.', 'Longer-form, field-tested playbooks your team can act on the same day.', [ { h2: 'Topics we cover', body: 'Designing a rubric hiring managers trust; running a high-volume req; monitoring adverse impact; writing résumé-adaptive questions.' }, { h2: 'Get a copy', body: '[PLACEHOLDER: which guides are downloadable, and gating]. Ask us and we’ll send the ones relevant to your team.' } ], 'Request the playbooks', 'Tell us your use case and we’ll share what fits.'),
  page('resources/webinars', 'C', 'Learn · Webinars', 'Live and on-demand sessions.', 'Webinars | Mimic', 'Live and recorded sessions on fair AI screening, rubric design and hiring at volume.', 'Sessions with our team and practitioners on getting structured screening right.', [ { h2: 'What’s coming', body: 'Working sessions on rubric design, compliance-ready screening and candidate experience.' }, { h2: 'No sessions scheduled yet', body: 'Register your interest and we’ll notify you of the first one. [PLACEHOLDER: webinar platform / schedule].' } ], 'Register interest', 'Book a demo and we’ll invite you to the next session.'),
  page('resources/question-library', 'B', 'Learn · Questions', 'A library of role-ready interview questions.', 'Interview Question Library | Mimic', 'Structured, role-specific interview questions you can attach to any template — or let Mimic adapt them to each résumé.', 'Start from proven questions instead of a blank page — then let each interview adapt them to the candidate.', [ { h2: 'How it works in Mimic', body: 'Build fixed question sets, attach them to a template, or generate from a résumé. Every question maps to a rubric dimension.' }, { h2: 'Browse the library', body: '[PLACEHOLDER: is the library public, or in-product only? Link accordingly].' } ], 'See it in the product', 'Book a demo to browse the library on your roles.'),
  page('resources/rubric-templates', 'B', 'Learn · Rubrics', 'Rubric templates you can start from.', 'Rubric Templates | Mimic', 'Pre-built scoring rubrics for common roles — weighted dimensions you can adopt as-is or tune to your bar.', 'A good rubric is the difference between a defensible score and a gut call. Start from one that works.', [ { h2: 'What a rubric template gives you', body: 'Weighted dimensions for a role, ready to apply identically to every candidate.' }, { h2: 'Get the templates', body: '[PLACEHOLDER: which role templates ship, and how to access].' } ], 'Start from a template', 'Book a demo and we’ll set one up on your role.'),
  page('resources/glossary', 'C', 'Learn · Glossary', 'The AI-hiring terms buyers actually ask about.', 'AI Hiring Glossary | Mimic', 'Plain-English definitions of the terms that come up in AI-hiring reviews: adverse impact, rubric, adaptive interview, human-in-the-loop.', 'The words that show up in every procurement and legal review, defined plainly.', [ { h2: 'Adverse impact', body: 'When a selection procedure passes one group at a substantially lower rate than another — often referenced against the four-fifths rule.' }, { h2: 'Rubric', body: 'A fixed set of weighted dimensions used to score every candidate for a role the same way, with evidence attached.' }, { h2: 'Résumé-adaptive interview', body: 'An interview that reads the candidate’s résumé and tailors its follow-up questions to what they actually claim.' }, { h2: 'Human-in-the-loop', body: 'A design where the AI recommends and a person makes every decision that affects a candidate.' } ], 'See these in practice', 'Book a demo to see how Mimic applies them.'),
  page('resources/customer-stories', 'A', 'Proof · Stories', 'How teams hire with Mimic.', 'Customer Stories | Mimic', 'Real results from teams screening at volume with Mimic — time-to-shortlist, recruiter hours returned and candidate experience.', 'The best proof is a team like yours. We publish stories only with the customer’s name and numbers confirmed.', [ { h2: 'What a story covers', body: 'The hiring problem, how the team rolled Mimic out, and the measured change afterwards.' }, { h2: 'Stories coming soon', body: '[PLACEHOLDER: published customer stories — name, metrics, quote, all confirmed by the customer]. We won’t post invented ones.' }, { h2: 'Be a reference', body: 'Already using Mimic and happy to share results? We’d love to tell your story.' } ], 'Talk to a reference', 'Ask us to connect you with a customer like you.'),
  page('resources/roi-calculator', 'B', 'Proof · ROI', 'Estimate what the first round is costing you.', 'ROI Calculator | Mimic', 'Estimate the recruiter hours and time-to-fill you get back by automating the first round with Mimic.', 'The first round has a price — in recruiter hours and in candidates lost to a faster competitor. Put a number on it.', [ { h2: 'What it estimates', body: 'From your monthly applicants, minutes per manual screen and loaded recruiter cost, an estimate of hours and cost returned.' }, { h2: 'Get your number', body: '[PLACEHOLDER: embed the interactive calculator here]. Meanwhile, book a demo and we’ll run the numbers on your actual volume.' } ], 'Get a tailored estimate', 'Book a demo and we’ll model it on your reqs.'),
  page('resources/benchmark-report', 'C', 'Proof · Benchmark', 'What 340,000 scored interviews reveal.', 'Screening Benchmark Report | Mimic', 'Findings from 340,000 scored interviews on screening accuracy, candidate experience and where manual screening leaks good people.', 'Aggregate findings from 340,000 scored interviews — what actually predicts a good hire, and where manual screening leaks talent.', [ { h2: 'What’s inside', body: 'Screening-accuracy findings, candidate-experience data, and where good candidates fall out of a manual funnel.' }, { h2: 'Download', body: '[PLACEHOLDER: report download / gating]. Ask us for a copy in the meantime.' } ], 'Get the report', 'Book a demo and we’ll send the benchmark report.'),
  page('resources/documentation', 'C', 'Build · Docs', 'Documentation.', 'Documentation | Mimic', 'Guides for setting up templates, question sets, pipelines and integrations, plus how scoring and rubrics work.', 'Everything to set Mimic up and run it well — for admins and developers.', [ { h2: 'What’s documented', body: 'Templates, question sets, pipelines, rubrics, roles/permissions, and integration setup.' }, { h2: 'Read the docs', body: '[PLACEHOLDER: documentation URL].' } ], 'Get set up fast', 'Book a demo and we’ll walk your team through setup.'),
  page('resources/api-reference', 'C', 'Build · API', 'API reference.', 'API Reference | Mimic', 'Programmatically create sessions, invite candidates, and pull scored results into your own systems.', 'Wire Mimic into your stack — create sessions, invite candidates and pull results.', [ { h2: 'What the API covers', body: 'Sessions, invitations, candidates, and scored results/reports.' }, { h2: 'Reference & auth', body: '[PLACEHOLDER: API base URL, auth model and full reference link].' } ], 'Talk to our team', 'Book a demo to discuss your integration.'),
  page('resources/ats-integrations', 'A', 'Build · Integrations', 'Mimic fits the ATS you already run.', 'ATS Integrations | Mimic', 'Start today with a CSV, an ATS export or a shareable link — and connect your ATS directly on enterprise plans. No rip-and-replace.', 'You are not replacing your ATS. Mimic slots into it — start with an export today, wire up a direct connector when you’re ready.', [ { h2: 'Start with zero integration', body: 'Bulk-invite from a CSV, an ATS export, or a single shareable link. You can run your first req today.' }, { h2: 'Direct connectors', body: 'Push statuses and scores back into your ATS on enterprise plans. [PLACEHOLDER: named ATS integrations available].' }, { h2: 'What syncs', body: 'Candidates in, and scores, statuses and report links back out — so your ATS stays the system of record.' } ], 'Check your ATS', 'Book a demo and we’ll confirm your integration path.'),
  page('resources/changelog', 'C', 'Build · Changelog', 'What’s new in Mimic.', 'Changelog | Mimic', 'Product updates, improvements and fixes to Mimic — shipped continuously.', 'What we’ve shipped, in plain language.', [ { h2: 'How we ship', body: 'We release continuously and note customer-facing changes here.' }, { h2: 'Recent updates', body: '[PLACEHOLDER: real release notes — we won’t invent version history]. Subscribe to get them as they ship.' } ], 'Subscribe to updates', 'Book a demo and we’ll keep you posted.'),
  page('resources/help', 'C', 'Build · Help', 'Help centre.', 'Help Centre | Mimic', 'Answers to common setup and usage questions, plus how to reach Mimic support.', 'Quick answers, and a fast path to a human when you need one.', [ { h2: 'Common topics', body: 'Setting up templates, inviting candidates, reading reports, and managing access.' }, { h2: 'Contact support', body: '[PLACEHOLDER: support email / in-app support / hours].' } ], 'Need a hand?', 'Book a demo or reach support and we’ll help.'),
]
const COMPANY_PAGES: MktPage[] = [
  page('company/about', 'A', 'About · Company', 'AI interviews for every candidate — built by TalbotIQ.', 'About TalbotIQ — the team behind Mimic', 'TalbotIQ builds Mimic: AI interviewing that measures every candidate the same way and keeps a human on every decision.', 'We started TalbotIQ because the first round of hiring was broken: good people wait weeks, recruiters drown, and no two candidates get the same interview. Mimic is our answer.', [ { h2: 'What we believe', body: 'Every applicant deserves a real first interview; every score should carry its evidence; and a human should make every decision.' }, { h2: 'What we build', body: 'Mimic interviews and scores candidates across five tracks on one rubric — fast enough for volume, structured enough to defend.' }, { h2: 'The company', body: '[PLACEHOLDER: founded year, HQ, team size, funding — add only what is true].' } ], 'Work with us', 'Book a demo, or see open roles on the careers page.'),
  page('company/careers', 'C', 'About · Careers', 'Build the future of fair hiring.', 'Careers at TalbotIQ | Mimic', 'Join the team building AI interviewing that’s fast, fair and defensible. See open roles at TalbotIQ.', 'We’re a small team with an outsized mission: make the first round fair and fast for everyone.', [ { h2: 'How we work', body: 'Small team, high ownership, close to customers and to the product.' }, { h2: 'Open roles', body: '[PLACEHOLDER: current openings / careers-page link — we won’t list roles that aren’t open]. Don’t see a fit? Introduce yourself.' } ], 'Introduce yourself', 'Tell us where you’d make an impact.'),
  page('company/newsroom', 'C', 'About · Newsroom', 'News & press.', 'Newsroom | TalbotIQ & Mimic', 'Announcements, press coverage and media resources for TalbotIQ and Mimic.', 'Company and product news, and everything press need in one place.', [ { h2: 'Announcements', body: '[PLACEHOLDER: real announcements only]. Nothing to share yet — check back or subscribe.' }, { h2: 'Press enquiries', body: '[PLACEHOLDER: press contact email and media kit].' } ], 'Media enquiries', 'Reach out and we’ll respond quickly.'),
  page('company/contact', 'A', 'About · Contact', 'Talk to us.', 'Contact TalbotIQ | Mimic', 'Reach sales, support, partnerships or press. Book a demo, or send us a note and we’ll route you to the right person.', 'Whatever you need — a demo, a security review, a partnership — start here and we’ll get you to the right person fast.', [ { h2: 'Sales & demos', body: 'The fastest path is to book a demo — we’ll tailor it to your roles.' }, { h2: 'Support', body: 'Already a customer? Reach support through the help centre. [PLACEHOLDER: support contact].' }, { h2: 'Partnerships & press', body: '[PLACEHOLDER: partnerships and press email addresses, and postal address if you list one].' } ], 'Book a demo', 'The quickest way to a useful conversation.'),
  page('company/partners', 'C', 'Connect · Partners', 'Partner with Mimic.', 'Partners | Mimic by TalbotIQ', 'Technology and services partners who help customers screen faster and more fairly with Mimic.', 'We work with ATS platforms, RPOs and services firms to get customers to value faster.', [ { h2: 'Partner types', body: 'Technology (ATS and HR tech), services (RPO and consultancies), and referral partners.' }, { h2: 'Become a partner', body: '[PLACEHOLDER: partner program details / application].' } ], 'Explore partnership', 'Tell us how you’d like to work together.'),
  page('company/reseller', 'C', 'Connect · Reseller', 'Become a reseller.', 'Become a Reseller | Mimic', 'Resell Mimic to your clients with margin, enablement and support from the TalbotIQ team.', 'Bring structured AI screening to your clients, with the commercials and support to make it work.', [ { h2: 'What resellers get', body: 'Margin, enablement, and co-selling support. [PLACEHOLDER: program terms].' }, { h2: 'Apply', body: '[PLACEHOLDER: reseller application / contact].' } ], 'Talk to our team', 'Let’s discuss a reseller arrangement.'),
  page('company/events', 'C', 'Connect · Events', 'Events.', 'Events | Mimic by TalbotIQ', 'Where to meet the TalbotIQ team — conferences, meetups and webinars.', 'Come say hello in person or online.', [ { h2: 'Upcoming', body: '[PLACEHOLDER: real events only]. Nothing scheduled right now — subscribe to hear about the next one.' } ], 'Meet the team', 'Book a demo and we’ll tell you where we’ll be.'),
  page('company/legal', 'C', 'Connect · Legal', 'Legal & privacy.', 'Legal & Privacy | Mimic by TalbotIQ', 'Privacy notice, terms of service, DPA and sub-processor list for Mimic and TalbotIQ.', 'The documents your legal team needs, in one place. This page links documents; it is not legal advice.', [ { h2: 'Documents', body: '[PLACEHOLDER: links to the real Privacy Notice, Terms of Service, DPA and sub-processor list].' }, { h2: 'Data requests', body: 'Access, correction and deletion requests are handled per GDPR and India’s DPDP Act. [PLACEHOLDER: privacy/DPO contact].' } ], 'Questions for legal?', 'We’ll connect you with the right person.'),
]

/* ─── Platform pages ───────────────────────────────────────────────────────
 * The 5 interview tracks are the crown-jewel product/SEO pages (Tier A); the
 * workflow + intelligence items are tighter capability pages (Tier B). */
function plat(slug: string, tier: 'A' | 'B', kicker: string, h1: string, metaTitle: string, metaDesc: string, intro: string, sections: PageSection[], faqs?: FaqItem[]): MktPage {
  return { slug: `platform/${slug}`, section: 'Platform', sectionTo: '/mimic/platform', tier, kicker, h1, metaTitle, metaDesc, intro, sections, faqs, cta: { title: 'See it on your roles', sub: 'Book a 30-minute walkthrough — no card required.' } }
}
const PLATFORM_PAGES: MktPage[] = [
  plat('conversational-chat', 'A', 'Interview tracks · Async', 'A first interview candidates finish on their phone in minutes.',
    'Conversational Chat Interviews | Mimic', 'A text interview candidates finish on a phone in minutes — résumé-adaptive, scored on your rubric. Ideal for hourly and high-volume roles.',
    'Scheduling is where the first round dies. A chat interview removes it entirely: candidates answer on their phone, whenever they can, and you get a scored result the same day.',
    [
      { h2: 'How it works', body: 'Candidates open a link and answer a short, structured set of questions in text. Each interview reads the résumé first and adapts its follow-ups.' },
      { h2: 'Best for', body: 'Hourly, frontline and high-volume roles where speed and mobile access matter most.', bullets: ['No scheduling', 'Mobile-first, no app', 'Finishes in minutes', 'Scored on your rubric'] },
      { h2: 'What you get', body: 'A consistent, evidence-backed score for every applicant, the day they applied.' },
    ],
    [{ q: 'Do candidates need an account?', a: 'No — they open a link and answer in the browser.' }]),
  plat('voice-screening', 'A', 'Interview tracks · Async', 'Hear how a candidate communicates — then score it consistently.',
    'AI Voice Screening Software | Mimic', 'Spoken interviews transcribed and scored on tone, pacing and content together — consistent, evidence-backed, no scheduling.',
    'For roles where communication is the job, a résumé tells you nothing. Voice screening lets every candidate speak, and scores what they say the same way.',
    [
      { h2: 'How it works', body: 'Candidates answer aloud; Mimic transcribes and scores content alongside delivery signals, against your rubric.' },
      { h2: 'Best for', body: 'Sales, support, and any customer-facing role where communication matters.', bullets: ['Transcription included', 'Signal analysis on delivery', 'No scheduling', 'One rubric across candidates'] },
      { h2: 'What you get', body: 'The communication signal you used to only get on a live call — for every applicant, scored consistently.' },
    ],
    [{ q: 'Is the transcript available?', a: 'Yes — every score cites the transcript span it came from.' }]),
  plat('ai-video-avatar', 'A', 'Interview tracks · Async', 'A face-to-face round that adapts and follows up — on the candidate’s schedule.',
    'AI Video Avatar Interviews | Mimic', 'A configured AI video interviewer that reacts, follows up and probes shallow answers — a real face-to-face round without the scheduling.',
    'Candidates take a video interview seriously, but scheduling one with a human at scale is impossible. An AI video avatar gives every candidate the face-to-face round, any time.',
    [
      { h2: 'How it works', body: 'A configured persona interviews the candidate on video, reacts to answers, follows up, and probes when an answer is thin — then scores against your rubric.' },
      { h2: 'Configure the interviewer', body: 'Set the persona, greeting, and what it is allowed to ask in the Avatar studio.', bullets: ['Personas & replicas', 'Résumé-adaptive follow-ups', 'On the candidate’s schedule', 'Scored on your rubric'] },
      { h2: 'What you get', body: 'A structured, consistent video round for everyone — not just the shortlist you had time to call.' },
    ],
    [{ q: 'Do candidates know it’s AI?', a: 'Yes — candidates are told and consent before starting. See Trust → Candidate rights.' }]),
  plat('live-two-way', 'A', 'Interview tracks · Live', 'A real interviewer in the room — with Mimic taking notes and scoring.',
    'Live Two-Way Interviews | Mimic', 'A live video interview where a human leads and Mimic captures notes, scores the rubric and records with consent — structure without the busywork.',
    'Later rounds still need a human. Mimic makes the live interview structured and consistent: your interviewer talks to the candidate while Mimic handles notes, scoring and the record.',
    [
      { h2: 'How it works', body: 'A live two-way video call where your interviewer leads; Mimic captures notes, scores the rubric, and records consentfully.' },
      { h2: 'Best for', body: 'Panel and final rounds where a human decision needs a consistent structure and record.', bullets: ['Host room + candidate lobby', 'Interviewer star-rating + notes', 'Consented recording', 'Same rubric as async rounds'] },
      { h2: 'What you get', body: 'The human touch of a live interview with the consistency and evidence of a structured one.' },
    ]),
  plat('timed-qa', 'A', 'Interview tracks · Async', 'Per-question timers for skills that only show up under pressure.',
    'Timed Q&A Interviews | Mimic', 'Per-question timers pressure-test skills like triage and dispatch — with integrity checks and consistent, evidence-backed scoring.',
    'Some skills only reveal themselves under a clock. Timed Q&A puts a fair, identical time limit on every candidate and scores how they perform against it.',
    [
      { h2: 'How it works', body: 'Each question has a prep and answer timer; candidates respond under the same constraints, and Mimic scores against your rubric.' },
      { h2: 'Best for', body: 'Support triage, trading floors, dispatch — roles where speed under pressure is the job.', bullets: ['Per-question timers', 'Integrity checks', 'Identical constraints for all', 'Evidence-backed scores'] },
      { h2: 'What you get', body: 'A fair, pressure-tested read on performance you can’t get from a résumé.' },
    ]),
  plat('bulk-invitations', 'B', 'Workflow · Invitations', 'From a spreadsheet to interviews in inboxes in minutes.',
    'Bulk Candidate Invitations | Mimic', 'Invite thousands of candidates from a CSV, an ATS export or one shareable link — Mimic parses each résumé and personalises every email.',
    'The first bottleneck is just getting the interview to everyone. Mimic sends them all in minutes.',
    [ { h2: 'How it works', body: 'Drop in a CSV or ATS export, or share one link. Mimic parses each résumé, personalises the email, and sends the links.', bullets: ['CSV / ATS export / shareable link', 'Résumé parsing per candidate', 'Personalised invite emails'] } ]),
  plat('interview-templates', 'B', 'Workflow · Templates', 'Configure an interview once. Reuse it across your whole team.',
    'Interview Templates | Mimic', 'Save track, question source, rubric weights, timing and branding as one reusable template your whole team applies consistently.',
    'Consistency comes from reuse. A template captures how a role is interviewed so every recruiter runs it the same way.',
    [ { h2: 'What a template holds', body: 'Track, question source, rubric and weights, timing, and branding — one object your team reuses.', bullets: ['One config, reused everywhere', 'Consistent across recruiters', 'Versioned and editable'] } ]),
  plat('question-sets', 'B', 'Workflow · Questions', 'Fixed question banks, or questions generated from a résumé.',
    'Question Sets | Mimic', 'Build reusable fixed question banks, attach them to any template, or let Mimic generate role-specific questions from a résumé.',
    'Start from proven questions instead of a blank page — and map every one to a rubric dimension.',
    [ { h2: 'How it works', body: 'Create fixed sets, attach them to templates, reorder by drag, or generate from a résumé. Each question maps to a scoring dimension.', bullets: ['Reusable fixed sets', 'Résumé-generated questions', 'Mapped to the rubric'] } ]),
  plat('pipelines', 'B', 'Workflow · Pipelines', 'Move candidates through rounds — or advance everyone above a bar.',
    'Multi-Round Hiring Pipelines | Mimic', 'Drag candidates through rounds, or auto-advance everyone above a score threshold, then export the board — multi-round progression made simple.',
    'Multi-round hiring gets messy in spreadsheets. A pipeline board keeps every candidate’s stage and score in one place.',
    [ { h2: 'How it works', body: 'Each round is a column; drag a candidate to advance them, or quick-advance everyone above a threshold. Export the board when you’re done.', bullets: ['Drag-to-advance', 'Score-threshold / top-N quick advance', 'CSV export'] } ]),
  plat('rubrics-scoring', 'B', 'Workflow · Scoring', 'One rubric, applied identically, with the evidence attached.',
    'Rubrics & Scoring | Mimic', 'Define weighted rubric dimensions once; Mimic scores every candidate the same way and cites the answer behind each dimension.',
    'A score is only useful if it’s consistent and explainable. The rubric is how Mimic guarantees both.',
    [ { h2: 'How it works', body: 'You set weighted dimensions; every candidate is scored identically, and each dimension cites its evidence. See Trust → How Mimic scores.', bullets: ['Weighted, you-defined dimensions', 'Identical for every candidate', 'Evidence per dimension'] } ]),
  plat('candidate-reports', 'B', 'Intelligence · Reports', 'A report that shows the working behind every score.',
    'Candidate Reports | Mimic', 'A full scored report per candidate — overall score, per-dimension breakdown with evidence, transcript and signal analysis.',
    'Hiring managers don’t want a number; they want to see why. The candidate report shows the evidence behind every dimension.',
    [ { h2: 'What’s in a report', body: 'Overall score and recommendation, a per-dimension breakdown with the answer behind each, transcript, and signal analysis.', bullets: ['Score + recommendation', 'Per-dimension evidence', 'Transcript & signals'] } ]),
  plat('recruiter-analytics', 'B', 'Intelligence · Analytics', 'See your whole funnel, by role, team and track.',
    'Recruiter Analytics | Mimic', 'Aggregate results across every scored interview — by role, template, track and recruiter — with adverse-impact reporting built in.',
    'Structured scoring finally makes hiring measurable. Analytics turn thousands of interviews into decisions.',
    [ { h2: 'What you can see', body: 'Volume, completion, score distributions and averages, sliced by role, template, track and recruiter — plus adverse-impact monitoring.', bullets: ['By role / template / track / recruiter', 'Score distributions & trends', 'Adverse-impact reporting'] } ]),
  plat('signal-analysis', 'B', 'Intelligence · Signals', 'Delivery signals, alongside content — not instead of it.',
    'Signal Analysis | Mimic', 'For voice and video, Mimic assesses delivery signals such as pace and clarity alongside answer content — always as supporting evidence, never a verdict.',
    'How something is said can matter for customer-facing roles. Mimic surfaces delivery signals as evidence, never as a standalone judgement.',
    [ { h2: 'How it works', body: 'On voice/video tracks, delivery signals are analysed alongside content and shown as supporting evidence in the report.', bullets: ['Pace, clarity, filler words', 'Shown with content, not alone', 'Human interprets it'] } ]),
  plat('mimic-guide', 'B', 'Intelligence · Assistant', 'An assistant that operates Mimic by voice or type.',
    'Mimic Guide Assistant | Mimic', 'A built-in assistant that answers questions and, with Autopilot, operates the product — setting up interviews, filtering analytics, advancing pipelines — with confirmation before anything sends.',
    'The fastest way to run Mimic is to ask it. The Mimic Guide answers questions and can operate the product for you, hands-free.',
    [ { h2: 'What it does', body: 'Ask how something works, or turn on Autopilot and it drives the UI — setting up interviews, filtering the dashboard, advancing candidates — reading back and confirming before any action that sends.', bullets: ['Voice or typed', 'Operates the real UI', 'Confirms before side-effects'] } ]),
]

export const PAGES: MktPage[] = [...HUBS, ...PLATFORM_PAGES, ...SOLUTION_PAGES, ...SOLUTION_BRIEFS, ...TRUST_PAGES, ...RESOURCE_PAGES, ...COMPANY_PAGES]
export const PAGE_BY_SLUG: Record<string, MktPage> = Object.fromEntries(PAGES.map((p) => [p.slug, p]))
export { DEMO }

# EU AI Act — Compliance Assessment (Emotion Recognition & Candidate Scoring)

**Researched:** 12 August 2026 · **Re-check by:** 12 February 2027 (this area moved twice in 18 months)
**Scope:** EU AI Act only. **GDPR, UK, retention and data-transfer questions are NOT covered — see [Scope Gap](#scope-gap).**
**Status:** legal-risk synthesis from primary sources, **not legal advice**. Obtain EU counsel before relying on it.

---

## Executive summary

The platform's AI features split into two legally distinct buckets, and the difference matters enormously.

| Feature | Code | Status |
|---|---|---|
| Facial expression → emotion/engagement scoring | [`server/services/rekognition.ts`](../server/services/rekognition.ts), `session.facialSummary` | 🔴 **Prohibited outright** for EU candidates |
| Vocal prosody → named emotion categories | [`server/routes/avatar.ts`](../server/routes/avatar.ts) (Hume + Gemini fallback) | 🔴 **Prohibited outright** for EU candidates |
| Transcript scoring → recruiter report | Gemini scoring pipeline | 🟠 **High-risk but permitted**, obligations from 2 Dec 2027 |

**The critical distinction:** a prohibited practice under Art 5 cannot be cured by consent, candidate notice, human review, a bias audit, or a DPIA. None of those are defences. The only compliant responses are **removing the feature** or **hard-geofencing it away from EU candidates**. This is categorically different from the high-risk regime, where the scoring layer stays legal provided obligations are met.

**Timing:** the Art 5 prohibitions have applied since **2 February 2025** and were **not** delayed by the 2026 Digital Omnibus. The delay to December 2027 applies only to the high-risk obligations — it gives **zero relief** on the emotion-recognition exposure.

---

## 1. The prohibition (Art 5(1)(f))

**Settled law — statutory text.** Reg. (EU) 2024/1689 Art 5(1)(f) prohibits the placing on the market, putting into service for that purpose, or use of

> "AI systems to infer emotions of a natural person in the areas of workplace and education institutions, except where the use of the AI system is intended to be put in place or into the market for medical or safety reasons"

Recital 44 uses the wider phrasing "in situations related to the workplace and education", and illustrates the carve-out with "systems intended for therapeutical use". The operative text does **not** define "workplace" and does **not** mention job candidates — that gap is filled by the Guidelines below.

The two carve-outs are narrow: medical or safety. On the Dutch DPA's reading the therapeutic exception requires CE-marked medical devices. Neither applies to hiring.

### 1.1 Does it cover job *candidates*? Yes — on the regulators' unanimous reading

**This is the dispositive finding.** The European Commission's adopted Guidelines on prohibited AI practices, **para 254**, state:

> "The notion of 'workplace' in Article 5(1)(f) AI Act should also be understood to apply to **candidates during the selection and hiring process**, consistently with other provisions of the AI Act addressing the placing on the market, putting into service or use of AI systems in the area of employment, workers management and access to self-employment, since there is an imbalance of powers and the intrusive nature of emotion recognition may already apply at the recruitment stage."

The same paragraph gives express prohibited examples:

> "- Using emotion recognition AI systems during the recruitment process is prohibited."
> "- Using emotion recognition AI systems during the probationary period is prohibited."
> "- AI systems monitoring the emotional tone in hybrid work teams by identifying and inferring emotions **from voice and imagery of hybrid video calls** … are prohibited."

That third example describes this platform's architecture almost exactly.

The **Dutch DPA** (Autoriteit Persoonsgegevens, DCA-2025-02, Feb 2026) reaches the same conclusion and adds three points that map directly onto this codebase:

- **Consent is no defence.** "There is no basis for such an exception in the AI Act; therefore, consent cannot be an exception to the prohibition."
- **Emotion recognition need not be the primary purpose** of the system. (The AP hedges here — "It appears to the AP" — and notes the Guidelines do not resolve it.)
- **A probability score for a named emotion is emotion recognition.** "Respondents specify that, in fact, emotion recognition is often a percentage of the possible presence of a particular emotion. According to the AP, this is emotion recognition within the meaning of the AI Act. A different conclusion would deprive the prohibition of all relevance."

That last point is directly on the nose: [`avatar.ts`](../server/routes/avatar.ts) returns exactly `{name: "Anxiety", score: 0.42}` shaped output.

**Recorded dissent (one respondent, rejected):** one AP consultation respondent argued that because recruitment appears in Annex III as *high-risk*, emotion recognition in recruitment "cannot be prohibited". Both the Commission (Guidelines fn 161, citing recital 56 and Annex III point 4 as *support* for the broad reading) and the AP reject this. The two regimes stack rather than being mutually exclusive.

### 1.2 Scope gate 1 — must be based on biometric data

The prohibition, as construed by the Commission and AP, reaches only emotion inference **on the basis of biometric data**. Guidelines para 251:

> "An AI system inferring emotions from written text (content/sentiment analyses) … is not based on biometric data and therefore does not fall within the scope of the prohibition."
> "An AI system inferring emotions from key stroke (way of typing), facial expressions, body postures or movements is based on biometric data and falls within the scope of the prohibition."

Behavioural biometrics are read broadly — "signatures, gait, **voice**, and keystrokes through to eye tracking and heartbeats". The AI Act's biometric-data definition (Art 3(34)) **omits the GDPR's "unique identification" requirement** (Guidelines fn 160), so it is *wider* than GDPR Art 4(14). Facial-expression analysis and vocal-prosody scoring are both inside scope.

> ⚠️ **Contested interpretation, and the risk runs against us.** Art 5(1)(f)'s own wording says only "AI systems to infer emotions" — it never mentions biometric data. The biometric limitation is a Commission/AP interpretive *gloss*; the AP itself concedes "the AI Act contains an inconsistency in this regard", and FPF and EUobserver criticise the text carve-out as a loophole. So "Gemini scoring the transcript is outside Art 5(1)(f)" is defensible but **not risk-free** — a court applying the literal wording could catch it. This matters here because our transcript is *derived from the candidate's voice* via Deepgram. Pipeline design and documentation matter.

### 1.3 Scope gate 2 — inference, not mere detection

Detecting a readily apparent expression is not emotion recognition; inferring an emotion from it is. Guidelines para 249:

> "The observation that a person is smiling is not emotion recognition. … Concluding that a person is happy is emotion recognition."

Crucially, para 248 closes the relabelling escape:

> "The prohibition should not be circumvented by referring to attitudes, and includes cases where the AI system finds on the basis of the biometric data that a person is showing for example an angry attitude."

Emotions and intentions are to be read "in a wide sense and not interpreted restrictively" (para 247). Recital 18 excludes **physical states** such as pain or fatigue — an exclusion unavailable to us, since our outputs are named emotions and engagement, not drowsiness detection.

**Consequence:** renaming `facialSummary` to "engagement", or expressing outputs as confidence percentages, does **not** move the feature out of scope. The two gates are cumulative: biometric basis **and** genuine inference.

### 1.4 Timing and penalties

- **Art 5 has applied since 2 February 2025**, regardless of whether the system was placed on the market before that date (Art 111 grandfathering is without prejudice to Art 5).
- **Penalties applied from 2 August 2025.** In the interim the prohibitions still had direct effect, "enabl[ing] affected parties to enforce them in national courts and request interim injunctions" (Guidelines para 431). Note the Act contains no express private right to damages — interim private enforcement is injunctive, not compensatory.
- **Art 99(3):** up to €35,000,000 or 7% of total worldwide annual turnover, whichever is **higher**.

> ✅ **Important correction for a platform this size.** Do **not** quote the "€35m or 7%, whichever is higher" figure without **Art 99(6)**, which caps fines for SMEs including start-ups at "whichever thereof is **lower**". Realistic Art 5 exposure is therefore **7% of this platform's own turnover**, not €35m. (Currency caveat: Art 99(1) was rewritten by the Digital Omnibus and a new Art 99(6a) caps small mid-cap fines; sources differ on whether "including start-ups" survived the rewrite. Cite the consolidated text, not the 2024 OJ PDF alone.)

---

## 2. The high-risk layer (Annex III point 4)

**Settled law.** Annex III point 4(a) covers

> "AI systems intended to be used for the recruitment or selection of natural persons, in particular to place targeted job advertisements, to analyse and filter job applications, and to evaluate candidates"

The Gemini transcript-scoring and candidate-ranking layer falls squarely inside this.

**The Art 6(3) escape is unavailable.** An Annex III system "shall always be considered to be high-risk where the AI system performs profiling of natural persons" — which per-candidate scoring plainly does. Draft Commission Guidelines on Art 6 (19 May 2026) confirm the derogation is foreclosed once profiling occurs.

**The regimes stack.** One platform can simultaneously be Annex III(4)(a) high-risk for its scoring *and* contain an outright-prohibited Art 5(1)(f) component. Fixing one does not fix the other.

Obligations (per the Commission's FAQ, pending the primary-source pass noted below): providers must run conformity assessments covering "risk management, data quality, documentation and traceability, transparency, human oversight, accuracy, cybersecurity and robustness"; deployers must inform affected workers and their representatives beforehand, explain AI-influenced decisions, and monitor operation.

> ⚠️ **Not yet verified from primary text:** the granular Art 8–27 obligation breakdown (risk management system, data governance, record-keeping/logging, technical documentation, EU database registration, Art 27 fundamental rights impact assessment). This mapping needs its own primary-source pass before it goes into a compliance deliverable.

### 2.1 Timeline — the original dates are out of date

The **Digital Omnibus on AI** ("Omnibus VII", Reg. (EU) **2026/1744**; proposed 19 Nov 2025, political agreement 6–7 May 2026, EP vote 16 June 2026, Council adoption 29 June 2026, OJ 24 July 2026, **in force 27 July 2026**) postponed stand-alone Annex III high-risk obligations — the category containing employment and recruitment — from **2 August 2026 to 2 December 2027**. Embedded high-risk AI moved to 2 August 2028.

| What | When |
|---|---|
| Art 5 prohibitions (incl. emotion recognition) | **2 Feb 2025** — not delayed |
| Penalties for Art 5 breaches | 2 Aug 2025 |
| Art 50 transparency obligations | Aug 2026 — still bite |
| Annex III high-risk obligations (our scoring layer) | **2 Dec 2027** (was 2 Aug 2026) |
| Embedded high-risk AI in products | 2 Aug 2028 |

**Net effect: the delay gives no relief whatsoever on the emotion-recognition exposure — only breathing room on the Chapter III high-risk obligations.**

> ⚠️ **Verified only indirectly.** No verifier could render the EUR-Lex text of Reg. (EU) 2026/1744 (empty response bodies / bot-blocking). These dates rest on two current Commission pages, the Council press release of 29 June 2026, and the EP procedure file 2025/0359(COD). Unconfirmed against the OJ text: whether the 2 Dec 2027 date is **unconditional or trigger-linked to standards availability** (as in the Nov 2025 proposal), and formal confirmation that no Art 5 or Annex III wording was narrowed (multiple independent trackers say it was not). **Read this off the OJ text before planning any compliance runway on it.**

---

## 3. How much weight these findings carry

**Settled law:** the statutory text — Art 5(1)(f), Arts 3(34)/3(39), recitals 14/18/44, Annex III point 4, Arts 99/111/113.

**Soft law:** the two propositions that actually decide our position — that "workplace" includes job candidates, and that the prohibition is gated on biometric data — rest on the Commission's **non-binding** Guidelines plus a Dutch DPA consultation view. Guidelines para 5: "These Guidelines are non-binding. Any authoritative interpretation of the AI Act may ultimately only be given by the Court of Justice of the European Union."

> ⚠️ **Do not read that as reassurance.** During adversarial verification, two narrower framings of the "it's only Commission interpretation" point were **voted down 0-3** — not because non-bindingness is false, but because that framing *materially understates exposure* when detached from Guidelines para 254. The candidate-coverage reading is **unanimous among regulators**; no authority has adopted the narrower employees-only view. And the live interpretive dispute (the biometric gate) is criticised as *too narrow*, meaning a broader judicial reading is a risk running **against** us, not for us.

The AP document is a **consultation response summary** — a preliminary supervisory interpretation, published while the Netherlands was still designating its AI Act supervisors. Cite it as such, **not** as an enforcement precedent.

**No enforcement action has surfaced.** No DPA decision, fine, or formal Art 5(1)(f) action was found anywhere in the evidence base.

---

## 4. Recommended actions

Ordered by exposure. Items 1–2 address a prohibition; the rest address high-risk and hygiene.

1. **Decide the EU question first: remove or geofence the emotion features.** Both the Rekognition facial emotion/engagement summary and the Hume/Gemini prosody categories. Mitigation is not available for a prohibited practice — consent, notice, and human review are not defences. If the platform will not serve EU candidates, that decision needs to be enforced in code and documented, not merely assumed.
2. **Do not attempt to relabel.** Renaming outputs to "engagement" or "attitude", or emitting confidence percentages instead of emotion names, is expressly anticipated and closed off by Guidelines para 248 and AP para 10.
3. **Consider whether the emotion features earn their keep at all.** Note that Hume's batch Expression Measurement API is already discontinued, and the current path is a Gemini prompt asking an LLM to score vocal prosody ([`avatar.ts:104-114`](../server/routes/avatar.ts#L104-L114)). The evidential value of that output is questionable independent of its legality.
4. **Keep the transcript-scoring layer, and plan for Chapter III by 2 Dec 2027.** Verify the obligation set against primary text first (see the gap flagged in §2).
5. **Review the Deepgram → Gemini pipeline boundary.** Text-only sentiment scoring is outside Art 5(1)(f) on the Guidelines' reading — but our text is voice-derived. Document the pipeline so the boundary is defensible, and treat the literal-wording risk as live.

---

## 5. Scope gap

**Four of the six questions researched returned nothing that survived verification.** Zero claims on the following topics were confirmed, so **this document is not a complete compliance assessment**:

- **GDPR** — lawful basis for recordings/transcripts/facial and voice analysis; whether emotion inference is Art 9 special-category or Art 4(14) biometric data; validity of consent given recruitment power imbalance; Art 22 and *SCHUFA* (C-634/21); Arts 13/14 transparency; Art 35 DPIA triggers; Art 5(1)(e) storage limitation
- **Concrete retention periods** endorsed, recommended or fined over by EU/UK regulators
- **Named DPA enforcement actions** involving recruitment, video interviews, or biometric data in hiring
- **The entire UK limb** — UK GDPR, DPA 2018, the ICO's 2024 AI-in-recruitment audit outcomes report, ICO biometric/emotion guidance, the Data (Use and Access) Act 2025, UK divergence from the AI Act. **This matters: a UK-only deployment may face a materially different — possibly permitted-with-conditions rather than prohibited — analysis.**
- **International transfers** — SCCs, EU–US Data Privacy Framework standing
- **The practical compliance checklist** (records of processing, vendor DPAs, DSAR/erasure handling)

**These are independent of the prohibition finding.** Removing the emotion features would **not** cure the known data-handling exposure documented separately:

- Two-way call recordings in Firebase Storage with **no retention or deletion policy**
- Transcripts, résumé text and analysis summaries stored **indefinitely in a plaintext JSON file** on a server disk
- A **Tavus API key in plaintext** in that same file
- Tokenised Storage download URLs that **bypass `storage.rules`**
- Processing by **US-based vendors** (Tavus, Daily, Deepgram, AWS, Hume, Google) with no verified transfer mechanism

A second research pass is required for sections 3–6 of the original brief.

---

## 6. Open questions

1. What are the GDPR answers? (Art 9 vs Art 4(14) classification, consent validity in recruitment, Art 22 + *SCHUFA*, DPIA triggers, regulator-endorsed retention periods.)
2. What is the UK position, and does it diverge enough to permit the emotion features there?
3. Has any DPA or market surveillance authority **actually enforced** Art 5(1)(f) or GDPR against emotion analysis in hiring? Which Member States have designated Art 5 market surveillance authorities?
4. Does the operative text of Reg. (EU) 2026/1744 leave Art 5(1)(f), Annex III point 4 and the biometric definitions untouched — and is 2 Dec 2027 unconditional or standards-triggered?
5. Where exactly is the biometric/text boundary in *our* pipeline? Does routing emotion inference through a voice-derived transcript stay outside Art 5(1)(f), or does a literal reading catch it? And does one prohibited feature taint a multi-functional system, or only that feature? (The AP notes "the Guidelines do not elaborate on this issue".)

---

## 7. Sources

Primary sources only; date-stamped because this area is moving fast.

| Source | Date | Used for |
|---|---|---|
| [Reg. (EU) 2024/1689 (AI Act), OJ L](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=OJ:L_202401689) | 12 Jul 2024 | Art 5(1)(f), Arts 3(34)/3(39), Arts 6, 99, 111, 113, Annex III(4), recitals 14/18/44 |
| [Commission Guidelines on prohibited AI practices, **C(2025) 5052 final**](https://ai-act-service-desk.ec.europa.eu/sites/default/files/2025-08/guidelines_on_prohibited_artificial_intelligence_practices_established_by_regulation_eu_20241689_ai_act_english_ied3r5nwo50xggpcfmwckm3nuc_112367-1.PDF) | 29 Jul 2025 | paras 5, 55, 247–255, 429–431, fn 160/161 |
| [Dutch DPA (AP), DCA-2025-02 — call-for-input summary](https://www.autoriteitpersoonsgegevens.nl/en/documents/summary-and-next-steps-call-for-input-on-prohibition-on-ai-systems-for-emotion-recognition-in-the-areas-of-workplace-or-education-institutions) | Feb 2026 | paras 5–23 (candidates, consent, primary purpose, probability scores) |
| [EC FAQ — Navigating the AI Act](https://digital-strategy.ec.europa.eu/en/faqs/navigating-ai-act) | upd. 7 Aug 2026 | high-risk vs prohibited buckets, omnibus dates |
| [EC — Regulatory framework for AI](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai) | upd. 3 Aug 2026 | "biometrics and employment" moving to 2 Dec 2027 |
| [Council press release — final green light](https://www.consilium.europa.eu/en/press/press-releases/2026/06/29/artificial-intelligence-council-gives-final-green-light-to-simplify-and-streamline-rules/) | 29 Jun 2026 | omnibus adoption and new dates |
| [EP Legislative Observatory, 2025/0359(COD)](https://oeil.europarl.europa.eu/oeil/en/procedure-file?reference=2025/0359\(COD\)) | — | procedural history |
| [Reg. (EU) 2026/1744 (Digital Omnibus on AI)](https://eur-lex.europa.eu/eli/reg/2026/1744/oj/eng) | OJ 24 Jul 2026 | **could not be rendered — dates verified indirectly** |
| [EPIC comments to the Dutch DPA, DCA-2024-02](https://epic.org/documents/epic-comments-to-dutch-dpa-on-emotion-recognition-prohibition-under-eu-ai-act/) | 17 Dec 2024 | corroborating colour only — advocacy submission, not law |

### Citation hygiene

Two Commission instruments are routinely conflated. **C(2025) 884 final (4 Feb 2025)** is the *approval of the content of the draft* Communication; **C(2025) 5052 final (29 Jul 2025)** is the *adopted* Communication. Paragraph numbering shifted between them — the AP cites paras 250–255 for passages appearing at 249–254 in the adopted text, and much published commentary cites the February number. Preferred citation form:

> Commission Guidelines on prohibited AI practices, C(2025) 5052 final, 29 July 2025 (content approved as C(2025) 884 final, 4 February 2025), para 254.

Access notes: the AP page and epic.org return 403 to automated fetch — cite the underlying PDFs. `artificialintelligenceact.eu`'s implementation timeline is **stale** (last updated Aug 2024) and will mislead. Several low-authority 2026 trackers carry garbled Art 5 detail (one invents an "Article 5(1)(j)") and were given zero weight.

### Method

5 search angles → 26 sources fetched → 118 candidate claims extracted → 25 verified under 3-vote adversarial review (2/3 refutes kills a claim) → 22 confirmed, 3 killed → 11 findings after de-duplication. 108 agents. Verification limit: the search budget was exhausted in several sessions, so some "no contradicting source found" conclusions rest on targeted primary fetches rather than full adversarial keyword sweeps.

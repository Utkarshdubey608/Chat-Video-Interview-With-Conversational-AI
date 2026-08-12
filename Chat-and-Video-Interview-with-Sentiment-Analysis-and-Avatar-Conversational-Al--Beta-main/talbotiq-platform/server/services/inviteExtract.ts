import * as XLSX from 'xlsx'
import { extractResumeText } from './resume'
import type { ExtractedCandidate, ExtractCandidatesResult } from '../../shared/types'

/**
 * Extract candidate {email, role} pairs from an uploaded file for the bulk-invite
 * flow. Structured files (CSV / Excel) are read column-wise — we detect the email
 * and role columns; unstructured files (PDF / DOCX / TXT) fall back to an email
 * regex with the recruiter's Step-1 role as the role. Emails are validated and
 * de-duplicated (case-insensitive). This produces the rows the recruiter reviews
 * and confirms before any invite is created — it never sends anything.
 */

// Deliberately simple + permissive; the review table is the real gate.
const EMAIL_GLOBAL = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g
export const isValidEmail = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e.trim())

const EMAIL_HEADER = /\b(e-?mail|mail)\b/i
const ROLE_HEADER = /\b(role|position|title|designation|profile|job)\b/i

function isSpreadsheet(name: string, mime: string): boolean {
  const l = (name || '').toLowerCase()
  return (
    l.endsWith('.csv') || l.endsWith('.xlsx') || l.endsWith('.xls') || l.endsWith('.tsv') ||
    mime.includes('spreadsheet') || mime.includes('excel') || mime.includes('csv') || mime === 'text/tab-separated-values'
  )
}

/** Rows (array-of-arrays) → candidates, detecting the email & role columns. */
function fromRows(aoa: unknown[][], fallbackRole: string): { rows: { email: string; role: string }[]; headered: boolean } {
  const cell = (v: unknown) => (v == null ? '' : String(v).trim())
  const nonEmpty = aoa.filter((r) => r.some((c) => cell(c) !== ''))
  if (nonEmpty.length === 0) return { rows: [], headered: false }

  // A row is a "header" if it has a cell whose TEXT names an email column but is
  // not itself an email address.
  const first = nonEmpty[0].map(cell)
  const headerHasEmailLabel = first.some((c) => EMAIL_HEADER.test(c) && !c.includes('@'))

  if (headerHasEmailLabel) {
    let emailCol = first.findIndex((c) => EMAIL_HEADER.test(c) && !c.includes('@'))
    let roleCol = first.findIndex((c) => ROLE_HEADER.test(c))
    if (emailCol < 0) emailCol = 0
    const rows = nonEmpty.slice(1).map((r) => {
      const email = cell(r[emailCol]) || (r.map(cell).find((c) => c.includes('@')) ?? '')
      const role = (roleCol >= 0 ? cell(r[roleCol]) : '') || fallbackRole
      return { email, role }
    })
    return { rows, headered: true }
  }

  // No header: take the first email-looking cell in each row; role can't be mapped.
  const rows = nonEmpty.map((r) => {
    const email = r.map(cell).find((c) => c.includes('@')) ?? ''
    return { email, role: fallbackRole }
  })
  return { rows, headered: false }
}

export async function extractCandidates(
  buffer: Buffer,
  mimetype: string,
  filename: string,
  fallbackRole: string,
): Promise<ExtractCandidatesResult> {
  const warnings: string[] = []
  let raw: { email: string; role: string }[] = []

  if (isSpreadsheet(filename, mimetype)) {
    const wb = XLSX.read(buffer, { type: 'buffer' })
    const sheet = wb.Sheets[wb.SheetNames[0]]
    if (!sheet) return { rows: [], warnings: ['The spreadsheet had no sheets.'] }
    const aoa = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, blankrows: false, defval: '' })
    const { rows, headered } = fromRows(aoa, fallbackRole)
    raw = rows
    if (!headered) warnings.push('No email/role header row detected — mapped the first email in each row and defaulted roles to the batch role.')
  } else {
    // Unstructured (PDF / DOCX / TXT): pull emails by regex; roles can't be mapped.
    const text = await extractResumeText(buffer, mimetype, filename)
    const found = [...text.matchAll(EMAIL_GLOBAL)].map((m) => m[0])
    raw = found.map((email) => ({ email, role: fallbackRole }))
    if (found.length) warnings.push('Unstructured file — emails were extracted by pattern and roles defaulted to the batch role. Please review carefully.')
  }

  // Normalize, validate, de-duplicate (case-insensitive by email).
  const seen = new Set<string>()
  let dupes = 0
  const rows: ExtractedCandidate[] = []
  for (const r of raw) {
    const email = r.email.trim()
    if (!email) continue
    const key = email.toLowerCase()
    if (seen.has(key)) { dupes++; continue }
    seen.add(key)
    rows.push({ email, role: (r.role || fallbackRole).trim(), valid: isValidEmail(email) })
  }
  if (dupes > 0) warnings.push(`${dupes} duplicate email${dupes === 1 ? '' : 's'} removed.`)
  if (rows.length === 0) warnings.push('No email addresses found in this file.')

  return { rows, warnings }
}

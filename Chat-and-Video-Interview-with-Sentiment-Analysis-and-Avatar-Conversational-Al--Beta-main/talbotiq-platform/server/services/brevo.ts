/**
 * Brevo REST (transactional) helpers — used ONLY to list verified senders for the
 * invite-email sender picker. Sending itself still goes through SMTP (email.ts).
 *
 * The API key is SERVER-ONLY (BREVO_API_KEY) — never sent to the client, never
 * VITE_-prefixed. Branded sending from your own domain (instead of the default
 * "…@brevosend.com" subdomain) requires domain + SPF/DKIM verification in Brevo;
 * this endpoint surfaces which senders are already verified.
 */

const BREVO_API = 'https://api.brevo.com/v3'

export function brevoReady(): boolean {
  return Boolean((process.env.BREVO_API_KEY || '').trim())
}

export interface VerifiedSender {
  email: string
  name: string
  active: boolean
}

/**
 * List senders configured in the Brevo account. Returns [] when no key is set
 * (the UI then offers manual entry + verification guidance). Throws on API errors
 * so the route can surface a helpful message.
 */
export async function listVerifiedSenders(): Promise<VerifiedSender[]> {
  const key = (process.env.BREVO_API_KEY || '').trim()
  if (!key) return []
  const res = await fetch(`${BREVO_API}/senders`, {
    headers: { 'api-key': key, accept: 'application/json' },
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`Brevo senders request failed (${res.status})${body ? `: ${body.slice(0, 200)}` : ''}`)
  }
  const data = (await res.json()) as { senders?: Array<{ email: string; name?: string; active?: boolean }> }
  return (data.senders ?? []).map((s) => ({
    email: s.email,
    name: s.name ?? '',
    active: s.active !== false,
  }))
}

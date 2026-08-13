/**
 * Server-side invite-email rendering.
 *
 * The recruiter authors only the BODY (WYSIWYG). This module sanitises that body
 * (allowlist — defence in depth; also sanitised on save) and delegates to the
 * SHARED renderInviteEmail() so the sent email is byte-identical to the client
 * preview. The interview link + "exact email" note are injected + locked by the
 * shared renderer regardless of body content.
 */
import sanitizeHtml from 'sanitize-html'
import type { InviteEmailTemplate } from '../../shared/types'
import { renderInviteEmail, type InviteRenderVars, type InviteRenderOpts } from '../../shared/inviteEmail'

export type { InviteRenderVars, InviteRenderOpts }

/** Allowlist sanitiser for WYSIWYG body HTML. Strips scripts, event handlers, etc. */
export function sanitizeBodyHtml(html: string): string {
  return sanitizeHtml(html ?? '', {
    allowedTags: [
      'p', 'br', 'strong', 'em', 'u', 's', 'a', 'ul', 'ol', 'li',
      'h1', 'h2', 'h3', 'span', 'div', 'blockquote',
    ],
    allowedAttributes: {
      a: ['href', 'style'],
      span: ['style'],
      p: ['style'],
      div: ['style'],
      li: ['style'],
    },
    allowedStyles: {
      '*': {
        color: [/^#(0x)?[0-9a-f]+$/i, /^rgb\(/i],
        'background-color': [/^#(0x)?[0-9a-f]+$/i, /^rgb\(/i],
        'text-align': [/^left$|^right$|^center$|^justify$/],
        'font-weight': [/^\d+$|^bold$|^normal$/],
      },
    },
    allowedSchemes: ['http', 'https', 'mailto'],
    disallowedTagsMode: 'discard',
  }).trim()
}

/** Sanitise the body, then render the full { subject, html } via the shared builder. */
export function buildInviteEmailHtml(
  tpl: InviteEmailTemplate,
  vars: InviteRenderVars,
  opts: InviteRenderOpts,
): { subject: string; html: string } {
  return renderInviteEmail({ ...tpl, bodyHtml: sanitizeBodyHtml(tpl.bodyHtml) }, vars, opts)
}

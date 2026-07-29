import { Fragment, type ReactNode } from "react";
import { Link } from "react-router-dom";

/**
 * Minimal markdown renderer for Mimic Guide replies. No external dependency —
 * supports exactly what the system prompt produces: **bold**, `inline code`,
 * [links](/path) (internal links use react-router <Link>), bullet lists,
 * paragraphs, and the <details><summary>English</summary>…</details>
 * multilingual block. It parses a known, constrained subset (never
 * dangerouslySetInnerHTML), so model output can't inject arbitrary HTML.
 */

const DETAILS_RE =
  /<details>\s*<summary>([\s\S]*?)<\/summary>([\s\S]*?)<\/details>/gi;
const INLINE_RE = /(\*\*([^*]+)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\))/g;

const LINK_CLASS =
  "text-[#c4b5fd] underline underline-offset-2 hover:text-[#a78bfa]";

function renderInline(
  text: string,
  keyBase: string,
  onNavigate?: () => void,
): ReactNode[] {
  const nodes: ReactNode[] = [];
  let last = 0;
  let token = 0;
  INLINE_RE.lastIndex = 0;
  let match: RegExpExecArray | null = INLINE_RE.exec(text);
  while (match !== null) {
    if (match.index > last) nodes.push(text.slice(last, match.index));
    const key = `${keyBase}-${token++}`;
    if (match[2] !== undefined) {
      nodes.push(
        <strong key={key} className="font-semibold text-white">
          {match[2]}
        </strong>,
      );
    } else if (match[3] !== undefined) {
      nodes.push(
        <code
          key={key}
          className="rounded bg-[#a78bfa]/10 px-1 py-0.5 font-mono text-xs text-[#c4b5fd]"
        >
          {match[3]}
        </code>,
      );
    } else if (match[4] !== undefined && match[5] !== undefined) {
      const label = match[4];
      const href = match[5];
      nodes.push(
        href.startsWith("/") ? (
          <Link key={key} to={href} className={LINK_CLASS} onClick={onNavigate}>
            {label}
          </Link>
        ) : (
          <a
            key={key}
            href={href}
            target="_blank"
            rel="noreferrer"
            className={LINK_CLASS}
          >
            {label}
          </a>
        ),
      );
    }
    last = INLINE_RE.lastIndex;
    match = INLINE_RE.exec(text);
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}

function renderBlocks(
  text: string,
  keyBase: string,
  onNavigate?: () => void,
): ReactNode[] {
  const trimmed = text.replace(/^\n+|\n+$/g, "");
  if (!trimmed) return [];
  return trimmed.split(/\n{2,}/).map((para, pIdx) => {
    const lines = para.split("\n");
    const isList =
      lines.length > 0 && lines.every((line) => /^\s*[-*]\s+/.test(line));
    if (isList) {
      return (
        <ul
          key={`${keyBase}-p${pIdx}`}
          className="flex list-disc flex-col gap-1 pl-5"
        >
          {lines.map((line, lIdx) => (
            <li key={lIdx}>
              {renderInline(
                line.replace(/^\s*[-*]\s+/, ""),
                `${keyBase}-p${pIdx}-l${lIdx}`,
                onNavigate,
              )}
            </li>
          ))}
        </ul>
      );
    }
    return (
      <p key={`${keyBase}-p${pIdx}`} className="leading-relaxed">
        {lines.map((line, lIdx) => (
          <Fragment key={lIdx}>
            {lIdx > 0 ? <br /> : null}
            {renderInline(line, `${keyBase}-p${pIdx}-l${lIdx}`, onNavigate)}
          </Fragment>
        ))}
      </p>
    );
  });
}

export function GuideMarkdown({
  text,
  onNavigate,
}: {
  text: string;
  onNavigate?: () => void;
}) {
  const parts: ReactNode[] = [];
  let last = 0;
  let index = 0;
  DETAILS_RE.lastIndex = 0;
  let match: RegExpExecArray | null = DETAILS_RE.exec(text);
  while (match !== null) {
    if (match.index > last) {
      parts.push(
        ...renderBlocks(text.slice(last, match.index), `pre${index}`, onNavigate),
      );
    }
    const summary = match[1].trim() || "English";
    const inner = match[2];
    parts.push(
      <details
        key={`details-${index}`}
        className="rounded-lg border border-white/10 bg-white/5 px-3 py-2"
      >
        <summary className="cursor-pointer text-xs font-medium text-[#c4b5fd]">
          {summary}
        </summary>
        <div className="mt-2 flex flex-col gap-2">
          {renderBlocks(inner, `in${index}`, onNavigate)}
        </div>
      </details>,
    );
    last = DETAILS_RE.lastIndex;
    index += 1;
    match = DETAILS_RE.exec(text);
  }
  if (last < text.length) {
    parts.push(...renderBlocks(text.slice(last), "tail", onNavigate));
  }
  return <div className="flex flex-col gap-2 text-sm text-neutral-200">{parts}</div>;
}

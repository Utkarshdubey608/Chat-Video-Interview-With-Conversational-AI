import { useEffect } from 'react'
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import { Bold, Italic, List, ListOrdered, Link2, Heading2, Variable } from 'lucide-react'
import { MERGE_VARS } from '@shared/inviteEmail'
import { cn } from '@/components/ui'

/**
 * Minimal WYSIWYG for the invite-email BODY. Tiptap (StarterKit + Link) emits a
 * constrained, safe HTML subset; the server re-sanitises before sending. An
 * "Insert variable" control drops merge tokens at the cursor — including the locked
 * {{interview_link}} which renders as the CTA button at send time.
 */
export function RichTextEditor({
  value,
  onChange,
}: {
  value: string
  onChange: (html: string) => void
}) {
  const editor = useEditor({
    extensions: [
      StarterKit.configure({ heading: { levels: [2, 3] } }),
      Link.configure({ openOnClick: false, autolink: false }),
    ],
    content: value || '<p></p>',
    editorProps: {
      attributes: {
        class: 'min-h-[180px] rounded-b-lg border border-t-0 border-border bg-white px-3 py-2.5 text-sm leading-relaxed text-neutral-800 focus:outline-none',
      },
    },
    onUpdate: ({ editor }) => onChange(editor.getHTML()),
  })

  // Sync external changes (e.g. loading a saved template) into the editor.
  useEffect(() => {
    if (!editor) return
    const current = editor.getHTML()
    if (value !== current) editor.commands.setContent(value || '<p></p>', false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, editor])

  if (!editor) return null

  const Btn = ({ on, active, title, children }: { on: () => void; active?: boolean; title: string; children: React.ReactNode }) => (
    <button
      type="button"
      title={title}
      onMouseDown={(e) => { e.preventDefault(); on() }}
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-md transition-colors',
        active ? 'bg-primary-100 text-primary-700' : 'text-neutral-500 hover:bg-neutral-100 hover:text-neutral-800',
      )}
    >
      {children}
    </button>
  )

  return (
    <div>
      <div className="flex flex-wrap items-center gap-1 rounded-t-lg border border-border bg-neutral-50 px-2 py-1.5">
        <Btn title="Bold" active={editor.isActive('bold')} on={() => editor.chain().focus().toggleBold().run()}><Bold size={15} /></Btn>
        <Btn title="Italic" active={editor.isActive('italic')} on={() => editor.chain().focus().toggleItalic().run()}><Italic size={15} /></Btn>
        <Btn title="Heading" active={editor.isActive('heading', { level: 2 })} on={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}><Heading2 size={15} /></Btn>
        <Btn title="Bullet list" active={editor.isActive('bulletList')} on={() => editor.chain().focus().toggleBulletList().run()}><List size={15} /></Btn>
        <Btn title="Numbered list" active={editor.isActive('orderedList')} on={() => editor.chain().focus().toggleOrderedList().run()}><ListOrdered size={15} /></Btn>
        <Btn title="Add link" active={editor.isActive('link')} on={() => {
          const prev = editor.getAttributes('link').href as string | undefined
          const url = window.prompt('Link URL', prev || 'https://')
          if (url === null) return
          if (url === '') editor.chain().focus().extendMarkRange('link').unsetLink().run()
          else editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
        }}><Link2 size={15} /></Btn>

        <span className="mx-1 h-5 w-px bg-border" />

        <div className="relative">
          <select
            className="h-8 cursor-pointer appearance-none rounded-md bg-white pl-7 pr-6 text-xs font-semibold text-neutral-600 ring-1 ring-border hover:ring-neutral-300 focus:outline-none"
            value=""
            onChange={(e) => {
              const tok = e.target.value
              if (tok) editor.chain().focus().insertContent(tok).run()
              e.target.value = ''
            }}
          >
            <option value="">Insert variable</option>
            {MERGE_VARS.map((v) => (
              <option key={v.token} value={v.token}>{v.label}</option>
            ))}
          </select>
          <Variable size={13} className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-neutral-400" />
        </div>
      </div>
      <EditorContent editor={editor} />
    </div>
  )
}

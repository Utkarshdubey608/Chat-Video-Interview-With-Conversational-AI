import mammoth from 'mammoth'
import { PDFParse } from 'pdf-parse'
import { HttpError } from '../util/ah'

/** Extract plain text from an uploaded résumé (PDF / DOCX / TXT), server-side. */
export async function extractResumeText(
  buffer: Buffer,
  mimetype: string,
  filename: string,
): Promise<string> {
  const lower = (filename || '').toLowerCase()

  if (mimetype?.includes('pdf') || lower.endsWith('.pdf')) {
    const parser = new PDFParse({ data: new Uint8Array(buffer) })
    const result = await parser.getText()
    return (result.text || '').trim()
  }

  if (lower.endsWith('.docx') || mimetype?.includes('officedocument.wordprocessingml')) {
    const { value } = await mammoth.extractRawText({ buffer })
    return (value || '').trim()
  }

  if (mimetype?.includes('text') || lower.endsWith('.txt')) {
    return buffer.toString('utf8').trim()
  }

  throw new HttpError(400, 'Unsupported file type — upload a PDF, DOCX, or TXT résumé.')
}

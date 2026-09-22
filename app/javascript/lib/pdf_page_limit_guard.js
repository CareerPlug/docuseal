// Client-side page-count guard for PDF uploads (CP-13579).
//
// Minimal PDF parse (no pdfjs-dist): counts page objects via a latin1 regex,
// with a /Count fallback. Anything undecipherable (non-PDF, encrypted, parse
// error) returns null so callers fail open (allow the upload).
//
// Two readers share the counting core. Small files scan synchronously (sync
// XHR over an object URL) so allow-case uploads still dispatch in the
// file-input change task; larger files use the async chunked reader.

export const PAGE_LIMIT = 120
export const SYNC_SCAN_LIMIT = 8 * 1024 * 1024

// Best-practices copy for blocked dashboard uploads. The dashboard has no t()
// i18n, so this module is the single shared source (overridable per element via
// a data-page-limit-message attribute); mirrors the builder page_limit_body copy.
export const PAGE_LIMIT_MESSAGE = 'This PDF has {page_count} pages, which exceeds the 120-page limit. Split it into smaller documents under 120 pages and add fields to each document.'

const CHUNK_SIZE = 1024 * 256
const OVERLAP = 64

const PAGE_OBJECT_PATTERN = /\/Type\s*\/Page(?!s)/g
const COUNT_PATTERN = /\/Count\s+(\d+)/g

const readChunk = async (file, start, end) => {
  const buffer = await file.slice(start, end).arrayBuffer()

  return new TextDecoder('latin1').decode(buffer)
}

const matchAllAfter = (text, pattern, fromIndex) => {
  pattern.lastIndex = 0

  const matches = []
  let match

  while ((match = pattern.exec(text)) !== null) {
    if (match.index >= fromIndex) {
      matches.push(match)
    }
  }

  return matches
}

const countInText = (text, fromIndex) => {
  const pages = matchAllAfter(text, PAGE_OBJECT_PATTERN, fromIndex).length

  let maxCount = 0

  for (const match of matchAllAfter(text, COUNT_PATTERN, fromIndex)) {
    maxCount = Math.max(maxCount, parseInt(match[1], 10))
  }

  return { pages, maxCount }
}

const isPdfFile = (file) => !file.type || file.type === 'application/pdf'

const scanPdfText = (text) => {
  if (!text.slice(0, CHUNK_SIZE).includes('%PDF-')) {
    return null
  }

  if (text.includes('/Encrypt')) {
    return null
  }

  const { pages, maxCount } = countInText(text, 0)

  if (pages > 0) {
    return pages
  }

  return maxCount > 0 ? maxCount : null
}

export function countPdfPagesSync (file) {
  try {
    if (!isPdfFile(file)) {
      return null
    }

    const url = URL.createObjectURL(file)

    try {
      const request = new XMLHttpRequest()

      request.open('GET', url, false)
      request.overrideMimeType('text/plain; charset=x-user-defined')
      request.send()

      return scanPdfText(request.responseText || '')
    } finally {
      URL.revokeObjectURL(url)
    }
  } catch {
    return null
  }
}

export async function countPdfPages (file) {
  try {
    if (!isPdfFile(file)) {
      return null
    }

    const head = await readChunk(file, 0, Math.min(CHUNK_SIZE, file.size))

    if (!head.includes('%PDF-')) {
      return null
    }

    let pages = 0
    let maxCount = 0
    let tail = ''

    for (let offset = 0; offset < file.size; offset += CHUNK_SIZE) {
      const text = tail + await readChunk(file, offset, Math.min(offset + CHUNK_SIZE, file.size))

      if (text.includes('/Encrypt')) {
        return null
      }

      const counts = countInText(text, tail.length)

      pages += counts.pages
      maxCount = Math.max(maxCount, counts.maxCount)

      tail = text.slice(-OVERLAP)
    }

    if (pages > 0) {
      return pages
    }

    return maxCount > 0 ? maxCount : null
  } catch {
    return null
  }
}

export function reportBlocked ({ pageCount, surface, fileSize }) {
  try {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch('/page_limit_events', {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
        ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
      },
      body: JSON.stringify({ page_count: pageCount, surface, file_size: fileSize })
    }).catch(() => {})
  } catch {
    // Metrics must never break the upload UX.
  }
}

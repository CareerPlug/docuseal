import { actionable } from '@github/catalyst/lib/actionable'
import { target, targetable } from '@github/catalyst/lib/targetable'
import { PAGE_LIMIT, SYNC_SCAN_LIMIT, countPdfPages, countPdfPagesSync, bucketFor, reportBlocked } from '../lib/pdf_page_limit_guard'

// Best-practices copy for blocked dashboard uploads. The dashboard has no t()
// i18n, so the copy is held here (overridable per element via a
// data-page-limit-message attribute); mirrors the builder page_limit_body copy.
const PAGE_LIMIT_MESSAGE = 'This PDF has {page_count} pages, which exceeds the 120-page limit. Split it into smaller documents under 120 pages and add fields to each document.'

// Blocked uploads make no request, so there is no flash cycle: render an
// inline DOM message only.
const showBlockedMessage = (element, pageCount) => {
  element.querySelector(':scope > .page-limit-message')?.remove()

  const message = document.createElement('div')

  message.className = 'page-limit-message mt-2 text-sm text-red-400'
  message.setAttribute('role', 'status')
  message.setAttribute('aria-live', 'polite')
  message.textContent = (element.dataset.pageLimitMessage || PAGE_LIMIT_MESSAGE).replace('{page_count}', String(pageCount))

  element.append(message)
}

export default actionable(targetable(class extends HTMLElement {
  static [target.static] = [
    'loading',
    'icon',
    'input',
    'area'
  ]

  connectedCallback () {
    this.addEventListener('dragover', (e) => e.preventDefault())
    this.addEventListener('drop', this.onDrop)
    document.addEventListener('turbo:submit-end', this.toggleLoading)
    this.area?.addEventListener('dragover', this.onDragover)
    this.area?.addEventListener('dragleave', this.onDragleave)
  }

  disconnectedCallback () {
    this.removeEventListener('drop', this.onDrop)
    document.removeEventListener('turbo:submit-end', this.toggleLoading)
    this.area?.removeEventListener('dragover', this.onDragover)
    this.area?.removeEventListener('dragleave', this.onDragleave)
  }

  onDragover (e) {
    if (e.dataTransfer?.types?.includes('Files')) {
      this.style.backgroundColor = '#F7F3F0'
      this.classList.remove('border-base-300', 'hover:bg-base-200/30')
      this.classList.add('border-base-content/30')
    }
  }

  onDragleave () {
    this.style.backgroundColor = null
    this.classList.remove('border-base-content/30')
    this.classList.add('border-base-300', 'hover:bg-base-200/30')
  }

  onDrop (e) {
    e.preventDefault()

    this.input.files = e.dataTransfer.files

    this.uploadFiles(e.dataTransfer.files)
  }

  onSelectFiles (e) {
    e.preventDefault()

    this.uploadFiles(this.input.files)
  }

  toggleLoading = (e) => {
    if (e && e.target && (!e.target.contains(this) || !e.detail?.formSubmission?.formElement?.contains(this))) {
      return
    }

    this.loading.classList.toggle('hidden')
    this.icon.classList.toggle('hidden')
    this.classList.toggle('opacity-50')
  }

  async uploadFiles (files) {
    if (this.dataset.pageLimitGuard) {
      for (const file of files) {
        // Small files scan synchronously so allow-case uploads still dispatch
        // in the change-event task; large files use the async chunked reader.
        const pageCount = file.size <= SYNC_SCAN_LIMIT ? countPdfPagesSync(file) : await countPdfPages(file)

        if (pageCount && pageCount > PAGE_LIMIT) {
          reportBlocked({ pageCount, bucket: bucketFor(pageCount), surface: 'dashboard', fileSize: file.size })

          this.input.value = ''

          showBlockedMessage(this, pageCount)

          return
        }
      }
    }

    this.toggleLoading()

    if (this.dataset.submitOnUpload) {
      this.closest('form').querySelector('button[type="submit"]').click()
    }
  }
}))

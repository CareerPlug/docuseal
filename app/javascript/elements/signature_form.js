import { target, targetable } from '@github/catalyst/lib/targetable'
import { cropCanvasAndExportToPNG } from '../submission_form/crop_canvas'

export default targetable(class extends HTMLElement {
  static [target.static] = ['canvas', 'input', 'clear', 'button']

  async connectedCallback () {
    this.scale = 3

    const { default: SignaturePad } = await import('signature_pad')

    this.pad = new SignaturePad(this.canvas)

    this.clear.addEventListener('click', (e) => {
      e.preventDefault()

      this.pad.clear()
    })

    this.button.addEventListener('click', (e) => {
      e.preventDefault()

      this.button.disabled = true

      this.submit()
    })

    this.setupCanvasSizing()
  }

  disconnectedCallback () {
    this.teardownCanvasSizing()
  }

  setupCanvasSizing () {
    this.resizeCanvas()

    this.onResizeCanvas = () => {
      if (this.resizeRaf) {
        cancelAnimationFrame(this.resizeRaf)
      }

      this.resizeRaf = requestAnimationFrame(() => {
        this.resizeRaf = requestAnimationFrame(() => {
          this.resizeCanvas()
        })
      })
    }

    window.addEventListener('resize', this.onResizeCanvas)
    screen?.orientation?.addEventListener('change', this.onResizeCanvas)

    if (typeof ResizeObserver !== 'undefined' && this.canvas?.parentNode) {
      this.resizeObserver = new ResizeObserver(this.onResizeCanvas)
      this.resizeObserver.observe(this.canvas.parentNode)
    }
  }

  teardownCanvasSizing () {
    if (this.resizeRaf) {
      cancelAnimationFrame(this.resizeRaf)
      this.resizeRaf = null
    }

    if (this.onResizeCanvas) {
      window.removeEventListener('resize', this.onResizeCanvas)
      screen?.orientation?.removeEventListener('change', this.onResizeCanvas)
    }

    this.resizeObserver?.disconnect()
  }

  resizeCanvas () {
    if (!this.canvas?.parentNode) {
      return
    }

    const width = this.canvas.parentNode.clientWidth
    const height = this.canvas.parentNode.clientHeight

    if (!width || !height) {
      return
    }

    const nextW = width * this.scale
    const nextH = height * this.scale

    if (this.canvas.width === nextW && this.canvas.height === nextH) {
      return
    }

    const prevCssW = this.canvas.width / this.scale
    const prevCssH = this.canvas.height / this.scale
    const ratioX = prevCssW > 0 ? width / prevCssW : 1
    const ratioY = prevCssH > 0 ? height / prevCssH : 1

    let data = []

    if (this.pad) {
      data = this.pad.toData()

      if (data.length && (ratioX !== 1 || ratioY !== 1)) {
        data = data.map((group) => ({
          ...group,
          points: group.points.map((point) => ({
            ...point,
            x: point.x * ratioX,
            y: point.y * ratioY
          }))
        }))
      }
    }

    this.canvas.width = nextW
    this.canvas.height = nextH
    this.canvas.getContext('2d').scale(this.scale, this.scale)

    if (this.pad) {
      this.pad.clear()

      if (data.length) {
        this.pad.fromData(data)
      }
    }
  }

  async submit () {
    const blob = await cropCanvasAndExportToPNG(this.canvas)
    const file = new File([blob], 'signature.png', { type: 'image/png' })

    const dataTransfer = new DataTransfer()

    dataTransfer.items.add(file)

    this.input.files = dataTransfer.files

    if (this.input.webkitEntries.length) {
      this.input.dataset.file = `${dataTransfer.files[0].name}`
    }

    this.closest('form').requestSubmit()
  }
})

function setupCanvasSizing (options) {
  let resizeRaf = null
  let resizeObserver = null
  let intersectionObserver = null

  function resizeCanvas () {
    const canvas = options.getCanvas()

    if (!canvas?.parentNode) {
      return
    }

    const { width: nextW, height: nextH } = options.nextSize(canvas)

    if (!nextW || !nextH) {
      return
    }

    if (canvas.width === nextW && canvas.height === nextH) {
      return
    }

    const ratioX = canvas.width > 0 ? nextW / canvas.width : 1
    const ratioY = options.perAxisStrokeRatios
      ? (canvas.height > 0 ? nextH / canvas.height : 1)
      : ratioX

    let data = []

    const pad = options.getPad()

    if (pad) {
      data = pad.toData()

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

    canvas.width = nextW
    canvas.height = nextH
    canvas.getContext('2d').scale(options.scale, options.scale)

    if (pad) {
      pad.clear()

      if (data.length) {
        pad.fromData(data)
      } else {
        options.onNoStrokes?.(canvas)
      }
    }
  }

  resizeCanvas()

  const onResizeCanvas = () => {
    if (resizeRaf) {
      cancelAnimationFrame(resizeRaf)
    }

    // Double rAF: orientationchange often fires before layout has settled.
    resizeRaf = requestAnimationFrame(() => {
      resizeRaf = requestAnimationFrame(() => {
        resizeCanvas()
      })
    })
  }

  window.addEventListener('resize', onResizeCanvas)
  screen?.orientation?.addEventListener('change', onResizeCanvas)

  const canvas = options.getCanvas()

  if (typeof ResizeObserver !== 'undefined' && canvas?.parentNode) {
    resizeObserver = new ResizeObserver(onResizeCanvas)
    resizeObserver.observe(canvas.parentNode)
  }

  if (options.watchVisibility) {
    intersectionObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          resizeCanvas()
        }
      })
    })

    intersectionObserver.observe(canvas)
  }

  function teardown () {
    if (resizeRaf) {
      cancelAnimationFrame(resizeRaf)
      resizeRaf = null
    }

    window.removeEventListener('resize', onResizeCanvas)
    screen?.orientation?.removeEventListener('change', onResizeCanvas)

    resizeObserver?.disconnect()
    intersectionObserver?.disconnect()
  }

  return { resizeCanvas, teardown }
}

export { setupCanvasSizing }

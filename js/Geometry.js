.pragma library

// Logical-coords-only mapping from Hyprland global client geometry to a
// per-output layer surface. Never multiply by monitor.scale — both hyprctl
// `at`/`size` and QML layer surfaces are already logical.

function asPair(value, fallbackX, fallbackY) {
    if (Array.isArray(value) && value.length >= 2)
        return [Number(value[0]) || 0, Number(value[1]) || 0]
    if (value && typeof value === "object")
        return [Number(value.x) || 0, Number(value.y) || 0]
    return [fallbackX || 0, fallbackY || 0]
}

function reservedBox(monitor) {
    var r = monitor && monitor.reserved
    if (r && typeof r === "object" && !Array.isArray(r)) {
        return {
            top: Number(r.top) || 0,
            right: Number(r.right) || 0,
            bottom: Number(r.bottom) || 0,
            left: Number(r.left) || 0
        }
    }
    if (Array.isArray(r) && r.length >= 4) {
        // Hyprland JSON dump is [top, bottom, left, right].
        return {
            top: Number(r[0]) || 0,
            bottom: Number(r[1]) || 0,
            left: Number(r[2]) || 0,
            right: Number(r[3]) || 0
        }
    }
    return { top: 0, right: 0, bottom: 0, left: 0 }
}

function rotateLocal(x, y, w, h, monW, monH, transform) {
    var t = Number(transform) || 0
    var flip = t >= 4
    var rot = t % 4
    var lx = x
    var ly = y
    var lw = w
    var lh = h
    if (flip)
        lx = monW - lx - lw
    if (rot === 0)
        return { x: lx, y: ly, w: lw, h: lh }
    if (rot === 1)
        return { x: ly, y: monW - lx - lw, w: lh, h: lw }
    if (rot === 2)
        return { x: monW - lx - lw, y: monH - ly - lh, w: lw, h: lh }
    if (rot === 3)
        return { x: monH - ly - lh, y: lx, w: lh, h: lw }
    return { x: lx, y: ly, w: lw, h: lh }
}

function outputExtent(monitor) {
    var w = Number(monitor && monitor.width) || 0
    var h = Number(monitor && monitor.height) || 0
    var t = Number(monitor && monitor.transform) || 0
    if (monitor && monitor.preTransform && (t % 4 === 1 || t % 4 === 3))
        return { w: h, h: w }
    return { w: w, h: h }
}

function globalToOutput(at, size, monitor) {
    var p = asPair(at, 0, 0)
    var s = asPair(size, 0, 0)
    var mx = Number(monitor && monitor.x) || 0
    var my = Number(monitor && monitor.y) || 0
    var mw = Number(monitor && monitor.width) || 0
    var mh = Number(monitor && monitor.height) || 0
    var t = Number(monitor && monitor.transform) || 0

    // Scale is recorded so callers can see it, but it must not be applied.
    var relX = p[0] - mx
    var relY = p[1] - my

    if (monitor && monitor.preTransform && t)
        return rotateLocal(relX, relY, s[0], s[1], mw, mh, t)

    return { x: relX, y: relY, w: s[0], h: s[1] }
}

function clamp(n, lo, hi) {
    if (n < lo)
        return lo
    if (n > hi)
        return hi
    return n
}

function labelAnchor(outputRect, monitor, inset, pillW, pillH, stackIndex) {
    var box = reservedBox(monitor)
    var insetN = Number(inset)
    if (isNaN(insetN))
        insetN = 8
    var pw = pillW || 36
    var ph = pillH || 28
    var stack = stackIndex || 0
    var gap = 4
    var extent = outputExtent(monitor)
    var mw = extent.w
    var mh = extent.h

    var x = (outputRect && outputRect.x || 0) + insetN
    var y = (outputRect && outputRect.y || 0) + insetN + stack * (ph + gap)

    var minX = box.left + 2
    var minY = box.top + 2
    var maxX = mw - box.right - pw - 2
    var maxY = mh - box.bottom - ph - 2
    if (maxX < minX)
        maxX = minX
    if (maxY < minY)
        maxY = minY

    return {
        x: clamp(x, minX, maxX),
        y: clamp(y, minY, maxY),
        w: pw,
        h: ph
    }
}

function overlaps(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

function stackOffsets(anchors) {
    var out = []
    var i
    for (i = 0; i < anchors.length; i++) {
        var cur = {
            x: anchors[i].x,
            y: anchors[i].y,
            w: anchors[i].w,
            h: anchors[i].h
        }
        var bumped = true
        var guard = 0
        while (bumped && guard < 40) {
            bumped = false
            guard++
            for (var j = 0; j < out.length; j++) {
                if (overlaps(cur, out[j])) {
                    cur.y = out[j].y + out[j].h + 4
                    bumped = true
                }
            }
        }
        out.push(cur)
    }
    return out
}

function looksBroken(outputRect, monitor) {
    if (!outputRect || !monitor)
        return true
    var extent = outputExtent(monitor)
    if (extent.w <= 0 || extent.h <= 0)
        return true
    if (outputRect.w <= 0 || outputRect.h <= 0)
        return true
    if (outputRect.x + outputRect.w < -8 || outputRect.y + outputRect.h < -8)
        return true
    if (outputRect.x > extent.w + 8 || outputRect.y > extent.h + 8)
        return true
    return false
}

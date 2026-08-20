.pragma library

function create() {
    return {
        state: "idle",
        prefix: "",
        verb: "focus",
        moveTo: 0,
        armedAddress: "",
        armedUntil: 0
    }
}

function reset(s) {
    if (!s)
        s = create()
    s.state = "idle"
    s.prefix = ""
    s.verb = "focus"
    s.moveTo = 0
    s.armedAddress = ""
    s.armedUntil = 0
    return s
}

function begin(s) {
    if (!s)
        s = create()
    s.state = "hinting"
    s.prefix = ""
    s.verb = "focus"
    s.moveTo = 0
    s.armedAddress = ""
    s.armedUntil = 0
    return s
}

function isEscape(key) {
    var lower = String(key || "").toLowerCase()
    return lower === "escape" || lower === "esc"
}

function isLetter(key) {
    return /^[a-zA-Z]$/.test(String(key || ""))
}

function matchPrefix(labels, prefix) {
    var p = String(prefix || "")
    var exact = []
    var partial = []
    for (var i = 0; i < (labels || []).length; i++) {
        var c = labels[i].chord || ""
        if (p && c === p)
            exact.push(labels[i])
        else if (p && c.indexOf(p) === 0)
            partial.push(labels[i])
    }
    return { exact: exact, partial: partial }
}

function handleKey(s, raw, labels, now, armMs) {
    if (!s)
        s = create()
    var result = { action: "none", state: s, target: null, verb: s.verb, moveTo: s.moveTo }
    if (s.state === "idle")
        return result

    var key = String(raw || "")
    if (!key.length)
        return result

    if (isEscape(key)) {
        if (s.state === "armed") {
            s.state = "hinting"
            s.prefix = ""
            s.verb = "focus"
            s.armedAddress = ""
            s.armedUntil = 0
            result.action = "abort-arm"
            return result
        }
        result.action = "dismiss"
        return result
    }

    if (s.state === "armed")
        return result

    if (key === "BackSpace" || key === "backspace") {
        if (s.prefix.length)
            s.prefix = s.prefix.slice(0, s.prefix.length - 1)
        else {
            s.verb = "focus"
            s.moveTo = 0
            s.state = "hinting"
        }
        result.action = "prefix"
        return result
    }

    if ((s.state === "hinting" || s.state === "close-prefix" || s.state === "move-prefix") && s.prefix === "" && /^[1-9]$/.test(key)) {
        s.verb = "move"
        s.moveTo = parseInt(key, 10)
        s.state = "move-prefix"
        result.action = "verb"
        result.verb = "move"
        result.moveTo = s.moveTo
        return result
    }

    if (s.state === "hinting" && s.prefix === "" && String(key).toLowerCase() === "x") {
        s.verb = "close"
        s.state = "close-prefix"
        result.action = "verb"
        result.verb = "close"
        return result
    }

    if (!isLetter(key))
        return result

    var isShift = key !== key.toLowerCase()
    var letter = key.toLowerCase()
    if (s.verb === "focus" && isShift) {
        s.verb = "swap"
        result.verb = "swap"
    }

    s.prefix += letter
    var m = matchPrefix(labels, s.prefix)
    if (m.exact.length === 1 && m.partial.length === 0) {
        if (s.verb === "close") {
            s.state = "armed"
            s.armedAddress = m.exact[0].address
            s.armedUntil = (now || 0) + (armMs || 250)
            result.action = "arm"
            result.target = m.exact[0]
            result.verb = "close"
            return result
        }
        result.action = "commit"
        result.target = m.exact[0]
        result.verb = s.verb
        result.moveTo = s.moveTo
        return result
    }
    if (m.exact.length === 0 && m.partial.length === 0) {
        s.prefix = ""
        if (s.verb === "swap")
            s.verb = "focus"
        result.action = "miss"
        result.verb = s.verb
        return result
    }
    result.action = "prefix"
    return result
}

function armExpired(s, now) {
    return s && s.state === "armed" && now >= s.armedUntil
}

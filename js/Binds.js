.pragma library

// Detect live Hyprland binds and plan a bindings.lua snippet.
// Lua binds show up as dispatcher "__lua" with a description, not the
// omarchy-shell command in `arg`, so "ours" is plugin-id in arg OR our
// descriptions OR a live submap named "hints".
//
// Stock Omarchy binds SUPER+F to Full screen. Never steal it, never unbind it.

var PLUGIN_ID = "io.github.chris.window-hints"
var DESC = "Window hints"
var NOTIFY_DESC = "Window Hints (then type a letter)"
var ALPHABET = "asdfghjkl"
var SUPER = 64
var SHIFT = 1
var CTRL = 4
var ALT = 8

var CANDIDATES = [
    { keys: "SUPER + H", modmask: SUPER, key: "H" },
    { keys: "SUPER + semicolon", modmask: SUPER, key: "semicolon" },
    { keys: "SUPER + ALT + F", modmask: SUPER + ALT, key: "F" }
]

var offer = {
    needed: true,
    canInstall: false,
    note: "",
    already: 0,
    toAdd: [],
    skipped: [],
    chosen: ""
}

function setOffer(next) {
    offer = next || offer
}

function parseBinds(raw) {
    if (!raw)
        return []
    var data = raw
    if (typeof raw === "string") {
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return []
        }
    }
    return data && data.length ? data : []
}

function keyOf(bind) {
    var k = String((bind && bind.key) || "")
    if (k === ";" || k.toLowerCase() === "semicolon")
        return "SEMICOLON"
    return k.toUpperCase()
}

function compactKeys(keys) {
    var s = String(keys || "").replace(/\s+/g, "").toUpperCase()
    s = s.replace("SEMICOLON", ";")
    return s
}

function isForbiddenSuperF(keys, modmask, key) {
    if (keys !== undefined && keys !== null && String(keys).length)
        return compactKeys(keys) === "SUPER+F"
    var mask = Number(modmask)
    var k = keyOf({ key: key })
    return mask === SUPER && k === "F"
}

function isOurs(bind) {
    if (!bind)
        return false
    var arg = String(bind.arg || "")
    var desc = String(bind.description || "")
    if (arg.indexOf(PLUGIN_ID) >= 0)
        return true
    if (desc.toLowerCase().indexOf("window hints") >= 0)
        return true
    return false
}

function hintsSubmapInstalled(binds) {
    var list = binds || []
    for (var i = 0; i < list.length; i++) {
        var b = list[i]
        if (!b)
            continue
        // Members of a leftover `hints` submap are not a summon bind.
        // Only a dispatcher that *enters* the submap counts as installed.
        if (String(b.dispatcher || "") === "submap" && String(b.arg || "") === "hints")
            return true
        if (String(b.dispatcher || "") === "__lua" && String(b.description || "").toLowerCase().indexOf("window hints") >= 0)
            return true
    }
    return false
}

function alreadyInstalled(binds) {
    if (hintsSubmapInstalled(binds))
        return true
    var list = binds || []
    for (var i = 0; i < list.length; i++) {
        if (isOurs(list[i]))
            return true
    }
    return false
}

function comboOwner(binds, modmask, key) {
    var want = keyOf({ key: key })
    var list = binds || []
    for (var i = 0; i < list.length; i++) {
        var b = list[i]
        if (Number(b.modmask) !== Number(modmask))
            continue
        if (keyOf(b) !== want)
            continue
        if (isOurs(b))
            return { ours: true, desc: String(b.description || "") }
        return { ours: false, desc: String(b.description || b.dispatcher || "already bound") }
    }
    return null
}

function noteFor(chosen, skipped) {
    var note = "Add " + (chosen.keys || chosen.chosen)
    for (var i = 0; i < (skipped || []).length; i++)
        note += " — skipped " + skipped[i].keys + " (" + skipped[i].conflict + ")"
    return note
}

function plan(binds) {
    if (alreadyInstalled(binds)) {
        return {
            needed: false,
            canInstall: false,
            already: 1,
            toAdd: [],
            skipped: [],
            chosen: "",
            note: ""
        }
    }
    var skipped = []
    for (var i = 0; i < CANDIDATES.length; i++) {
        var c = CANDIDATES[i]
        if (isForbiddenSuperF(c.keys, c.modmask, c.key))
            continue
        var owner = comboOwner(binds, c.modmask, c.key)
        if (!owner) {
            var pick = {
                keys: c.keys,
                modmask: c.modmask,
                key: c.key,
                chosen: c.keys,
                desc: NOTIFY_DESC
            }
            return {
                needed: true,
                canInstall: true,
                already: 0,
                toAdd: [pick],
                skipped: skipped,
                chosen: c.keys,
                note: noteFor(pick, skipped)
            }
        }
        if (owner.ours) {
            return {
                needed: false,
                canInstall: false,
                already: 1,
                toAdd: [],
                skipped: [],
                chosen: "",
                note: ""
            }
        }
        skipped.push({ keys: c.keys, desc: DESC, conflict: owner.desc })
    }
    var note = skipped.map(function (s) {
        return s.keys + " is " + (s.conflict || "taken")
    }).join("; ")
    return {
        needed: true,
        canInstall: false,
        already: 0,
        toAdd: [],
        skipped: skipped,
        chosen: "",
        note: note
    }
}

function luaKeys(spec) {
    var raw = String(spec === undefined || spec === null ? "" : spec).trim()
    if (!raw)
        return ""
    var norm = raw.replace(/\s+/g, "")
    var idx = norm.lastIndexOf("+")
    if (idx <= 0)
        return raw
    var mods = norm.slice(0, idx).replace(/\+/g, " + ")
    var key = norm.slice(idx + 1)
    if (key === ";")
        key = "semicolon"
    return mods + " + " + key
}

function bindLine(keys, payload, indent) {
    var pad = ""
    var n = indent || 0
    for (var i = 0; i < n; i++)
        pad += " "
    return pad + "hl.bind(\"" + keys + "\", hl.dsp.exec_cmd(\"omarchy-shell window-hints key " + payload + "\"))"
}

function pickKeys(item) {
    if (!item)
        return ""
    if (typeof item === "string")
        return item
    if (typeof item.chosen === "string" && item.chosen.length)
        return item.chosen
    if (typeof item.keys === "string")
        return item.keys
    return ""
}

function luaBlock(items) {
    var keys = ""
    if (typeof items === "string")
        keys = items
    else if (items && items.length)
        keys = pickKeys(items[0])
    else
        keys = pickKeys(items)
    if (!keys || isForbiddenSuperF(keys))
        return ""
    var summon = luaKeys(keys)
    if (compactKeys(summon) === "SUPER+F")
        return ""
    var lines = []
    lines.push("hl.bind(\"" + summon + "\", hl.dsp.exec_cmd(\"omarchy-shell shell toggle " + PLUGIN_ID + " '{}'\"))")
    lines.push("hl.define_submap(\"hints\", function()")
    for (var i = 0; i < ALPHABET.length; i++) {
        var ch = ALPHABET.charAt(i)
        lines.push(bindLine(ch, ch, 4))
        lines.push(bindLine("SHIFT + " + ch, ch.toUpperCase(), 4))
    }
    lines.push(bindLine("x", "x", 4))
    for (var n = 1; n <= 9; n++)
        lines.push(bindLine(String(n), String(n), 4))
    lines.push("    hl.bind(\"escape\", function()")
    lines.push("        hl.dispatch(hl.dsp.exec_cmd(\"omarchy-shell window-hints key escape\"))")
    lines.push("        hl.dispatch(hl.dsp.submap(\"reset\"))")
    lines.push("    end)")
    lines.push("    hl.bind(\"catchall\", hl.dsp.no_op())")
    lines.push("end)")
    var body = lines.join("\n")
    if (body.indexOf("hl.unbind") >= 0)
        return ""
    if (body.indexOf("shell call") >= 0)
        return ""
    return body
}

function applyScan(raw) {
    var p = plan(parseBinds(raw))
    setOffer(p)
    return p
}

function notifyBody(items, skipped) {
    var lines = []
    var list = items || []
    for (var i = 0; i < list.length; i++) {
        var it = list[i]
        lines.push((it.chosen || it.keys) + " — " + (it.desc || NOTIFY_DESC))
    }
    var miss = skipped || []
    for (var s = 0; s < miss.length; s++)
        lines.push("skipped " + miss[s].keys + " (" + (miss[s].conflict || "taken") + ")")
    return lines.join("\n")
}

function notifyArgv(appName, headline, body) {
    return ["omarchy", "notification", "send", "--app-name", String(appName || PLUGIN_ID), "-g", "󰌌", String(headline || "Keybindings"), String(body || "")]
}

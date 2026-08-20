.pragma library

// Inline settings only. The host puts these on the shell.json plugin
// entry; we never write a settings file of our own.

var VERSION = 1

var ALPHABET = "asdfghjkl"

var DEFAULTS = {
    inset: 8,
    maxHints: 25,
    watchdogMs: 15000,
    armMs: 250,
    inputPath: "submap",
    suggestedBind: "SUPER+F",
    alternateBinds: ["SUPER+H", "SUPER+;"],
    pillWidth: 36,
    pillHeight: 28,
    stackGap: 4,
    fadeAfterMs: 100,
    fadeMs: 80
}

var inset = DEFAULTS.inset
var maxHints = DEFAULTS.maxHints
var watchdogMs = DEFAULTS.watchdogMs
var armMs = DEFAULTS.armMs
var inputPath = DEFAULTS.inputPath
var suggestedBind = DEFAULTS.suggestedBind
var alternateBinds = DEFAULTS.alternateBinds.slice()
var pillWidth = DEFAULTS.pillWidth
var pillHeight = DEFAULTS.pillHeight
var stackGap = DEFAULTS.stackGap
var fadeAfterMs = DEFAULTS.fadeAfterMs
var fadeMs = DEFAULTS.fadeMs
var revision = 0

var SETTING_KEYS = ["inset", "maxHints", "watchdogMs", "armMs", "inputPath", "suggestedBind"]

function snapshot() {
    return {
        version: VERSION,
        alphabet: ALPHABET,
        inset: inset,
        maxHints: maxHints,
        watchdogMs: watchdogMs,
        armMs: armMs,
        inputPath: inputPath,
        suggestedBind: suggestedBind,
        alternateBinds: alternateBinds.slice(),
        pillWidth: pillWidth,
        pillHeight: pillHeight,
        stackGap: stackGap,
        fadeAfterMs: fadeAfterMs,
        fadeMs: fadeMs,
        revision: revision
    }
}

function asInt(value, fallback, min, max) {
    var n = parseInt(value, 10)
    if (isNaN(n))
        return fallback
    if (min !== undefined && n < min)
        n = min
    if (max !== undefined && n > max)
        n = max
    return n
}

function apply(raw) {
    var data = raw
    if (typeof raw === "string") {
        if (!raw.length)
            data = {}
        else {
            try {
                data = JSON.parse(raw)
            } catch (e) {
                return false
            }
        }
    }
    if (!data || typeof data !== "object")
        return false

    if (data.inset !== undefined)
        inset = asInt(data.inset, DEFAULTS.inset, 0, 64)
    if (data.maxHints !== undefined)
        maxHints = asInt(data.maxHints, DEFAULTS.maxHints, 1, 25)
    if (data.watchdogMs !== undefined)
        watchdogMs = asInt(data.watchdogMs, DEFAULTS.watchdogMs, 2000, 60000)
    if (data.armMs !== undefined)
        armMs = asInt(data.armMs, DEFAULTS.armMs, 50, 2000)
    if (data.inputPath !== undefined) {
        var path = String(data.inputPath)
        inputPath = path === "overlay" ? "overlay" : "submap"
    }
    if (data.suggestedBind !== undefined && String(data.suggestedBind).length)
        suggestedBind = String(data.suggestedBind)
    if (data.alternateBinds && data.alternateBinds.length) {
        alternateBinds = []
        for (var i = 0; i < data.alternateBinds.length; i++)
            alternateBinds.push(String(data.alternateBinds[i]))
    }
    if (data.pillWidth !== undefined)
        pillWidth = asInt(data.pillWidth, DEFAULTS.pillWidth, 20, 96)
    if (data.pillHeight !== undefined)
        pillHeight = asInt(data.pillHeight, DEFAULTS.pillHeight, 16, 72)
    if (data.stackGap !== undefined)
        stackGap = asInt(data.stackGap, DEFAULTS.stackGap, 0, 24)
    revision += 1
    return true
}

function overlayBag(dst, src) {
    if (!src || typeof src !== "object")
        return dst
    for (var i = 0; i < SETTING_KEYS.length; i++) {
        var k = SETTING_KEYS[i]
        if (src[k] !== undefined && src[k] !== null)
            dst[k] = src[k]
    }
    return dst
}

function pickNonDefaults(current) {
    var bag = {}
    if (!current || typeof current !== "object")
        return bag
    for (var i = 0; i < SETTING_KEYS.length; i++) {
        var k = SETTING_KEYS[i]
        if (current[k] === undefined || current[k] === null)
            continue
        if (current[k] !== DEFAULTS[k])
            bag[k] = current[k]
    }
    return bag
}

function resolveSettings(itemProps, settings, payload) {
    var bag = pickNonDefaults(itemProps)
    overlayBag(bag, settings)
    overlayBag(bag, payload)
    return bag
}

function parseBind(spec) {
    var raw = String(spec === undefined || spec === null ? "" : spec).trim()
    if (!raw)
        return { mods: "SUPER", key: "F" }
    var norm = raw.replace(/\s+/g, "")
    var idx = norm.lastIndexOf("+")
    if (idx <= 0)
        return { mods: "SUPER", key: norm || "F" }
    var mods = norm.slice(0, idx)
    var key = norm.slice(idx + 1)
    if (!mods)
        mods = "SUPER"
    if (!key)
        key = "F"
    if (key === ";")
        key = "semicolon"
    return { mods: mods, key: key }
}

function parseInstall(text) {
    var raw = String(text || "").trim()
    if (!raw)
        return { installed: false, via: "", error: "empty" }
    try {
        var data = JSON.parse(raw)
        if (!data || typeof data !== "object")
            return { installed: false, via: "", error: "unparseable" }
        return {
            installed: !!data.installed,
            via: String(data.via || ""),
            error: String(data.error || "")
        }
    } catch (e) {
        return { installed: false, via: "", error: "unparseable" }
    }
}

function reset() {
    apply(DEFAULTS)
    revision = 0
}

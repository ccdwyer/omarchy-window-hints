.pragma library

// Inline settings only. The host puts these on the shell.json plugin
// entry; we never write a settings file of our own.

var VERSION = 1

var DEFAULTS = {
    alphabet: "asdfghjkl",
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

var alphabet = DEFAULTS.alphabet
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

function snapshot() {
    return {
        version: VERSION,
        alphabet: alphabet,
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

function sanitizeAlphabet(value) {
    var raw = String(value === undefined || value === null ? "" : value)
    var seen = {}
    var out = ""
    for (var i = 0; i < raw.length; i++) {
        var ch = raw.charAt(i).toLowerCase()
        if (!/[a-z]/.test(ch))
            continue
        if (seen[ch])
            continue
        seen[ch] = true
        out += ch
    }
    if (out.length < 2)
        return DEFAULTS.alphabet
    return out
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

    if (data.alphabet !== undefined)
        alphabet = sanitizeAlphabet(data.alphabet)
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

function reset() {
    apply(DEFAULTS)
    revision = 0
}

.pragma library

var revision = 0
var opened = false
var labels = []
var prefix = ""
var verb = "focus"
var moveTo = 0
var armedAddress = ""
var overflow = 0
var toast = ""
var toastUntil = 0
var firstRun = false
var bindCollision = false
var suggestedBind = "SUPER+F"
var alternateBinds = ["SUPER+H", "SUPER+;"]
var swapCapable = false
var swapGreyed = true
var moreNote = ""
var paintedAt = 0
var gutter = false
var error = ""
var submapActive = false
var submapInstalled = false
var bindingsWarning = ""
var inputPath = "submap"

function snapshot() {
    return {
        revision: revision,
        opened: opened,
        labels: labels,
        prefix: prefix,
        verb: verb,
        moveTo: moveTo,
        armedAddress: armedAddress,
        overflow: overflow,
        toast: toast,
        toastUntil: toastUntil,
        firstRun: firstRun,
        bindCollision: bindCollision,
        suggestedBind: suggestedBind,
        alternateBinds: alternateBinds.slice(),
        swapCapable: swapCapable,
        swapGreyed: swapGreyed,
        moreNote: moreNote,
        paintedAt: paintedAt,
        gutter: gutter,
        error: error,
        submapActive: submapActive,
        submapInstalled: submapInstalled,
        bindingsWarning: bindingsWarning,
        inputPath: inputPath
    }
}

function bump() {
    revision += 1
}

function setOpened(value) {
    opened = !!value
    bump()
}

function setLabels(list, extraOverflow) {
    labels = list || []
    overflow = extraOverflow || 0
    moreNote = overflow > 0 ? ("+" + overflow + " more") : ""
    bump()
}

function setPrefix(value) {
    prefix = String(value || "")
    bump()
}

function setVerb(value, n) {
    verb = String(value || "focus")
    moveTo = n || 0
    bump()
}

function setArmed(address) {
    armedAddress = String(address || "")
    bump()
}

function setToast(message, until) {
    toast = String(message || "")
    toastUntil = until || 0
    bump()
}

function setFirstRun(value, collision, bind, alts) {
    firstRun = !!value
    bindCollision = !!collision
    if (bind)
        suggestedBind = bind
    if (alts && alts.length)
        alternateBinds = alts.slice()
    bump()
}

function setSwap(capable) {
    swapCapable = !!capable
    swapGreyed = !swapCapable
    bump()
}

function setGutter(value) {
    gutter = !!value
    bump()
}

function setError(value) {
    error = String(value || "")
    bump()
}

function setSubmap(value) {
    submapActive = !!value
    bump()
}

function setSubmapInstalled(value) {
    submapInstalled = !!value
    bump()
}

function setBindingsWarning(value) {
    bindingsWarning = String(value || "")
    bump()
}

function setInputPath(value) {
    inputPath = value === "overlay" ? "overlay" : "submap"
    bump()
}

function setPaintedAt(ts) {
    paintedAt = ts || 0
}

function resetView() {
    opened = false
    labels = []
    prefix = ""
    verb = "focus"
    moveTo = 0
    armedAddress = ""
    overflow = 0
    moreNote = ""
    toast = ""
    toastUntil = 0
    gutter = false
    error = ""
    submapActive = false
    bump()
}

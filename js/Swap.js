.pragma library

function workspaceId(ws) {
    if (ws === undefined || ws === null)
        return null
    if (typeof ws === "number")
        return ws
    if (typeof ws === "object" && ws.id !== undefined && ws.id !== null)
        return ws.id
    if (typeof ws === "string") {
        var n = parseInt(ws, 10)
        return isNaN(n) ? ws : n
    }
    return null
}

function sameWorkspace(a, b) {
    if (!a || !b)
        return false
    var aid = workspaceId(a.workspace)
    var bid = workspaceId(b.workspace)
    if (aid === null || bid === null)
        return false
    return aid === bid
}

function findByAddress(clients, address) {
    var want = String(address || "").toLowerCase()
    if (want.indexOf("0x") !== 0)
        want = "0x" + want
    for (var i = 0; i < (clients || []).length; i++) {
        var got = String(clients[i].address || "").toLowerCase()
        if (got === want)
            return clients[i]
    }
    return null
}

function canSwap(focused, target, swapCapable) {
    if (!swapCapable)
        return { ok: false, reason: "greyed" }
    if (!focused || !target)
        return { ok: false, reason: "missing" }
    if (String(focused.address).toLowerCase() === String(target.address).toLowerCase())
        return { ok: false, reason: "same-window" }
    if (!sameWorkspace(focused, target))
        return { ok: false, reason: "cross-workspace" }
    return { ok: true, reason: "" }
}

function parseDispatchResult(text) {
    var lower = String(text || "").toLowerCase()
    if (lower.indexOf("l|r|u|d") >= 0 || lower.indexOf("l/r/u/d") >= 0 || lower.indexOf("invalid direction") >= 0)
        return { capable: false, reason: "directional-only" }
    if (lower.indexOf("invalid window") >= 0 || lower.indexOf("window not found") >= 0 || lower.indexOf("couldn't find") >= 0 || lower.indexOf("could not find") >= 0 || lower.indexOf("no such window") >= 0 || lower.indexOf("unknown window") >= 0)
        return { capable: true, reason: "dispatch-accepted-address" }
    if (lower.indexOf("address:") >= 0)
        return { capable: true, reason: "dispatch-mentions-address" }
    return { capable: false, reason: "unknown" }
}

function parseSwapProbe(text) {
    var raw = String(text || "")
    var data = null
    var trimmed = raw.replace(/^\s+/, "")
    if (trimmed.charAt(0) === "{") {
        try {
            data = JSON.parse(trimmed)
        } catch (e) {
            data = null
        }
    }
    if (data && typeof data === "object" && data.capable !== undefined)
        return { capable: !!data.capable, reason: String(data.reason || "") }
    return parseDispatchResult(raw)
}

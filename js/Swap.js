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

function parseSwapProbe(text) {
    var raw = String(text || "")
    var data = null
    if (raw.charAt(0) === "{") {
        try {
            data = JSON.parse(raw)
        } catch (e) {
            data = null
        }
    }
    if (data && typeof data === "object") {
        return {
            capable: !!data.capable,
            reason: String(data.reason || "")
        }
    }
    var lower = raw.toLowerCase()
    if (lower.indexOf("l|r|u|d") >= 0 || (lower.indexOf("direction") >= 0 && lower.indexOf("address") < 0 && lower.indexOf("target") < 0))
        return { capable: false, reason: "directional-only" }
    if (lower.indexOf("address") >= 0 || lower.indexOf("target") >= 0)
        return { capable: true, reason: "help-mentions-target" }
    return { capable: false, reason: "unknown" }
}

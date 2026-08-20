.pragma library

function addr(address) {
    var s = String(address || "").trim().toLowerCase()
    if (!s)
        return ""
    if (s.indexOf("0x") !== 0)
        s = "0x" + s
    return s
}

function focusCmd(address) {
    return "focuswindow address:" + addr(address)
}

function closeCmd(address) {
    return "closewindow address:" + addr(address)
}

function moveCmd(address, workspace) {
    return "movetoworkspacesilent " + String(workspace) + ",address:" + addr(address)
}

// Same dispatcher string the swap probe exercises. Service only
// commits this when swapCapable is true (address targeting confirmed).
function swapCmd(address) {
    return "swapwindow address:" + addr(address)
}

function swapProbeCmd() {
    return swapCmd("0x0")
}

function swapProbeArgv() {
    return ["swapwindow", "address:0x0"]
}

function submapCmd(name) {
    return "submap " + String(name || "reset")
}

function dispatchArgv(request) {
    var s = String(request || "").trim()
    if (!s)
        return []
    var i = s.indexOf(" ")
    if (i < 0)
        return ["hyprctl", "dispatch", s]
    return ["hyprctl", "dispatch", s.slice(0, i), s.slice(i + 1)]
}

function batch(cmds) {
    var parts = []
    for (var i = 0; i < (cmds || []).length; i++) {
        if (cmds[i])
            parts.push("dispatch " + cmds[i])
    }
    return parts.join(" ; ")
}

function commit(verb, target, moveTo) {
    if (!target || !target.address)
        return null
    var a = addr(target.address)
    if (verb === "close")
        return { kind: "close", dispatch: closeCmd(a), address: a }
    if (verb === "move")
        return { kind: "move", dispatch: moveCmd(a, moveTo), address: a, workspace: moveTo }
    if (verb === "swap")
        return { kind: "swap", dispatch: swapCmd(a), address: a }
    return { kind: "focus", dispatch: focusCmd(a), address: a }
}

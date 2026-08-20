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
    return "hl.dsp.focus({ window = \"address:" + addr(address) + "\" })"
}

function closeCmd(address) {
    return "hl.dsp.window.close({ window = \"address:" + addr(address) + "\" })"
}

function moveCmd(address, workspace) {
    return "hl.dsp.window.move({ workspace = \"" + String(workspace) + "\", follow = false, window = \"address:" + addr(address) + "\" })"
}

// Same Lua dispatcher the swap probe exercises. Service only
// commits this when swapCapable is true (address targeting confirmed).
function swapCmd(address) {
    return "hl.dsp.window.swap({ target = \"address:" + addr(address) + "\" })"
}

function swapProbeCmd() {
    return swapCmd("0x0")
}

function swapProbeArgv() {
    return dispatchArgv(swapProbeCmd())
}

function submapCmd(name) {
    return "hl.dsp.submap(\"" + String(name || "reset") + "\")"
}

// Hyprland 0.56: `hyprctl dispatch` takes one Lua expression argv.
// Splitting dispatcher/arg concatenates into invalid Lua (exit 7).
function dispatchArgv(request) {
    var s = String(request || "").trim()
    if (!s)
        return []
    return ["hyprctl", "dispatch", s]
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

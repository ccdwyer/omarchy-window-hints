.pragma library

function normalizeAddress(value) {
    var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    if (!s)
        return ""
    if (s.indexOf("0x") !== 0)
        s = "0x" + s
    return s
}

function asNumber(value, fallback) {
    var n = Number(value)
    if (isNaN(n))
        return fallback
    return n
}

function asPair(value) {
    if (Array.isArray(value) && value.length >= 2)
        return [asNumber(value[0], 0), asNumber(value[1], 0)]
    if (value && typeof value === "object")
        return [asNumber(value.x, 0), asNumber(value.y, 0)]
    return [0, 0]
}

function workspaceObj(raw) {
    if (raw === undefined || raw === null)
        return { id: null, name: "" }
    if (typeof raw === "number")
        return { id: raw, name: String(raw) }
    if (typeof raw === "string") {
        var n = parseInt(raw, 10)
        return { id: isNaN(n) ? null : n, name: raw }
    }
    if (typeof raw === "object") {
        var id = raw.id
        if (id === undefined)
            id = raw.ID
        var name = raw.name
        if (name === undefined)
            name = raw.Name
        return {
            id: id === undefined || id === null ? null : asNumber(id, null),
            name: name === undefined || name === null ? "" : String(name)
        }
    }
    return { id: null, name: "" }
}

function parseClient(raw) {
    if (!raw || typeof raw !== "object")
        return null
    var address = normalizeAddress(raw.address || raw.Address || "")
    if (!address)
        return null
    var monitor = raw.monitor
    if (monitor === undefined)
        monitor = raw.monitorID
    if (monitor === undefined)
        monitor = raw.monitorId
    var mapped = raw.mapped
    if (mapped === undefined)
        mapped = true
    var hidden = !!raw.hidden
    var fullscreen = raw.fullscreen
    if (fullscreen === undefined)
        fullscreen = raw.fullscreenClient
    return {
        address: address,
        mapped: !!mapped,
        hidden: hidden,
        at: asPair(raw.at),
        size: asPair(raw.size),
        workspace: workspaceObj(raw.workspace),
        floating: !!raw.floating,
        monitor: monitor === undefined || monitor === null ? null : asNumber(monitor, null),
        monitorName: raw.monitorName ? String(raw.monitorName) : "",
        className: String(raw.class || raw.className || raw.klass || raw.initialClass || ""),
        title: String(raw.title || raw.initialTitle || ""),
        pid: asNumber(raw.pid, 0),
        fullscreen: fullscreen === undefined || fullscreen === null ? 0 : asNumber(fullscreen, 0),
        focusHistoryID: asNumber(raw.focusHistoryID, 9999)
    }
}

function parseJsonArray(text) {
    var data = text
    if (typeof text === "string") {
        try {
            data = JSON.parse(text)
        } catch (e) {
            return { ok: false, value: [] }
        }
    }
    if (!Array.isArray(data))
        return { ok: false, value: [] }
    return { ok: true, value: data }
}

function parseClients(text) {
    var bag = parseJsonArray(text)
    if (!bag.ok)
        return { ok: false, clients: [] }
    var out = []
    for (var i = 0; i < bag.value.length; i++) {
        try {
            var c = parseClient(bag.value[i])
            if (c)
                out.push(c)
        } catch (err) {
            // Feature-detect: skip a malformed client rather than crash.
        }
    }
    return { ok: true, clients: out }
}

function parseMonitor(raw) {
    if (!raw || typeof raw !== "object")
        return null
    var id = raw.id
    if (id === undefined)
        id = raw.ID
    var reserved = raw.reserved
    if (reserved && typeof reserved === "object" && !Array.isArray(reserved)) {
        reserved = [
            asNumber(reserved.top, 0),
            asNumber(reserved.bottom, 0),
            asNumber(reserved.left, 0),
            asNumber(reserved.right, 0)
        ]
    }
    if (!Array.isArray(reserved) || reserved.length < 4)
        reserved = [0, 0, 0, 0]
    return {
        id: id === undefined || id === null ? null : asNumber(id, null),
        name: String(raw.name || raw.Name || ""),
        x: asNumber(raw.x, 0),
        y: asNumber(raw.y, 0),
        width: asNumber(raw.width, 0),
        height: asNumber(raw.height, 0),
        scale: asNumber(raw.scale, 1) || 1,
        transform: asNumber(raw.transform, 0),
        activeWorkspace: workspaceObj(raw.activeWorkspace || raw.activeworkspace),
        specialWorkspace: workspaceObj(raw.specialWorkspace || raw.specialworkspace),
        reserved: reserved,
        focused: !!raw.focused,
        disabled: !!raw.disabled
    }
}

function parseMonitors(text) {
    var bag = parseJsonArray(text)
    if (!bag.ok)
        return { ok: false, monitors: [] }
    var out = []
    for (var i = 0; i < bag.value.length; i++) {
        try {
            var m = parseMonitor(bag.value[i])
            if (m && !m.disabled)
                out.push(m)
        } catch (err) {
        }
    }
    return { ok: true, monitors: out }
}

function fromToplevel(top) {
    if (!top)
        return null
    var ipc = null
    try {
        ipc = top.lastIpcObject
    } catch (e) {
        ipc = null
    }
    if (ipc && typeof ipc === "object") {
        var parsed = parseClient(ipc)
        if (parsed)
            return parsed
    }
    var address = ""
    try {
        address = normalizeAddress(top.address)
    } catch (e2) {
        address = ""
    }
    if (!address)
        return null
    var workspace = null
    try {
        workspace = top.workspace
    } catch (e3) {
        workspace = null
    }
    var title = ""
    try {
        title = String(top.title || "")
    } catch (e4) {
        title = ""
    }
    return {
        address: address,
        mapped: true,
        hidden: false,
        at: [0, 0],
        size: [0, 0],
        workspace: workspaceObj(workspace),
        floating: false,
        monitor: null,
        monitorName: "",
        className: "",
        title: title,
        pid: 0,
        fullscreen: 0,
        focusHistoryID: 9999
    }
}

function hasGeometry(client) {
    if (!client || !client.size)
        return false
    var w = 0
    var h = 0
    if (Array.isArray(client.size) && client.size.length >= 2) {
        w = Number(client.size[0]) || 0
        h = Number(client.size[1]) || 0
    }
    return w > 0 || h > 0
}

function mergeToplevels(existing, tops) {
    var byAddr = {}
    var i
    var list = existing || []
    for (i = 0; i < list.length; i++) {
        var addr = normalizeAddress(list[i].address)
        if (addr)
            byAddr[addr] = list[i]
    }
    var incoming = tops || []
    for (i = 0; i < incoming.length; i++) {
        var top = incoming[i]
        if (!top)
            continue
        var a = normalizeAddress(top.address)
        if (!a)
            continue
        var prev = byAddr[a]
        if (!prev) {
            if (hasGeometry(top))
                byAddr[a] = top
            continue
        }
        if (top.title)
            prev.title = top.title
        if (top.className)
            prev.className = top.className
        if (top.workspace)
            prev.workspace = top.workspace
        if (top.mapped !== undefined)
            prev.mapped = top.mapped
        if (hasGeometry(top)) {
            prev.at = top.at
            prev.size = top.size
            if (top.monitor !== null && top.monitor !== undefined)
                prev.monitor = top.monitor
        }
        byAddr[a] = prev
    }
    var out = []
    for (var k in byAddr) {
        if (byAddr.hasOwnProperty(k))
            out.push(byAddr[k])
    }
    return out
}

function fromToplevels(model) {
    if (!model)
        return null
    var values = null
    try {
        if (model.values)
            values = model.values
        else if (typeof model.count === "number") {
            values = []
            for (var i = 0; i < model.count; i++)
                values.push(model.get ? model.get(i) : model[i])
        } else if (Array.isArray(model))
            values = model
    } catch (e) {
        return null
    }
    if (!values)
        return null
    var out = []
    for (var j = 0; j < values.length; j++) {
        try {
            var c = fromToplevel(values[j])
            if (c)
                out.push(c)
        } catch (err) {
        }
    }
    return out
}

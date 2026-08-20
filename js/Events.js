.pragma library

var KNOWN = {
    openwindow: { args: 4, fields: ["address", "workspace", "klass", "title"] },
    closewindow: { args: 1, fields: ["address"] },
    movewindow: { args: 2, fields: ["address", "workspace"] },
    movewindowv2: { args: 3, fields: ["address", "workspaceId", "workspace"] },
    activewindow: { args: 2, fields: ["klass", "title"] },
    activewindowv2: { args: 1, fields: ["address"] },
    workspace: { args: 1, fields: ["workspace"] },
    workspacev2: { args: 2, fields: ["workspaceId", "workspace"] },
    focusedmon: { args: 2, fields: ["monitor", "workspace"] },
    focusedmonv2: { args: 2, fields: ["monitor", "workspaceId"] },
    fullscreen: { args: 1, fields: ["state"] },
    changefloatingmode: { args: 2, fields: ["address", "floating"] },
    monitoradded: { args: 1, fields: ["name"] },
    monitoraddedv2: { args: 3, fields: ["id", "name", "description"] },
    monitorremoved: { args: 1, fields: ["name"] },
    configreloaded: { args: 0, fields: [] }
}

var MODEL_EVENTS = {
    openwindow: true,
    closewindow: true,
    movewindow: true,
    movewindowv2: true,
    workspace: true,
    workspacev2: true,
    focusedmon: true,
    focusedmonv2: true,
    fullscreen: true,
    changefloatingmode: true,
    monitoradded: true,
    monitoraddedv2: true,
    monitorremoved: true
}

function normalizeAddress(value) {
    var s = String(value || "").trim().toLowerCase()
    if (!s)
        return ""
    if (s.indexOf("0x") !== 0)
        s = "0x" + s
    return s
}

function splitArgs(data, count) {
    if (count <= 0)
        return []
    if (data === undefined || data === null || data === "")
        return count === 1 ? [""] : []
    var parts = []
    var rest = String(data)
    for (var i = 0; i < count - 1; i++) {
        var idx = rest.indexOf(",")
        if (idx < 0) {
            parts.push(rest)
            rest = ""
            break
        }
        parts.push(rest.slice(0, idx))
        rest = rest.slice(idx + 1)
    }
    while (parts.length < count - 1)
        parts.push("")
    parts.push(rest)
    return parts
}

function parseLine(line) {
    var raw = String(line || "").replace(/\r$/, "")
    if (!raw)
        return null
    var sep = raw.indexOf(">>")
    if (sep < 0)
        return { kind: "unknown", name: "", data: raw, raw: raw, fields: {}, refreshModel: false, mru: false }
    var name = raw.slice(0, sep)
    var data = raw.slice(sep + 2)
    var spec = KNOWN[name]
    if (!spec) {
        return {
            kind: "unknown",
            name: name,
            data: data,
            raw: raw,
            fields: {},
            refreshModel: false,
            mru: false
        }
    }
    var args = splitArgs(data, spec.args)
    var fields = {}
    for (var i = 0; i < spec.fields.length; i++)
        fields[spec.fields[i]] = args[i] === undefined ? "" : args[i]
    if (fields.address)
        fields.address = normalizeAddress(fields.address)
    return {
        kind: name,
        name: name,
        data: data,
        raw: raw,
        fields: fields,
        refreshModel: !!MODEL_EVENTS[name],
        mru: name === "activewindowv2"
    }
}

function parseStream(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
        var ev = parseLine(lines[i])
        if (ev)
            out.push(ev)
    }
    return out
}

.pragma library

var DEFAULT_ALPHABET = "asdfghjkl"
var DEFAULT_CAP = 25

var sessionChords = {}
var sessionSetKey = ""

function resetSession() {
    sessionChords = {}
    sessionSetKey = ""
}

function normalizeAddress(value) {
    var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    if (!s)
        return ""
    if (s.indexOf("0x") !== 0)
        s = "0x" + s
    return s
}

function workspaceId(ws) {
    if (ws === undefined || ws === null)
        return null
    if (typeof ws === "number")
        return ws
    if (typeof ws === "string") {
        var n = parseInt(ws, 10)
        if (!isNaN(n))
            return n
        return ws
    }
    if (typeof ws === "object") {
        if (ws.id !== undefined && ws.id !== null)
            return ws.id
        if (ws.name !== undefined)
            return ws.name
    }
    return null
}

function workspaceName(ws) {
    if (ws === undefined || ws === null)
        return ""
    if (typeof ws === "string")
        return ws
    if (typeof ws === "object")
        return String(ws.name || "")
    return String(ws)
}

function isSpecialWorkspace(ws) {
    var name = workspaceName(ws)
    if (name.indexOf("special") === 0)
        return true
    var id = workspaceId(ws)
    if (typeof id === "number" && id < 0)
        return true
    return false
}

function specialShown(mon) {
    var sp = mon && mon.specialWorkspace
    if (!sp)
        return false
    var name = workspaceName(sp)
    if (name && name !== "" && name !== "0")
        return true
    var id = workspaceId(sp)
    if (typeof id === "number" && id !== 0)
        return true
    return false
}

function findMonitor(monitors, client) {
    if (!monitors || !monitors.length || !client)
        return null
    var mid = client.monitor
    if (mid === -1 || mid === "-1")
        return null
    var i
    for (i = 0; i < monitors.length; i++) {
        if (monitors[i].id === mid || monitors[i].id === Number(mid))
            return monitors[i]
    }
    if (client.monitorName) {
        for (i = 0; i < monitors.length; i++) {
            if (monitors[i].name === client.monitorName)
                return monitors[i]
        }
    }
    return null
}

function isVisible(client, monitors) {
    if (!client)
        return false
    if (client.hidden === true)
        return false
    if (client.mapped === false)
        return false
    var mid = client.monitor
    if (mid === -1 || mid === "-1" || mid === null || mid === undefined)
        return false
    var mon = findMonitor(monitors, client)
    if (!mon)
        return false
    var wsId = workspaceId(client.workspace)
    var wsName = workspaceName(client.workspace)
    var activeId = workspaceId(mon.activeWorkspace)
    var activeName = workspaceName(mon.activeWorkspace)

    if (specialShown(mon)) {
        var sp = mon.specialWorkspace
        var spId = workspaceId(sp)
        var spName = workspaceName(sp)
        if ((spId !== null && wsId === spId) || (spName && wsName === spName))
            return true
    }

    if (isSpecialWorkspace(client.workspace) && !specialShown(mon))
        return false

    if (wsId !== null && activeId !== null && wsId === activeId)
        return true
    if (wsName && activeName && String(wsName) === String(activeName))
        return true
    return false
}

function visibleClients(clients, monitors) {
    var out = []
    var list = clients || []
    for (var i = 0; i < list.length; i++) {
        try {
            if (isVisible(list[i], monitors))
                out.push(list[i])
        } catch (e) {
        }
    }
    return out
}

function setKeyOf(addresses) {
    var copy = addresses.slice()
    copy.sort()
    return copy.join(",")
}

function sortByMru(windows, mru) {
    var rank = {}
    var list = mru || []
    for (var i = 0; i < list.length; i++)
        rank[normalizeAddress(list[i])] = i
    var copy = windows.slice()
    copy.sort(function (a, b) {
        var aa = normalizeAddress(a.address)
        var bb = normalizeAddress(b.address)
        var ra = rank.hasOwnProperty(aa) ? rank[aa] : 10000 + (a.focusHistoryID || 0)
        var rb = rank.hasOwnProperty(bb) ? rank[bb] : 10000 + (b.focusHistoryID || 0)
        if (ra !== rb)
            return ra - rb
        if (aa < bb)
            return -1
        if (aa > bb)
            return 1
        return 0
    })
    return copy
}

function maxAddressable(k) {
    var max = 0
    for (var s = 0; s <= k; s++) {
        var capn = s + (k - s) * k
        if (capn > max)
            max = capn
    }
    return max
}

function chordsNeeded(n, k) {
    if (n <= k)
        return { singles: n, prefixes: 0 }
    var best = 0
    for (var s = 0; s <= k; s++) {
        if (s + (k - s) * k >= n)
            best = s
    }
    return { singles: best, prefixes: k - best }
}

function allocateFresh(addresses, alphabet) {
    var k = alphabet.length
    var n = addresses.length
    var plan = chordsNeeded(n, k)
    var map = {}
    var i
    for (i = 0; i < plan.singles && i < n; i++)
        map[addresses[i]] = alphabet.charAt(i)
    var prefixIdx = plan.singles
    var second = 0
    for (i = plan.singles; i < n; i++) {
        if (prefixIdx >= k)
            break
        map[addresses[i]] = alphabet.charAt(prefixIdx) + alphabet.charAt(second)
        second++
        if (second >= k) {
            second = 0
            prefixIdx++
        }
    }
    return map
}

function prefixFreeMap(map) {
    var chords = []
    var a
    for (a in map) {
        if (map.hasOwnProperty(a))
            chords.push(map[a])
    }
    for (var i = 0; i < chords.length; i++) {
        for (var j = 0; j < chords.length; j++) {
            if (i === j)
                continue
            if (chords[i] === chords[j])
                return false
            if (chords[j].indexOf(chords[i]) === 0)
                return false
        }
    }
    return true
}

function uniqueChords(map) {
    var seen = {}
    var a
    for (a in map) {
        if (!map.hasOwnProperty(a))
            continue
        var c = map[a]
        if (!c || seen[c])
            return false
        seen[c] = true
    }
    return true
}

function assignSession(windows, alphabet, mru, cap) {
    alphabet = DEFAULT_ALPHABET
    cap = cap || DEFAULT_CAP
    var k = alphabet.length
    var chordCap = maxAddressable(k)
    if (cap > chordCap)
        cap = chordCap
    var ordered = sortByMru(windows || [], mru)
    var overflow = Math.max(0, ordered.length - cap)
    var hinted = ordered.slice(0, cap)
    var addrs = []
    var i
    for (i = 0; i < hinted.length; i++)
        addrs.push(normalizeAddress(hinted[i].address))

    var key = setKeyOf(addrs) + "|" + alphabet
    if (key === sessionSetKey && Object.keys(sessionChords).length) {
        return { chords: sessionChords, hinted: hinted, overflow: overflow, reused: true }
    }

    var fresh = allocateFresh(addrs, alphabet)
    var kept = []
    for (i = 0; i < hinted.length; i++) {
        var ch = fresh[addrs[i]]
        if (ch)
            kept.push(hinted[i])
        else
            overflow += 1
    }
    sessionChords = fresh
    sessionSetKey = key
    return { chords: fresh, hinted: kept, overflow: overflow, reused: false }
}

function freezeInvocation(assignment, visibleNow) {
    var hinted = (assignment && assignment.hinted) || []
    var chords = (assignment && assignment.chords) || {}
    var live = {}
    var vis = visibleNow || hinted
    var i
    for (i = 0; i < vis.length; i++)
        live[normalizeAddress(vis[i].address)] = vis[i]

    var frozen = []
    var seen = {}
    for (i = 0; i < hinted.length; i++) {
        var addr = normalizeAddress(hinted[i].address)
        if (!live[addr])
            continue
        if (seen[addr])
            continue
        seen[addr] = true
        var w = live[addr]
        frozen.push({
            address: addr,
            chord: chords[addr] || "",
            className: w.className || w.class || w.klass || "",
            title: w.title || "",
            at: w.at,
            size: w.size,
            workspace: w.workspace,
            monitor: w.monitor,
            monitorName: w.monitorName || "",
            floating: !!w.floating,
            fullscreen: w.fullscreen
        })
    }
    return {
        labels: frozen,
        overflow: (assignment && assignment.overflow) || 0,
        vanished: hinted.length - frozen.length
    }
}

function dropVanished(labels, liveAddresses) {
    var live = {}
    var i
    for (i = 0; i < (liveAddresses || []).length; i++)
        live[normalizeAddress(liveAddresses[i])] = true
    var kept = []
    for (i = 0; i < (labels || []).length; i++) {
        if (live[normalizeAddress(labels[i].address)])
            kept.push(labels[i])
    }
    return kept
}

function matchPrefix(labels, prefix) {
    var p = String(prefix || "")
    var exact = []
    var partial = []
    var rest = []
    for (var i = 0; i < (labels || []).length; i++) {
        var c = labels[i].chord || ""
        if (p && c === p)
            exact.push(labels[i])
        else if (p && c.indexOf(p) === 0)
            partial.push(labels[i])
        else
            rest.push(labels[i])
    }
    return { exact: exact, partial: partial, rest: rest }
}

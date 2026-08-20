#!/usr/bin/env node
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ROOT = path.resolve(__dirname, "..")
const JS = path.join(ROOT, "js")
const FIX = path.join(__dirname, "fixtures")

function loadEngine(file) {
  const src = fs
    .readFileSync(path.join(JS, file), "utf8")
    .replace(/^\.pragma library\s*\n/, "")
  const sandbox = {
    console,
    Date,
    Math,
    JSON,
    String,
    Number,
    Array,
    Object,
    parseInt,
    isNaN,
    exports: {},
    module: { exports: {} }
  }
  vm.createContext(sandbox)
  vm.runInContext(src, sandbox, { filename: file })
  const exported = {}
  for (const key of Object.keys(sandbox)) {
    if (["console", "Date", "Math", "JSON", "String", "Number", "Array", "Object", "parseInt", "isNaN", "exports", "module"].indexOf(key) >= 0)
      continue
    exported[key] = sandbox[key]
  }
  return exported
}

const Config = loadEngine("Config.js")
const Clients = loadEngine("Clients.js")
const Events = loadEngine("Events.js")
const Geometry = loadEngine("Geometry.js")
const HintEngine = loadEngine("HintEngine.js")
const Input = loadEngine("Input.js")
const Actions = loadEngine("Actions.js")
const Swap = loadEngine("Swap.js")
const Session = loadEngine("Session.js")
const Binds = loadEngine("Binds.js")

let passed = 0
let failed = 0

function same(actual, expected) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))
}

function test(name, fn) {
  try {
    HintEngine.resetSession()
    Config.reset()
    Input.reset(Input.create())
    Session.resetView()
    fn()
    passed += 1
    process.stdout.write("ok  " + name + "\n")
  } catch (err) {
    failed += 1
    process.stderr.write("FAIL " + name + "\n" + (err && err.stack ? err.stack : err) + "\n")
  }
}

function fixture(name) {
  return fs.readFileSync(path.join(FIX, name), "utf8")
}

function jsonFix(name) {
  return JSON.parse(fixture(name))
}

function win(address, extras) {
  return Object.assign({
    address,
    mapped: true,
    hidden: false,
    at: [0, 0],
    size: [200, 200],
    workspace: { id: 1, name: "1" },
    floating: false,
    monitor: 0,
    className: "app",
    title: address,
    focusHistoryID: 99
  }, extras || {})
}

function manyWindows(n) {
  const out = []
  for (let i = 0; i < n; i++)
    out.push(win("0x" + (1000 + i).toString(16), { focusHistoryID: i }))
  return out
}

function parsedClients(src) {
  const r = Clients.parseClients(src)
  assert.strictEqual(r.ok, true)
  return r.clients
}

function parsedMonitors(src) {
  const r = Clients.parseMonitors(src)
  assert.strictEqual(r.ok, true)
  return r.monitors
}

test("clients: parse tiled fixture and normalize address", () => {
  const clients = parsedClients(fixture("clients-six.json"))
  assert.strictEqual(clients.length, 6)
  assert.strictEqual(clients[0].address, "0xaaa1")
  assert.strictEqual(clients[0].className, "firefox")
  same(clients[0].at, [40, 80])
})

test("clients: sparse / missing optional fields never throw", () => {
  const c = Clients.parseClient(jsonFix("clients-sparse.json"))
  assert.strictEqual(c.address, "0x64cea2525760")
  same(c.at, [12, 48])
  assert.strictEqual(c.workspace.id, 1)
  assert.strictEqual(c.mapped, true)
  assert.strictEqual(c.hidden, false)
})

test("clients: malformed payload is empty not throw", () => {
  const bad = Clients.parseClients("not-json")
  assert.strictEqual(bad.ok, false)
  same(bad.clients, [])
  const obj = Clients.parseClients("{}")
  assert.strictEqual(obj.ok, false)
  same(obj.clients, [])
  const empty = Clients.parseClients("[]")
  assert.strictEqual(empty.ok, true)
  same(empty.clients, [])
  assert.strictEqual(Clients.parseMonitors("not-json").ok, false)
  assert.strictEqual(Clients.parseMonitors("[]").ok, true)
  assert.strictEqual(Clients.parseClient(null), null)
})

test("visibility: per-monitor activeWorkspace, not a global singleton", () => {
  const clients = parsedClients(fixture("clients-six.json"))
  const monitors = parsedMonitors(fixture("monitors-mixed-scale.json"))
  const vis = HintEngine.visibleClients(clients, monitors)
  assert.strictEqual(vis.length, 6)
  const ws1 = vis.filter((c) => c.workspace.id === 1)
  const ws2 = vis.filter((c) => c.workspace.id === 2)
  assert.strictEqual(ws1.length, 3)
  assert.strictEqual(ws2.length, 3)
})

test("visibility: monitor -1 and hidden special are excluded", () => {
  const clients = parsedClients(fixture("clients-hidden-special.json"))
  const monitors = parsedMonitors(fixture("monitors-single.json"))
  const vis = HintEngine.visibleClients(clients, monitors)
  assert.strictEqual(vis.length, 1)
  assert.strictEqual(vis[0].address, "0xvis1")
})

test("visibility: shown special workspace is included", () => {
  const monitors = parsedMonitors(fixture("monitors-single.json"))
  monitors[0].specialWorkspace = { id: -97, name: "special:magic" }
  const clients = parsedClients(fixture("clients-hidden-special.json"))
  const vis = HintEngine.visibleClients(clients, monitors)
  const addrs = vis.map((c) => c.address).sort()
  same(addrs, ["0xspec1", "0xvis1"])
})

test("allocator: unique and prefix-free for 1..25 windows", () => {
  for (let n = 1; n <= 25; n++) {
    HintEngine.resetSession()
    const assignment = HintEngine.assignSession(manyWindows(n), "asdfghjkl", [], 25)
    assert.ok(HintEngine.uniqueChords(assignment.chords), "unique n=" + n)
    assert.ok(HintEngine.prefixFreeMap(assignment.chords), "prefix-free n=" + n)
    assert.strictEqual(Object.keys(assignment.chords).length, n)
  }
})

test("allocator: <=9 windows are single-key", () => {
  const assignment = HintEngine.assignSession(manyWindows(9), "asdfghjkl", [], 25)
  for (const addr of Object.keys(assignment.chords))
    assert.strictEqual(assignment.chords[addr].length, 1)
})

test("allocator: 10 windows mix one-key and two-key", () => {
  const assignment = HintEngine.assignSession(manyWindows(10), "asdfghjkl", [], 25)
  const lengths = Object.values(assignment.chords).map((c) => c.length)
  assert.ok(lengths.indexOf(1) >= 0)
  assert.ok(lengths.indexOf(2) >= 0)
})

test("allocator: MRU windows get the shortest chords", () => {
  const windows = manyWindows(12)
  const mru = ["0x3f3", "0x3f2", "0x3f1"]
  const assignment = HintEngine.assignSession(windows, "asdfghjkl", mru, 25)
  assert.strictEqual(assignment.chords["0x3f3"].length, 1)
  assert.strictEqual(assignment.chords["0x3f2"].length, 1)
  assert.strictEqual(assignment.chords["0x3f1"].length, 1)
})

test("allocator: determinism — same set same chords", () => {
  const windows = manyWindows(11)
  const a = HintEngine.assignSession(windows, "asdfghjkl", ["0x3e8"], 25)
  const first = Object.assign({}, a.chords)
  HintEngine.resetSession()
  const b = HintEngine.assignSession(windows, "asdfghjkl", ["0x3e8"], 25)
  same(b.chords, first)
})

test("allocator: session-stable across MRU reorder", () => {
  const windows = manyWindows(8)
  const first = HintEngine.assignSession(windows, "asdfghjkl", ["0x3e8", "0x3e9"], 25)
  const chords = Object.assign({}, first.chords)
  const again = HintEngine.assignSession(windows, "asdfghjkl", ["0x3ef", "0x3e8"], 25)
  assert.strictEqual(again.reused, true)
  same(again.chords, chords)
})

test("allocator: 25-cap and overflow note", () => {
  const assignment = HintEngine.assignSession(manyWindows(40), "asdfghjkl", [], 25)
  assert.strictEqual(assignment.hinted.length, 25)
  assert.strictEqual(assignment.overflow, 15)
})

test("freeze: vanished label dropped, chord never reassigned", () => {
  const windows = manyWindows(5)
  const assignment = HintEngine.assignSession(windows, "asdfghjkl", [], 25)
  const gone = windows[0].address
  const chord = assignment.chords[gone]
  const live = windows.slice(1)
  const frozen = HintEngine.freezeInvocation(assignment, live)
  assert.strictEqual(frozen.labels.length, 4)
  assert.strictEqual(frozen.vanished, 1)
  assert.ok(!frozen.labels.some((l) => l.address === gone))
  assert.ok(!frozen.labels.some((l) => l.chord === chord))
})

test("freeze: new windows mid-hint are ignored", () => {
  const windows = manyWindows(4)
  const assignment = HintEngine.assignSession(windows, "asdfghjkl", [], 25)
  const extra = windows.concat([win("0xdeadbeef")])
  const frozen = HintEngine.freezeInvocation(assignment, extra)
  assert.strictEqual(frozen.labels.length, 4)
  assert.ok(!frozen.labels.some((l) => l.address === "0xdeadbeef"))
})

test("cold start: empty model then real windows is a new freeze, not prune-only", () => {
  HintEngine.resetSession()
  const empty = HintEngine.assignSession([], "asdfghjkl", [], 25)
  const frozenEmpty = HintEngine.freezeInvocation(empty, [])
  assert.strictEqual(frozenEmpty.labels.length, 0)
  const windows = manyWindows(6)
  const assignment = HintEngine.assignSession(windows, "asdfghjkl", [], 25)
  const frozen = HintEngine.freezeInvocation(assignment, windows)
  assert.strictEqual(frozen.labels.length, 6)
  const pruned = HintEngine.dropVanished(frozenEmpty.labels, windows.map((w) => w.address))
  assert.strictEqual(pruned.length, 0)
})

test("geometry: scale 1.0 / 1.25 / 2.0 never multiplies", () => {
  const at = [100, 200]
  const size = [400, 300]
  for (const scale of [1.0, 1.25, 2.0]) {
    const out = Geometry.globalToOutput(at, size, {
      x: 0, y: 0, width: 1920, height: 1080, scale, transform: 0
    })
    same(out, { x: 100, y: 200, w: 400, h: 300 })
  }
})

test("geometry: mixed 1x+2x side-by-side subtracts monitor offset only", () => {
  const monitors = jsonFix("monitors-mixed-scale.json")
  const left = Geometry.globalToOutput([40, 80], [800, 600], monitors[0])
  const right = Geometry.globalToOutput([2000, 80], [800, 600], monitors[1])
  same(left, { x: 40, y: 80, w: 800, h: 600 })
  same(right, { x: 80, y: 80, w: 800, h: 600 })
})

test("geometry: transform 0 is a straight subtract", () => {
  const out = Geometry.globalToOutput([2020, 100], [200, 200], {
    x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0
  })
  same(out, { x: 100, y: 100, w: 200, h: 200 })
})

test("geometry: transform 90 with preTransform rotates into output-local", () => {
  const mon = jsonFix("monitors-rotated-pre.json")[0]
  const out = Geometry.globalToOutput([100, 50], [200, 80], mon)
  assert.strictEqual(out.x, 50)
  assert.strictEqual(out.y, 1920 - 100 - 200)
  assert.strictEqual(out.w, 80)
  assert.strictEqual(out.h, 200)
})

test("geometry: post-transform rotated monitor does not double-rotate", () => {
  const mon = jsonFix("monitors-rotated.json")[0]
  const out = Geometry.globalToOutput([40, 80], [200, 120], mon)
  same(out, { x: 40, y: 80, w: 200, h: 120 })
})

test("geometry: label anchor respects reserved bar and inset", () => {
  const mon = jsonFix("monitors-single.json")[0]
  const out = { x: 0, y: 0, w: 800, h: 600 }
  const anchor = Geometry.labelAnchor(out, mon, 8, 36, 28, 0)
  assert.ok(anchor.y >= 32 + 2, "below reserved top")
  assert.ok(anchor.x >= 2)
})

test("geometry: stacked overlapping labels are offset vertically", () => {
  const a = { x: 10, y: 10, w: 36, h: 28 }
  const stacked = Geometry.stackOffsets([a, { x: 10, y: 10, w: 36, h: 28 }])
  assert.strictEqual(stacked[0].y, 10)
  assert.ok(stacked[1].y >= 10 + 28)
})

test("input: chord focuses, shift swaps, x arms close, digit moves", () => {
  const labels = [
    { address: "0x1", chord: "a" },
    { address: "0x2", chord: "s" }
  ]
  let s = Input.begin(Input.create())
  let r = Input.handleKey(s, "a", labels, 0, 250)
  assert.strictEqual(r.action, "commit")
  assert.strictEqual(r.verb, "focus")
  assert.strictEqual(r.target.address, "0x1")

  s = Input.begin(Input.create())
  r = Input.handleKey(s, "S", labels, 0, 250)
  assert.strictEqual(r.action, "commit")
  assert.strictEqual(r.verb, "swap")

  s = Input.begin(Input.create())
  r = Input.handleKey(s, "x", labels, 0, 250)
  assert.strictEqual(r.action, "verb")
  r = Input.handleKey(s, "a", labels, 1000, 250)
  assert.strictEqual(r.action, "arm")
  assert.strictEqual(s.state, "armed")
  r = Input.handleKey(s, "escape", labels, 1100, 250)
  assert.strictEqual(r.action, "dismiss")

  s = Input.begin(Input.create())
  r = Input.handleKey(s, "3", labels, 0, 250)
  assert.strictEqual(r.verb, "move")
  r = Input.handleKey(s, "s", labels, 0, 250)
  assert.strictEqual(r.action, "commit")
  assert.strictEqual(r.moveTo, 3)
})

test("input: two-key prefix then unique match", () => {
  const labels = [
    { address: "0x1", chord: "sa" },
    { address: "0x2", chord: "sd" }
  ]
  const s = Input.begin(Input.create())
  let r = Input.handleKey(s, "s", labels, 0, 250)
  assert.strictEqual(r.action, "prefix")
  r = Input.handleKey(s, "d", labels, 0, 250)
  assert.strictEqual(r.action, "commit")
  assert.strictEqual(r.target.address, "0x2")
})

test("input: escape dismisses", () => {
  const s = Input.begin(Input.create())
  const r = Input.handleKey(s, "escape", [], 0, 250)
  assert.strictEqual(r.action, "dismiss")
})

test("swap: same-workspace only; cross-workspace refused", () => {
  const a = win("0x1", { workspace: { id: 1, name: "1" } })
  const b = win("0x2", { workspace: { id: 1, name: "1" } })
  const c = win("0x3", { workspace: { id: 2, name: "2" } })
  assert.strictEqual(Swap.canSwap(a, b, true).ok, true)
  assert.strictEqual(Swap.canSwap(a, c, true).reason, "cross-workspace")
  assert.strictEqual(Swap.canSwap(a, b, false).reason, "greyed")
})

test("swap probe parser: directional vs address dispatch", () => {
  assert.strictEqual(Swap.parseDispatchResult("usage: swapwindow l|r|u|d").capable, false)
  assert.strictEqual(Swap.parseDispatchResult("Invalid direction, expected l/r/u/d").capable, false)
  assert.strictEqual(Swap.parseDispatchResult("Invalid window").capable, true)
  assert.strictEqual(Swap.parseDispatchResult("Window not found").capable, true)
  assert.strictEqual(Swap.parseSwapProbe("{\"capable\":false,\"reason\":\"unknown\"}").capable, false)
  assert.strictEqual(Swap.parseSwapProbe("{\"capable\":true,\"reason\":\"x\"}").capable, true)
  assert.strictEqual(Actions.swapProbeCmd(), 'hl.dsp.window.swap({ target = "address:0x0" })')
  same(Actions.swapProbeArgv(), ["hyprctl", "dispatch", 'hl.dsp.window.swap({ target = "address:0x0" })'])
  assert.strictEqual(Swap.parseDispatchResult("target window not found").capable, true)
})

test("config: injected settings beat Item defaults", () => {
  const defaults = {
    inset: 8,
    maxHints: 25,
    watchdogMs: 15000,
    armMs: 250,
    inputPath: "submap",
    suggestedBind: "SUPER+F"
  }
  const fromDefaults = Config.resolveSettings(defaults, { inset: 12 }, null)
  assert.strictEqual(fromDefaults.inset, 12)
  assert.strictEqual(fromDefaults.maxHints, undefined)
  const hostBound = Config.resolveSettings(Object.assign({}, defaults, { inset: 20 }), null, null)
  assert.strictEqual(hostBound.inset, 20)
  const settingsWin = Config.resolveSettings(Object.assign({}, defaults, { inset: 20 }), { inset: 12 }, { armMs: 400 })
  assert.strictEqual(settingsWin.inset, 12)
  assert.strictEqual(settingsWin.armMs, 400)
  assert.strictEqual(Config.ALPHABET, "asdfghjkl")
  assert.ok(Config.ALPHABET.indexOf("x") < 0)
})

test("config: parseBind uses suggestedBind, not a hardcoded F", () => {
  same(Config.parseBind("SUPER+H"), { mods: "SUPER", key: "H" })
  same(Config.parseBind("SUPER + ;"), { mods: "SUPER", key: "semicolon" })
  same(Config.parseBind(""), { mods: "SUPER", key: "F" })
  assert.strictEqual(Config.luaBind("SUPER+H"), "SUPER + H")
  assert.strictEqual(Config.luaBind("SUPER+;"), "SUPER + semicolon")
  assert.strictEqual(Config.luaBind(""), "SUPER + F")
  assert.strictEqual(Config.keywordBind("SUPER+H"), "SUPER,H")
  assert.strictEqual(Config.keywordBind("SUPER+;"), "SUPER,semicolon")
  assert.strictEqual(Config.keywordBind("SUPER+F"), "SUPER,F")
})

test("config: parseInstall treats missing/false as not installed", () => {
  assert.strictEqual(Config.parseInstall("").installed, false)
  assert.strictEqual(Config.parseInstall("not-json").installed, false)
  assert.strictEqual(Config.parseInstall("{\"ok\":true,\"installed\":false,\"via\":\"bindings.lua\"}").installed, false)
  assert.strictEqual(Config.parseInstall("{\"ok\":true,\"installed\":true,\"via\":\"eval\"}").installed, true)
})

test("actions: dispatch strings", () => {
  const focus = 'hl.dsp.focus({ window = "address:0xaaa" })'
  const close = 'hl.dsp.window.close({ window = "address:0x1" })'
  const move = 'hl.dsp.window.move({ workspace = "3", follow = false, window = "address:0x1" })'
  const swap = 'hl.dsp.window.swap({ target = "address:0x1" })'
  const reset = 'hl.dsp.submap("reset")'
  assert.strictEqual(Actions.focusCmd("AAA"), focus)
  assert.strictEqual(Actions.closeCmd("0x1"), close)
  assert.strictEqual(Actions.moveCmd("0x1", 3), move)
  assert.strictEqual(Actions.swapCmd("0x1"), swap)
  assert.strictEqual(Actions.submapCmd("reset"), reset)
  const plan = Actions.commit("focus", { address: "0x1" }, 0)
  assert.strictEqual(plan.kind, "focus")
  assert.strictEqual(plan.dispatch, 'hl.dsp.focus({ window = "address:0x1" })')
  same(Actions.dispatchArgv(focus), ["hyprctl", "dispatch", focus])
  same(Actions.dispatchArgv(reset), ["hyprctl", "dispatch", reset])
  assert.strictEqual(Actions.dispatchArgv(focus).length, 3)
  same(Actions.dispatchArgv(""), [])
  assert.strictEqual(
    Actions.batch([Actions.focusCmd("0x1"), Actions.submapCmd("reset")]),
    'dispatch hl.dsp.focus({ window = "address:0x1" }) ; dispatch hl.dsp.submap("reset")'
  )
})

test("events: socket2 parse + unknown skipped", () => {
  const evs = Events.parseStream(fixture("socket2-activewindowv2.txt"))
  assert.strictEqual(evs[0].mru, true)
  assert.strictEqual(evs[0].fields.address, "0x64cea2525760")
  assert.strictEqual(evs[1].kind, "openwindow")
  const unk = evs.filter((e) => e.kind === "unknown")
  assert.ok(unk.length >= 1)
})

test("config: inline settings ignore alphabet; fixed home-row", () => {
  Config.apply({ alphabet: "asx", inset: 12, inputPath: "overlay", maxHints: 99 })
  const snap = Config.snapshot()
  assert.strictEqual(snap.alphabet, "asdfghjkl")
  assert.strictEqual(snap.inset, 12)
  assert.strictEqual(snap.inputPath, "overlay")
  assert.strictEqual(snap.maxHints, 25)
})

test("allocator: extra windows become overflow, never empty chords", () => {
  HintEngine.resetSession()
  const assignment = HintEngine.assignSession(manyWindows(90), "as", [], 100)
  const chords = Object.values(assignment.chords)
  assert.ok(chords.length > 0)
  chords.forEach((c) => assert.ok(c && c.length >= 1))
  assert.ok(assignment.overflow > 0)
  assignment.hinted.forEach((w) => {
    assert.ok(assignment.chords[HintEngine.normalizeAddress(w.address)])
  })
})

test("clients: mergeToplevels does not clobber real geometry with zeros", () => {
  const existing = [{
    address: "0xaaa1",
    at: [40, 80],
    size: [800, 600],
    title: "old",
    monitor: 0
  }]
  const tops = [{
    address: "0xaaa1",
    at: [0, 0],
    size: [0, 0],
    title: "new-title",
    monitor: 0
  }]
  const merged = Clients.mergeToplevels(existing, tops)
  assert.strictEqual(merged.length, 1)
  assert.strictEqual(merged[0].title, "new-title")
  same(merged[0].at, [40, 80])
  same(merged[0].size, [800, 600])
})

test("session: shared snapshot mutates", () => {
  Session.setOpened(true)
  Session.setLabels([{ address: "0x1", chord: "a" }], 3)
  const snap = Session.snapshot()
  assert.strictEqual(snap.opened, true)
  assert.strictEqual(snap.overflow, 3)
  assert.strictEqual(snap.moreNote, "+3 more")
})

test("matchPrefix: typed letters split exact/partial/rest", () => {
  const labels = [
    { chord: "a" },
    { chord: "sa" },
    { chord: "sd" },
    { chord: "f" }
  ]
  const m = HintEngine.matchPrefix(labels, "s")
  assert.strictEqual(m.partial.length, 2)
  assert.strictEqual(m.exact.length, 0)
  assert.strictEqual(m.rest.length, 2)
})

test("binds: empty live list offers SUPER+H and never Super+F", () => {
  const p = Binds.plan([])
  assert.strictEqual(p.needed, true)
  assert.strictEqual(p.canInstall, true)
  assert.strictEqual(p.toAdd.length, 1)
  assert.strictEqual(p.chosen, "SUPER + H")
  assert.ok(p.note.indexOf("SUPER + H") >= 0)
  const lua = Binds.luaBlock(p.toAdd)
  assert.ok(lua.indexOf('hl.bind("SUPER + H"') >= 0)
  assert.ok(lua.indexOf('hl.bind("SUPER + F"') < 0)
  assert.ok(lua.indexOf("hl.unbind") < 0)
})

test("binds: Super+F fullscreen is skipped, Super+H is used", () => {
  const live = jsonFix("binds-super-f.json")
  const p = Binds.plan(live)
  assert.strictEqual(p.needed, true)
  assert.strictEqual(p.chosen, "SUPER + H")
  assert.strictEqual(Binds.isForbiddenSuperF("SUPER + F"), true)
  assert.strictEqual(Binds.isForbiddenSuperF("SUPER+F"), true)
  assert.strictEqual(Binds.isForbiddenSuperF("SUPER + ALT + F"), false)
  assert.strictEqual(Binds.luaBlock("SUPER + F"), "")
  assert.strictEqual(Binds.luaBlock("SUPER+F"), "")
})

test("binds: occupied Super+H uses semicolon; then Super+Alt+F", () => {
  const hTaken = [{ modmask: 64, key: "H", dispatcher: "exec", arg: "other", description: "Voxtype" }]
  const p = Binds.plan(hTaken)
  assert.strictEqual(p.chosen, "SUPER + semicolon")
  assert.ok(p.note.indexOf("SUPER + semicolon") >= 0)
  assert.ok(p.note.indexOf("SUPER + H") >= 0)
  const both = hTaken.concat([{ modmask: 64, key: "semicolon", dispatcher: "exec", arg: "menu" }])
  const p2 = Binds.plan(both)
  assert.strictEqual(p2.chosen, "SUPER + ALT + F")
  const lua = Binds.luaBlock(p2.toAdd)
  assert.ok(lua.indexOf('hl.bind("SUPER + ALT + F"') >= 0)
  assert.ok(lua.indexOf('hl.bind("SUPER + F"') < 0)
})

test("binds: every alternate taken lists conflicts and does not install", () => {
  const live = [
    { modmask: 64, key: "H", dispatcher: "exec", arg: "a", description: "Voxtype" },
    { modmask: 64, key: "semicolon", dispatcher: "exec", arg: "b", description: "menu" },
    { modmask: 72, key: "F", dispatcher: "fullscreen", arg: "0", description: "Alt fullscreen" }
  ]
  const p = Binds.plan(live)
  assert.strictEqual(p.needed, true)
  assert.strictEqual(p.canInstall, false)
  assert.strictEqual(p.toAdd.length, 0)
  assert.ok(p.note.indexOf("SUPER + H") >= 0)
  assert.ok(p.note.indexOf("SUPER + semicolon") >= 0)
  assert.ok(p.note.indexOf("SUPER + ALT + F") >= 0)
  assert.strictEqual(Binds.luaBlock(p.toAdd), "")
})

test("binds: plugin id, description, or hints submap hides the offer", () => {
  const byArg = [{ modmask: 64, key: "H", dispatcher: "exec", arg: "omarchy-shell shell toggle io.github.chris.window-hints '{}'" }]
  assert.strictEqual(Binds.plan(byArg).needed, false)
  const byDesc = [{ modmask: 64, key: "H", dispatcher: "__lua", arg: "15", description: "Window hints" }]
  assert.strictEqual(Binds.plan(byDesc).needed, false)
  const bySubmap = [{ modmask: 0, key: "a", dispatcher: "exec", arg: "omarchy-shell window-hints key a", submap: "hints" }]
  assert.strictEqual(Binds.plan(bySubmap).needed, false)
  const byDispatch = [{ modmask: 64, key: "H", dispatcher: "submap", arg: "hints" }]
  assert.strictEqual(Binds.plan(byDispatch).needed, false)
})

test("binds: lua block is the hints submap, chords go to window-hints, no unbind", () => {
  const lua = Binds.luaBlock("SUPER + H")
  assert.ok(lua.indexOf('hl.define_submap("hints"') >= 0)
  assert.ok(lua.indexOf("omarchy-shell shell toggle io.github.chris.window-hints '{}'") >= 0)
  assert.ok(lua.indexOf("omarchy-shell window-hints key a") >= 0)
  assert.ok(lua.indexOf("omarchy-shell window-hints key A") >= 0)
  assert.ok(lua.indexOf("omarchy-shell window-hints key x") >= 0)
  assert.ok(lua.indexOf("omarchy-shell window-hints key 3") >= 0)
  assert.ok(lua.indexOf("omarchy-shell window-hints key escape") >= 0)
  assert.ok(lua.indexOf("catchall") >= 0)
  assert.ok(lua.indexOf('hl.dsp.submap("reset")') >= 0)
  assert.ok(lua.indexOf("shell call") < 0)
  assert.ok(lua.indexOf("hl.unbind") < 0)
  assert.ok(lua.indexOf('hl.unbind("SUPER + F"') < 0)
  assert.ok(lua.indexOf('hl.bind("SUPER + F"') < 0)
})

if (failed) {
  process.stderr.write("\n" + failed + " failed, " + passed + " passed\n")
  process.exit(1)
}
process.stdout.write("\n" + passed + " passed\n")

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "js/Config.js" as Config
import "js/Clients.js" as Clients
import "js/Events.js" as Events
import "js/HintEngine.js" as HintEngine
import "js/Geometry.js" as Geometry
import "js/Input.js" as Input
import "js/Actions.js" as Actions
import "js/Swap.js" as Swap
import "js/Session.js" as Session

Item {
  id: root

  readonly property string moduleName: "io.github.chris.window-hints"
  readonly property string pluginId: "io.github.chris.window-hints"

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var settings: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  property string alphabet: Config.DEFAULTS.alphabet
  property int inset: Config.DEFAULTS.inset
  property int maxHints: Config.DEFAULTS.maxHints
  property int watchdogMs: Config.DEFAULTS.watchdogMs
  property int armMs: Config.DEFAULTS.armMs
  property string inputPath: Config.DEFAULTS.inputPath
  property string suggestedBind: Config.DEFAULTS.suggestedBind

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0)
      u = u.slice(7)
    if (u.length > 1 && u.charAt(u.length - 1) === "/")
      u = u.slice(0, u.length - 1)
    return u
  }
  readonly property string helperBin: pluginDir + "/bin/hints-ctl"
  readonly property string helperSh: pluginDir + "/compat/hints-ctl.sh"

  property bool helperIsBinary: false
  property bool helperReady: false
  property bool hyprlandEventsLive: false
  property bool socketWanted: true
  property int socketBackoffMs: 250
  property bool swapCapable: false
  property bool swapProbed: false
  property bool firstRunShown: false
  property bool bindCollision: false
  property bool hinting: false
  property bool overlayExclusive: false
  property string lastStatus: "starting"
  property string lastError: ""
  property string lastActiveAddress: ""
  property var clients: []
  property var monitors: []
  property var mru: []
  property var inputState: Input.create()
  property var frozenLabels: []
  property var workQueue: []
  property var workCurrent: null
  property int sessionRevision: 0

  function helperCommand() {
    return root.helperIsBinary ? root.helperBin : root.helperSh
  }

  function applySettingsObject(obj) {
    if (!obj || typeof obj !== "object")
      return
    Config.apply(obj)
    root.alphabet = Config.alphabet
    root.inset = Config.inset
    root.maxHints = Config.maxHints
    root.watchdogMs = Config.watchdogMs
    root.armMs = Config.armMs
    root.inputPath = Config.inputPath
    root.suggestedBind = Config.suggestedBind
    root.overlayExclusive = root.inputPath === "overlay"
    Session.setInputPath(root.inputPath)
  }

  function ingestHostSettings() {
    var bag = {}
    if (root.settings && typeof root.settings === "object") {
      for (var k in root.settings) {
        if (root.settings.hasOwnProperty(k))
          bag[k] = root.settings[k]
      }
    }
    var keys = ["alphabet", "inset", "maxHints", "watchdogMs", "armMs", "inputPath", "suggestedBind"]
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (root[key] !== undefined && root[key] !== null)
        bag[key] = root[key]
    }
    root.applySettingsObject(bag)
  }

  function publish() {
    root.sessionRevision = Session.snapshot().revision
  }

  function toast(message, ms) {
    Session.setToast(message, Date.now() + (ms || 1200))
    toastTimer.interval = ms || 1200
    toastTimer.restart()
    root.publish()
  }

  function findFocused() {
    if (root.lastActiveAddress)
      return Swap.findByAddress(root.clients, root.lastActiveAddress)
    if (root.mru.length)
      return Swap.findByAddress(root.clients, root.mru[0])
    return null
  }

  function rememberMru(address) {
    var addr = Clients.normalizeAddress(address)
    if (!addr)
      return
    root.lastActiveAddress = addr
    var next = [addr]
    for (var i = 0; i < root.mru.length; i++) {
      if (root.mru[i] !== addr)
        next.push(root.mru[i])
    }
    if (next.length > 80)
      next = next.slice(0, 80)
    root.mru = next
  }

  function decorateLabels(frozen) {
    var broken = 0
    var groups = {}
    var decorated = []
    var i
    for (i = 0; i < frozen.length; i++) {
      var label = frozen[i]
      var mon = HintEngine.findMonitor(root.monitors, label)
      var out = mon ? Geometry.globalToOutput(label.at, label.size, mon) : { x: 0, y: 0, w: 0, h: 0 }
      if (!mon || Geometry.looksBroken(out, mon))
        broken++
      var key = mon ? String(mon.name || mon.id) : "?"
      if (!groups[key])
        groups[key] = []
      groups[key].push({ label: label, mon: mon, out: out })
    }
    var gutter = broken > frozen.length / 2 && frozen.length > 0
    Session.setGutter(gutter)
    for (var g in groups) {
      if (!groups.hasOwnProperty(g))
        continue
      var pack = groups[g]
      var prelim = []
      var rows = []
      for (i = 0; i < pack.length; i++) {
        var item = pack[i]
        var stack = 0
        var px = Math.round((item.out.x || 0) / 12)
        var py = Math.round((item.out.y || 0) / 12)
        for (var j = 0; j < i; j++) {
          var other = pack[j]
          if (Math.round((other.out.x || 0) / 12) === px && Math.round((other.out.y || 0) / 12) === py)
            stack++
        }
        var anchor = item.mon
          ? Geometry.labelAnchor(item.out, item.mon, root.inset, Config.pillWidth, Config.pillHeight, stack)
          : { x: 8, y: 8 + i * 32, w: Config.pillWidth, h: Config.pillHeight }
        if (gutter) {
          anchor = {
            x: 8,
            y: 8 + i * (Config.pillHeight + Config.stackGap),
            w: Config.pillWidth,
            h: Config.pillHeight
          }
        }
        prelim.push(anchor)
        rows.push(item)
      }
      var stacked = Geometry.stackOffsets(prelim)
      for (i = 0; i < rows.length; i++) {
        var row = rows[i].label
        var mon = rows[i].mon
        decorated.push({
          address: row.address,
          chord: row.chord,
          className: row.className,
          title: row.title,
          at: row.at,
          size: row.size,
          workspace: row.workspace,
          monitor: row.monitor,
          monitorName: mon ? mon.name : row.monitorName,
          floating: row.floating,
          fullscreen: row.fullscreen,
          x: stacked[i].x,
          y: stacked[i].y,
          w: stacked[i].w,
          h: stacked[i].h,
          gutter: gutter
        })
      }
    }
    return decorated
  }

  function snapshotVisible() {
    return HintEngine.visibleClients(root.clients, root.monitors)
  }

  function beginHint(payloadJson) {
    try {
      if (payloadJson && String(payloadJson).length && String(payloadJson) !== "{}")
        root.applySettingsObject(JSON.parse(payloadJson))
    } catch (e) {
    }
    root.ingestHostSettings()
    if (root.hinting) {
      root.endHint("toggle")
      return "hidden"
    }
    var visible = root.snapshotVisible()
    var assignment = HintEngine.assignSession(visible, root.alphabet, root.mru, root.maxHints)
    var frozen = HintEngine.freezeInvocation(assignment, visible)
    var decorated = root.decorateLabels(frozen.labels)
    root.frozenLabels = decorated
    root.inputState = Input.begin(root.inputState)
    root.hinting = true
    Session.setOpened(true)
    Session.setLabels(decorated, frozen.overflow)
    Session.setPrefix("")
    Session.setVerb("focus", 0)
    Session.setArmed("")
    Session.setPaintedAt(Date.now())
    Session.setFirstRun(!root.firstRunShown, root.bindCollision, root.suggestedBind, Config.alternateBinds)
    Session.setSwap(root.swapCapable)
    Session.setError("")
    root.activateSubmap()
    watchdogTimer.interval = root.watchdogMs
    watchdogTimer.restart()
    root.lastStatus = "hinting"
    root.publish()
    if (!visible.length)
      root.toast("no visible windows", 1400)
    return "ok"
  }

  function endHint(reason) {
    var was = root.hinting
    root.hinting = false
    Input.reset(root.inputState)
    root.resetSubmap()
    watchdogTimer.stop()
    armTimer.stop()
    Session.resetView()
    root.frozenLabels = []
    root.lastStatus = reason || "idle"
    root.publish()
    return was ? "hidden" : "idle"
  }

  function toggleHint(payloadJson) {
    if (root.hinting)
      return root.endHint("toggle")
    return root.beginHint(payloadJson || "{}")
  }

  function syncLiveLabels() {
    if (!root.hinting)
      return
    var visible = root.snapshotVisible()
    var live = []
    for (var i = 0; i < visible.length; i++)
      live.push(visible[i].address)
    var kept = HintEngine.dropVanished(root.frozenLabels, live)
    if (kept.length !== root.frozenLabels.length) {
      root.frozenLabels = kept
      Session.setLabels(kept, Session.snapshot().overflow)
      root.publish()
    }
  }

  function commitAction(verb, target, moveTo) {
    if (!target || !target.address) {
      root.toast("window vanished")
      root.endHint("vanished")
      return "vanished"
    }
    var still = Swap.findByAddress(root.clients, target.address)
    if (!still) {
      root.toast("window vanished")
      root.endHint("vanished")
      return "vanished"
    }
    if (verb === "swap") {
      var check = Swap.canSwap(root.findFocused(), still, root.swapCapable)
      if (!check.ok) {
        if (check.reason === "cross-workspace")
          root.toast("swap is same-workspace only")
        else if (check.reason === "greyed")
          root.toast("swap unavailable")
        else
          root.toast("cannot swap")
        Session.setPrefix("")
        Session.setVerb("focus", 0)
        Input.begin(root.inputState)
        root.publish()
        return check.reason
      }
    }
    var plan = Actions.commit(verb, still, moveTo)
    root.endHint("commit")
    if (!plan)
      return "empty"
    root.dispatchHypr(plan.dispatch)
    return plan.kind
  }

  function onKey(raw) {
    if (!root.hinting)
      return "idle"
    watchdogTimer.restart()
    var result = Input.handleKey(root.inputState, raw, root.frozenLabels, Date.now(), root.armMs)
    if (result.action === "dismiss") {
      root.firstRunShown = true
      Session.setFirstRun(false, root.bindCollision, root.suggestedBind, Config.alternateBinds)
      return root.endHint("escape")
    }
    if (result.action === "abort-arm") {
      Session.setArmed("")
      Session.setPrefix("")
      Session.setVerb("focus", 0)
      root.publish()
      return "abort-arm"
    }
    if (result.action === "verb") {
      Session.setVerb(result.verb, result.moveTo || 0)
      Session.setPrefix("")
      root.publish()
      return result.verb
    }
    if (result.action === "prefix") {
      Session.setPrefix(root.inputState.prefix)
      Session.setVerb(root.inputState.verb, root.inputState.moveTo)
      root.publish()
      return "prefix"
    }
    if (result.action === "miss") {
      Session.setPrefix("")
      Session.setVerb(root.inputState.verb, 0)
      root.publish()
      return "miss"
    }
    if (result.action === "arm") {
      Session.setArmed(result.target.address)
      Session.setPrefix(root.inputState.prefix)
      Session.setVerb("close", 0)
      armTimer.interval = root.armMs
      armTimer.restart()
      root.publish()
      return "arm"
    }
    if (result.action === "commit")
      return root.commitAction(result.verb, result.target, result.moveTo)
    return "none"
  }

  function dispatchHypr(request) {
    if (!request)
      return false
    try {
      Hyprland.dispatch(request)
      return true
    } catch (e) {
      root.enqueueWork(["hyprctl", "dispatch"].concat(String(request).split(" ")), function (text, ok) {
        if (!ok)
          root.toast("hyprctl failed")
      })
      return true
    }
  }

  function activateSubmap() {
    if (root.overlayExclusive) {
      Session.setSubmap(false)
      return
    }
    root.dispatchHypr(Actions.submapCmd("hints"))
    Session.setSubmap(true)
  }

  function resetSubmap() {
    root.dispatchHypr(Actions.submapCmd("reset"))
    Session.setSubmap(false)
  }

  function enqueueWork(command, done) {
    workQueue.push({ command: command, done: done || null })
    root.runWork()
  }

  function runWork() {
    if (workProc.running || root.workCurrent)
      return
    if (!workQueue.length)
      return
    root.workCurrent = workQueue.shift()
    workProc.command = root.workCurrent.command
    workTimeout.restart()
    workProc.running = true
  }

  function requestSnapshot(reason) {
    root.enqueueWork(["hyprctl", "-j", "clients"], function (text) {
      root.onClientsJson(text)
      root.enqueueWork(["hyprctl", "-j", "monitors"], function (monText) {
        root.onMonitorsJson(monText)
        if (root.hinting)
          root.syncLiveLabels()
        root.lastStatus = reason || root.lastStatus
      })
    })
  }

  function collectFromModule() {
    var tops = null
    try {
      tops = Clients.fromToplevels(Hyprland.toplevels)
    } catch (e) {
      tops = null
    }
    if (tops && tops.length)
      root.clients = tops
  }

  function onClientsJson(text) {
    var parsed = Clients.parseClients(text)
    if (parsed)
      root.clients = parsed
  }

  function onMonitorsJson(text) {
    var parsed = Clients.parseMonitors(text)
    if (parsed)
      root.monitors = parsed
  }

  function handleLine(line) {
    var ev = Events.parseLine(line)
    if (!ev)
      return
    if (ev.mru && ev.fields.address)
      root.rememberMru(ev.fields.address)
    if (ev.refreshModel) {
      if (ev.kind === "closewindow" && ev.fields.address && root.hinting) {
        var live = []
        for (var i = 0; i < root.frozenLabels.length; i++) {
          if (root.frozenLabels[i].address !== ev.fields.address)
            live.push(root.frozenLabels[i])
        }
        root.frozenLabels = live
        Session.setLabels(live, Session.snapshot().overflow)
        root.publish()
      }
      root.requestSnapshot(ev.kind)
    }
  }

  function summonOverlay(payload) {
    var body = payload || "{}"
    root.beginHint(body)
    if (shell && typeof shell.summon === "function") {
      shell.summon(root.pluginId, body)
      return "ok"
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.pluginId, body])
    return "ok"
  }

  function hideOverlay() {
    root.endHint("hide")
    if (shell && typeof shell.hide === "function") {
      shell.hide(root.pluginId)
      return "hidden"
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "hide", root.pluginId])
    return "hidden"
  }

  function statusJson() {
    var snap = Session.snapshot()
    return JSON.stringify({
      ok: true,
      hinting: root.hinting,
      clients: root.clients.length,
      monitors: root.monitors.length,
      labels: snap.labels.length,
      overflow: snap.overflow,
      swapCapable: root.swapCapable,
      helper: root.helperIsBinary ? "binary" : "compat",
      inputPath: root.inputPath,
      bindCollision: root.bindCollision,
      status: root.lastStatus,
      error: root.lastError
    })
  }

  function probeSwap() {
    root.enqueueWork([root.helperCommand(), "swap-probe"], function (text) {
      var result = Swap.parseSwapProbe(text)
      root.swapCapable = !!result.capable
      root.swapProbed = true
      Session.setSwap(root.swapCapable)
      root.publish()
    })
  }

  function checkBinds() {
    root.enqueueWork([root.helperCommand(), "binds-check", "SUPER", "F"], function (text) {
      try {
        var data = JSON.parse(String(text || "{}"))
        root.bindCollision = !!data.collision
        if (data.suggested)
          root.suggestedBind = String(data.suggested)
      } catch (e) {
        root.bindCollision = false
      }
    })
  }

  function installSubmap() {
    root.enqueueWork([root.helperCommand(), "submap", "install"], null)
  }

  Process {
    id: workProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        workTimeout.stop()
        var job = root.workCurrent
        root.workCurrent = null
        workProc.running = false
        if (job && job.done) {
          try {
            job.done(String(text || ""), true)
          } catch (e) {
            root.lastError = String(e)
          }
        }
        root.runWork()
      }
    }
    onExited: function (code) {
      workTimeout.stop()
      if (code !== 0 && root.workCurrent && root.workCurrent.done) {
        var job = root.workCurrent
        root.workCurrent = null
        try {
          job.done("", false)
        } catch (e) {
        }
      } else if (code !== 0) {
        root.workCurrent = null
      }
      if (!workProc.running)
        root.runWork()
    }
  }

  Timer {
    id: workTimeout
    interval: 800
    repeat: false
    onTriggered: {
      if (workProc.running) {
        workProc.running = false
        var job = root.workCurrent
        root.workCurrent = null
        root.lastError = "hyprctl timed out"
        root.toast("hyprctl timed out")
        if (root.hinting)
          root.endHint("timeout")
        if (job && job.done) {
          try { job.done("", false) } catch (e) {}
        }
        root.runWork()
      }
    }
  }

  Process {
    id: helperWhichProc
    command: ["sh", "-c", "test -x \"$1\" && echo binary || echo missing", "sh", root.helperBin]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        root.helperIsBinary = out === "binary"
        root.helperReady = true
        root.installSubmap()
        root.probeSwap()
        root.checkBinds()
        root.requestSnapshot("boot")
      }
    }
  }

  Socket {
    id: eventSock
    path: {
      try {
        if (Hyprland.eventSocketPath)
          return Hyprland.eventSocketPath
      } catch (e) {
      }
      var runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
      var sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
      if (!sig)
        return ""
      return runtime + "/hypr/" + sig + "/.socket2.sock"
    }
    connected: false
    onConnectedChanged: {
      if (connected) {
        root.socketBackoffMs = 250
        root.lastStatus = "socket-connected"
        reconnectTimer.stop()
      } else if (root.socketWanted && !root.hyprlandEventsLive) {
        reconnectTimer.interval = root.socketBackoffMs
        reconnectTimer.start()
      }
    }
    onError: {
      if (!root.hyprlandEventsLive) {
        reconnectTimer.interval = root.socketBackoffMs
        reconnectTimer.start()
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event)
        return
      root.hyprlandEventsLive = true
      if (eventSock.connected)
        eventSock.connected = false
      var line = String(event.name || "") + ">>" + String(event.data || "")
      root.handleLine(line)
    }
  }

  Timer {
    id: socketFallbackTimer
    interval: 2000
    repeat: false
    running: true
    onTriggered: {
      if (!root.hyprlandEventsLive && eventSock.path && eventSock.path.length)
        eventSock.connected = true
    }
  }

  Timer {
    id: reconnectTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (!root.hyprlandEventsLive && root.socketWanted) {
        root.socketBackoffMs = Math.min(root.socketBackoffMs * 2, 4000)
        eventSock.connected = true
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.hinting ? 400 : 1200
    repeat: true
    running: true
    onTriggered: {
      root.collectFromModule()
      if (!root.hyprlandEventsLive)
        root.requestSnapshot("poll")
      else if (root.hinting)
        root.syncLiveLabels()
    }
  }

  Timer {
    id: watchdogTimer
    interval: 15000
    repeat: false
    onTriggered: {
      if (root.hinting) {
        root.toast("hints timed out")
        root.endHint("watchdog")
      } else {
        root.resetSubmap()
      }
    }
  }

  Timer {
    id: armTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (!root.hinting)
        return
      if (root.inputState.state !== "armed")
        return
      var target = Swap.findByAddress(root.frozenLabels, root.inputState.armedAddress)
      root.commitAction("close", target, 0)
    }
  }

  Timer {
    id: toastTimer
    interval: 1200
    repeat: false
    onTriggered: {
      Session.setToast("", 0)
      root.publish()
    }
  }

  IpcHandler {
    target: "io.github.chris.window-hints"

    function key(k: string): string { return root.onKey(k) }
    function summon(): string { return root.summonOverlay("{}") }
    function toggle(): string { return root.toggleHint("{}") }
    function hide(): string { return root.hideOverlay() }
    function dismiss(): string { return root.endHint("dismiss") }
    function end(reason: string): string { return root.endHint(reason || "end") }
    function ping(): string { return "ok" }
    function status(): string { return root.statusJson() }
    function begin(payload: string): string { return root.beginHint(payload) }
    function markFirstRun(): string {
      root.firstRunShown = true
      Session.setFirstRun(false, root.bindCollision, root.suggestedBind, Config.alternateBinds)
      root.publish()
      return "ok"
    }
  }

  function open(payloadJson) { return root.beginHint(payloadJson || "{}") }
  function close() { return root.endHint("close") }

  Component.onCompleted: {
    Config.reset()
    root.ingestHostSettings()
    helperWhichProc.running = true
    root.collectFromModule()
    root.publish()
  }
}

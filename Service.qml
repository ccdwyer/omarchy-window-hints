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
import "js/Binds.js" as Binds

Item {
  id: root

  readonly property string moduleName: "io.github.chris.window-hints"
  readonly property string pluginId: "io.github.chris.window-hints"

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var settings: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  readonly property string alphabet: Config.ALPHABET
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
  readonly property string installBindsPy: pluginDir + "/compat/install-binds.py"

  property bool helperIsBinary: false
  property bool helperReady: false
  property bool hyprlandEventsLive: false
  property bool swapCapable: false
  property bool swapProbed: false
  property bool firstRunShown: false
  property bool bindCollision: false
  property bool hinting: false
  property bool overlayExclusive: false
  property bool submapInstalled: false
  property bool submapInstallTried: false
  property bool submapActivated: false
  property bool installInFlight: false
  property bool pendingActivate: false
  property string installedAlphabet: ""
  property string bindingsWarning: ""
  property bool bindOfferNeeded: false
  property bool bindOfferCanInstall: false
  property string bindOfferNote: ""
  property string lastStatus: "starting"
  property string lastError: ""
  property string lastActiveAddress: ""
  property var clients: []
  property var monitors: []
  property var mru: []
  property var frozenLabels: []
  property var workQueue: []
  property var workCurrent: null
  property int sessionRevision: 0
  property bool clientsReady: false
  property bool monitorsReady: false
  property bool frozenOnUnreadyModel: false
  property bool tearingDown: false
  property bool socketWanted: true
  property int socketBackoffMs: 250
  property string workStdout: ""
  property bool workFinalized: false

  function helperCommand() {
    return root.helperIsBinary ? root.helperBin : root.helperSh
  }

  function applySettingsObject(obj) {
    if (!obj || typeof obj !== "object")
      return
    Config.apply(obj)
    root.inset = Config.inset
    root.maxHints = Config.maxHints
    root.watchdogMs = Config.watchdogMs
    root.armMs = Config.armMs
    root.inputPath = Config.inputPath
    root.suggestedBind = Config.suggestedBind
    if (root.hinting)
      Session.setInputPath(root.effectiveInputPath())
    else
      Session.setInputPath(root.inputPath)
    root.overlayExclusive = root.hinting && root.effectiveInputPath() === "overlay"
  }

  function effectiveInputPath() {
    if (root.inputPath === "overlay")
      return "overlay"
    if (root.submapInstalled && !root.installInFlight)
      return "submap"
    return "overlay"
  }

  function currentItemProps() {
    return {
      inset: root.inset,
      maxHints: root.maxHints,
      watchdogMs: root.watchdogMs,
      armMs: root.armMs,
      inputPath: root.inputPath,
      suggestedBind: root.suggestedBind
    }
  }

  function ingestHostSettings(payload) {
    var bag = Config.resolveSettings(root.currentItemProps(), root.settings, payload || null)
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

  function modelReady() {
    return root.clientsReady && root.monitorsReady
  }

  function paintFrozenLabels() {
    var visible = root.snapshotVisible()
    var assignment = HintEngine.assignSession(visible, root.alphabet, root.mru, root.maxHints)
    var frozen = HintEngine.freezeInvocation(assignment, visible)
    var decorated = root.decorateLabels(frozen.labels)
    root.frozenLabels = decorated
    Session.setLabels(decorated, frozen.overflow)
    Session.setPaintedAt(Date.now())
    if (!visible.length)
      root.toast("no visible windows", 1400)
  }

  function rebuildHintSession() {
    if (!root.hinting || !root.frozenOnUnreadyModel)
      return
    if (!root.modelReady())
      return
    root.frozenOnUnreadyModel = false
    root.paintFrozenLabels()
    Session.setSwap(root.swapCapable)
    Session.setBindingsWarning(root.bindingsWarning)
    Session.setSubmapInstalled(root.submapInstalled)
    root.publish()
  }

  function beginHint(payloadJson) {
    var payload = null
    try {
      if (payloadJson && String(payloadJson).length && String(payloadJson) !== "{}")
        payload = JSON.parse(payloadJson)
    } catch (e) {
      payload = null
    }
    root.ingestHostSettings(payload)
    root.scanBinds()
    if (root.hinting) {
      if (root.frozenOnUnreadyModel)
        root.requestSnapshot("begin-retry")
      return "ok"
    }
    Input.begin(Session.input())
    root.hinting = true
    Session.setHinting(true)
    Session.setOpened(true)
    Session.setPrefix("")
    Session.setVerb("focus", 0)
    Session.setArmed("")
    Session.setFirstRun(!root.firstRunShown, root.bindCollision, root.suggestedBind, Config.alternateBinds)
    Session.setSwap(root.swapCapable)
    Session.setError("")
    Session.setBindingsWarning(root.bindingsWarning)
    Session.setSubmapInstalled(root.submapInstalled)
    root.activateSubmap()
    watchdogTimer.interval = root.watchdogMs
    watchdogTimer.restart()
    root.lastStatus = "hinting"
    if (!root.modelReady()) {
      root.frozenOnUnreadyModel = true
      root.frozenLabels = []
      Session.setLabels([], 0)
      Session.setPaintedAt(Date.now())
      root.requestSnapshot("begin-wait")
      root.publish()
      return "ok"
    }
    root.frozenOnUnreadyModel = false
    root.paintFrozenLabels()
    root.publish()
    return "ok"
  }

  function endHint(reason) {
    var was = root.hinting
    root.hinting = false
    root.frozenOnUnreadyModel = false
    Session.setHinting(false)
    Input.reset(Session.input())
    root.resetSubmap()
    root.overlayExclusive = false
    Session.setInputPath(root.inputPath)
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
    if (root.frozenOnUnreadyModel) {
      root.rebuildHintSession()
      return
    }
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
        Input.begin(Session.input())
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
    var result = Input.handleKey(Session.input(), raw, root.frozenLabels.length ? root.frozenLabels : Session.snapshot().labels, Date.now(), root.armMs)
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
      Session.setPrefix(Session.input().prefix)
      Session.setVerb(Session.input().verb, Session.input().moveTo)
      root.publish()
      return "prefix"
    }
    if (result.action === "miss") {
      Session.setPrefix("")
      Session.setVerb(Session.input().verb, 0)
      root.publish()
      return "miss"
    }
    if (result.action === "arm") {
      Session.setArmed(result.target.address)
      Session.setPrefix(Session.input().prefix)
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
    if (!request || root.tearingDown)
      return false
    var argv = Actions.dispatchArgv(request)
    if (!argv.length)
      return false
    root.enqueueWork(argv, function (text, ok) {
      if (!ok) {
        root.lastError = "hyprctl failed"
        root.toast("hyprctl failed")
      }
    })
    return true
  }

  function dispatchHyprImmediate(request) {
    if (!request)
      return
    var argv = Actions.dispatchArgv(request)
    try {
      Hyprland.dispatch(request)
    } catch (e) {
    }
    try {
      if (argv.length)
        Quickshell.execDetached(argv)
    } catch (e2) {
    }
  }

  function useOverlayInput(warnInstall) {
    root.overlayExclusive = true
    Session.setInputPath("overlay")
    Session.setSubmap(false)
    if (warnInstall) {
      root.bindingsWarning = "Use the bar chip: Set hotkey / Install hints submap. Overlay has exclusive keys until the submap exists. Stuck: hyprctl dispatch 'hl.dsp.submap(\"reset\")'"
      Session.setBindingsWarning(root.bindingsWarning)
    }
  }

  function activateSubmap() {
    if (root.tearingDown)
      return
    if (root.inputPath === "overlay") {
      root.useOverlayInput(false)
      root.pendingActivate = false
      return
    }
    if (root.installInFlight) {
      root.pendingActivate = true
      root.useOverlayInput(false)
      return
    }
    if (!root.submapInstalled) {
      root.pendingActivate = false
      root.useOverlayInput(true)
      return
    }
    root.overlayExclusive = false
    Session.setInputPath("submap")
    root.dispatchHypr(Actions.submapCmd("hints"))
    root.submapActivated = true
    root.pendingActivate = false
    Session.setSubmap(true)
    Session.setBindingsWarning(root.bindingsWarning)
  }

  function resetSubmap() {
    if (root.submapActivated) {
      if (root.tearingDown)
        root.dispatchHyprImmediate(Actions.submapCmd("reset"))
      else
        root.dispatchHypr(Actions.submapCmd("reset"))
      root.submapActivated = false
    }
    Session.setSubmap(false)
  }

  function teardown() {
    if (root.tearingDown)
      return
    root.tearingDown = true
    root.socketWanted = false
    try { eventSock.connected = false } catch (e) {}
    pollTimer.stop()
    watchdogTimer.stop()
    armTimer.stop()
    toastTimer.stop()
    workTimeout.stop()
    socketFallbackTimer.stop()
    reconnectTimer.stop()
    bindScanTimer.stop()
    root.workQueue = []
    root.workCurrent = null
    try { workProc.running = false } catch (e2) {}
    try { helperWhichProc.running = false } catch (e3) {}
    root.dispatchHyprImmediate(Actions.submapCmd("reset"))
    root.submapActivated = false
    root.hinting = false
    root.frozenOnUnreadyModel = false
    Session.setSubmap(false)
    Session.setHinting(false)
  }

  function enqueueWork(command, done) {
    if (root.tearingDown)
      return
    workQueue.push({ command: command, done: done || null })
    root.runWork()
  }

  function runWork() {
    if (root.tearingDown)
      return
    if (workProc.running || root.workCurrent)
      return
    if (!workQueue.length)
      return
    root.workCurrent = workQueue.shift()
    root.workStdout = ""
    root.workFinalized = false
    workProc.command = root.workCurrent.command
    workTimeout.restart()
    workProc.running = true
  }

  function finishWork(code, timedOut) {
    if (root.workFinalized)
      return
    root.workFinalized = true
    workTimeout.stop()
    var job = root.workCurrent
    root.workCurrent = null
    try { workProc.running = false } catch (e) {}
    var text = root.workStdout
    try {
      if ((!text || !text.length) && workProc.stdout && workProc.stdout.text !== undefined)
        text = String(workProc.stdout.text || "")
    } catch (e2) {}
    root.workStdout = ""
    var ok = !timedOut && code === 0
    if (timedOut) {
      root.lastError = "hyprctl timed out"
      root.toast("hyprctl timed out")
      if (root.hinting)
        root.endHint("timeout")
    }
    if (job && job.done) {
      try { job.done(text, ok) } catch (e3) { root.lastError = String(e3) }
    }
    if (!root.tearingDown)
      Qt.callLater(function () { root.runWork() })
  }

  function requestSnapshot(reason) {
    root.enqueueWork(["hyprctl", "-j", "clients"], function (text, ok) {
      if (ok && root.onClientsJson(text))
        root.clientsReady = true
      root.enqueueWork(["hyprctl", "-j", "monitors"], function (monText, monOk) {
        if (monOk && root.onMonitorsJson(monText))
          root.monitorsReady = true
        root.lastStatus = reason || root.lastStatus
        if (root.hinting && root.frozenOnUnreadyModel)
          root.rebuildHintSession()
        else if (root.hinting)
          root.syncLiveLabels()
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
      root.clients = Clients.mergeToplevels(root.clients, tops)
  }

  function onClientsJson(text) {
    var parsed = Clients.parseClients(text)
    if (!parsed || !parsed.ok)
      return false
    root.clients = parsed.clients
    return true
  }

  function onMonitorsJson(text) {
    var parsed = Clients.parseMonitors(text)
    if (!parsed || !parsed.ok)
      return false
    root.monitors = parsed.monitors
    return true
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
    if (!root.hinting)
      root.beginHint(body)
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.pluginId, body])
    return "ok"
  }

  function hideOverlay() {
    root.endHint("hide")
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
      inputPath: root.effectiveInputPath(),
      overlayExclusive: root.overlayExclusive,
      modelReady: root.modelReady(),
      submapInstalled: root.submapInstalled,
      bindingsWarning: root.bindingsWarning,
      bindCollision: root.bindCollision,
      bindOfferNeeded: root.bindOfferNeeded,
      bindOfferNote: root.bindOfferNote,
      status: root.lastStatus,
      error: root.lastError
    })
  }

  function applyBindPlan(plan) {
    var p = plan || Binds.offer
    root.bindOfferNeeded = !!p.needed
    root.bindOfferCanInstall = !!p.canInstall
    root.bindOfferNote = String(p.note || "")
    Binds.setOffer(p)
    Session.setBindOffer(root.bindOfferNeeded, root.bindOfferCanInstall, root.bindOfferNote)
    root.publish()
  }

  function scanBinds() {
    if (root.tearingDown)
      return
    root.enqueueWork(["hyprctl", "-j", "binds"], function (text, ok) {
      if (!ok)
        return
      var plan = Binds.applyScan(text)
      root.applyBindPlan(plan)
    })
  }

  function notifyNewBinds(plan) {
    var body = Binds.notifyBody(plan.toAdd, plan.skipped)
    if (!body)
      return
    Quickshell.execDetached(Binds.notifyArgv("Window Hints", "Window Hints keybindings", body))
  }

  function installBinds(arg) {
    if (String(arg || "") === "auto")
      return "refused"
    root.enqueueWork(["hyprctl", "-j", "binds"], function (text, ok) {
      if (!ok) {
        root.bindOfferNote = "could not read keybinds"
        root.bindOfferNeeded = true
        root.bindOfferCanInstall = false
        Session.setBindOffer(true, false, root.bindOfferNote)
        root.publish()
        return
      }
      var plan = Binds.applyScan(text)
      if (!plan.toAdd || !plan.toAdd.length) {
        root.applyBindPlan(plan)
        return
      }
      var lua = Binds.luaBlock(plan.toAdd)
      var keys = plan.chosen || Binds.pickKeys(plan.toAdd[0])
      if (!lua.length || lua.indexOf("hl.unbind") >= 0 || Binds.isForbiddenSuperF(keys)) {
        root.applyBindPlan(plan)
        return
      }
      root.enqueueWork(["python3", root.installBindsPy, root.pluginId, "--summon", keys], function (out, instOk) {
        var msg = String(out || "")
        if (!instOk) {
          if (msg.indexOf("XDG_RUNTIME_DIR") >= 0)
            root.bindOfferNote = "XDG_RUNTIME_DIR is unset; refusing to write via /tmp"
          else
            root.bindOfferNote = "could not write ~/.config/hypr/bindings.lua"
          root.bindOfferNeeded = true
          root.bindOfferCanInstall = true
          Session.setBindOffer(true, true, root.bindOfferNote)
          root.publish()
          return
        }
        root.notifyNewBinds(plan)
        Qt.callLater(root.scanBinds)
      })
    })
    return "ok"
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

  function checkBinds(done) {
    var bind = Config.parseBind(root.suggestedBind)
    root.enqueueWork([root.helperCommand(), "binds-check", bind.mods, bind.key], function (text, ok) {
      if (ok) {
        try {
          var data = JSON.parse(String(text || "{}"))
          var checked = bind.mods + "+" + (bind.key === "semicolon" ? ";" : bind.key)
          root.bindCollision = !!data.collision
          if (data.collision && data.suggested) {
            var alt = String(data.suggested)
            if (alt !== checked) {
              root.suggestedBind = alt
              root.bindCollision = false
            }
          }
        } catch (e) {
          root.bindCollision = false
        }
        Session.setFirstRun(!root.firstRunShown, root.bindCollision, root.suggestedBind, Config.alternateBinds)
        root.publish()
      }
      if (typeof done === "function")
        done()
    })
  }

  function installSubmap() {
    if (root.installInFlight || root.tearingDown)
      return
    root.installInFlight = true
    root.enqueueWork([root.helperCommand(), "submap", "install", root.suggestedBind], function (text, ok) {
      root.installInFlight = false
      var result = Config.parseInstall(ok ? text : "")
      root.submapInstallTried = true
      root.submapInstalled = !!result.installed
      if (root.submapInstalled) {
        root.installedAlphabet = Config.ALPHABET
        root.bindingsWarning = ""
      } else {
        root.bindingsWarning = "Use the bar chip: Set hotkey / Install hints submap. Overlay has exclusive keys until the submap exists. Stuck: hyprctl dispatch 'hl.dsp.submap(\"reset\")'"
      }
      Session.setSubmapInstalled(root.submapInstalled)
      Session.setBindingsWarning(root.bindingsWarning)
      if (root.pendingActivate || root.hinting)
        root.activateSubmap()
      root.publish()
    })
  }

  Process {
    id: workProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.workStdout = String(text || "")
      }
    }
    onExited: function (code) {
      root.finishWork(code, false)
    }
  }

  Timer {
    id: workTimeout
    interval: 800
    repeat: false
    onTriggered: {
      if (workProc.running || root.workCurrent) {
        try { workProc.running = false } catch (e) {}
        root.finishWork(-1, true)
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
        root.requestSnapshot("boot")
        root.scanBinds()
        root.checkBinds()
        root.probeSwap()
      }
    }
  }

  Socket {
    id: eventSock
    path: {
      try {
        if (Hyprland.eventSocketPath)
          return Hyprland.eventSocketPath
      } catch (e) {}
      var runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
      var sig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
      if (!sig)
        return ""
      return runtime + "/hypr/" + sig + "/.socket2.sock"
    }
    connected: false
    parser: SplitParser {
      onRead: function (line) {
        if (root.hyprlandEventsLive || root.tearingDown)
          return
        root.handleLine(line)
      }
    }
    onConnectedChanged: {
      if (connected) {
        root.socketBackoffMs = 250
        root.lastStatus = "socket-connected"
        reconnectTimer.stop()
      } else if (root.socketWanted && !root.hyprlandEventsLive && !root.tearingDown) {
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
      if (root.hyprlandEventsLive || root.tearingDown)
        return
      if (eventSock.path && eventSock.path.length > 0)
        eventSock.connected = root.socketWanted
    }
  }

  Timer {
    id: reconnectTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (root.tearingDown || root.hyprlandEventsLive)
        return
      root.socketBackoffMs = Math.min(root.socketBackoffMs * 2, 5000)
      eventSock.connected = false
      Qt.callLater(function () {
        if (!root.hyprlandEventsLive && root.socketWanted && !root.tearingDown)
          eventSock.connected = true
      })
    }
  }

  Timer {
    id: pollTimer
    interval: root.hinting ? 400 : 1200
    repeat: true
    running: true
    onTriggered: {
      if (root.tearingDown)
        return
      root.collectFromModule()
      var live = root.hyprlandEventsLive || eventSock.connected
      root.requestSnapshot(live ? "poll-geo" : "poll")
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
      if (Session.input().state !== "armed")
        return
      var target = Swap.findByAddress(root.frozenLabels, Session.input().armedAddress)
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

  function key(k) { return root.onKey(k) }
  function summon() { return root.summonOverlay("{}") }
  function toggle() { return root.toggleHint("{}") }
  function hide() { return root.hideOverlay() }
  function dismiss() { return root.endHint("dismiss") }
  function end(reason) { return root.endHint(reason || "end") }
  function ping() { return "ok" }
  function status(arg) { return root.statusJson() }
  function begin(payload) { return root.beginHint(payload) }
  function markFirstRun() {
    root.firstRunShown = true
    Session.setFirstRun(false, root.bindCollision, root.suggestedBind, Config.alternateBinds)
    root.publish()
    return "ok"
  }
  function open(payloadJson) { return root.beginHint(payloadJson || "{}") }
  function close() { return root.endHint("close") }

  IpcHandler {
    target: "window-hints"

    function key(k: string): string { return root.key(k) }
    function summon(): string { return root.summon() }
    function toggle(): string { return root.toggle() }
    function hide(): string { return root.hide() }
    function dismiss(): string { return root.dismiss() }
    function end(reason: string): string { return root.end(reason) }
    function ping(): string { return root.ping() }
    function status(arg: string): string { return root.status(arg) }
    function begin(payload: string): string { return root.begin(payload) }
    function markFirstRun(): string { return root.markFirstRun() }
    function installBinds(arg: string): string { return root.installBinds(arg) }
  }

  Timer {
    id: bindScanTimer
    interval: 3000
    repeat: true
    running: true
    onTriggered: {
      if (!root.tearingDown)
        root.scanBinds()
    }
  }

  Component.onCompleted: {
    Config.reset()
    root.ingestHostSettings(null)
    helperWhichProc.running = true
    root.collectFromModule()
    root.publish()
  }

  Component.onDestruction: root.teardown()
}

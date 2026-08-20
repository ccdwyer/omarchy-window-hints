import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "js/Session.js" as Session
import "js/Config.js" as Config
import "js/Input.js" as Input
import "js/Actions.js" as Actions
import "js/Swap.js" as Swap

Item {
  id: root

  readonly property string moduleName: "io.github.chris.window-hints"
  readonly property string pluginId: "io.github.chris.window-hints"

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""
  property bool opened: false
  property int sessionRevision: 0
  property var labels: []
  property string prefix: ""
  property string verb: "focus"
  property int moveTo: 0
  property string armedAddress: ""
  property string toast: ""
  property bool firstRun: false
  property bool bindCollision: false
  property string suggestedBind: "SUPER+F"
  property var alternateBinds: ["SUPER+H", "SUPER+;"]
  property bool swapGreyed: true
  property string moreNote: ""
  property bool gutter: false
  property string inputPath: "submap"
  property string bindingsWarning: ""
  property bool submapInstalled: false
  property int paintedAt: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property color danger: {
    try { if (Color.destructive) return Color.destructive } catch (e) {}
    try { if (Color.danger) return Color.danger } catch (e2) {}
    try { if (Color.error) return Color.error } catch (e3) {}
    return "#e85d4c"
  }
  property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius

  readonly property bool reduceMotion: {
    try { if (Style && Style.reduceMotion) return true } catch (e) {}
    try { if (Quickshell.env("OMARCHY_REDUCED_MOTION") === "1") return true } catch (e2) {}
    return false
  }
  readonly property int fadeMs: {
    if (root.reduceMotion)
      return 0
    if (!root.opened)
      return 0
    if (root.paintedAt && Date.now() - root.paintedAt < Config.DEFAULTS.fadeAfterMs)
      return 0
    return Config.DEFAULTS.fadeMs
  }

  function serviceRef() {
    if (pluginRegistry && typeof pluginRegistry.serviceFor === "function") {
      var a = pluginRegistry.serviceFor(root.pluginId)
      if (a)
        return a
    }
    if (shell && typeof shell.serviceFor === "function") {
      var b = shell.serviceFor(root.pluginId)
      if (b)
        return b
    }
    if (shell && typeof shell.firstPartyServiceFor === "function") {
      var c = shell.firstPartyServiceFor(root.pluginId)
      if (c)
        return c
    }
    return null
  }

  function callService(method, arg) {
    var svc = root.serviceRef()
    if (svc && svc !== root) {
      if (method === "key" && typeof svc.onKey === "function")
        return svc.onKey(arg)
      if (method === "begin" && typeof svc.beginHint === "function")
        return svc.beginHint(arg)
      if (method === "end" && typeof svc.endHint === "function")
        return svc.endHint(arg)
      if (method === "markFirstRun" && typeof svc.firstRunShown !== "undefined") {
        svc.firstRunShown = true
        return "ok"
      }
    }
    if (method === "key")
      return root.handleKeyDirect(arg)
    if (method === "begin") {
      Quickshell.execDetached(["omarchy-shell", "window-hints", "begin", arg || "{}"])
      root.opened = true
      return "queued"
    }
    if (method === "end") {
      Quickshell.execDetached(["omarchy-shell", "window-hints", "end", arg || "hide"])
      root.finishSession()
      return "hidden"
    }
    return "ok"
  }

  function pullSession() {
    var snap = Session.snapshot()
    root.sessionRevision = snap.revision
    root.labels = snap.labels
    root.prefix = snap.prefix
    root.verb = snap.verb
    root.moveTo = snap.moveTo
    root.armedAddress = snap.armedAddress
    root.toast = snap.toast
    root.firstRun = snap.firstRun
    root.bindCollision = snap.bindCollision
    root.suggestedBind = snap.suggestedBind
    root.alternateBinds = snap.alternateBinds
    root.swapGreyed = snap.swapGreyed
    root.moreNote = snap.moreNote
    root.gutter = snap.gutter
    root.inputPath = snap.inputPath
    root.bindingsWarning = snap.bindingsWarning || ""
    root.submapInstalled = !!snap.submapInstalled
    root.paintedAt = snap.paintedAt
    if (!snap.opened && root.opened)
      root.opened = false
    if (snap.opened && !root.opened)
      root.opened = true
  }

  function key(k) { return root.handleKeyDirect(k) }
  function ping() { return "ok" }
  function status(arg) {
    var snap = Session.snapshot()
    return JSON.stringify({
      ok: true,
      hinting: snap.hinting || root.opened,
      labels: (snap.labels || []).length,
      overflow: snap.overflow
    })
  }
  function begin(payload) {
    root.open(payload || "{}")
    return "ok"
  }
  function summon() { root.open("{}"); return "ok" }
  function hide() { return root.close() }
  function dismiss() { return root.close() }
  function end(reason) { return root.close() }

  function dispatchHypr(request) {
    if (!request)
      return
    try {
      Hyprland.dispatch(request)
    } catch (e) {
      hyprProc.command = ["hyprctl", "dispatch"].concat(String(request).split(" "))
      hyprProc.running = true
    }
  }

  function finishSession() {
    Session.resetView()
    root.opened = false
    root.dispatchHypr(Actions.submapCmd("reset"))
    overlayArmTimer.stop()
  }

  function handleKeyDirect(raw) {
    root.pullSession()
    var snap = Session.snapshot()
    if (!snap.opened && !snap.hinting && !root.opened)
      return "idle"
    var result = Input.handleKey(Session.input(), raw, snap.labels, Date.now(), Config.DEFAULTS.armMs)
    if (result.action === "dismiss") {
      root.finishSession()
      return "escape"
    }
    if (result.action === "verb") {
      Session.setVerb(result.verb, result.moveTo || 0)
      Session.setPrefix("")
      root.pullSession()
      return result.verb
    }
    if (result.action === "prefix") {
      Session.setPrefix(Session.input().prefix)
      Session.setVerb(Session.input().verb, Session.input().moveTo)
      root.pullSession()
      return "prefix"
    }
    if (result.action === "miss") {
      Session.setPrefix("")
      Session.setVerb(Session.input().verb, 0)
      root.pullSession()
      return "miss"
    }
    if (result.action === "arm") {
      Session.setArmed(result.target.address)
      Session.setPrefix(Session.input().prefix)
      Session.setVerb("close", 0)
      overlayArmTimer.interval = Config.DEFAULTS.armMs
      overlayArmTimer.restart()
      root.pullSession()
      return "arm"
    }
    if (result.action === "commit")
      return root.commitDirect(result.verb, result.target, result.moveTo)
    return "none"
  }

  function commitDirect(verb, target, moveTo) {
    if (!target || !target.address) {
      Session.setToast("window vanished", Date.now() + 1200)
      root.finishSession()
      return "vanished"
    }
    if (verb === "swap") {
      var snap = Session.snapshot()
      if (snap.swapGreyed) {
        Session.setToast("swap unavailable", Date.now() + 1200)
        Session.setPrefix("")
        Session.setVerb("focus", 0)
        Input.begin(Session.input())
        root.pullSession()
        return "greyed"
      }
    }
    var plan = Actions.commit(verb, target, moveTo)
    root.finishSession()
    if (plan && plan.dispatch)
      root.dispatchHypr(plan.dispatch)
    return plan ? plan.kind : "empty"
  }

  function open(payloadJson) {
    root.opened = true
    var snap = Session.snapshot()
    if (!snap.opened)
      root.callService("begin", payloadJson || "{}")
    Qt.callLater(function () {
      root.pullSession()
      if (root.inputPath === "overlay")
        keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    if (root.opened)
      root.callService("end", "hide")
    root.opened = false
  }

  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open("{}")
  }

  function labelsForScreen(screen) {
    var list = root.labels || []
    if (!screen)
      return list
    var name = screen.name || ""
    var out = []
    for (var i = 0; i < list.length; i++) {
      var lab = list[i]
      if (lab.monitorName && name && lab.monitorName === name) {
        out.push(lab)
        continue
      }
      if (!lab.monitorName && screen.x !== undefined) {
        var at = lab.at || [0, 0]
        var sx = Number(screen.x) || 0
        var sy = Number(screen.y) || 0
        var sw = Number(screen.width) || 0
        var sh = Number(screen.height) || 0
        if (at[0] >= sx && at[0] < sx + sw && at[1] >= sy && at[1] < sy + sh)
          out.push(lab)
      }
    }
    if (!out.length && list.length && (!name || list.length <= 4))
      return list
    return out
  }

  function pillOpacity(lab) {
    if (!root.prefix)
      return 1
    var chord = lab.chord || ""
    if (chord === root.prefix || chord.indexOf(root.prefix) === 0)
      return 1
    return 0.18
  }

  function chordLeft(lab) {
    var chord = lab.chord || ""
    if (!root.prefix)
      return chord
    if (chord.indexOf(root.prefix) === 0)
      return root.prefix
    return ""
  }

  function chordRight(lab) {
    var chord = lab.chord || ""
    if (!root.prefix)
      return ""
    if (chord.indexOf(root.prefix) === 0)
      return chord.slice(root.prefix.length)
    return chord
  }

  function keyFromEvent(event) {
    if (event.key === Qt.Key_Escape)
      return "escape"
    if (event.key === Qt.Key_Backspace)
      return "backspace"
    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
      return String(event.key - Qt.Key_0)
    if (event.text && event.text.length)
      return (event.modifiers & Qt.ShiftModifier) ? event.text.toUpperCase() : event.text.toLowerCase()
    return ""
  }

  Process {
    id: hyprProc
    running: false
  }

  Timer {
    id: overlayArmTimer
    interval: 250
    repeat: false
    onTriggered: {
      var snap = Session.snapshot()
      var target = Swap.findByAddress(snap.labels, Session.input().armedAddress)
      root.commitDirect("close", target, 0)
    }
  }

  Timer {
    interval: root.opened ? 32 : 400
    running: true
    repeat: true
    onTriggered: root.pullSession()
  }

  Item {
    id: keyCatcher
    width: 1
    height: 1
    focus: root.opened && root.inputPath === "overlay"
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      if (!root.opened || root.inputPath !== "overlay")
        return
      var k = root.keyFromEvent(event)
      if (!k)
        return
      root.callService("key", k)
      event.accepted = true
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: panel
      property var modelData
      visible: root.opened
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "window-hints"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: (root.opened && root.inputPath === "overlay") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      readonly property var screenLabels: root.labelsForScreen(modelData)

      Item {
        anchors.fill: parent
        focus: root.opened && root.inputPath === "overlay"
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (!root.opened || root.inputPath !== "overlay")
            return
          var k = root.keyFromEvent(event)
          if (!k)
            return
          root.callService("key", k)
          event.accepted = true
        }
      }

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        opacity: root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
      }

      Repeater {
        model: panel.screenLabels.length
        Rectangle {
          property var lab: panel.screenLabels[index]
          x: lab ? lab.x : 0
          y: lab ? lab.y : 0
          width: lab ? Math.max(lab.w, 28) : 28
          height: lab ? lab.h : 28
          radius: root.cornerRadius
          color: lab && lab.address === root.armedAddress ? root.danger : root.accent
          border.color: root.border
          border.width: 1
          opacity: root.opened && lab ? root.pillOpacity(lab) : 0
          Behavior on opacity { NumberAnimation { duration: root.fadeMs } }

          Row {
            anchors.centerIn: parent
            spacing: 0
            Text {
              text: lab && root.prefix ? root.chordLeft(lab) : (lab ? lab.chord : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              visible: !!(root.prefix && lab && root.chordRight(lab).length)
              text: lab ? root.chordRight(lab) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              opacity: 0.45
            }
          }

          Text {
            visible: !!(lab && lab.gutter && (lab.title || lab.className))
            anchors.left: parent.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: lab ? (lab.title || lab.className) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            opacity: 0.8
          }
        }
      }

      Rectangle {
        visible: root.moreNote.length > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.gapsOut
        width: moreLabel.implicitWidth + 16
        height: moreLabel.implicitHeight + 10
        radius: root.cornerRadius
        color: root.background
        border.color: root.border
        border.width: 1
        Text {
          id: moreLabel
          anchors.centerIn: parent
          text: root.moreNote
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Rectangle {
        visible: root.toast.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.gapsOut + 8
        width: toastLabel.implicitWidth + 24
        height: toastLabel.implicitHeight + 12
        radius: root.cornerRadius
        color: root.background
        border.color: root.border
        border.width: 1
        Text {
          id: toastLabel
          anchors.centerIn: parent
          text: root.toast
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Rectangle {
        visible: root.bindingsWarning.length > 0 || root.firstRun || root.verb !== "focus" || root.swapGreyed && root.verb === "swap"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.gapsOut + 8
        width: Math.min(parent.width - 24, bannerCol.implicitWidth + 28)
        height: bannerCol.implicitHeight + 18
        radius: root.cornerRadius
        color: root.background
        border.color: root.border
        border.width: 1

        Column {
          id: bannerCol
          anchors.centerIn: parent
          spacing: 4
          Text {
            visible: root.bindingsWarning.length > 0
            text: root.bindingsWarning
            color: root.danger
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            visible: root.verb === "close"
            text: "close — type a chord, Esc aborts"
            color: root.danger
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            visible: root.verb === "move"
            text: "move to workspace " + root.moveTo + " — type a chord"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            visible: root.verb === "swap"
            text: root.swapGreyed ? "swap unavailable on this Hyprland" : "swap (same workspace)"
            color: root.swapGreyed ? root.foreground : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            visible: root.firstRun && !root.bindingsWarning.length
            text: root.bindCollision
                  ? (root.suggestedBind + " is taken. Try " + root.alternateBinds.join(" or ") + ".")
                  : ("bind " + root.suggestedBind + "  ·  chord focus  ·  Shift+chord swap  ·  x then chord close  ·  1-9 then chord move")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            opacity: 0.86
          }
        }
      }
    }
  }
}

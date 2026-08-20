import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Session.js" as Session
import "js/Config.js" as Config

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
  property string suggestedBind: "SUPER+H"
  property var alternateBinds: ["SUPER+;", "SUPER+ALT+F"]
  property bool swapGreyed: true
  property string moreNote: ""
  property bool gutter: false
  property string inputPath: "submap"
  property string bindingsWarning: ""
  property bool bindOfferNeeded: false
  property bool bindOfferCanInstall: false
  property string bindOfferNote: ""
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

  property bool awaitingService: false

  // Display-only. Input, actions, watchdog, and teardown live on the
  // keepLoaded Service. Keys go to the extra IPC target `window-hints`
  // (not `shell call <id>`, which can land back here and recurse).
  function sendToService(method, arg) {
    var argv = ["omarchy-shell", "window-hints", method]
    if (arg !== undefined && arg !== null && String(arg).length)
      argv.push(String(arg))
    Quickshell.execDetached(argv)
    return "queued"
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
    root.bindOfferNeeded = !!snap.bindOfferNeeded
    root.bindOfferCanInstall = !!snap.bindOfferCanInstall
    root.bindOfferNote = snap.bindOfferNote || ""
    root.submapInstalled = !!snap.submapInstalled
    root.paintedAt = snap.paintedAt
    if (snap.opened || snap.hinting) {
      root.opened = true
      root.awaitingService = false
    } else if (!root.awaitingService) {
      root.opened = false
    }
  }

  function key(k) { return root.sendToService("key", k) }
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

  function open(payloadJson) {
    root.opened = true
    root.awaitingService = true
    var snap = Session.snapshot()
    if (!snap.hinting)
      root.sendToService("begin", payloadJson || "{}")
    Qt.callLater(function () {
      root.pullSession()
      if (root.inputPath === "overlay")
        keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.awaitingService = false
    root.opened = false
    root.sendToService("end", "hide")
  }

  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open("{}")
  }

  function installBinds(arg) {
    Quickshell.execDetached(["omarchy-shell", "window-hints", "installBinds", arg === undefined || arg === null ? "" : String(arg)])
    return "queued"
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
      root.sendToService("key", k)
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
          root.sendToService("key", k)
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
        visible: root.bindingsWarning.length > 0 || root.firstRun || (root.bindOfferNeeded && !root.bindOfferCanInstall) || root.verb !== "focus" || root.swapGreyed && root.verb === "swap"
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
          Text {
            visible: root.bindOfferNeeded && root.bindOfferNote.length > 0
            text: root.bindOfferCanInstall
                  ? "Use the bar chip: Set hotkey / Install hints submap"
                  : root.bindOfferNote
            color: root.danger
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            width: Math.min(panel.width - 48, 520)
          }
        }
      }
    }
  }
}

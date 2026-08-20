import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "js/Session.js" as Session

BarWidget {
  id: root
  moduleName: "io.github.chris.window-hints"

  readonly property string pluginId: "io.github.chris.window-hints"
  property bool bindOfferNeeded: true
  property bool bindOfferCanInstall: false
  property string bindOfferNote: ""
  property bool setupOpen: true
  property bool hinting: false

  function refresh() {
    var snap = Session.snapshot()
    root.bindOfferNeeded = !!snap.bindOfferNeeded
    root.bindOfferCanInstall = !!snap.bindOfferCanInstall
    root.bindOfferNote = snap.bindOfferNote || ""
    root.hinting = !!(snap.hinting || snap.opened)
    if (!root.bindOfferNeeded)
      root.setupOpen = false
  }

  function summonOverlay() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, "{}"])
  }

  function hideOverlay() {
    Quickshell.execDetached(["omarchy-shell", "shell", "hide", root.pluginId])
  }

  function installBinds() {
    Quickshell.execDetached(["omarchy-shell", "window-hints", "installBinds", "opt-in"])
  }

  function onChip() {
    if (root.bindOfferNeeded) {
      root.setupOpen = true
      return
    }
    root.summonOverlay()
  }

  function open() {
    if (root.bindOfferNeeded) {
      root.setupOpen = true
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.pluginId, "{}"])
  }

  function close() { root.hideOverlay() }
  function toggle() { root.onChip() }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Style.space(4)

    WidgetButton {
      id: chip
      bar: root.bar
      text: root.bindOfferNeeded ? "hints?" : (root.hinting ? "hints ▸" : "hints")
      tooltipText: root.bindOfferNeeded
                   ? ("Window Hints — no hotkey yet. " + (root.bindOfferNote || "Set hotkey from the bar."))
                   : (root.hinting ? "Window Hints — click to dismiss" : "Window Hints — click to hint windows")
      onPressed: function (buttonCode) {
        if (buttonCode === Qt.LeftButton)
          root.onChip()
        else if (buttonCode === Qt.RightButton && root.bindOfferNeeded)
          root.setupOpen = true
        else if (buttonCode === Qt.RightButton)
          root.open()
      }
    }

    WidgetButton {
      visible: root.bindOfferNeeded && root.setupOpen
      bar: root.bar
      text: "Set hotkey"
      tooltipText: root.bindOfferCanInstall
                   ? (root.bindOfferNote || "Install Super+H (or Super+;) and the hints submap")
                   : (root.bindOfferNote || "No free summon key")
      onPressed: function (buttonCode) {
        if (buttonCode === Qt.LeftButton)
          root.installBinds()
      }
    }

    WidgetButton {
      visible: root.bindOfferNeeded && root.setupOpen
      bar: root.bar
      text: "Install hints submap"
      tooltipText: "Write the hints submap and summon bind to ~/.config/hypr/bindings.lua"
      onPressed: function (buttonCode) {
        if (buttonCode === Qt.LeftButton)
          root.installBinds()
      }
    }
  }

  Timer {
    interval: 250
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()
}

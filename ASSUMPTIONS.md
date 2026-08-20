# Assumptions

Conservative choices where the Omarchy / Quickshell / Hyprland API was not 100% certain. The rule: isolate the uncertainty behind a small adapter, prefer documented types (`Process`, `Socket`, `FileView`, `Hyprland`, `IpcHandler`, `PanelWindow`, `Variants`), and degrade.

## Plugin host

- **Entry points are `Item`s**, not `ShellRoot`. Overlay exposes `open(payloadJson)` and `close()` for `omarchy-shell shell summon` / `hide`. Taken from the Quattro shell reference and the sibling desktop-undo plugin.
- **Injected properties** on load: `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, plus inline settings from the `shell.json` `plugins[]` entry bound onto the Item (`alphabet`, `inset`, …) or via a `settings` object. Overlay and Service still function if some of these are missing.
- **`keepLoaded: true`** so the overlay's layer-shell surfaces and the warm window model survive between summons. The spec's "perceived-instant summon" requirement needs this. The spec JSON block did not include the flag; the Quattro reference wins.
- **`moduleName`** is a readonly property on both entry points, equal to the plugin id. The spec said the two share `moduleName` per platform rules; the exact host field is not in the Quattro README, so it is not a QML module registration.
- **Third-party service lookup** tries `pluginRegistry.serviceFor`, then `shell.serviceFor`, then `shell.firstPartyServiceFor`, then `omarchy-shell shell call`. Live hint state is also shared via `.pragma library` `js/Session.js`.
- **IPC verb** is `omarchy-shell shell call <id> <method> <arg>` and `shell summon|hide|toggle <id> <payloadJson>`. Confirmed in `quattro-shell-reference.md`. `IpcHandler` target is the plugin id as a convenience; `shell call` is the primary path.
- **No `barWidget` metadata block.** Kinds are overlay + service only, matching the spec.

## Settings

- Settings arrive **inline on the shell.json entry**. There is no plugin-owned config file. Defaults live in `js/Config.js` and as QML properties on `Service.qml`. First-run / collision flags are in-memory for the process lifetime, not persisted.

## Quickshell

- **`Hyprland.rawEvent`** is the documented socket2 feed (`event.name`, `event.data`). Primary event source.
- **`Socket { path; connected }`** opens only if `rawEvent` has not fired within 2s. Socket line parsing is not attached — `parser` is not documented as clearly as Process `stdout: SplitParser`. Model refresh then relies on a `hyprctl -j` poll.
- **`Hyprland.dispatch(request)`** is used for mutations. If it throws, we fall back to a `Process` of `hyprctl`. Both talk to the compositor.
- **`Hyprland.eventSocketPath`** is preferred when building the Socket path; otherwise `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`.
- **`Hyprland.toplevels` / `lastIpcObject`** are the primary client model. Geometry still comes from `hyprctl -j clients` because toplevels are not documented to expose live `x`/`y`/`size` without `refreshToplevels()`.
- **`Variants { model: Quickshell.screens }`** is the documented per-output window factory. Overlay maps labels to a screen by `monitorName`, then by global `at` containment.
- **Theme tokens** `Color.menu.*`, `Color.accent`, `Style.*`, `PanelWindow`, `WlrLayershell` — copied from first-party clipboard / desktop-undo. Danger color tries `Color.destructive` / `Color.danger` / `Color.error`, then `#e85d4c`. Reduced motion: `Style.reduceMotion` or `OMARCHY_REDUCED_MOTION=1`.
- **Overlay keyboard focus** defaults to `WlrKeyboardFocus.None` (pure display). `inputPath: "overlay"` is the day-1 enhancement toggle and also a fallback if the hints submap was not installed.

## Hyprland (Omarchy Quattro / 0.55 Lua)

- **Binds are Lua.** README and `bindings.lua` use `hl.bind` / `hl.define_submap`. The plugin does not write `hyprland.conf`.
- **`hyprctl keyword` may fail** on the non-legacy Lua parser (`keyword can't work with non-legacy parsers`). Submap install therefore tries `hyprctl eval` first, then keyword batch, then tells the user to paste `bindings.lua`. Summon still works without a pre-installed submap if `inputPath` is `overlay`; the submap path is still the one we activate (`dispatch submap hints`).
- **Esc inside the submap always `submap reset`s**, even if the shell is dead. Catch-all is `hl.dsp.no_op()` so unbound keys do not leak into the focused client.
- **Swap.** Hyprland 0.55 Lua has `hl.dsp.window.swap({ target })`. `hyprctl dispatch swapwindow` was historically directional-only. We probe (`hints-ctl swap-probe`); if unknown or directional-only, the Shift+chord verb is greyed. Cross-workspace swap is never implemented (no pair of `movetoworkspacesilent`).
- **Monitor JSON `reserved`** is treated as `[top, bottom, left, right]`. Width/height are treated as already-logical layout size. `globalToOutput` never multiplies by `scale`. Rotation is applied only when `monitor.preTransform` is set; default Hyprland JSON is assumed post-transform (90° monitors report swapped width/height).
- Address spelling is normalized to lowercase `0x…`. Optional client fields are feature-detected; a malformed client is skipped.

## Helper

- Spec said no helper daemon is required (pure compositor-IPC). The competition brief still asked for a helper binary with `build.sh` and a missing-binary fallback. Both ship: Rust `src/hints-ctl` → `bin/hints-ctl`, POSIX `compat/hints-ctl.sh`.
- Core path (clients, dispatch, submap activate/reset) works with `hyprctl` directly from QML when the binary is absent.

## Out of scope (intentional, spec / tribunal)

- Hinting Omarchy bar widgets (needs shell-internal knowledge).
- `Tab` other-workspace gutter (cut to v1.1).
- Cross-workspace swap.
- A second Quickshell process.
- Network, accounts, telemetry.
- Writing Hyprland config for the user.

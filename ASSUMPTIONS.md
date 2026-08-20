# Assumptions

Conservative choices where the Omarchy / Quickshell / Hyprland API was not 100% certain. The rule: isolate the uncertainty behind a small adapter, prefer documented types (`Process`, `FileView`, `Hyprland`, `IpcHandler`, `PanelWindow`, `Variants`), and degrade.

## Plugin host

- **Entry points are `Item`s**, not `ShellRoot`. Overlay exposes `open(payloadJson)` and `close()` for `omarchy-shell shell summon` / `hide`. Taken from the Quattro shell reference and the sibling desktop-undo plugin.
- **Injected properties** on load: `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, plus inline settings from the `shell.json` `plugins[]` entry bound onto the Item (`alphabet`, `inset`, …) or via a `settings` object. Overlay and Service still function if some of these are missing.
- **`keepLoaded: true`** so the overlay's layer-shell surfaces and the warm window model survive between summons. The spec's "perceived-instant summon" requirement needs this. The spec JSON block did not include the flag; the Quattro reference wins.
- **`moduleName`** is a readonly property on both entry points, equal to the plugin id. The spec said the two share `moduleName` per platform rules; the exact host field is not in the Quattro README, so it is not a QML module registration.
- **Third-party service lookup** tries `pluginRegistry.serviceFor`, then `shell.serviceFor`, then `shell.firstPartyServiceFor`, then `omarchy-shell shell call`. Live hint state is also shared via `.pragma library` `js/Session.js`.
- **IPC verb** is `omarchy-shell shell call <id> <method> <arg>` and `shell summon|hide|toggle <id> <payloadJson>`. Confirmed in `quattro-shell-reference.md`. `status` is called as `call <id> status '{}'`. `IpcHandler` target is the plugin id as a convenience; `shell call` is the primary path.
- **No `barWidget` metadata block.** Kinds are overlay + service only, matching the spec.

## Settings

- Settings arrive **inline on the shell.json entry**. Merge order (see `Config.resolveSettings`): compiled defaults, then Item properties that differ from those defaults (host-bound), then the injected `settings` object (authoritative), then a summon payload. Root QML defaults never overwrite `settings`.
- **`suggestedBind`** is parsed (`SUPER+F` → mods `SUPER`, key `F`) and passed to `binds-check`. Collision detection uses that pair, not a hardcoded Super+F.
- **`alphabet`** drives both chord assignment and the generated `hints` submap. `hints-ctl submap install <alphabet>` (and the POSIX fallback) emit binds for that set, plus `x` / digits / Esc / catchall.

## Quickshell

- **`Hyprland.rawEvent`** is the documented socket2 feed (`event.name`, `event.data`). Primary event source.
- **No `Socket` fallback.** `Socket.parser` / line reads are not documented as clearly as Process `stdout: SplitParser`. A connected-but-unread socket is not an event source, so it is not used. If `rawEvent` is silent, the service refreshes the model with a `hyprctl -j clients` / `monitors` poll (400 ms while hinting, 1200 ms idle).
- **`Hyprland.dispatch(request)`** is used for mutations. If it throws, we fall back to a queued `Process` of `hyprctl`. Both talk to the compositor. Only the queued Process path has the 800 ms timeout.
- **`Hyprland.toplevels` / `lastIpcObject`** are the primary client model. Geometry still comes from `hyprctl -j clients` because toplevels are not documented to expose live `x`/`y`/`size` without `refreshToplevels()`.
- **`Variants { model: Quickshell.screens }`** is the documented per-output window factory. Overlay maps labels to a screen by `monitorName`, then by global `at` containment.
- **Theme tokens** `Color.menu.*`, `Color.accent`, `Style.*`, `PanelWindow`, `WlrLayershell` — copied from first-party clipboard / desktop-undo. Danger color tries `Color.destructive` / `Color.danger` / `Color.error`, then `#e85d4c`. Reduced motion: `Style.reduceMotion` or `OMARCHY_REDUCED_MOTION=1`.
- **Overlay keyboard focus** is `WlrKeyboardFocus.None` on the submap path. Exclusive overlay focus is only `inputPath: "overlay"` (progressive enhancement). A failed submap *install* still *activates* `submap hints` and shows a paste-`bindings.lua` banner; it does not switch input to the overlay.

## Hyprland (Omarchy Quattro / 0.55 Lua)

- **Binds are Lua.** README and `bindings.lua` use `hl.bind` / `hl.define_submap`. The plugin does not write `hyprland.conf`.
- **`hyprctl keyword` may fail** on the non-legacy Lua parser. Submap install tries `hyprctl eval`, then a keyword batch. The helper returns `installed:false` when both fail. Summon still `dispatch submap hints` (the load-bearing path) and warns to paste `bindings.lua`. Overlay exclusive input is not used as a fallback.
- **Esc inside the submap always `submap reset`s**, even if the shell is dead. Catch-all is `hl.dsp.no_op()` so unbound keys do not leak into the focused client.
- **Swap.** Probe is `hyprctl dispatch swapwindow address:0x0` — dispatcher and argument as separate argv tokens, matching Hyprland’s `dispatch <dispatcher> <argument>` contract. Capable only if that call shows an address target was accepted (`Invalid window` / `Window not found`). Directional-only usage keeps the verb greyed. Version is not used as a capability signal. Cross-workspace swap is never implemented.
- **`beginHint` is idempotent.** A second begin (Overlay.open after service summon) keeps the session; only `toggleHint` / hide / Esc dismisses it.
- **Monitor JSON `reserved`** is treated as `[top, bottom, left, right]`. Width/height are treated as already-logical layout size. `globalToOutput` never multiplies by `scale`. Rotation is applied only when `monitor.preTransform` is set; default Hyprland JSON is assumed post-transform (90° monitors report swapped width/height).
- Address spelling is normalized to lowercase `0x…`. Optional client fields are feature-detected; a malformed client is skipped.

## Helper

- Spec said no helper daemon is required (pure compositor-IPC). The competition brief still asked for a helper binary with `build.sh` and a missing-binary fallback. Both ship: Rust `src/hints-ctl` → `bin/hints-ctl`, POSIX `compat/hints-ctl.sh`.
- Core path (clients, dispatch) works with `hyprctl` directly from QML when the binary is absent.
- `src/hints-ctl/target/` is build output and must not ship in an archive; it is gitignored and deleted from the tree.

## Out of scope (intentional, spec / tribunal)

- Hinting Omarchy bar widgets (needs shell-internal knowledge).
- `Tab` other-workspace gutter (cut to v1.1).
- Cross-workspace swap.
- A second Quickshell process.
- Network, accounts, telemetry.
- Writing Hyprland config for the user.

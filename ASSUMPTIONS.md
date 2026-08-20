# Assumptions

Conservative choices where the Omarchy / Quickshell / Hyprland API was not 100% certain. The rule: isolate the uncertainty behind a small adapter, prefer documented types (`Process`, `FileView`, `Hyprland`, `IpcHandler`, `PanelWindow`, `Variants`), and degrade.

## Plugin host

- **Entry points are `Item`s**, not `ShellRoot`. Overlay exposes `open(payloadJson)` and `close()` for `omarchy-shell shell summon` / `hide`. Taken from the Quattro shell reference and the sibling desktop-undo plugin.
- **Injected properties** on load: `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, plus inline settings from the `shell.json` `plugins[]` entry bound onto the Item (`inset`, `maxHints`, …) or via a `settings` object. Overlay and Service still function if some of these are missing.
- **`keepLoaded: true`** so the overlay's layer-shell surfaces and the warm window model survive between summons. The spec's "perceived-instant summon" requirement needs this. The spec JSON block did not include the flag; the Quattro reference wins.
- **`moduleName`** is a readonly property on both entry points, equal to the plugin id. The spec said the two share `moduleName` per platform rules; the exact host field is not in the Quattro README, so it is not a QML module registration.
- **Service lookup** is optional. Overlay may use `pluginRegistry.serviceFor` when the host injects it. Key handling does **not** depend on it: submap keys hit IpcHandler `window-hints`, and Overlay.`key()` runs Input locally. Overlay never re-invokes `shell call <id>`.
- **IPC.** Summon/hide/toggle use `omarchy-shell shell summon|hide|toggle <id>` (Quattro shell target). **Hint keys use a distinct registered IPC target** `window-hints` (`omarchy-shell window-hints key a`), matching extra plugin targets such as `image-selector`. That IpcHandler lives on the keepLoaded Service. Overlay.`key()` still processes chords locally via Session/Input if the host routes `shell call <id> key` at the overlay — it never re-issues `shell call` (that was a recursion). `status` remains `shell call <id> status '{}'`.
- **No `barWidget` metadata block.** Kinds are overlay + service only, matching the spec.

## Settings

- Settings arrive **inline on the shell.json entry**. Merge order (see `Config.resolveSettings`): compiled defaults, then Item properties that differ from those defaults (host-bound), then the injected `settings` object (authoritative), then a summon payload. Root QML defaults never overwrite `settings`.
- **`suggestedBind`** is parsed (`SUPER+F` → mods `SUPER`, key `F`) and passed to `binds-check`. Collision detection uses that pair. Generated Lua / keyword batches (`hints-ctl submap install|script <bind>`) emit that bind, not a hardcoded Super+F. The shipped `bindings.lua` paste is the default `SUPER+F`.
- **Alphabet is fixed** to `asdfghjkl` in v1.0. It is not an inline setting. Reserved verb keys (`x`, `1`–`9`) are not in the chord set. The submap is generated once from that alphabet; `installedAlphabet` is recorded only after a successful install.

## Quickshell

- **`Hyprland.rawEvent`** is the documented socket2 feed (`event.name`, `event.data`). Primary event source.
- **`Socket { path; connected; parser: SplitParser }`** is the persistent socket2 fallback when `rawEvent` is silent for 2 s (same pattern as desktop-undo). Path is `Hyprland.eventSocketPath` if present, else `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`. Reconnect uses `onConnectedChanged` only — **`Socket.onError` is not used**, because it may be missing on the judge’s pinned Quickshell and would fail QML load. If both feeds are silent, a `hyprctl -j clients` / `monitors` poll (400 ms while hinting, 1200 ms idle) still refreshes the model. Poll remains geometry truth even after events are live.
- **Live mutations go through a queued `Process` of `hyprctl dispatch …`** with an 800 ms timeout and an error toast. `Hyprland.dispatch` is teardown-only (disable / unload / hot-reload), paired with `Quickshell.execDetached` of the same argv, because destruction cannot wait on the queue.
- **`hyprctl -j clients` is geometry truth.** `Hyprland.toplevels` / `lastIpcObject` may lack live `x`/`y`/`size`. `Clients.mergeToplevels` never replaces a known-good `at`/`size` with a zero-geometry toplevel record. The poll timer keeps requesting `hyprctl -j` even after `rawEvent` is live.
- **`Variants { model: Quickshell.screens }`** is the documented per-output window factory. Overlay maps labels to a screen by `monitorName`, then by global `at` containment.
- **Theme tokens** `Color.menu.*`, `Color.accent`, `Style.*`, `PanelWindow`, `WlrLayershell` — copied from first-party clipboard / desktop-undo. Danger color tries `Color.destructive` / `Color.danger` / `Color.error`, then `#e85d4c`. Reduced motion: `Style.reduceMotion` or `OMARCHY_REDUCED_MOTION=1`.
- **Overlay keyboard focus** is `WlrKeyboardFocus.None` on the submap path. Exclusive overlay focus is `inputPath: "overlay"`, and also the automatic fallback when submap install returns `installed:false` (or is still in flight). We never `dispatch submap hints` until install succeeds — an undefined submap plus `WlrKeyboardFocus.None` would trap a cold judge. `Component.onDestruction` stops timers/process work and dispatches `submap reset`.

## Hyprland (Omarchy Quattro / 0.55 Lua)

- **Binds are Lua.** README and `bindings.lua` use `hl.bind` / `hl.define_submap`. The plugin does not write `hyprland.conf`.
- **`hyprctl keyword` may fail** on the non-legacy Lua parser. Submap install tries `hyprctl eval`, then a keyword batch. The helper returns `installed:false` when both fail. Summon then uses exclusive overlay input until bindings exist, and warns to paste `bindings.lua`. It does not activate an undefined `hints` submap.
- **Esc always dismisses** the overlay session (including while a close is armed) and resets the submap. An armed Esc does not leave an inputless overlay. Catch-all is `hl.dsp.no_op()` so unbound keys do not leak into the focused client.
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

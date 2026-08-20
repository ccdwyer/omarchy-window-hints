# Window Hints

Vimium for the whole desktop. One hotkey sprinkles avy-style home-row labels over every visible window; type the chord to focus, swap, close, or throw it to a workspace.

This is an Omarchy shell plugin (bar-widget + service + overlay). It runs inside the long-lived `omarchy-shell` process. It does not start a second Quickshell instance.

![preview](preview.png)

## Install

```sh
omarchy plugin add https://github.com/ccdwyer/omarchy-window-hints.git --enable
```

`--enable` turns the plugin on. The bar chip lands in `barWidget.defaultSection` (`right`). Move it with `omarchy bar move` as documented in the Quattro shell README.

Then, on the machine, build the helper (optional — QML talks to `hyprctl` directly if the binary is missing):

```sh
~/.config/omarchy/plugins/io.github.chris.window-hints/build.sh
```

Reload plugins if the shell was already running:

```sh
omarchy-shell shell rescanPlugins
```

Keybindings are **opt-in**. Nothing is written to `~/.config/hypr/bindings.lua` on first load. Click the bar chip, then **Set hotkey** or **Install hints submap**. That explicit click is the only path that writes the marked Hyprland block. Suggested summon is Super+H, then Super+;. Super+F is never used and never unbound.

You can also paste `bindings.lua` or run `hints-ctl submap install SUPER+H` (tries `hyprctl eval`, then a `hyprctl --batch` keyword fallback).

## Usage

Click the **hints** chip to summon the overlay once a hotkey is installed. If no hotkey/submap is installed, the chip shows setup instead: **Set hotkey** and **Install hints submap**.

| Chord | Action |
|---|---|
| hint key, then `a` / `sd` / … | Focus that window |
| hint key, then `Shift+chord` | Swap with the focused window (same workspace only) |
| hint key, then `x` then chord | Close — the target flashes danger for 250 ms; `Esc` aborts |
| hint key, then `1`–`9` then chord | Move to workspace N (`movetoworkspacesilent`) |
| `Esc` | Always dismiss (including while a close is armed); always resets the Hyprland submap |

Suggested summon is **Super+H**. Stock Omarchy binds **Super+F** to Full screen — this plugin never steals it and never `hl.unbind`s it. Occupied shortcuts (including stock Omarchy hotkeys) are skipped. If Super+H is taken, opt-in install tries **Super+;** then **Super+Alt+F**. If every alternate is taken, nothing is written.

```lua
-- ~/.config/hypr/bindings.lua  (full copy in bindings.lua)
hl.bind("SUPER + H", hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.chris.window-hints '{}'"))
```

The `hints` submap is the load-bearing input path. Chord keys are sent to the plugin’s registered IPC target `window-hints` (`omarchy-shell window-hints key a`), not through `shell call <plugin-id>` (that would hit the overlay and must not bounce). The overlay is display-only in both submap and exclusive-fallback modes: exclusive overlay keystrokes are forwarded to that same `window-hints` target so the service owns input, actions, the watchdog, and teardown. Summon activates `submap hints` only after install reports the submap live. If install has not happened, the overlay takes exclusive keyboard focus until bindings exist so a cold session is never inputless; a banner tells you to use the bar chip. Recovery is `hyprctl dispatch 'hl.dsp.submap("reset")'`. Setting `inputPath: "overlay"` forces exclusive overlay keys even when the submap is installed.

## IPC

```sh
omarchy-shell shell toggle io.github.chris.window-hints '{}'
omarchy-shell shell summon io.github.chris.window-hints '{}'
omarchy-shell shell hide io.github.chris.window-hints
omarchy-shell window-hints key a
omarchy-shell window-hints installBinds opt-in
omarchy-shell shell call io.github.chris.window-hints status '{}'
```

`installBinds auto` is refused. Only an explicit bar click (or `installBinds opt-in`) writes `bindings.lua`.

## Settings

Inline on the `shell.json` plugin entry. No config file of our own.

```json
{
  "id": "io.github.chris.window-hints",
  "inset": 8,
  "maxHints": 25,
  "watchdogMs": 15000,
  "armMs": 250,
  "inputPath": "submap",
  "suggestedBind": "SUPER+H"
}
```

Chords use a **fixed** home-row alphabet `asdfghjkl` (v1.0). `x` and `1`–`9` are reserved verbs, not chords. `inputPath: "overlay"` is an optional latency enhancement (exclusive overlay focus). Leave it at `"submap"` for the compositor-grabbed path.

## Honest limitations

- **Windows only.** Bar-widget *hinting* (labels on the bar itself) needs shell internals; not in 1.0. The bar chip summons the overlay and offers opt-in hotkey install. Other-workspace gutter (`Tab`) is v1.1.
- **Swap is same-workspace only.** Cross-workspace swap is not a swap (it would take two `movetoworkspacesilent` and wreck both layouts). If this Hyprland's `swapwindow` is directional-only, the Shift+chord verb is greyed rather than surprising you.
- **25 visible windows (or chord capacity, whichever is smaller).** Beyond that, a "+N more" chip; extra windows are not hinted.
- **Label freeze.** A window that closes mid-hint loses its label; that chord is never reused. New windows opening mid-hint are ignored until the next summon. The first summon waits for a successful `hyprctl` clients+monitors snapshot before freezing; it will not lock in an empty label set from a cold start.
- **Keybinds are opt-in from the bar.** Super+H (or Super+; / Super+Alt+F) plus the `hints` submap are written only when you click **Set hotkey** / **Install hints submap**. Super+F is never used. Occupied combos (including stock Omarchy hotkeys) are skipped. Notify only after a successful write. Generated `hints-ctl submap install|script` uses the live `suggestedBind`. On Hyprland 0.55, `hyprctl keyword` may refuse to install the submap at runtime — use the bar chip or paste `bindings.lua`. Until that install succeeds, the overlay keeps exclusive keys. Overlay-only input is fine.
- **Installer never stages Lua in /tmp.** `compat/install-binds.py --summon` writes `~/.config/hypr/bindings.lua` directly. If a staged file is requested, `XDG_RUNTIME_DIR` must be set and usable; otherwise the installer fails closed instead of falling back to `/tmp`.
- **Helper binary.** `bin/hints-ctl` is built by `build.sh`. If it is missing, QML uses `compat/hints-ctl.sh` and raw `hyprctl`. Submap *definition* may need the Lua snippet; summon does **not** enter an undefined `hints` submap.
- **Timeouts.** Every live `hyprctl` from the service is a queued `Process` with an 800 ms timeout and an error toast. The helper’s own `hyprctl` children use the same 800 ms cap (or `timeout 1` in the POSIX fallback). `Hyprland.dispatch` is used only on teardown, where we cannot wait, plus `execDetached hyprctl dispatch 'hl.dsp.submap("reset")'`. The 15 s idle watchdog still dismisses the overlay and resets a live submap. Disable / unload / hot-reload runs `Component.onDestruction` cleanup (stop timers and processes, `submap reset`).
- **Coordinates.** Mapping is logical-coords only (no `* scale`). Rotated outputs that already report swapped width/height are subtracted; a pre-transform JSON is rotated in `globalToOutput`. If geometry looks unusable, labels fall back to a per-monitor gutter with titles.

## Tests (off-device)

```sh
node tests/run.js
sh tests/helper-fallback.test.sh
# helper, if you have cargo:
cargo test --manifest-path src/hints-ctl/Cargo.toml
```

## Remove

Remove the plugin **and** the Hyprland block it installed (opt-in or leftover from an older auto-install). Do the bind removal first, while the plugin files are still on disk:

```sh
python3 ~/.config/omarchy/plugins/io.github.chris.window-hints/compat/install-binds.py \
  io.github.chris.window-hints --remove
omarchy plugin remove io.github.chris.window-hints
```

`--remove` deletes the marked `-- BEGIN io.github.chris.window-hints` / `-- END io.github.chris.window-hints` block from `~/.config/hypr/bindings.lua`. If the plugin is already gone, delete that block by hand.

#!/bin/sh
# Off-device checks for the POSIX helper. No Hyprland required.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SH="$ROOT/compat/hints-ctl.sh"
chmod +x "$SH"

out=$("$SH" ping)
printf '%s\n' "$out" | grep -q '"ok":true' || { echo "ping failed: $out"; exit 1; }
printf '%s\n' "$out" | grep -q compat || { echo "ping missing compat tag"; exit 1; }

script=$("$SH" submap script)
printf '%s\n' "$script" | grep -q 'define_submap("hints"' || { echo "script missing submap"; exit 1; }
printf '%s\n' "$script" | grep -q 'submap("reset")' || { echo "script missing reset"; exit 1; }
printf '%s\n' "$script" | grep -q 'catchall' || { echo "script missing catchall"; exit 1; }
printf '%s\n' "$script" | grep -q 'window-hints key a' || { echo "default script missing window-hints key a"; exit 1; }
printf '%s\n' "$script" | grep -q 'shell call' && { echo "submap must not use recursive shell call: $script"; exit 1; }

ignored=$("$SH" submap script qwer)
printf '%s\n' "$ignored" | grep -q 'hl.bind("a"' || { echo "fixed alphabet missing a"; exit 1; }
printf '%s\n' "$ignored" | grep -q 'hl.bind("q"' && { echo "v1.0 must ignore custom alphabet: $ignored"; exit 1; }
printf '%s\n' "$ignored" | grep -q 'key x' || { echo "close verb x missing"; exit 1; }
printf '%s\n' "$ignored" | grep -q 'SUPER + F' || { echo "default script bind should be SUPER + F: $ignored"; exit 1; }
alt=$("$SH" submap script SUPER+H)
printf '%s\n' "$alt" | grep -q 'SUPER + H' || { echo "script should honor suggestedBind SUPER+H: $alt"; exit 1; }
printf '%s\n' "$alt" | grep -q 'hl.bind("SUPER + F"' && { echo "script must not hardcode SUPER + F when SUPER+H requested: $alt"; exit 1; }
grep -q 'keyword_batch' "$SH" || { echo "POSIX helper missing keyword_batch"; exit 1; }
grep -q -- '--batch' "$SH" || { echo "POSIX helper install missing --batch fallback"; exit 1; }
grep -q 'format_lua_bind' "$SH" || { echo "POSIX helper missing format_lua_bind"; exit 1; }
grep -q 'try_hypr' "$SH" || { echo "POSIX helper missing try_hypr timeout wrapper"; exit 1; }

SVC="$ROOT/Service.qml"
grep -q 'Component.onDestruction' "$SVC" || { echo "Service missing onDestruction teardown"; exit 1; }
grep -q 'function teardown' "$SVC" || { echo "Service missing teardown()"; exit 1; }
grep -q 'id: eventSock' "$SVC" || { echo "Service missing Socket fallback"; exit 1; }
grep -q 'function finishWork' "$SVC" || { echo "Service missing onExited job finalize"; exit 1; }
grep -q 'submap", "install", root.suggestedBind' "$SVC" || { echo "install must pass suggestedBind"; exit 1; }
grep -q 'useOverlayInput(true)' "$SVC" || { echo "failed install must switch to exclusive overlay"; exit 1; }
grep -q 'frozenOnUnreadyModel' "$SVC" || { echo "Service missing cold-start rebuild"; exit 1; }
grep -q 'rebuildHintSession' "$SVC" || { echo "Service missing rebuildHintSession"; exit 1; }
grep -q 'serviceFor' "$ROOT/Overlay.qml" && { echo "Overlay must not call undocumented serviceFor"; exit 1; }
grep -q 'firstPartyServiceFor' "$ROOT/Overlay.qml" && { echo "Overlay must not call firstPartyServiceFor"; exit 1; }
grep -q 'shell.summon' "$SVC" && { echo "Service must not call undocumented shell.summon"; exit 1; }
grep -q 'shell.hide' "$SVC" && { echo "Service must not call undocumented shell.hide"; exit 1; }
OV="$ROOT/Overlay.qml"
grep -q 'handleKeyDirect' "$OV" && { echo "Overlay must not handle keys locally"; exit 1; }
grep -q 'commitDirect' "$OV" && { echo "Overlay must not commit actions locally"; exit 1; }
grep -q 'js/Input.js' "$OV" && { echo "Overlay must not import Input.js"; exit 1; }
grep -q 'sendToService("key"' "$OV" || { echo "Overlay exclusive keys must go through sendToService"; exit 1; }
grep -q 'window-hints' "$OV" || { echo "Overlay must forward to window-hints IPC"; exit 1; }
grep -q 'Add keybindings' "$OV" && { echo "Overlay must not offer Add keybindings"; exit 1; }
grep -q 'notifyNewBinds' "$SVC" || { echo "Service missing notifyNewBinds"; exit 1; }
grep -q 'claimAuto' "$SVC" || { echo "Service missing claimAuto"; exit 1; }
grep -q 'hl.unbind(' "$ROOT/js/Binds.js" && { echo "Binds.js must never call hl.unbind"; exit 1; }
grep -q 'hl.unbind(' "$SVC" && { echo "Service must never call hl.unbind"; exit 1; }
test -f "$ROOT/compat/install-binds.py" || { echo "missing compat/install-binds.py"; exit 1; }
grep -q 'target/' "$ROOT/.gitignore" || { echo ".gitignore must exclude cargo target/"; exit 1; }
grep -q 'export-ignore' "$ROOT/.gitattributes" || { echo ".gitattributes must export-ignore target/"; exit 1; }

snap_out=$(mktemp)
snap_err=$(mktemp)
if HINTS_HYPRCTL=/no/such/hyprctl "$SH" snapshot >"$snap_out" 2>"$snap_err"; then
  echo "snapshot should fail without hyprctl"
  rm -f "$snap_out" "$snap_err"
  exit 1
fi
grep -q '"ok":false' "$snap_out" || { echo "snapshot error json missing"; rm -f "$snap_out" "$snap_err"; exit 1; }
rm -f "$snap_out" "$snap_err"

install=$(HINTS_HYPRCTL=/no/such/hyprctl "$SH" submap install)
printf '%s\n' "$install" | grep -q '"installed":false' || { echo "install should report installed:false without hypr: $install"; exit 1; }

swap=$(HINTS_HYPRCTL=/no/such/hyprctl "$SH" swap-probe)
printf '%s\n' "$swap" | grep -q '"capable":false' || { echo "swap-probe should not guess capable: $swap"; exit 1; }
printf '%s\n' "$swap" | grep -q '0.55' && { echo "swap-probe still uses version heuristic: $swap"; exit 1; }
grep -q "hyprctl dispatch submap reset" "$SVC" && { echo "Service still documents classic submap reset dispatch"; exit 1; }
grep -q 'hl.dsp.submap' "$SVC" || { echo "Service recovery must use Lua submap dispatch"; exit 1; }
grep -q 'dispatch swapwindow' "$SH" && { echo "POSIX helper still probes classic swapwindow"; exit 1; }
grep -q 'hl.dsp.window.swap' "$SH" || { echo "POSIX helper swap-probe must dispatch Lua table"; exit 1; }

mock=$(mktemp)
cat > "$mock" <<'EOF'
#!/bin/sh
if [ "$1" = "-j" ] && [ "$2" = "binds" ]; then
  cat "$HINTS_BINDS_FIXTURE"
  exit 0
fi
exit 1
EOF
chmod +x "$mock"

HINTS_BINDS_FIXTURE="$ROOT/tests/fixtures/binds-super-f.json"
export HINTS_BINDS_FIXTURE
col=$(HINTS_HYPRCTL="$mock" "$SH" binds-check SUPER F)
printf '%s\n' "$col" | grep -q '"collision":true' || { echo "SUPER+F should collide: $col"; exit 1; }

HINTS_BINDS_FIXTURE="$ROOT/tests/fixtures/binds-f-no-super.json"
col=$(HINTS_HYPRCTL="$mock" "$SH" binds-check SUPER F)
printf '%s\n' "$col" | grep -q '"collision":false' || { echo "bare F must not count as SUPER+F: $col"; exit 1; }

HINTS_BINDS_FIXTURE="$ROOT/tests/fixtures/binds-unrelated-super-q.json"
col=$(HINTS_HYPRCTL="$mock" "$SH" binds-check SUPER F)
printf '%s\n' "$col" | grep -q '"collision":false' || { echo "unrelated Super+Q must not collide Super+F: $col"; exit 1; }

rm -f "$mock"

mock=$(mktemp)
log=$(mktemp)
cat > "$mock" <<'EOF'
#!/bin/sh
: > "$HINTS_HYPR_LOG"
i=1
for a in "$@"; do
  printf 'arg%d=%s\n' "$i" "$a" >> "$HINTS_HYPR_LOG"
  i=$((i + 1))
done
if [ "$1" = "dispatch" ]; then
  printf '%s\n' 'target window not found' >&2
  exit 0
fi
exit 1
EOF
chmod +x "$mock"
HINTS_HYPR_LOG="$log"
export HINTS_HYPR_LOG
swap=$(HINTS_HYPRCTL="$mock" "$SH" swap-probe)
printf '%s\n' "$swap" | grep -q '"capable":true' || { echo "lua swap-probe should be capable: $swap"; rm -f "$mock" "$log"; exit 1; }
grep -q 'hl.dsp.window.swap' "$log" || { echo "swap-probe must dispatch lua table: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }
grep -q '^arg3=' "$log" && { echo "swap-probe lua must be a single argv: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

HINTS_HYPRCTL="$mock" "$SH" dispatch focus 0xaaa >/dev/null 2>&1
grep -q 'hl.dsp.focus' "$log" || { echo "dispatch focus must use lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }
grep -q '^arg3=' "$log" && { echo "dispatch must not split lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

HINTS_HYPRCTL="$mock" "$SH" dispatch close AAA >/dev/null 2>&1
grep -q 'hl.dsp.window.close' "$log" || { echo "dispatch close must use lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

HINTS_HYPRCTL="$mock" "$SH" dispatch swap 0x1 >/dev/null 2>&1
grep -q 'hl.dsp.window.swap' "$log" || { echo "dispatch swap must use lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

HINTS_HYPRCTL="$mock" "$SH" dispatch move 0x1 3 >/dev/null 2>&1
grep -q 'hl.dsp.window.move' "$log" || { echo "dispatch move must use lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }
grep -q 'follow = false' "$log" || { echo "dispatch move must set follow=false: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }
grep -q '^arg3=' "$log" && { echo "dispatch move lua must be a single argv: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

HINTS_HYPRCTL="$mock" "$SH" submap reset >/dev/null 2>&1
grep -q 'hl.dsp.submap("reset")' "$log" || { echo "submap reset must dispatch lua: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }
grep -q '^arg3=' "$log" && { echo "submap reset lua must be a single argv: $(cat "$log")"; rm -f "$mock" "$log"; exit 1; }

rm -f "$mock" "$log"
echo "ok  helper-fallback"

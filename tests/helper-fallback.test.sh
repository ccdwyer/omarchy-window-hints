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

snap_out=$(mktemp)
snap_err=$(mktemp)
if HINTS_HYPRCTL=/no/such/hyprctl "$SH" snapshot >"$snap_out" 2>"$snap_err"; then
  echo "snapshot should fail without hyprctl"
  rm -f "$snap_out" "$snap_err"
  exit 1
fi
grep -q '"ok":false' "$snap_out" || { echo "snapshot error json missing"; rm -f "$snap_out" "$snap_err"; exit 1; }
rm -f "$snap_out" "$snap_err"

install=$("$SH" submap install)
printf '%s\n' "$install" | grep -q '"installed":false' || { echo "install should report installed:false without hypr: $install"; exit 1; }

swap=$("$SH" swap-probe)
printf '%s\n' "$swap" | grep -q '"capable":false' || { echo "swap-probe should not guess capable: $swap"; exit 1; }
printf '%s\n' "$swap" | grep -q '0.55' && { echo "swap-probe still uses version heuristic: $swap"; exit 1; }

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

rm -f "$mock"
echo "ok  helper-fallback"

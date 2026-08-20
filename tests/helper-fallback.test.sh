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

if HINTS_HYPRCTL=/no/such/hyprctl "$SH" snapshot >/tmp/hints-ctl-snap.out 2>/tmp/hints-ctl-snap.err; then
  echo "snapshot should fail without hyprctl"
  exit 1
fi
grep -q '"ok":false' /tmp/hints-ctl-snap.out || { echo "snapshot error json missing"; exit 1; }

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

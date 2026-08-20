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

echo "ok  helper-fallback"

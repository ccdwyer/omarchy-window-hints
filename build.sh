#!/bin/sh
# Build the hints-ctl helper. The plugin QML degrades to compat/hints-ctl.sh
# when bin/hints-ctl is missing, so a failed build is not fatal at runtime.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC="$ROOT/src/hints-ctl"
OUT="$ROOT/bin"

mkdir -p "$OUT"
chmod +x "$ROOT/compat/hints-ctl.sh" 2>/dev/null || true

if ! command -v cargo >/dev/null 2>&1; then
  echo "build.sh: cargo not found; installing POSIX fallback as bin/hints-ctl" >&2
  cp "$ROOT/compat/hints-ctl.sh" "$OUT/hints-ctl"
  chmod +x "$OUT/hints-ctl"
  echo "build.sh: wrote $OUT/hints-ctl (shell fallback)"
  exit 0
fi

if ! cargo build --release --manifest-path "$SRC/Cargo.toml"; then
  echo "build.sh: cargo build failed; installing POSIX fallback as bin/hints-ctl" >&2
  cp "$ROOT/compat/hints-ctl.sh" "$OUT/hints-ctl"
  chmod +x "$OUT/hints-ctl"
  echo "build.sh: wrote $OUT/hints-ctl (shell fallback)"
  exit 0
fi

BIN="$SRC/target/release/hints-ctl"
if [ ! -x "$BIN" ]; then
  echo "build.sh: release binary missing after cargo build" >&2
  exit 1
fi
cp "$BIN" "$OUT/hints-ctl"
chmod +x "$OUT/hints-ctl"
echo "build.sh: wrote $OUT/hints-ctl"

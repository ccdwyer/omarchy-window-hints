#!/bin/sh
# POSIX fallback when bin/hints-ctl is missing. Same verbs, no Rust.
set -eu

PLUGIN_ID=${HINTS_PLUGIN_ID:-io.github.chris.window-hints}
HYPR=${HINTS_HYPRCTL:-hyprctl}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

ok() {
  printf '%s\n' "$1"
}

err() {
  printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$1")"
  exit 1
}

have_hypr() {
  command -v "$HYPR" >/dev/null 2>&1
}

run_hypr() {
  if ! have_hypr; then
    err "hyprctl missing"
  fi
  "$HYPR" "$@"
}

cmd_ping() {
  ok '{"ok":true,"pong":true,"helper":"compat"}'
}

cmd_snapshot() {
  clients=$(run_hypr -j clients) || err "clients failed"
  monitors=$(run_hypr -j monitors) || err "monitors failed"
  printf '{"ok":true,"clients":%s,"monitors":%s}\n' "$clients" "$monitors"
}

sanitize_alphabet() {
  raw=$1
  out=
  i=1
  len=${#raw}
  while [ "$i" -le "$len" ]; do
    ch=$(printf '%s' "$raw" | cut -c "$i" | tr 'A-Z' 'a-z')
    case "$ch" in
      [a-z])
        case "$out" in
          *"$ch"*) ;;
          *) out=$out$ch ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done
  if [ "${#out}" -lt 2 ]; then
    printf '%s' "asdfghjkl"
  else
    printf '%s' "$out"
  fi
}

lua_script() {
  alphabet=$(sanitize_alphabet "${1:-asdfghjkl}")
  printf '%s\n' "-- Window Hints submap. Generated from alphabet=${alphabet}."
  printf '%s\n' "hl.bind(\"SUPER + F\", hl.dsp.exec_cmd(\"omarchy-shell shell toggle ${PLUGIN_ID} '{}'\"))"
  printf '%s\n' "hl.define_submap(\"hints\", function()"
  i=1
  len=${#alphabet}
  has_x=0
  while [ "$i" -le "$len" ]; do
    ch=$(printf '%s' "$alphabet" | cut -c "$i")
    up=$(printf '%s' "$ch" | tr 'a-z' 'A-Z')
    printf '%s\n' "    hl.bind(\"${ch}\", hl.dsp.exec_cmd(\"omarchy-shell shell call ${PLUGIN_ID} key ${ch}\"))"
    printf '%s\n' "    hl.bind(\"SHIFT + ${ch}\", hl.dsp.exec_cmd(\"omarchy-shell shell call ${PLUGIN_ID} key ${up}\"))"
    [ "$ch" = "x" ] && has_x=1
    i=$((i + 1))
  done
  if [ "$has_x" -eq 0 ]; then
    printf '%s\n' "    hl.bind(\"x\", hl.dsp.exec_cmd(\"omarchy-shell shell call ${PLUGIN_ID} key x\"))"
  fi
  n=1
  while [ "$n" -le 9 ]; do
    printf '%s\n' "    hl.bind(\"${n}\", hl.dsp.exec_cmd(\"omarchy-shell shell call ${PLUGIN_ID} key ${n}\"))"
    n=$((n + 1))
  done
  printf '%s\n' "    hl.bind(\"escape\", function()"
  printf '%s\n' "        hl.dispatch(hl.dsp.exec_cmd(\"omarchy-shell shell call ${PLUGIN_ID} key escape\"))"
  printf '%s\n' "        hl.dispatch(hl.dsp.submap(\"reset\"))"
  printf '%s\n' "    end)"
  printf '%s\n' "    hl.bind(\"catchall\", hl.dsp.no_op())"
  printf '%s\n' "end)"
}

cmd_submap() {
  action=${1:-status}
  alphabet=$(sanitize_alphabet "${2:-asdfghjkl}")
  case "$action" in
    script) lua_script "$alphabet" ;;
    install)
      script=$(lua_script "$alphabet" | sed '/^--/d')
      if have_hypr && "$HYPR" eval "$script" >/tmp/hints-ctl-eval.out 2>/tmp/hints-ctl-eval.err; then
        printf '{"ok":true,"installed":true,"via":"eval","alphabet":"%s"}\n' "$(json_escape "$alphabet")"
      else
        printf '{"ok":true,"installed":false,"via":"bindings.lua","alphabet":"%s","error":"hyprctl eval failed; paste bindings.lua"}\n' "$(json_escape "$alphabet")"
      fi
      ;;
    activate)
      run_hypr dispatch submap hints >/dev/null || err "submap activate failed"
      ok '{"ok":true,"submap":"hints"}'
      ;;
    reset)
      run_hypr dispatch submap reset >/dev/null || err "submap reset failed"
      ok '{"ok":true,"submap":"reset"}'
      ;;
    status)
      cur=$(run_hypr submap 2>/dev/null || printf 'unknown')
      printf '{"ok":true,"submap":"%s"}\n' "$(json_escape "$cur")"
      ;;
    *) err "unknown submap action: $action" ;;
  esac
}

cmd_swap_probe() {
  if ! have_hypr; then
    ok '{"ok":true,"capable":false,"reason":"no-hyprctl"}'
    return
  fi
  # Same dispatcher string QML uses. Dummy address: syntax accepted ⇒ capable.
  help=$("$HYPR" dispatch swapwindow address:0x0 2>&1 || true)
  case "$help" in
    *'l|r|u|d'*|*'l/r/u/d'*|[Ii]nvalid\ direction*)
      ok '{"ok":true,"capable":false,"reason":"directional-only"}'
      ;;
    *[Ii]nvalid\ window*|[Ww]indow\ not\ found*|*"couldn't find"*|*"no such window"*|*"unknown window"*)
      ok '{"ok":true,"capable":true,"reason":"dispatch-accepted-address"}'
      ;;
    *address:*)
      ok '{"ok":true,"capable":true,"reason":"dispatch-mentions-address"}'
      ;;
    *)
      ok '{"ok":true,"capable":false,"reason":"unknown"}'
      ;;
  esac
}

binds_collision() {
  mods=$1
  key=$2
  raw=$3
  mods_l=$(printf '%s' "$mods" | tr 'A-Z' 'a-z')
  key_l=$(printf '%s' "$key" | tr 'A-Z' 'a-z')
  printf '%s' "$raw" | awk -v mods="$mods_l" -v key="$key_l" '
    BEGIN { RS="{"; found=0 }
    {
      rec = tolower($0)
      if (index(rec, "\"key\": \"" key "\"") == 0 && index(rec, "\"key\":\"" key "\"") == 0) next
      modmask = 0
      if (match(rec, /"modmask":[ \t]*[0-9]+/)) {
        n = substr(rec, RSTART, RLENGTH)
        sub(/.*:/, "", n)
        gsub(/[ \t]/, "", n)
        modmask = n + 0
      }
      superbit = (int(modmask / 64) % 2 == 1)
      if (index(mods, "super") > 0) {
        if (superbit || index(rec, "super") > 0) { found=1; exit }
        next
      }
      if (index(rec, mods) > 0) { found=1; exit }
    }
    END { exit found ? 0 : 1 }
  '
}

cmd_binds_check() {
  mods=${1:-SUPER}
  key=${2:-F}
  if [ "$key" = ";" ]; then
    key="semicolon"
  fi
  if have_hypr; then
    raw=$("$HYPR" -j binds 2>/dev/null || printf '[]')
  else
    raw='[]'
  fi
  collision=false
  if binds_collision "$mods" "$key" "$raw"; then
    collision=true
  fi
  if [ "$collision" = true ]; then
    suggested="SUPER+H"
  else
    suggested="${mods}+${key}"
    if [ "$key" = "semicolon" ]; then
      suggested="${mods}+;"
    fi
  fi
  printf '{"ok":true,"collision":%s,"suggested":"%s","alternates":["SUPER+H","SUPER+;"]}\n' \
    "$collision" "$(json_escape "$suggested")"
}

cmd_dispatch() {
  verb=${1:-}
  addr=${2:-}
  ws=${3:-1}
  [ -n "$verb" ] && [ -n "$addr" ] || err "dispatch needs VERB ADDRESS"
  case "$addr" in
    0x*|0X*) ;;
    *) addr="0x$addr" ;;
  esac
  case "$verb" in
    focus) req="focuswindow address:$addr" ;;
    close) req="closewindow address:$addr" ;;
    swap) req="swapwindow address:$addr" ;;
    move) req="movetoworkspacesilent $ws,address:$addr" ;;
    *) err "unknown dispatch verb: $verb" ;;
  esac
  out=$(run_hypr dispatch $req) || err "dispatch failed"
  printf '{"ok":true,"dispatched":"%s","output":"%s"}\n' \
    "$(json_escape "$req")" "$(json_escape "$out")"
}

[ $# -gt 0 ] || { printf '%s\n' "usage: hints-ctl ping|snapshot|submap|swap-probe|binds-check|dispatch"; exit 2; }

cmd=$1
shift
case "$cmd" in
  ping) cmd_ping ;;
  snapshot) cmd_snapshot ;;
  submap) cmd_submap "${1:-status}" "${2:-asdfghjkl}" ;;
  swap-probe) cmd_swap_probe ;;
  binds-check) cmd_binds_check "${1:-SUPER}" "${2:-F}" ;;
  dispatch) cmd_dispatch "${1:-}" "${2:-}" "${3:-1}" ;;
  --version) printf 'hints-ctl 1.0.0 (compat)\n' ;;
  *) err "unknown command: $cmd" ;;
esac

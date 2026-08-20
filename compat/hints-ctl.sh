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

lua_script() {
  cat <<EOF
-- Window Hints submap. Paste into ~/.config/hypr/bindings.lua
hl.bind("SUPER + F", hl.dsp.exec_cmd("omarchy-shell shell toggle ${PLUGIN_ID} '{}'"))
hl.define_submap("hints", function()
    hl.bind("a", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key a"))
    hl.bind("SHIFT + a", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key A"))
    hl.bind("s", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key s"))
    hl.bind("SHIFT + s", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key S"))
    hl.bind("d", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key d"))
    hl.bind("SHIFT + d", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key D"))
    hl.bind("f", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key f"))
    hl.bind("SHIFT + f", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key F"))
    hl.bind("g", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key g"))
    hl.bind("SHIFT + g", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key G"))
    hl.bind("h", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key h"))
    hl.bind("SHIFT + h", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key H"))
    hl.bind("j", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key j"))
    hl.bind("SHIFT + j", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key J"))
    hl.bind("k", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key k"))
    hl.bind("SHIFT + k", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key K"))
    hl.bind("l", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key l"))
    hl.bind("SHIFT + l", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key L"))
    hl.bind("x", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key x"))
    hl.bind("1", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 1"))
    hl.bind("2", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 2"))
    hl.bind("3", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 3"))
    hl.bind("4", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 4"))
    hl.bind("5", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 5"))
    hl.bind("6", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 6"))
    hl.bind("7", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 7"))
    hl.bind("8", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 8"))
    hl.bind("9", hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key 9"))
    hl.bind("escape", function()
        hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell call ${PLUGIN_ID} key escape"))
        hl.dispatch(hl.dsp.submap("reset"))
    end)
    hl.bind("catchall", hl.dsp.no_op())
end)
EOF
}

cmd_submap() {
  action=${1:-status}
  case "$action" in
    script) lua_script ;;
    install)
      script=$(lua_script | sed '/^--/d')
      if have_hypr && "$HYPR" eval "$script" >/tmp/hints-ctl-eval.out 2>/tmp/hints-ctl-eval.err; then
        ok '{"ok":true,"installed":true,"via":"eval"}'
      else
        ok '{"ok":true,"installed":false,"via":"bindings.lua","error":"hyprctl eval failed; paste bindings.lua"}'
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
  ver=$(run_hypr version 2>/dev/null || printf '')
  case "$ver" in
    *[Hh]yprland*0.5[5-9]*|*[Hh]yprland*[1-9].*)
      ok '{"ok":true,"capable":true,"reason":"hyprland-0.55-target-swap"}'
      return
      ;;
  esac
  help=$(run_hypr dispatch swapwindow 2>&1 || true)
  case "$help" in
    *address*) ok '{"ok":true,"capable":true,"reason":"help-mentions-address"}' ;;
    *target*) ok '{"ok":true,"capable":true,"reason":"help-mentions-target"}' ;;
    *l\|r\|u\|d*|*direction*) ok '{"ok":true,"capable":false,"reason":"directional-only"}' ;;
    *) ok '{"ok":true,"capable":false,"reason":"unknown"}' ;;
  esac
}

cmd_binds_check() {
  mods=${1:-SUPER}
  key=${2:-F}
  raw=$(run_hypr -j binds 2>/dev/null || printf '[]')
  collision=false
  printf '%s' "$raw" | grep -qi "\"key\": *\"$key\"" && collision=true
  if [ "$collision" = true ]; then
    suggested="SUPER+H"
  else
    suggested="${mods}+${key}"
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
  submap) cmd_submap "${1:-status}" ;;
  swap-probe) cmd_swap_probe ;;
  binds-check) cmd_binds_check "${1:-SUPER}" "${2:-F}" ;;
  dispatch) cmd_dispatch "${1:-}" "${2:-}" "${3:-1}" ;;
  --version) printf 'hints-ctl 1.0.0 (compat)\n' ;;
  *) err "unknown command: $cmd" ;;
esac

#!/usr/bin/env python3
"""Install or remove the marked Window Hints block in ~/.config/hypr/bindings.lua.

Writes the Hyprland file directly. Never stages generated Lua under /tmp.
`--file` is fail-closed: XDG_RUNTIME_DIR must be a usable directory, the path
must live under it, and the file is opened O_NOFOLLOW as a user-owned regular
file. A missing or unusable XDG_RUNTIME_DIR is an error, not a /tmp fallback.
"""

from __future__ import annotations

import os
import stat
import sys



def _refuse_symlink(path: str) -> None:
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return
    if stat.S_ISLNK(st.st_mode):
        raise OSError("refusing symlink: %s" % path)
    if not stat.S_ISREG(st.st_mode):
        raise OSError("not a regular file: %s" % path)


def read_text_nofollow(path: str) -> str:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        data = os.read(fd, 4_000_000)
    finally:
        os.close(fd)
    return data.decode("utf-8")


def write_text_atomic(path: str, text: str) -> None:
    parent = os.path.dirname(path) or "."
    os.makedirs(parent, exist_ok=True)
    pst = os.lstat(parent)
    if stat.S_ISLNK(pst.st_mode):
        raise OSError("refusing symlink directory: %s" % parent)
    _refuse_symlink(path)
    fd, tmp = tempfile.mkstemp(prefix=".bindings.", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode):
            raise OSError("refusing to leave a symlink at %s" % path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

ALPHABET = "asdfghjkl"
FORBIDDEN = "SUPER+F"


def compact_keys(keys: str) -> str:
    s = "".join(str(keys or "").split()).upper()
    return s.replace("SEMICOLON", ";")


def is_forbidden_super_f(keys: str) -> bool:
    return compact_keys(keys) == FORBIDDEN


def lua_keys(spec: str) -> str:
    raw = str(spec or "").strip()
    if not raw:
        return "SUPER + H"
    norm = "".join(raw.split())
    idx = norm.rfind("+")
    if idx <= 0:
        return raw
    mods = norm[:idx].replace("+", " + ")
    key = norm[idx + 1 :]
    if key == ";":
        key = "semicolon"
    return f"{mods} + {key}"


def lua_block(keys: str) -> str:
    if not keys or is_forbidden_super_f(keys):
        return ""
    summon = lua_keys(keys)
    if compact_keys(summon) == FORBIDDEN:
        return ""
    lines = [
        f'hl.bind("{summon}", hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.chris.window-hints \'{{}}\'"))',
        'hl.define_submap("hints", function())',
    ]
    for ch in ALPHABET:
        lines.append(
            f'    hl.bind("{ch}", hl.dsp.exec_cmd("omarchy-shell window-hints key {ch}"))'
        )
        lines.append(
            f'    hl.bind("SHIFT + {ch}", hl.dsp.exec_cmd("omarchy-shell window-hints key {ch.upper()}"))'
        )
    lines.append(
        '    hl.bind("x", hl.dsp.exec_cmd("omarchy-shell window-hints key x"))'
    )
    for n in range(1, 10):
        lines.append(
            f'    hl.bind("{n}", hl.dsp.exec_cmd("omarchy-shell window-hints key {n}"))'
        )
    lines.extend(
        [
            '    hl.bind("escape", function()',
            '        hl.dispatch(hl.dsp.exec_cmd("omarchy-shell window-hints key escape"))',
            '        hl.dispatch(hl.dsp.submap("reset"))',
            "    end)",
            '    hl.bind("catchall", hl.dsp.no_op())',
            "end)",
        ]
    )
    body = "\n".join(lines) + "\n"
    if "hl.unbind" in body:
        return ""
    if "shell call" in body:
        return ""
    return body


def config_path() -> str:
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
        os.path.expanduser("~"), ".config"
    )
    return os.path.join(config_home, "hypr", "bindings.lua")


def fail(message: str, code: int = 1) -> int:
    print(message, file=sys.stderr)
    print(message)
    return code


def is_tmp_path(path: str) -> bool:
    abs_path = os.path.abspath(path)
    return (
        abs_path == "/tmp"
        or abs_path.startswith("/tmp/")
        or abs_path == "/var/tmp"
        or abs_path.startswith("/var/tmp/")
    )


def read_staged_lua(path: str) -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or ""
    if not runtime:
        raise RuntimeError(
            "error: XDG_RUNTIME_DIR is unset; refusing to stage Lua (no /tmp fallback)"
        )
    if not os.path.isdir(runtime) or not os.access(runtime, os.W_OK | os.X_OK):
        raise RuntimeError(
            "error: XDG_RUNTIME_DIR is unusable; refusing to stage Lua (no /tmp fallback)"
        )
    abs_path = os.path.abspath(path)
    if is_tmp_path(abs_path):
        raise RuntimeError("error: refusing to read staged Lua from /tmp")
    runtime_abs = os.path.abspath(runtime)
    if abs_path != runtime_abs and not abs_path.startswith(runtime_abs + os.sep):
        raise RuntimeError("error: staged Lua must be under XDG_RUNTIME_DIR")
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(abs_path, flags)
    except OSError as exc:
        raise RuntimeError(f"error: cannot open staged Lua: {exc}") from exc
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise RuntimeError("error: staged Lua is not a regular file")
        if st.st_uid != os.getuid():
            raise RuntimeError("error: staged Lua is not owned by the current user")
        data = b""
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            data += chunk
            if len(data) > 1_000_000:
                raise RuntimeError("error: staged Lua is too large")
    finally:
        os.close(fd)
    return data.decode("utf-8")


def apply_block(plugin_id: str, block: str, remove: bool) -> int:
    if "hl.unbind" in block:
        return fail("error: refusing to write hl.unbind")
    path = config_path()
    begin = f"-- BEGIN {plugin_id}"
    end = f"-- END {plugin_id}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = ""
    if os.path.islink(path):
        print("error: refusing symlink %s" % path, file=sys.stderr)
        return 1
    if os.path.isfile(path):
        text = read_text_nofollow(path)
    if begin in text and end in text:
        pre = text[: text.index(begin)]
        post = text[text.index(end) + len(end) :].lstrip("\n")
        text = pre.rstrip()
        if not remove:
            if not block.endswith("\n"):
                block += "\n"
            chunk = f"{begin}\n{block}{end}\n"
            text = text + "\n\n" + chunk
        else:
            text = text + "\n"
        if post:
            text = text.rstrip() + "\n" + post
            if not text.endswith("\n"):
                text += "\n"
        elif text and not text.endswith("\n"):
            text += "\n"
    elif remove:
        if text and not text.endswith("\n"):
            text += "\n"
    else:
        if not block.endswith("\n"):
            block += "\n"
        chunk = f"{begin}\n{block}{end}\n"
        if text and not text.endswith("\n"):
            text += "\n"
        text = text.rstrip() + "\n\n" + chunk
        if not text.endswith("\n"):
            text += "\n"
    write_text_atomic(path, text)
    print("ok")
    return 0


def usage() -> int:
    return fail(
        "usage: install-binds.py PLUGIN_ID --summon KEYS|--remove|--stdin|--file PATH|LUA_BLOCK",
        2,
    )


def main() -> int:
    if len(sys.argv) < 3:
        return usage()
    plugin_id = sys.argv[1]
    action = sys.argv[2]
    if action == "--remove":
        return apply_block(plugin_id, "", True)
    if action == "--summon":
        if len(sys.argv) < 4:
            return usage()
        keys = sys.argv[3]
        if is_forbidden_super_f(keys):
            return fail("error: refusing SUPER+F (Omarchy fullscreen)")
        block = lua_block(keys)
        if not block:
            return fail("error: empty or forbidden lua block")
        return apply_block(plugin_id, block, False)
    if action == "--stdin":
        block = sys.stdin.read()
        if not block.strip():
            return fail("error: empty stdin")
        if is_forbidden_super_f(block) or "hl.bind(\"SUPER + F\"" in block:
            return fail("error: refusing SUPER+F (Omarchy fullscreen)")
        return apply_block(plugin_id, block, False)
    if action == "--file":
        if len(sys.argv) < 4:
            return usage()
        try:
            block = read_staged_lua(sys.argv[3])
        except RuntimeError as exc:
            return fail(str(exc))
        if not block.strip():
            return fail("error: staged Lua is empty")
        if "hl.bind(\"SUPER + F\"" in block or is_forbidden_super_f(block):
            return fail("error: refusing SUPER+F (Omarchy fullscreen)")
        return apply_block(plugin_id, block, False)
    # Legacy: LUA_BLOCK as a single argv. Multiline Process argv is unreliable
    # in Quickshell, so Service uses --summon instead of this path.
    block = action
    if is_tmp_path(block):
        return fail("error: refusing to treat a /tmp path as a Lua block")
    if not block.endswith("\n"):
        block += "\n"
    if "hl.bind(\"SUPER + F\"" in block:
        return fail("error: refusing SUPER+F (Omarchy fullscreen)")
    return apply_block(plugin_id, block, False)


if __name__ == "__main__":
    raise SystemExit(main())

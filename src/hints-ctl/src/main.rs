//! hints-ctl — Hyprland helper for Window Hints.
//!
//! The QML service talks to Hyprland directly when this binary is missing
//! (`compat/hints-ctl.sh` is the POSIX fallback). Commands:
//!
//!   hints-ctl ping
//!   hints-ctl snapshot
//!   hints-ctl submap install|reset|activate|status|script
//!   hints-ctl swap-probe
//!   hints-ctl binds-check [MOD] [KEY]
//!   hints-ctl dispatch focus|close|swap|move ADDR [WORKSPACE]
//!
//! HINTS_HYPRCTL overrides the hyprctl binary (tests). HINTS_PLUGIN_ID
//! overrides the IPC plugin id.

mod hypr;
mod submap;
mod swap;
mod binds;

use std::env;
use std::io::{self, Write};
use std::process;

const PLUGIN_ID: &str = "io.github.chris.window-hints";

fn plugin_id() -> String {
    env::var("HINTS_PLUGIN_ID").unwrap_or_else(|_| PLUGIN_ID.to_string())
}

fn json_escape(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn ok_json(fields: &[(&str, String)]) -> String {
    let mut body = String::from("{\"ok\":true");
    for (k, v) in fields {
        body.push_str(",\"");
        body.push_str(k);
        body.push_str("\":");
        body.push_str(v);
    }
    body.push('}');
    body
}

fn err_json(msg: &str) -> String {
    format!("{{\"ok\":false,\"error\":{}}}", json_escape(msg))
}

fn main() {
    let mut args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        print_usage();
        process::exit(0);
    }
    if args[0] == "--version" {
        println!("hints-ctl 1.0.0");
        process::exit(0);
    }

    let cmd = args.remove(0);
    let result = match cmd.as_str() {
        "ping" => Ok(ok_json(&[("pong", "true".into())])),
        "snapshot" => cmd_snapshot(),
        "submap" => cmd_submap(&args),
        "swap-probe" => cmd_swap_probe(),
        "binds-check" => cmd_binds_check(&args),
        "dispatch" => cmd_dispatch(&args),
        other => Err(format!("unknown command: {other}")),
    };

    match result {
        Ok(body) => {
            let mut stdout = io::stdout().lock();
            let _ = writeln!(stdout, "{body}");
        }
        Err(msg) => {
            let mut stdout = io::stdout().lock();
            let _ = writeln!(stdout, "{}", err_json(&msg));
            process::exit(1);
        }
    }
}

fn print_usage() {
    eprintln!(
        "usage:
  hints-ctl ping
  hints-ctl snapshot
  hints-ctl submap install|reset|activate|status|script
  hints-ctl swap-probe
  hints-ctl binds-check [MOD] [KEY]
  hints-ctl dispatch focus|close|swap|move ADDR [WORKSPACE]"
    );
}

fn cmd_snapshot() -> Result<String, String> {
    let clients = hypr::hyprctl(&["-j", "clients"])?;
    let monitors = hypr::hyprctl(&["-j", "monitors"])?;
    Ok(format!(
        "{{\"ok\":true,\"clients\":{clients},\"monitors\":{monitors}}}"
    ))
}

fn cmd_submap(args: &[String]) -> Result<String, String> {
    let action = args.first().map(String::as_str).unwrap_or("status");
    let bind = args
        .get(1)
        .map(String::as_str)
        .filter(|s| !s.is_empty())
        .unwrap_or("SUPER+H");
    let id = plugin_id();
    match action {
        "script" => Ok(submap::lua_script(&id, bind)),
        "install" => {
            let script = submap::eval_install(&id, bind);
            match hypr::hyprctl(&["eval", &script]) {
                Ok(out) => Ok(ok_json(&[
                    ("installed", "true".into()),
                    ("via", json_escape("eval")),
                    ("output", json_escape(&out)),
                ])),
                Err(eval_err) => {
                    let batch = submap::keyword_batch(&id, bind);
                    match hypr::hyprctl(&["--batch", &batch]) {
                        Ok(out) => Ok(ok_json(&[
                            ("installed", "true".into()),
                            ("via", json_escape("keyword")),
                            ("output", json_escape(&out)),
                        ])),
                        Err(kw_err) => Ok(ok_json(&[
                            ("installed", "false".into()),
                            ("via", json_escape("bindings.lua")),
                            ("error", json_escape(&format!("{eval_err}; {kw_err}"))),
                        ])),
                    }
                }
            }
        }
        "activate" => {
            hypr::dispatch_submap("hints")?;
            Ok(ok_json(&[("submap", json_escape("hints"))]))
        }
        "reset" => {
            hypr::dispatch_submap("reset")?;
            Ok(ok_json(&[("submap", json_escape("reset"))]))
        }
        "status" => {
            let raw = hypr::hyprctl(&["submap"]).unwrap_or_default();
            Ok(ok_json(&[("submap", json_escape(raw.trim()))]))
        }
        other => Err(format!("unknown submap action: {other}")),
    }
}

fn cmd_swap_probe() -> Result<String, String> {
    let result = swap::probe();
    Ok(format!(
        "{{\"ok\":true,\"capable\":{},\"reason\":{}}}",
        if result.capable { "true" } else { "false" },
        json_escape(&result.reason)
    ))
}

fn cmd_binds_check(args: &[String]) -> Result<String, String> {
    let mods = args.first().map(String::as_str).unwrap_or("SUPER");
    let key = args.get(1).map(String::as_str).unwrap_or("F");
    let raw = hypr::hyprctl(&["-j", "binds"]).unwrap_or_else(|_| "[]".into());
    let hit = binds::collision(&raw, mods, key);
    let original = if key == "semicolon" {
        format!("{mods}+;")
    } else {
        format!("{mods}+{key}")
    };
    let suggested = if hit {
        binds::first_free_alternate(&raw).unwrap_or(original)
    } else {
        original
    };
    Ok(format!(
        "{{\"ok\":true,\"collision\":{},\"suggested\":{},\"alternates\":[\"SUPER+H\",\"SUPER+;\"]}}",
        if hit { "true" } else { "false" },
        json_escape(&suggested)
    ))
}

fn dispatch_lua_expr(verb: &str, addr: &str, workspace: Option<&str>) -> Result<String, String> {
    let addr = binds::normalize_address(addr);
    match verb {
        "focus" => Ok(format!(r#"hl.dsp.focus({{ window = "address:{addr}" }})"#)),
        "close" => Ok(format!(r#"hl.dsp.window.close({{ window = "address:{addr}" }})"#)),
        "swap" => Ok(format!(r#"hl.dsp.window.swap({{ target = "address:{addr}" }})"#)),
        "move" => {
            let ws = workspace.unwrap_or("1");
            Ok(format!(
                r#"hl.dsp.window.move({{ workspace = "{ws}", follow = false, window = "address:{addr}" }})"#
            ))
        }
        other => Err(format!("unknown dispatch verb: {other}")),
    }
}

fn cmd_dispatch(args: &[String]) -> Result<String, String> {
    if args.len() < 2 {
        return Err("dispatch needs VERB ADDRESS".into());
    }
    let expr = dispatch_lua_expr(args[0].as_str(), &args[1], args.get(2).map(String::as_str))?;
    let out = hypr::dispatch_lua(&expr)?;
    Ok(ok_json(&[
        ("dispatched", json_escape(&expr)),
        ("output", json_escape(&out)),
    ]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_escape_quotes() {
        assert_eq!(json_escape("a\"b"), "\"a\\\"b\"");
    }

    #[test]
    fn err_json_shape() {
        let s = err_json("nope");
        assert!(s.contains("\"ok\":false"));
        assert!(s.contains("nope"));
    }

    #[test]
    fn dispatch_lua_expr_is_single_table() {
        assert_eq!(
            dispatch_lua_expr("focus", "AAA", None).unwrap(),
            r#"hl.dsp.focus({ window = "address:0xaaa" })"#
        );
        assert_eq!(
            dispatch_lua_expr("close", "0x1", None).unwrap(),
            r#"hl.dsp.window.close({ window = "address:0x1" })"#
        );
        assert_eq!(
            dispatch_lua_expr("swap", "0x1", None).unwrap(),
            r#"hl.dsp.window.swap({ target = "address:0x1" })"#
        );
        assert_eq!(
            dispatch_lua_expr("move", "0x1", Some("3")).unwrap(),
            r#"hl.dsp.window.move({ workspace = "3", follow = false, window = "address:0x1" })"#
        );
        assert!(dispatch_lua_expr("explode", "0x1", None).is_err());
    }
}

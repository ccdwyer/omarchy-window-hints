/// Fixed v1.0 home-row alphabet. Excludes reserved verb keys: `x` (close),
/// digits (workspace move), and is prefix-free for one- and two-key chords.
pub const ALPHABET: &str = "asdfghjkl";

pub fn format_lua_bind(spec: &str) -> String {
    let compact: String = spec.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.is_empty() || !compact.contains('+') {
        return "SUPER + F".into();
    }
    let idx = compact.rfind('+').unwrap();
    let mods = compact[..idx].replace('+', " + ");
    let mut key = compact[idx + 1..].to_string();
    if key.is_empty() {
        key = "F".into();
    }
    if key == ";" {
        key = "semicolon".into();
    }
    if mods.is_empty() {
        return format!("SUPER + {key}");
    }
    format!("{mods} + {key}")
}

pub fn format_keyword_bind(spec: &str) -> (String, String) {
    let compact: String = spec.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.is_empty() || !compact.contains('+') {
        return ("SUPER".into(), "F".into());
    }
    let idx = compact.rfind('+').unwrap();
    let mods = compact[..idx].replace('+', "_");
    let mut key = compact[idx + 1..].to_string();
    if key.is_empty() {
        key = "F".into();
    }
    if key == ";" {
        key = "semicolon".into();
    }
    let mods = if mods.is_empty() {
        "SUPER".into()
    } else {
        mods
    };
    (mods, key)
}

pub fn lua_script(plugin_id: &str, bind: &str) -> String {
    let lua_bind = format_lua_bind(bind);
    let mut body = String::new();
    body.push_str("-- Window Hints submap. Fixed alphabet asdfghjkl (v1.0).\n");
    body.push_str("-- Toggle bind is suggestedBind (default SUPER+F).\n");
    body.push_str("hl.bind(\"");
    body.push_str(&lua_bind);
    body.push_str("\", hl.dsp.exec_cmd(\"omarchy-shell shell toggle ");
    body.push_str(plugin_id);
    body.push_str(" '{}'\"))\n");
    body.push_str("hl.define_submap(\"hints\", function()\n");
    for ch in ALPHABET.chars() {
        body.push_str(&bind_line(&ch.to_string(), &ch.to_string(), 4));
        let up = ch.to_uppercase().to_string();
        body.push_str(&bind_line(&format!("SHIFT + {ch}"), &up, 4));
    }
    body.push_str(&bind_line("x", "x", 4));
    for d in 1..=9 {
        body.push_str(&bind_line(&d.to_string(), &d.to_string(), 4));
    }
    body.push_str("    hl.bind(\"escape\", function()\n");
    body.push_str("        hl.dispatch(hl.dsp.exec_cmd(\"omarchy-shell window-hints key escape\"))\n");
    body.push_str("        hl.dispatch(hl.dsp.submap(\"reset\"))\n");
    body.push_str("    end)\n");
    body.push_str("    hl.bind(\"catchall\", hl.dsp.no_op())\n");
    body.push_str("end)\n");
    body
}

fn bind_line(keys: &str, payload: &str, indent: usize) -> String {
    let pad = " ".repeat(indent);
    format!(
        "{pad}hl.bind(\"{keys}\", hl.dsp.exec_cmd(\"omarchy-shell window-hints key {payload}\"))\n"
    )
}

pub fn eval_install(plugin_id: &str, bind: &str) -> String {
    lua_script(plugin_id, bind)
        .lines()
        .filter(|l| !l.trim_start().starts_with("--") && !l.trim().is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn keyword_batch(plugin_id: &str, bind: &str) -> String {
    let (mods, key) = format_keyword_bind(bind);
    let mut parts: Vec<String> = Vec::new();
    parts.push(format!(
        "keyword bind {mods},{key},exec,omarchy-shell shell toggle {plugin_id} '{{}}'"
    ));
    parts.push("keyword submap hints".into());
    for ch in ALPHABET.chars() {
        parts.push(format!(
            "keyword bind ,{ch},exec,omarchy-shell window-hints key {ch}"
        ));
        let up = ch.to_uppercase().next().unwrap_or(ch);
        parts.push(format!(
            "keyword bind SHIFT,{ch},exec,omarchy-shell window-hints key {up}"
        ));
    }
    parts.push("keyword bind ,x,exec,omarchy-shell window-hints key x".into());
    for d in 1..=9 {
        parts.push(format!(
            "keyword bind ,{d},exec,omarchy-shell window-hints key {d}"
        ));
    }
    parts.push("keyword bind ,escape,exec,omarchy-shell window-hints key escape".into());
    parts.push("keyword bind ,escape,submap,reset".into());
    parts.push("keyword bind ,catchall,exec,true".into());
    parts.push("keyword submap reset".into());
    parts.join(" ; ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lua_contains_escape_reset() {
        let s = lua_script("io.github.chris.window-hints", "SUPER+F");
        assert!(s.contains("hl.define_submap(\"hints\""));
        assert!(s.contains("hl.dsp.submap(\"reset\")"));
        assert!(s.contains("catchall"));
        assert!(s.contains("SUPER + F"));
        assert!(s.contains("omarchy-shell window-hints key a"));
        assert!(s.contains("omarchy-shell window-hints key A"));
        assert!(s.contains("omarchy-shell window-hints key 3"));
        assert!(s.contains("omarchy-shell window-hints key x"));
        assert!(!s.contains("shell call"));
        assert!(!ALPHABET.contains('x'));
        assert!(!ALPHABET.chars().any(|c| c.is_ascii_digit()));
    }

    #[test]
    fn lua_uses_suggested_bind() {
        let s = lua_script("io.github.chris.window-hints", "SUPER+H");
        assert!(s.contains("SUPER + H"));
        assert!(!s.contains("SUPER + F"));
        let semi = lua_script("io.github.chris.window-hints", "SUPER+;");
        assert!(semi.contains("SUPER + semicolon"));
    }

    #[test]
    fn lua_ignores_custom_alphabet_arg_is_fixed() {
        let s = lua_script("io.github.chris.window-hints", "SUPER+F");
        assert!(s.contains("hl.bind(\"a\""));
        assert!(s.contains("hl.bind(\"l\""));
        assert!(!s.contains("hl.bind(\"q\""));
    }

    #[test]
    fn format_lua_bind_defaults_without_plus() {
        assert_eq!(format_lua_bind("qwer"), "SUPER + F");
        assert_eq!(format_lua_bind(""), "SUPER + F");
        assert_eq!(format_lua_bind("SUPER + H"), "SUPER + H");
    }

    #[test]
    fn keyword_batch_resets() {
        let s = keyword_batch("io.github.chris.window-hints", "SUPER+F");
        assert!(s.contains("submap reset"));
        assert!(s.contains("submap hints"));
        assert!(s.contains("key escape"));
        assert!(s.contains(",a,exec,"));
        assert!(s.contains(",x,exec,"));
        assert!(s.contains("SUPER,F,exec,omarchy-shell shell toggle"));
    }

    #[test]
    fn keyword_batch_uses_suggested_bind() {
        let s = keyword_batch("io.github.chris.window-hints", "SUPER+H");
        assert!(s.contains("SUPER,H,exec,omarchy-shell shell toggle"));
        assert!(!s.contains("SUPER,F,exec,omarchy-shell shell toggle"));
    }
}

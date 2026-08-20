const DEFAULT_ALPHABET: &str = "asdfghjkl";

pub fn sanitize_alphabet(raw: &str) -> String {
    let mut out = String::new();
    let mut seen = [false; 26];
    for c in raw.chars() {
        let c = c.to_ascii_lowercase();
        if c.is_ascii_lowercase() {
            let i = (c as u8 - b'a') as usize;
            if !seen[i] {
                seen[i] = true;
                out.push(c);
            }
        }
    }
    if out.len() < 2 {
        DEFAULT_ALPHABET.into()
    } else {
        out
    }
}

pub fn lua_script(plugin_id: &str, alphabet: &str) -> String {
    let alphabet = sanitize_alphabet(alphabet);
    let mut body = String::new();
    body.push_str("-- Window Hints submap. Generated from the active alphabet.\n");
    body.push_str("hl.bind(\"SUPER + F\", hl.dsp.exec_cmd(\"omarchy-shell shell toggle ");
    body.push_str(plugin_id);
    body.push_str(" '{}'\"))\n");
    body.push_str("hl.define_submap(\"hints\", function()\n");
    for ch in alphabet.chars() {
        body.push_str(&bind_line(plugin_id, &ch.to_string(), &ch.to_string(), 4));
        let up = ch.to_uppercase().to_string();
        body.push_str(&bind_line(plugin_id, &format!("SHIFT + {ch}"), &up, 4));
    }
    if !alphabet.contains('x') {
        body.push_str(&bind_line(plugin_id, "x", "x", 4));
    }
    for d in 1..=9 {
        body.push_str(&bind_line(plugin_id, &d.to_string(), &d.to_string(), 4));
    }
    body.push_str("    hl.bind(\"escape\", function()\n");
    body.push_str("        hl.dispatch(hl.dsp.exec_cmd(\"omarchy-shell shell call ");
    body.push_str(plugin_id);
    body.push_str(" key escape\"))\n");
    body.push_str("        hl.dispatch(hl.dsp.submap(\"reset\"))\n");
    body.push_str("    end)\n");
    body.push_str("    hl.bind(\"catchall\", hl.dsp.no_op())\n");
    body.push_str("end)\n");
    body
}

fn bind_line(plugin_id: &str, keys: &str, payload: &str, indent: usize) -> String {
    let pad = " ".repeat(indent);
    format!(
        "{pad}hl.bind(\"{keys}\", hl.dsp.exec_cmd(\"omarchy-shell shell call {plugin_id} key {payload}\"))\n"
    )
}

pub fn eval_install(plugin_id: &str, alphabet: &str) -> String {
    lua_script(plugin_id, alphabet)
        .lines()
        .filter(|l| !l.trim_start().starts_with("--") && !l.trim().is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn keyword_batch(plugin_id: &str, alphabet: &str) -> String {
    let alphabet = sanitize_alphabet(alphabet);
    let mut parts: Vec<String> = Vec::new();
    parts.push("keyword submap hints".into());
    for ch in alphabet.chars() {
        parts.push(format!(
            "keyword bind ,{ch},exec,omarchy-shell shell call {plugin_id} key {ch}"
        ));
        let up = ch.to_uppercase().next().unwrap_or(ch);
        parts.push(format!(
            "keyword bind SHIFT,{ch},exec,omarchy-shell shell call {plugin_id} key {up}"
        ));
    }
    if !alphabet.contains('x') {
        parts.push(format!(
            "keyword bind ,x,exec,omarchy-shell shell call {plugin_id} key x"
        ));
    }
    for d in 1..=9 {
        parts.push(format!(
            "keyword bind ,{d},exec,omarchy-shell shell call {plugin_id} key {d}"
        ));
    }
    parts.push(format!(
        "keyword bind ,escape,exec,omarchy-shell shell call {plugin_id} key escape"
    ));
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
        let s = lua_script("io.github.chris.window-hints", "asdfghjkl");
        assert!(s.contains("hl.define_submap(\"hints\""));
        assert!(s.contains("hl.dsp.submap(\"reset\")"));
        assert!(s.contains("catchall"));
        assert!(s.contains("SUPER + F"));
        assert!(s.contains("key a"));
        assert!(s.contains("key A"));
        assert!(s.contains("key 3"));
        assert!(s.contains("key x"));
    }

    #[test]
    fn lua_uses_active_alphabet() {
        let s = lua_script("io.github.chris.window-hints", "qwer");
        assert!(s.contains("key q"));
        assert!(s.contains("key w"));
        assert!(s.contains("SHIFT + q"));
        assert!(!s.contains("key a)"));
        assert!(s.contains("key x"));
    }

    #[test]
    fn keyword_batch_resets() {
        let s = keyword_batch("io.github.chris.window-hints", "asdfghjkl");
        assert!(s.contains("submap reset"));
        assert!(s.contains("submap hints"));
        assert!(s.contains("key escape"));
    }

    #[test]
    fn keyword_batch_custom_alphabet() {
        let s = keyword_batch("io.github.chris.window-hints", "aoeu");
        assert!(s.contains(",a,exec,"));
        assert!(s.contains(",o,exec,"));
        assert!(s.contains(",e,exec,"));
        assert!(s.contains(",u,exec,"));
        assert!(!s.contains(",s,exec,"));
    }
}

pub fn normalize_address(value: &str) -> String {
    let s = value.trim().to_lowercase();
    if s.is_empty() {
        return String::new();
    }
    if s.starts_with("0x") {
        s
    } else {
        format!("0x{s}")
    }
}

fn has_key(raw: &str, key_l: &str) -> bool {
    raw.contains(&format!("\"key\": \"{key_l}\"")) || raw.contains(&format!("\"key\":\"{key_l}\""))
}

fn contains_mod_key(raw: &str, mods: &str, key: &str) -> bool {
    let lower = raw.to_lowercase();
    let mods_l = mods.to_lowercase();
    let key_l = key.to_lowercase();
    if lower.contains(&format!("{mods_l}+{key_l}")) {
        return true;
    }
    if !has_key(&lower, &key_l) {
        return false;
    }
    if mods_l == "super" {
        return lower.contains("super")
            || lower.contains("\"modmask\":64")
            || lower.contains("\"modmask\": 64")
            || lower.contains("\"modmask\": 64,");
    }
    lower.contains(&mods_l)
}

pub fn collision(raw: &str, mods: &str, key: &str) -> bool {
    contains_mod_key(raw, mods, key)
}

pub fn first_free_alternate(raw: &str) -> Option<String> {
    for (mods, key, label) in [("SUPER", "H", "SUPER+H"), ("SUPER", "semicolon", "SUPER+;")] {
        if !collision(raw, mods, key) {
            return Some(label.into());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn address_prefix() {
        assert_eq!(normalize_address("ABC"), "0xabc");
        assert_eq!(normalize_address("0xFF"), "0xff");
    }

    #[test]
    fn detects_super_f() {
        let json = r#"[{"modmask":64,"key":"F","dispatcher":"exec","arg":"thunar"}]"#;
        assert!(collision(json, "SUPER", "F"));
        assert!(!collision("[]", "SUPER", "F"));
        let bare = r#"[{"modmask":0,"key":"F","dispatcher":"exec","arg":"x"}]"#;
        assert!(!collision(bare, "SUPER", "F"));
    }

    #[test]
    fn alternate_when_f_taken() {
        let json = r#"[{"key":"F","modmask":64}]"#;
        assert_eq!(first_free_alternate(json).as_deref(), Some("SUPER+H"));
    }
}

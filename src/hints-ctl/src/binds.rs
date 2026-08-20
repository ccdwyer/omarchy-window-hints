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

const SUPER_MASK: u32 = 64;

struct BindRec {
    key: String,
    modmask: u32,
}

fn skip_ws(bytes: &[u8], i: &mut usize) {
    while *i < bytes.len() && bytes[*i].is_ascii_whitespace() {
        *i += 1;
    }
}

fn parse_json_string(bytes: &[u8], i: &mut usize) -> Option<String> {
    if *i >= bytes.len() || bytes[*i] != b'"' {
        return None;
    }
    *i += 1;
    let mut out = String::new();
    while *i < bytes.len() {
        let c = bytes[*i];
        *i += 1;
        if c == b'"' {
            return Some(out);
        }
        if c == b'\\' {
            if *i >= bytes.len() {
                return None;
            }
            let e = bytes[*i];
            *i += 1;
            match e {
                b'"' | b'\\' | b'/' => out.push(e as char),
                b'n' => out.push('\n'),
                b'r' => out.push('\r'),
                b't' => out.push('\t'),
                _ => out.push(e as char),
            }
        } else {
            out.push(c as char);
        }
    }
    None
}

fn parse_json_u32(bytes: &[u8], i: &mut usize) -> Option<u32> {
    skip_ws(bytes, i);
    let start = *i;
    while *i < bytes.len() && bytes[*i].is_ascii_digit() {
        *i += 1;
    }
    if start == *i {
        return None;
    }
    std::str::from_utf8(&bytes[start..*i])
        .ok()
        .and_then(|s| s.parse().ok())
}

fn skip_json_value(bytes: &[u8], i: &mut usize) {
    skip_ws(bytes, i);
    if *i >= bytes.len() {
        return;
    }
    match bytes[*i] {
        b'"' => {
            let _ = parse_json_string(bytes, i);
        }
        b'{' => {
            *i += 1;
            let mut depth = 1u32;
            let mut in_str = false;
            let mut esc = false;
            while *i < bytes.len() && depth > 0 {
                let c = bytes[*i];
                *i += 1;
                if in_str {
                    if esc {
                        esc = false;
                    } else if c == b'\\' {
                        esc = true;
                    } else if c == b'"' {
                        in_str = false;
                    }
                    continue;
                }
                match c {
                    b'"' => in_str = true,
                    b'{' => depth += 1,
                    b'}' => depth -= 1,
                    _ => {}
                }
            }
        }
        b'[' => {
            *i += 1;
            let mut depth = 1u32;
            let mut in_str = false;
            let mut esc = false;
            while *i < bytes.len() && depth > 0 {
                let c = bytes[*i];
                *i += 1;
                if in_str {
                    if esc {
                        esc = false;
                    } else if c == b'\\' {
                        esc = true;
                    } else if c == b'"' {
                        in_str = false;
                    }
                    continue;
                }
                match c {
                    b'"' => in_str = true,
                    b'[' => depth += 1,
                    b']' => depth -= 1,
                    _ => {}
                }
            }
        }
        b't' | b'f' | b'n' => {
            while *i < bytes.len() && bytes[*i].is_ascii_alphabetic() {
                *i += 1;
            }
        }
        b'-' | b'0'..=b'9' => {
            *i += 1;
            while *i < bytes.len() && (bytes[*i].is_ascii_digit() || bytes[*i] == b'.') {
                *i += 1;
            }
        }
        _ => *i += 1,
    }
}

fn parse_one_object(bytes: &[u8], i: &mut usize) -> Option<BindRec> {
    skip_ws(bytes, i);
    if *i >= bytes.len() || bytes[*i] != b'{' {
        return None;
    }
    *i += 1;
    let mut key = String::new();
    let mut modmask = 0u32;
    loop {
        skip_ws(bytes, i);
        if *i >= bytes.len() {
            break;
        }
        if bytes[*i] == b'}' {
            *i += 1;
            break;
        }
        if bytes[*i] == b',' {
            *i += 1;
            continue;
        }
        let field = match parse_json_string(bytes, i) {
            Some(s) => s,
            None => {
                skip_json_value(bytes, i);
                continue;
            }
        };
        skip_ws(bytes, i);
        if *i < bytes.len() && bytes[*i] == b':' {
            *i += 1;
        }
        skip_ws(bytes, i);
        if field == "key" {
            if let Some(v) = parse_json_string(bytes, i) {
                key = v;
            } else {
                skip_json_value(bytes, i);
            }
        } else if field == "modmask" {
            if let Some(n) = parse_json_u32(bytes, i) {
                modmask = n;
            } else {
                skip_json_value(bytes, i);
            }
        } else {
            skip_json_value(bytes, i);
        }
    }
    if key.is_empty() {
        return None;
    }
    Some(BindRec { key, modmask })
}

fn parse_bind_records(raw: &str) -> Vec<BindRec> {
    let bytes = raw.as_bytes();
    let mut i = 0usize;
    skip_ws(bytes, &mut i);
    let mut out = Vec::new();
    if i < bytes.len() && bytes[i] == b'[' {
        i += 1;
        loop {
            skip_ws(bytes, &mut i);
            if i >= bytes.len() || bytes[i] == b']' {
                break;
            }
            if bytes[i] == b',' {
                i += 1;
                continue;
            }
            if let Some(rec) = parse_one_object(bytes, &mut i) {
                out.push(rec);
            } else {
                skip_json_value(bytes, &mut i);
            }
        }
        return out;
    }
    while i < bytes.len() {
        skip_ws(bytes, &mut i);
        if i >= bytes.len() {
            break;
        }
        if bytes[i] == b'{' {
            if let Some(rec) = parse_one_object(bytes, &mut i) {
                out.push(rec);
            } else {
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    out
}

fn mods_want_super(mods: &str) -> bool {
    mods.to_ascii_lowercase().contains("super")
}

pub fn collision(raw: &str, mods: &str, key: &str) -> bool {
    let want_key = key.to_ascii_lowercase();
    let super_needed = mods_want_super(mods);
    for rec in parse_bind_records(raw) {
        if rec.key.to_ascii_lowercase() != want_key {
            continue;
        }
        let has_super = rec.modmask & SUPER_MASK != 0;
        if super_needed {
            if has_super {
                return true;
            }
        } else if rec.modmask == 0 {
            return true;
        }
    }
    false
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
    fn unrelated_key_and_modmask_are_not_a_hit() {
        let json = r#"[
            {"modmask":0,"key":"F","dispatcher":"exec","arg":"bare-f"},
            {"modmask":64,"key":"Q","dispatcher":"exec","arg":"contains key F and \"modmask\":64"}
        ]"#;
        assert!(!collision(json, "SUPER", "F"));
        assert!(collision(json, "SUPER", "Q"));
    }

    #[test]
    fn spaced_fields_still_parse_per_record() {
        let json = r#"[{ "modmask": 64, "key": "F" }]"#;
        assert!(collision(json, "SUPER", "F"));
    }

    #[test]
    fn alternate_when_f_taken() {
        let json = r#"[{"key":"F","modmask":64}]"#;
        assert_eq!(first_free_alternate(json).as_deref(), Some("SUPER+H"));
    }
}

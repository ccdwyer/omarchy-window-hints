use crate::hypr;

pub struct Probe {
    pub capable: bool,
    pub reason: String,
}

pub fn parse_help(text: &str) -> Probe {
    let lower = text.to_lowercase();
    if lower.contains("address:") || lower.contains("address :") {
        return Probe {
            capable: true,
            reason: "help-mentions-address".into(),
        };
    }
    if lower.contains("target") && lower.contains("window") {
        return Probe {
            capable: true,
            reason: "help-mentions-target".into(),
        };
    }
    if lower.contains("l|r|u|d") || lower.contains("direction") {
        return Probe {
            capable: false,
            reason: "directional-only".into(),
        };
    }
    Probe {
        capable: false,
        reason: "unknown".into(),
    }
}

pub fn parse_version(text: &str) -> Option<(u32, u32)> {
    let needle = "hyprland";
    let lower = text.to_lowercase();
    let idx = lower.find(needle)?;
    let rest = &text[idx + needle.len()..];
    let mut nums = Vec::new();
    let mut cur = String::new();
    for c in rest.chars() {
        if c.is_ascii_digit() {
            cur.push(c);
        } else if !cur.is_empty() {
            if let Ok(n) = cur.parse::<u32>() {
                nums.push(n);
            }
            cur.clear();
            if nums.len() >= 2 {
                break;
            }
        }
    }
    if !cur.is_empty() {
        if let Ok(n) = cur.parse::<u32>() {
            nums.push(n);
        }
    }
    if nums.len() >= 2 {
        Some((nums[0], nums[1]))
    } else {
        None
    }
}

pub fn probe() -> Probe {
    if let Ok(ver) = hypr::hyprctl(&["version"]) {
        if let Some((maj, min)) = parse_version(&ver) {
            if maj > 0 || min >= 55 {
                return Probe {
                    capable: true,
                    reason: format!("hyprland-{maj}.{min}-target-swap"),
                };
            }
        }
    }
    let help = hypr::hyprctl(&["dispatch", "swapwindow"])
        .or_else(|_| hypr::hyprctl(&["dispatch", "help"]))
        .unwrap_or_default();
    parse_help(&help)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directional_only() {
        let p = parse_help("usage: swapwindow l|r|u|d");
        assert!(!p.capable);
        assert_eq!(p.reason, "directional-only");
    }

    #[test]
    fn address_capable() {
        let p = parse_help("swapwindow [direction | address:0x…]");
        assert!(p.capable);
    }

    #[test]
    fn version_055() {
        assert_eq!(
            parse_version("Hyprland 0.55.0 built from branch"),
            Some((0, 55))
        );
        assert_eq!(parse_version("not a version"), None);
    }
}

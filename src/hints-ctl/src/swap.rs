use crate::hypr;

pub struct Probe {
    pub capable: bool,
    pub reason: String,
}

/// Same dispatcher string QML uses: `swapwindow address:0x…`.
pub const SWAP_PROBE_DISPATCH: &str = "swapwindow address:0x0";

pub fn parse_dispatch_result(text: &str) -> Probe {
    let lower = text.to_lowercase();
    if lower.contains("l|r|u|d")
        || lower.contains("l/r/u/d")
        || lower.contains("invalid direction")
    {
        return Probe {
            capable: false,
            reason: "directional-only".into(),
        };
    }
    if lower.contains("invalid window")
        || lower.contains("window not found")
        || lower.contains("couldn't find")
        || lower.contains("could not find")
        || lower.contains("no such window")
        || lower.contains("unknown window")
    {
        return Probe {
            capable: true,
            reason: "dispatch-accepted-address".into(),
        };
    }
    if lower.contains("address:") {
        return Probe {
            capable: true,
            reason: "dispatch-mentions-address".into(),
        };
    }
    Probe {
        capable: false,
        reason: "unknown".into(),
    }
}

pub fn probe() -> Probe {
    match hypr::hyprctl_raw(&["dispatch", SWAP_PROBE_DISPATCH]) {
        Ok(out) => {
            let combined = format!("{} {}", out.stdout, out.stderr);
            parse_dispatch_result(&combined)
        }
        Err(err) => Probe {
            capable: false,
            reason: err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directional_only() {
        let p = parse_dispatch_result("Invalid direction, expected l/r/u/d");
        assert!(!p.capable);
        assert_eq!(p.reason, "directional-only");
        let p2 = parse_dispatch_result("usage: swapwindow l|r|u|d");
        assert!(!p2.capable);
    }

    #[test]
    fn dummy_address_accepted() {
        let p = parse_dispatch_result("Invalid window");
        assert!(p.capable);
        assert_eq!(p.reason, "dispatch-accepted-address");
        let p2 = parse_dispatch_result("Window not found");
        assert!(p2.capable);
    }

    #[test]
    fn probe_cmd_matches_qml() {
        assert_eq!(SWAP_PROBE_DISPATCH, "swapwindow address:0x0");
    }

    #[test]
    fn unknown_stays_greyed() {
        let p = parse_dispatch_result("");
        assert!(!p.capable);
        assert_eq!(p.reason, "unknown");
    }
}

use std::env;
use std::process::Command;

pub fn hyprctl_bin() -> String {
    env::var("HINTS_HYPRCTL").unwrap_or_else(|_| "hyprctl".to_string())
}

pub fn hyprctl(args: &[&str]) -> Result<String, String> {
    let bin = hyprctl_bin();
    let output = Command::new(&bin)
        .args(args)
        .output()
        .map_err(|e| format!("failed to spawn {bin}: {e}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        let mut msg = stderr.trim().to_string();
        if msg.is_empty() {
            msg = stdout.trim().to_string();
        }
        if msg.is_empty() {
            msg = format!("{bin} exited {}", output.status);
        }
        return Err(msg);
    }
    Ok(stdout)
}

pub fn dispatch_submap(name: &str) -> Result<String, String> {
    match hyprctl(&["dispatch", "submap", name]) {
        Ok(out) => Ok(out),
        Err(_) => {
            let expr = format!("hl.dispatch(hl.dsp.submap(\"{name}\"))");
            hyprctl(&["eval", &expr])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_bin_is_hyprctl() {
        env::remove_var("HINTS_HYPRCTL");
        assert_eq!(hyprctl_bin(), "hyprctl");
    }
}

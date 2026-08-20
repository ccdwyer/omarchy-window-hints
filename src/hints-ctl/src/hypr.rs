use std::env;
use std::io::Read;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, Instant};

pub const HYPRCTL_TIMEOUT_MS: u64 = 800;

pub struct RawOut {
    pub stdout: String,
    pub stderr: String,
    pub success: bool,
}

pub fn hyprctl_bin() -> String {
    env::var("HINTS_HYPRCTL").unwrap_or_else(|_| "hyprctl".to_string())
}

fn wait_timeout(child: &mut Child, dur: Duration) -> Result<ExitStatus, String> {
    let deadline = Instant::now() + dur;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status),
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("hyprctl timed out".into());
                }
                thread::sleep(Duration::from_millis(15));
            }
            Err(e) => return Err(format!("wait: {e}")),
        }
    }
}

pub fn hyprctl_raw(args: &[&str]) -> Result<RawOut, String> {
    let bin = hyprctl_bin();
    let mut child = Command::new(&bin)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to spawn {bin}: {e}"))?;
    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();
    let t_out = thread::spawn(move || {
        let mut s = String::new();
        if let Some(ref mut p) = stdout_pipe {
            let _ = p.read_to_string(&mut s);
        }
        s
    });
    let t_err = thread::spawn(move || {
        let mut s = String::new();
        if let Some(ref mut p) = stderr_pipe {
            let _ = p.read_to_string(&mut s);
        }
        s
    });
    let status = wait_timeout(&mut child, Duration::from_millis(HYPRCTL_TIMEOUT_MS))?;
    let stdout = t_out.join().unwrap_or_default();
    let stderr = t_err.join().unwrap_or_default();
    Ok(RawOut {
        stdout,
        stderr,
        success: status.success(),
    })
}

pub fn hyprctl(args: &[&str]) -> Result<String, String> {
    let bin = hyprctl_bin();
    let out = hyprctl_raw(args)?;
    if !out.success {
        let mut msg = out.stderr.trim().to_string();
        if msg.is_empty() {
            msg = out.stdout.trim().to_string();
        }
        if msg.is_empty() {
            msg = format!("{bin} failed");
        }
        return Err(msg);
    }
    Ok(out.stdout)
}

pub fn submap_lua(name: &str) -> String {
    format!("hl.dsp.submap(\"{name}\")")
}

pub fn dispatch_lua(expr: &str) -> Result<String, String> {
    hyprctl(&["dispatch", expr])
}

pub fn dispatch_submap(name: &str) -> Result<String, String> {
    dispatch_lua(&submap_lua(name))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_bin_is_hyprctl() {
        env::remove_var("HINTS_HYPRCTL");
        assert_eq!(hyprctl_bin(), "hyprctl");
    }

    #[test]
    fn timeout_constant_matches_qml() {
        assert_eq!(HYPRCTL_TIMEOUT_MS, 800);
    }

    #[test]
    fn submap_lua_is_single_dispatch_expr() {
        assert_eq!(submap_lua("reset"), r#"hl.dsp.submap("reset")"#);
        assert_eq!(submap_lua("hints"), r#"hl.dsp.submap("hints")"#);
    }
}

use crate::output;
use anyhow::Result;
use std::path::Path;
use std::process::Command;

pub fn run(dry_run: bool) -> Result<()> {
    let home = dirs::home_dir().unwrap_or_else(|| Path::new("/tmp").to_path_buf());
    let dev_dir = home.join("dev");

    if !dev_dir.exists() {
        output::warn("~/dev not found — skipping cargo sweep");
        return Ok(());
    }

    // Prefer cargo-sweep if available, fall back to manual target/ cleanup
    if has_cargo_sweep() {
        let args = [
            "sweep",
            "--time",
            "14",
            "--recursive",
            dev_dir.to_str().unwrap_or("~/dev"),
        ];
        if dry_run {
            output::info(&format!("[dry-run] cargo {}", args.join(" ")));
            return Ok(());
        }
        let pb = output::spinner("sweeping Rust build artifacts...");
        let result = Command::new("cargo").args(args).output();
        pb.finish_and_clear();
        match result {
            Ok(out) if out.status.success() => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                output::ok(&format!("cargo sweep complete\n{}", stdout.trim()));
            }
            Ok(out) => output::warn(&format!(
                "cargo sweep: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            )),
            Err(e) => output::warn(&format!("cargo sweep: {e}")),
        }
    } else {
        output::warn("cargo-sweep not found; use `cargo install cargo-sweep` for better cleanup");
        output::info("hint: run `mise run dev-tools` to install cargo-sweep");
    }

    Ok(())
}

fn has_cargo_sweep() -> bool {
    Command::new("cargo")
        .args(["sweep", "--version"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

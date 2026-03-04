use crate::output;
use anyhow::Result;
use std::process::Command;

pub fn run(dry_run: bool) -> Result<()> {
    let tasks: &[(&str, &[&str])] = &[
        ("remove stopped containers", &["container", "prune", "-f"]),
        ("remove dangling images", &["image", "prune", "-f"]),
        ("remove unused volumes", &["volume", "prune", "-f"]),
    ];

    // Check docker is available
    if Command::new("docker").arg("info").output().is_err() {
        output::warn("docker not available — skipping");
        return Ok(());
    }

    for (label, args) in tasks {
        if dry_run {
            output::info(&format!("[dry-run] docker {}", args.join(" ")));
            continue;
        }
        let pb = output::spinner(&format!("{label}..."));
        let result = Command::new("docker").args(*args).output();
        pb.finish_and_clear();
        match result {
            Ok(out) if out.status.success() => output::ok(label),
            Ok(out) => output::warn(&format!(
                "{label}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            )),
            Err(e) => output::warn(&format!("{label}: {e}")),
        }
    }

    Ok(())
}

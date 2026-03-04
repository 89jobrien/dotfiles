use crate::output;
use anyhow::Result;
use std::process::Command;

pub fn run(dry_run: bool) -> Result<()> {
    let tasks = [
        ("brew update", vec!["update"]),
        ("brew upgrade", vec!["upgrade"]),
        ("brew cleanup", vec!["cleanup", "--prune=all"]),
    ];

    for (label, args) in &tasks {
        if dry_run {
            output::info(&format!("[dry-run] brew {}", args.join(" ")));
            continue;
        }
        let pb = output::spinner(&format!("running {label}..."));
        let status = Command::new("brew").args(args).output();
        pb.finish_and_clear();
        match status {
            Ok(out) if out.status.success() => output::ok(label),
            Ok(out) => output::warn(&format!(
                "{label} exited non-zero: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            )),
            Err(e) => output::warn(&format!("{label} failed: {e}")),
        }
    }

    Ok(())
}

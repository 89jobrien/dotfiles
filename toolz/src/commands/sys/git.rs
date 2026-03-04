use crate::output;
use anyhow::Result;
use std::path::Path;
use std::process::Command;
use walkdir::WalkDir;

pub fn run(dry_run: bool) -> Result<()> {
    let home = dirs::home_dir().unwrap_or_else(|| Path::new("/tmp").to_path_buf());
    let dev_dir = home.join("dev");

    if !dev_dir.exists() {
        output::warn("~/dev not found — skipping git gc");
        return Ok(());
    }

    let repos: Vec<_> = WalkDir::new(&dev_dir)
        .max_depth(3)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_dir() && e.path().join(".git").exists())
        .map(|e| e.path().to_path_buf())
        .collect();

    if repos.is_empty() {
        output::warn("no git repos found in ~/dev");
        return Ok(());
    }

    output::info(&format!("found {} repos", repos.len()));

    for repo in &repos {
        let name = repo
            .strip_prefix(&home)
            .unwrap_or(repo)
            .display()
            .to_string();

        if dry_run {
            output::info(&format!("[dry-run] git gc --prune=now in ~/{name}"));
            continue;
        }

        let result = Command::new("git")
            .args(["gc", "--prune=now", "--quiet"])
            .current_dir(repo)
            .output();

        match result {
            Ok(out) if out.status.success() => output::ok(&format!("~/{name}")),
            Ok(out) => output::warn(&format!(
                "~/{name}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            )),
            Err(e) => output::warn(&format!("~/{name}: {e}")),
        }
    }

    Ok(())
}

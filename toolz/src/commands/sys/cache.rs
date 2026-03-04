use crate::output;
use anyhow::Result;
use bytesize::ByteSize;
use std::path::Path;
use std::process::Command;

pub fn run(dry_run: bool) -> Result<()> {
    let home = dirs::home_dir().unwrap_or_else(|| Path::new("/tmp").to_path_buf());

    // npm cache
    clean_npm(dry_run);

    // uv cache
    clean_uv(dry_run);

    // ~/.cache (Linux-style)
    let dot_cache = home.join(".cache");
    if dot_cache.exists() {
        report_dir_size(dot_cache.as_path(), "~/.cache");
    }

    // macOS Library/Caches
    if cfg!(target_os = "macos") {
        let lib_caches = home.join("Library").join("Caches");
        if lib_caches.exists() {
            clean_macos_caches(lib_caches.as_path(), dry_run);
        }
    }

    Ok(())
}

fn clean_npm(dry_run: bool) {
    if !has_cmd("npm") {
        return;
    }
    if dry_run {
        output::info("[dry-run] npm cache clean --force");
        return;
    }
    let pb = output::spinner("cleaning npm cache...");
    let result = Command::new("npm").args(["cache", "clean", "--force"]).output();
    pb.finish_and_clear();
    match result {
        Ok(out) if out.status.success() => output::ok("npm cache cleaned"),
        Ok(out) => output::warn(&format!(
            "npm cache: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        )),
        Err(e) => output::warn(&format!("npm cache: {e}")),
    }
}

fn clean_uv(dry_run: bool) {
    if !has_cmd("uv") {
        return;
    }
    if dry_run {
        output::info("[dry-run] uv cache clean");
        return;
    }
    let pb = output::spinner("cleaning uv cache...");
    let result = Command::new("uv").args(["cache", "clean"]).output();
    pb.finish_and_clear();
    match result {
        Ok(out) if out.status.success() => output::ok("uv cache cleaned"),
        Ok(_) => output::warn("uv cache clean returned non-zero"),
        Err(e) => output::warn(&format!("uv cache: {e}")),
    }
}

fn clean_macos_caches(lib_caches: &std::path::Path, dry_run: bool) {
    // Only report size — deleting Library/Caches wholesale is too aggressive
    report_dir_size(lib_caches, "~/Library/Caches");
    if dry_run {
        output::info("[dry-run] skipping ~/Library/Caches deletion (too broad — manual cleanup recommended)");
    } else {
        output::info("~/Library/Caches reported; use Finder or CleanMyMac for targeted cleanup");
    }
}

fn report_dir_size(path: &Path, label: &str) {
    match dir_size(path) {
        Ok(bytes) => output::info(&format!("{label}: {}", ByteSize::b(bytes))),
        Err(_) => output::warn(&format!("could not measure {label}")),
    }
}

fn dir_size(path: &Path) -> Result<u64> {
    let mut total = 0u64;
    for entry in walkdir::WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        total += entry.metadata().map(|m| m.len()).unwrap_or(0);
    }
    Ok(total)
}

fn has_cmd(cmd: &str) -> bool {
    Command::new("which")
        .arg(cmd)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

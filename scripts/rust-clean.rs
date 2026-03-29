#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive", "env"] }
//! ```
//!
//! Sweep Rust build artifacts older than N days using cargo-sweep.
//!
//! Usage:
//!   rust-clean [--dry-run] [--dir PATH] [--days N]

// ---------------------------------------------------------------------------
// Domain — types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct SweepConfig {
    pub scan_dir: String,
    pub keep_days: u32,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SweepResult {
    pub bytes_freed: u64,
    pub projects_cleaned: u32,
}

// ---------------------------------------------------------------------------
// Domain — ports
// ---------------------------------------------------------------------------

pub trait Sweeper {
    /// Returns true if cargo-sweep is available.
    fn is_available(&self) -> bool;
    /// Run the sweep. Returns result summary.
    fn sweep(&self, config: &SweepConfig) -> anyhow::Result<SweepResult>;
}

pub trait Reporter {
    fn info(&self, msg: &str);
    fn skip(&self, msg: &str);
    fn ok(&self, msg: &str);
    fn err(&self, msg: &str);
}

// ---------------------------------------------------------------------------
// Domain — core logic
// ---------------------------------------------------------------------------

pub struct RustCleaner<S: Sweeper, R: Reporter> {
    sweeper: S,
    reporter: R,
}

impl<S: Sweeper, R: Reporter> RustCleaner<S, R> {
    pub fn new(sweeper: S, reporter: R) -> Self {
        Self { sweeper, reporter }
    }

    pub fn run(&self, config: SweepConfig) -> anyhow::Result<()> {
        if !std::path::Path::new(&config.scan_dir).exists() {
            self.reporter.skip(&format!("scan dir not found: {}", config.scan_dir));
            return Ok(());
        }

        if !self.sweeper.is_available() {
            self.reporter.err("cargo-sweep not found — run: mise run dev-tools");
            anyhow::bail!("cargo-sweep not available");
        }

        if config.dry_run {
            self.reporter.info(&format!(
                "dry-run: artifacts older than {} days under {}",
                config.keep_days, config.scan_dir
            ));
        } else {
            self.reporter.info(&format!(
                "sweeping artifacts older than {} days under {}...",
                config.keep_days, config.scan_dir
            ));
        }

        let result = self.sweeper.sweep(&config)?;

        if config.dry_run {
            self.reporter.info(&format!(
                "would clean: {}",
                fmt_bytes(result.bytes_freed)
            ));
        } else {
            self.reporter.ok(&format!(
                "rust artifact sweep complete — freed {} across {} projects",
                fmt_bytes(result.bytes_freed),
                result.projects_cleaned,
            ));
        }

        Ok(())
    }
}

fn fmt_bytes(bytes: u64) -> String {
    if bytes == 0 { return "nothing".into(); }
    if bytes >= 1_073_741_824 {
        format!("{:.1} GiB", bytes as f64 / 1_073_741_824.0)
    } else if bytes >= 1_048_576 {
        format!("{:.1} MiB", bytes as f64 / 1_048_576.0)
    } else if bytes >= 1_024 {
        format!("{:.1} KiB", bytes as f64 / 1_024.0)
    } else {
        format!("{bytes} B")
    }
}

// ---------------------------------------------------------------------------
// Infrastructure adapters
// ---------------------------------------------------------------------------

use std::process::Command;

pub struct CargoSweepAdapter;

impl Sweeper for CargoSweepAdapter {
    fn is_available(&self) -> bool {
        Command::new("cargo").args(["sweep", "--version"])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    fn sweep(&self, config: &SweepConfig) -> anyhow::Result<SweepResult> {
        let mut args = vec!["sweep", "--time", "", "--recursive"];
        let days_str = config.keep_days.to_string();
        args[2] = &days_str;

        if config.dry_run {
            args.push("--dry-run");
        }

        args.push(&config.scan_dir);

        let out = Command::new("cargo").args(&args).output()?;
        let stdout = String::from_utf8_lossy(&out.stdout);

        // Parse "Cleaned X bytes" lines from cargo-sweep output
        let bytes_freed: u64 = stdout.lines()
            .filter_map(|l| {
                let l = l.trim();
                if l.starts_with("Cleaned") || l.starts_with("Would clean") {
                    l.split_whitespace().nth(1)?.parse::<u64>().ok()
                } else {
                    None
                }
            })
            .sum();

        let projects_cleaned = stdout.lines()
            .filter(|l| l.trim().starts_with("Cleaned") || l.trim().starts_with("Would clean"))
            .count() as u32;

        Ok(SweepResult { bytes_freed, projects_cleaned })
    }
}

pub struct ConsoleReporter;

impl Reporter for ConsoleReporter {
    fn info(&self, msg: &str) { eprintln!("[rust-clean] {msg}"); }
    fn skip(&self, msg: &str) { eprintln!("[rust-clean] skip: {msg}"); }
    fn ok(&self, msg: &str)   { eprintln!("[rust-clean] ok: {msg}"); }
    fn err(&self, msg: &str)  { eprintln!("[rust-clean] err: {msg}"); }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    // ── Test doubles ─────────────────────────────────────────────────────

    struct StubSweeper {
        available: bool,
        result: SweepResult,
        calls: RefCell<Vec<SweepConfig>>,
    }

    impl StubSweeper {
        fn available(result: SweepResult) -> Self {
            Self { available: true, result, calls: RefCell::new(vec![]) }
        }
        fn unavailable() -> Self {
            Self { available: false, result: SweepResult { bytes_freed: 0, projects_cleaned: 0 }, calls: RefCell::new(vec![]) }
        }
    }

    impl Sweeper for StubSweeper {
        fn is_available(&self) -> bool { self.available }
        fn sweep(&self, config: &SweepConfig) -> anyhow::Result<SweepResult> {
            self.calls.borrow_mut().push(config.clone());
            Ok(self.result.clone())
        }
    }

    #[derive(Default)]
    struct CapturingReporter {
        infos: RefCell<Vec<String>>,
        skips: RefCell<Vec<String>>,
        oks:   RefCell<Vec<String>>,
        errs:  RefCell<Vec<String>>,
    }

    impl Reporter for CapturingReporter {
        fn info(&self, m: &str) { self.infos.borrow_mut().push(m.to_string()); }
        fn skip(&self, m: &str) { self.skips.borrow_mut().push(m.to_string()); }
        fn ok(&self, m: &str)   { self.oks.borrow_mut().push(m.to_string()); }
        fn err(&self, m: &str)  { self.errs.borrow_mut().push(m.to_string()); }
    }

    fn result(bytes: u64, projects: u32) -> SweepResult {
        SweepResult { bytes_freed: bytes, projects_cleaned: projects }
    }

    fn cleaner(
        sweeper: StubSweeper,
    ) -> RustCleaner<StubSweeper, CapturingReporter> {
        RustCleaner::new(sweeper, CapturingReporter::default())
    }

    fn cfg(dir: &str, days: u32, dry_run: bool) -> SweepConfig {
        SweepConfig { scan_dir: dir.to_string(), keep_days: days, dry_run }
    }

    // ── Tests ─────────────────────────────────────────────────────────────

    #[test]
    fn missing_dir_skips_without_error() {
        let c = cleaner(StubSweeper::available(result(0, 0)));
        c.run(cfg("/nonexistent/path", 14, false)).unwrap();
        assert!(c.reporter.skips.borrow().iter().any(|m| m.contains("not found")));
        assert!(c.sweeper.calls.borrow().is_empty());
    }

    #[test]
    fn missing_tool_returns_error() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::unavailable());
        let err = c.run(cfg(tmp.to_str().unwrap(), 14, false));
        assert!(err.is_err());
        assert!(c.reporter.errs.borrow().iter().any(|m| m.contains("cargo-sweep")));
    }

    #[test]
    fn live_run_calls_sweeper_with_correct_config() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::available(result(1024, 2)));
        c.run(cfg(tmp.to_str().unwrap(), 7, false)).unwrap();
        let calls = c.sweeper.calls.borrow();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].keep_days, 7);
        assert!(!calls[0].dry_run);
    }

    #[test]
    fn dry_run_passes_flag_to_sweeper() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::available(result(0, 0)));
        c.run(cfg(tmp.to_str().unwrap(), 14, true)).unwrap();
        let calls = c.sweeper.calls.borrow();
        assert!(calls[0].dry_run);
    }

    #[test]
    fn live_run_reports_ok_with_freed_bytes() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::available(result(10 * 1_048_576, 3)));
        c.run(cfg(tmp.to_str().unwrap(), 14, false)).unwrap();
        assert!(c.reporter.oks.borrow().iter().any(|m| m.contains("10.0 MiB")));
        assert!(c.reporter.oks.borrow().iter().any(|m| m.contains("3 projects")));
    }

    #[test]
    fn dry_run_reports_would_clean_not_ok() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::available(result(512, 1)));
        c.run(cfg(tmp.to_str().unwrap(), 14, true)).unwrap();
        assert!(c.reporter.oks.borrow().is_empty());
        assert!(c.reporter.infos.borrow().iter().any(|m| m.contains("would clean") || m.contains("512 B")));
    }

    #[test]
    fn zero_bytes_freed_reports_nothing() {
        let tmp = std::env::temp_dir();
        let c = cleaner(StubSweeper::available(result(0, 0)));
        c.run(cfg(tmp.to_str().unwrap(), 14, false)).unwrap();
        assert!(c.reporter.oks.borrow().iter().any(|m| m.contains("nothing")));
    }

    // ── fmt_bytes unit tests ──────────────────────────────────────────────

    #[test]
    fn fmt_bytes_zero_returns_nothing() {
        assert_eq!(fmt_bytes(0), "nothing");
    }

    #[test]
    fn fmt_bytes_under_kib() {
        assert_eq!(fmt_bytes(512), "512 B");
    }

    #[test]
    fn fmt_bytes_kib_range() {
        assert_eq!(fmt_bytes(2048), "2.0 KiB");
    }

    #[test]
    fn fmt_bytes_mib_range() {
        assert_eq!(fmt_bytes(5 * 1_048_576), "5.0 MiB");
    }

    #[test]
    fn fmt_bytes_gib_range() {
        assert_eq!(fmt_bytes(2 * 1_073_741_824), "2.0 GiB");
    }
}

// ---------------------------------------------------------------------------
// CLI + Main
// ---------------------------------------------------------------------------

use clap::Parser;

#[derive(Parser)]
#[command(name = "rust-clean", about = "Sweep Rust build artifacts older than N days")]
struct Cli {
    /// Preview what would be removed without deleting
    #[arg(long, env = "DRY_RUN")]
    dry_run: bool,

    /// Directory to scan (env: RUST_CLEAN_DIR)
    #[arg(long, env = "RUST_CLEAN_DIR")]
    dir: Option<String>,

    /// Remove artifacts older than N days (env: RUST_CLEAN_DAYS)
    #[arg(long, env = "RUST_CLEAN_DAYS", default_value_t = 14)]
    days: u32,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let scan_dir = cli.dir.unwrap_or_else(|| format!("{home}/dev"));

    let cleaner = RustCleaner::new(CargoSweepAdapter, ConsoleReporter);
    cleaner.run(SweepConfig {
        scan_dir,
        keep_days: cli.days,
        dry_run: cli.dry_run,
    })
}

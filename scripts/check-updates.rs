#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//! ```
//!
//! Check dotfiles repo for updates from remote.
//!
//! Usage:
//!   check-updates [--force] [--quiet] [--notify]

// ---------------------------------------------------------------------------
// Domain — types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct UpdateStatus {
    pub local_sha:      String,
    pub remote_sha:     String,
    pub commits_behind: u32,
}

impl UpdateStatus {
    pub fn is_behind(&self) -> bool {
        self.commits_behind > 0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum CheckResult {
    UpToDate,
    Behind(UpdateStatus),
    NetworkError,
}

// ---------------------------------------------------------------------------
// Domain — ports
// ---------------------------------------------------------------------------

pub trait Cache {
    /// Seconds since the cache was last written, or None if it doesn't exist.
    fn age_secs(&self) -> Option<u64>;
    /// Write current timestamp to cache.
    fn touch(&self) -> anyhow::Result<()>;
    /// True if a "update available" marker exists.
    fn has_pending_update(&self) -> bool;
    /// Write the "update available" marker.
    fn set_pending_update(&self, available: bool) -> anyhow::Result<()>;
}

pub trait GitRemote {
    /// Fetch from remote. Returns false on network failure.
    fn fetch(&self) -> bool;
    /// Compare local HEAD vs remote branch.
    fn check_status(&self) -> anyhow::Result<CheckResult>;
}

pub trait Notifier {
    fn notify(&self, commits_behind: u32) -> anyhow::Result<()>;
}

pub trait Reporter {
    fn ok(&self, msg: &str);
    fn update_available(&self, status: &UpdateStatus);
}

// ---------------------------------------------------------------------------
// Domain — core logic
// ---------------------------------------------------------------------------

pub struct UpdateChecker<C: Cache, G: GitRemote, N: Notifier, R: Reporter> {
    cache: C,
    git: G,
    notifier: N,
    reporter: R,
    max_age_secs: u64,
}

impl<C: Cache, G: GitRemote, N: Notifier, R: Reporter> UpdateChecker<C, G, N, R> {
    pub fn new(cache: C, git: G, notifier: N, reporter: R, max_age_secs: u64) -> Self {
        Self { cache, git, notifier, reporter, max_age_secs }
    }

    pub fn run(&self, force: bool, quiet: bool, notify: bool) -> anyhow::Result<()> {
        // Cache gate
        if !force {
            if let Some(age) = self.cache.age_secs() {
                if age < self.max_age_secs {
                    // Cache fresh — replay pending update if any
                    if self.cache.has_pending_update() && !quiet {
                        // We don't have the status details anymore, just re-report
                        self.reporter.ok("updates available (cached) — run with --force to refresh");
                    } else if !quiet {
                        self.reporter.ok("Dotfiles are up to date (cached)");
                    }
                    return Ok(());
                }
            }
        }

        // Live check
        if !self.git.fetch() {
            // Network error — don't update cache
            if !quiet {
                self.reporter.ok("update check skipped (network unavailable)");
            }
            return Ok(());
        }

        let result = self.git.check_status()?;
        self.cache.touch()?;

        match result {
            CheckResult::UpToDate => {
                self.cache.set_pending_update(false)?;
                if !quiet {
                    self.reporter.ok("Dotfiles are up to date");
                }
            }
            CheckResult::Behind(ref status) => {
                self.cache.set_pending_update(true)?;
                if !quiet {
                    self.reporter.update_available(status);
                }
                if notify {
                    self.notifier.notify(status.commits_behind)?;
                }
            }
            CheckResult::NetworkError => {
                if !quiet {
                    self.reporter.ok("update check skipped (git error)");
                }
            }
        }

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Infrastructure adapters
// ---------------------------------------------------------------------------

use std::process::Command;
use std::path::{Path, PathBuf};

fn run_git(repo: &str, args: &[&str]) -> anyhow::Result<String> {
    let out = Command::new("git").arg("-C").arg(repo).args(args).output()?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        anyhow::bail!("git {}: {}", args.join(" "), String::from_utf8_lossy(&out.stderr).trim())
    }
}

pub struct FsCache {
    cache_file: PathBuf,
    update_file: PathBuf,
}

impl FsCache {
    pub fn new(cache_dir: &Path) -> Self {
        Self {
            cache_file: cache_dir.join("dotfiles-update-check"),
            update_file: cache_dir.join("dotfiles-update-available"),
        }
    }
}

impl Cache for FsCache {
    fn age_secs(&self) -> Option<u64> {
        let meta = std::fs::metadata(&self.cache_file).ok()?;
        let modified = meta.modified().ok()?;
        let elapsed = modified.elapsed().ok()?;
        Some(elapsed.as_secs())
    }

    fn touch(&self) -> anyhow::Result<()> {
        if let Some(parent) = self.cache_file.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&self.cache_file, b"")?;
        Ok(())
    }

    fn has_pending_update(&self) -> bool {
        self.update_file.exists()
    }

    fn set_pending_update(&self, available: bool) -> anyhow::Result<()> {
        if available {
            if let Some(parent) = self.update_file.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::write(&self.update_file, b"1")?;
        } else {
            let _ = std::fs::remove_file(&self.update_file);
        }
        Ok(())
    }
}

pub struct ProcessGitRemote {
    pub repo: String,
}

impl GitRemote for ProcessGitRemote {
    fn fetch(&self) -> bool {
        // Use timeout(1) if available, otherwise fall back to plain git fetch
        let has_timeout = Command::new("which").arg("timeout").output()
            .map(|o| o.status.success()).unwrap_or(false);

        if has_timeout {
            Command::new("timeout")
                .args(["5", "git", "-C", &self.repo, "fetch", "origin", "--quiet"])
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
        } else {
            Command::new("git")
                .args(["-C", &self.repo, "fetch", "origin", "--quiet"])
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
        }
    }

    fn check_status(&self) -> anyhow::Result<CheckResult> {
        let local = run_git(&self.repo, &["rev-parse", "HEAD"])?;
        let remote = run_git(&self.repo, &["rev-parse", "origin/main"])
            .or_else(|_| run_git(&self.repo, &["rev-parse", "origin/master"]))?;

        if local == remote {
            return Ok(CheckResult::UpToDate);
        }

        let local_short = run_git(&self.repo, &["rev-parse", "--short", "HEAD"])?;
        let remote_short = run_git(&self.repo, &["rev-parse", "--short", "origin/main"])
            .or_else(|_| run_git(&self.repo, &["rev-parse", "--short", "origin/master"]))?;
        let behind_str = run_git(&self.repo, &["rev-list", "--count", "HEAD..origin/main"])
            .or_else(|_| run_git(&self.repo, &["rev-list", "--count", "HEAD..origin/master"]))?;
        let commits_behind: u32 = behind_str.parse().unwrap_or(0);

        Ok(CheckResult::Behind(UpdateStatus {
            local_sha: local_short,
            remote_sha: remote_short,
            commits_behind,
        }))
    }
}

pub struct OsascriptNotifier;

impl Notifier for OsascriptNotifier {
    fn notify(&self, commits_behind: u32) -> anyhow::Result<()> {
        if cfg!(target_os = "macos") {
            let script = format!(
                r#"display notification "{commits_behind} commits behind remote" with title "Dotfiles Updates Available" sound name "Glass""#
            );
            Command::new("osascript").args(["-e", &script]).status()?;
        }
        Ok(())
    }
}

pub struct ConsoleReporter;

impl Reporter for ConsoleReporter {
    fn ok(&self, msg: &str) {
        eprintln!("[updates] ok: {msg}");
    }

    fn update_available(&self, s: &UpdateStatus) {
        println!(r#"
╭─────────────────────────────────────────────────────────╮
│  Dotfiles updates available!                            │
│                                                          │
│  Local:  {:<48}│
│  Remote: {:<48}│
│  Behind: {:<48}│
│                                                          │
│  Update: cd ~/dotfiles && git pull && source ~/.zshrc   │
╰─────────────────────────────────────────────────────────╯
"#,
            s.local_sha,
            s.remote_sha,
            format!("{} commits", s.commits_behind),
        );
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    // ── Test doubles ─────────────────────────────────────────────────────

    struct StubCache {
        age: Option<u64>,
        pending: RefCell<bool>,
        touched: RefCell<bool>,
    }

    impl StubCache {
        fn fresh(age: u64) -> Self { Self { age: Some(age), pending: RefCell::new(false), touched: RefCell::new(false) } }
        fn expired(age: u64) -> Self { Self { age: Some(age), pending: RefCell::new(false), touched: RefCell::new(false) } }
        fn missing() -> Self { Self { age: None, pending: RefCell::new(false), touched: RefCell::new(false) } }
        fn with_pending(mut self) -> Self { *self.pending.borrow_mut() = true; self }
    }

    impl Cache for StubCache {
        fn age_secs(&self) -> Option<u64> { self.age }
        fn touch(&self) -> anyhow::Result<()> { *self.touched.borrow_mut() = true; Ok(()) }
        fn has_pending_update(&self) -> bool { *self.pending.borrow() }
        fn set_pending_update(&self, v: bool) -> anyhow::Result<()> { *self.pending.borrow_mut() = v; Ok(()) }
    }

    struct StubGit(CheckResult);
    impl GitRemote for StubGit {
        fn fetch(&self) -> bool { true }
        fn check_status(&self) -> anyhow::Result<CheckResult> { Ok(self.0.clone()) }
    }

    struct FailingFetch;
    impl GitRemote for FailingFetch {
        fn fetch(&self) -> bool { false }
        fn check_status(&self) -> anyhow::Result<CheckResult> { Ok(CheckResult::UpToDate) }
    }

    #[derive(Default)]
    struct CapturingNotifier { calls: RefCell<Vec<u32>> }
    impl Notifier for CapturingNotifier {
        fn notify(&self, n: u32) -> anyhow::Result<()> { self.calls.borrow_mut().push(n); Ok(()) }
    }

    #[derive(Default)]
    struct CapturingReporter {
        ok_msgs:     RefCell<Vec<String>>,
        update_msgs: RefCell<Vec<UpdateStatus>>,
    }
    impl Reporter for CapturingReporter {
        fn ok(&self, msg: &str) { self.ok_msgs.borrow_mut().push(msg.to_string()); }
        fn update_available(&self, s: &UpdateStatus) { self.update_msgs.borrow_mut().push(s.clone()); }
    }

    fn status(behind: u32) -> CheckResult {
        CheckResult::Behind(UpdateStatus {
            local_sha: "abc1234".into(),
            remote_sha: "def5678".into(),
            commits_behind: behind,
        })
    }

    fn checker<C: Cache, G: GitRemote>(
        cache: C,
        git: G,
    ) -> UpdateChecker<C, G, CapturingNotifier, CapturingReporter> {
        UpdateChecker::new(cache, git, CapturingNotifier::default(), CapturingReporter::default(), 3600)
    }

    // ── Tests ─────────────────────────────────────────────────────────────

    #[test]
    fn fresh_cache_skips_fetch_and_reports_up_to_date() {
        let c = checker(StubCache::fresh(60), StubGit(CheckResult::UpToDate));
        c.run(false, false, false).unwrap();
        assert!(c.reporter.ok_msgs.borrow().iter().any(|m| m.contains("cached")));
        assert!(!*c.cache.touched.borrow()); // no fetch happened
    }

    #[test]
    fn fresh_cache_with_pending_update_replays_it() {
        let c = checker(StubCache::fresh(60).with_pending(), StubGit(CheckResult::UpToDate));
        c.run(false, false, false).unwrap();
        assert!(c.reporter.ok_msgs.borrow().iter().any(|m| m.contains("updates available")));
    }

    #[test]
    fn force_bypasses_fresh_cache() {
        let c = checker(StubCache::fresh(60), StubGit(CheckResult::UpToDate));
        c.run(true, false, false).unwrap();
        assert!(*c.cache.touched.borrow()); // fetch happened
    }

    #[test]
    fn expired_cache_triggers_fetch() {
        let c = checker(StubCache::expired(7200), StubGit(CheckResult::UpToDate));
        c.run(false, false, false).unwrap();
        assert!(*c.cache.touched.borrow());
    }

    #[test]
    fn missing_cache_triggers_fetch() {
        let c = checker(StubCache::missing(), StubGit(CheckResult::UpToDate));
        c.run(false, false, false).unwrap();
        assert!(*c.cache.touched.borrow());
    }

    #[test]
    fn up_to_date_clears_pending_and_reports_ok() {
        let c = checker(StubCache::missing(), StubGit(CheckResult::UpToDate));
        c.run(false, false, false).unwrap();
        assert!(!c.cache.has_pending_update());
        assert!(c.reporter.ok_msgs.borrow().iter().any(|m| m.contains("up to date")));
    }

    #[test]
    fn behind_sets_pending_and_reports_update() {
        let c = checker(StubCache::missing(), StubGit(status(3)));
        c.run(false, false, false).unwrap();
        assert!(c.cache.has_pending_update());
        assert!(!c.reporter.update_msgs.borrow().is_empty());
        assert_eq!(c.reporter.update_msgs.borrow()[0].commits_behind, 3);
    }

    #[test]
    fn network_error_skips_cache_touch() {
        let c = checker(StubCache::missing(), FailingFetch);
        c.run(false, false, false).unwrap();
        assert!(!*c.cache.touched.borrow());
    }

    #[test]
    fn quiet_mode_suppresses_up_to_date_output() {
        let c = checker(StubCache::missing(), StubGit(CheckResult::UpToDate));
        c.run(false, true, false).unwrap();
        assert!(c.reporter.ok_msgs.borrow().is_empty());
    }

    #[test]
    fn quiet_mode_suppresses_update_box() {
        let c = checker(StubCache::missing(), StubGit(status(2)));
        c.run(false, true, false).unwrap();
        assert!(c.reporter.update_msgs.borrow().is_empty());
    }

    #[test]
    fn notify_flag_triggers_notifier_when_behind() {
        let c = checker(StubCache::missing(), StubGit(status(5)));
        c.run(false, false, true).unwrap();
        assert_eq!(c.notifier.calls.borrow().as_slice(), &[5]);
    }

    #[test]
    fn notify_flag_does_not_trigger_when_up_to_date() {
        let c = checker(StubCache::missing(), StubGit(CheckResult::UpToDate));
        c.run(false, false, true).unwrap();
        assert!(c.notifier.calls.borrow().is_empty());
    }

    #[test]
    fn update_status_is_behind_true_when_commits_nonzero() {
        let s = UpdateStatus { local_sha: "a".into(), remote_sha: "b".into(), commits_behind: 1 };
        assert!(s.is_behind());
    }

    #[test]
    fn update_status_is_behind_false_when_zero() {
        let s = UpdateStatus { local_sha: "a".into(), remote_sha: "a".into(), commits_behind: 0 };
        assert!(!s.is_behind());
    }
}

// ---------------------------------------------------------------------------
// CLI + Main
// ---------------------------------------------------------------------------

use clap::Parser;

#[derive(Parser)]
#[command(name = "check-updates", about = "Check dotfiles repo for updates from remote")]
struct Cli {
    /// Force check even if cache is fresh
    #[arg(long)]
    force: bool,

    /// Suppress output unless updates are available
    #[arg(long)]
    quiet: bool,

    /// Send desktop notification if updates available (macOS)
    #[arg(long)]
    notify: bool,

    /// Cache max age in seconds (env: DOTFILES_UPDATE_CHECK_INTERVAL)
    #[arg(long)]
    max_age: Option<u64>,

    /// Dotfiles repo root (default: $HOME/dotfiles)
    #[arg(long)]
    repo: Option<String>,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    let max_age = cli.max_age
        .or_else(|| std::env::var("DOTFILES_UPDATE_CHECK_INTERVAL").ok()?.parse().ok())
        .unwrap_or(3600);

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let cache_dir = std::path::PathBuf::from(&home).join(".cache");

    let repo = cli.repo.unwrap_or_else(|| format!("{home}/dotfiles"));

    let checker = UpdateChecker::new(
        FsCache::new(&cache_dir),
        ProcessGitRemote { repo },
        OsascriptNotifier,
        ConsoleReporter,
        max_age,
    );

    checker.run(cli.force, cli.quiet, cli.notify)
}

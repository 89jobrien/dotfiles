#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//!
//! [dev-dependencies]
//! ```
//!
//! Check dotfiles repo for drift: uncommitted git changes and stow conflicts.
//!
//! Usage:
//!   drift-check [--repo PATH] [--stow-list PATH]

// ---------------------------------------------------------------------------
// Domain — ports and types
// ---------------------------------------------------------------------------

#[derive(Debug, PartialEq)]
pub enum DriftIssue {
    UncommittedChanges,
    StowConflict(String),
}

pub trait GitChecker {
    /// Returns true if the working tree and index are clean.
    fn is_clean(&self) -> anyhow::Result<bool>;
}

pub trait StowChecker {
    /// Returns packages that have symlink conflicts.
    fn conflicting_packages(&self, packages: &[String]) -> anyhow::Result<Vec<String>>;
}

pub trait Reporter {
    fn warn(&self, msg: &str);
    fn pass(&self, msg: &str);
    fn fail(&self, msg: &str);
}

// ---------------------------------------------------------------------------
// Domain — core logic
// ---------------------------------------------------------------------------

pub struct DriftChecker<G: GitChecker, S: StowChecker, R: Reporter> {
    git: G,
    stow: S,
    reporter: R,
    repo: String,
}

impl<G: GitChecker, S: StowChecker, R: Reporter> DriftChecker<G, S, R> {
    pub fn new(git: G, stow: S, reporter: R, repo: String) -> Self {
        Self { git, stow, reporter, repo }
    }

    /// Run all drift checks. Returns list of issues found.
    pub fn check(&self, packages: &[String]) -> anyhow::Result<Vec<DriftIssue>> {
        let mut issues = Vec::new();

        self.reporter.warn(&format!("repo={}", self.repo));

        if !self.git.is_clean()? {
            self.reporter.warn("dotfiles repo has uncommitted changes");
            issues.push(DriftIssue::UncommittedChanges);
        }

        for pkg in self.stow.conflicting_packages(packages)? {
            self.reporter.warn(&format!("stow conflict for package: {pkg}"));
            issues.push(DriftIssue::StowConflict(pkg));
        }

        if issues.is_empty() {
            self.reporter.pass("PASS");
        } else {
            self.reporter.fail("FAIL");
        }

        Ok(issues)
    }
}

// ---------------------------------------------------------------------------
// Infrastructure adapters
// ---------------------------------------------------------------------------

pub struct ProcessGitChecker {
    pub repo: String,
}

impl GitChecker for ProcessGitChecker {
    fn is_clean(&self) -> anyhow::Result<bool> {
        let worktree = std::process::Command::new("git")
            .args(["-C", &self.repo, "diff", "--quiet"])
            .status()?
            .success();
        let index = std::process::Command::new("git")
            .args(["-C", &self.repo, "diff", "--cached", "--quiet"])
            .status()?
            .success();
        Ok(worktree && index)
    }
}

pub struct ProcessStowChecker {
    pub repo: String,
    pub home: String,
}

impl StowChecker for ProcessStowChecker {
    fn conflicting_packages(&self, packages: &[String]) -> anyhow::Result<Vec<String>> {
        // Check if stow is available and home is valid
        if std::process::Command::new("stow").arg("--version").output().is_err() {
            return Ok(vec![]);
        }
        if self.home.is_empty() {
            return Ok(vec![]);
        }

        let mut conflicts = Vec::new();
        for pkg in packages {
            let out = std::process::Command::new("stow")
                .args(["-d", &self.repo, "-t", &self.home, "-n", pkg])
                .env("HOME", &self.home)
                .output()?;
            let stderr = String::from_utf8_lossy(&out.stderr);
            let stdout = String::from_utf8_lossy(&out.stdout);
            let combined = format!("{stdout}{stderr}");
            if combined.contains("would cause conflicts")
                || combined.contains("cannot stow")
                || combined.contains("existing target is not owned by stow")
                || combined.contains("ERROR")
            {
                conflicts.push(pkg.clone());
            }
        }
        Ok(conflicts)
    }
}

pub struct ConsoleReporter;

impl Reporter for ConsoleReporter {
    fn warn(&self, msg: &str) {
        eprintln!("[drift] warn: {msg}");
    }
    fn pass(&self, msg: &str) {
        eprintln!("[drift] ok: {msg}");
    }
    fn fail(&self, msg: &str) {
        eprintln!("[drift] err: {msg}");
    }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

use clap::Parser;

#[derive(Parser)]
#[command(name = "drift-check", about = "Detect dotfiles drift: git changes and stow conflicts")]
struct Cli {
    /// Dotfiles repo root (default: directory of this script)
    #[arg(long)]
    repo: Option<String>,

    /// Path to stow packages list (default: <repo>/config/stow-packages.txt)
    #[arg(long)]
    stow_list: Option<String>,
}

fn resolve_repo(cli_repo: Option<String>) -> String {
    if let Some(r) = cli_repo {
        return r;
    }
    // Walk up from current exe/script location to find repo root
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().and_then(|p| p.parent()).map(|p| p.to_path_buf()))
        .unwrap_or_else(|| std::env::current_dir().unwrap())
        .to_string_lossy()
        .to_string()
}

fn load_packages(stow_list: &str) -> Vec<String> {
    std::fs::read_to_string(stow_list)
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
        .map(|l| l.trim().to_string())
        .collect()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    // ── Test doubles ──────────────────────────────────────────────────────

    struct CleanGit;
    impl GitChecker for CleanGit {
        fn is_clean(&self) -> anyhow::Result<bool> { Ok(true) }
    }

    struct DirtyGit;
    impl GitChecker for DirtyGit {
        fn is_clean(&self) -> anyhow::Result<bool> { Ok(false) }
    }

    struct NoConflicts;
    impl StowChecker for NoConflicts {
        fn conflicting_packages(&self, _: &[String]) -> anyhow::Result<Vec<String>> {
            Ok(vec![])
        }
    }

    struct WithConflicts(Vec<String>);
    impl StowChecker for WithConflicts {
        fn conflicting_packages(&self, _: &[String]) -> anyhow::Result<Vec<String>> {
            Ok(self.0.clone())
        }
    }

    #[derive(Default)]
    struct CapturingReporter {
        warns: RefCell<Vec<String>>,
        passes: RefCell<Vec<String>>,
        fails:  RefCell<Vec<String>>,
    }
    impl Reporter for CapturingReporter {
        fn warn(&self, msg: &str) { self.warns.borrow_mut().push(msg.to_string()); }
        fn pass(&self, msg: &str) { self.passes.borrow_mut().push(msg.to_string()); }
        fn fail(&self, msg: &str) { self.fails.borrow_mut().push(msg.to_string()); }
    }

    fn checker<G: GitChecker, S: StowChecker>(
        git: G,
        stow: S,
    ) -> DriftChecker<G, S, CapturingReporter> {
        DriftChecker::new(git, stow, CapturingReporter::default(), "/repo".into())
    }

    // ── Tests ─────────────────────────────────────────────────────────────

    #[test]
    fn clean_repo_no_packages_returns_no_issues() {
        let c = checker(CleanGit, NoConflicts);
        let issues = c.check(&[]).unwrap();
        assert!(issues.is_empty());
        assert_eq!(c.reporter.passes.borrow().as_slice(), &["PASS"]);
        assert!(c.reporter.fails.borrow().is_empty());
    }

    #[test]
    fn dirty_git_returns_uncommitted_changes_issue() {
        let c = checker(DirtyGit, NoConflicts);
        let issues = c.check(&[]).unwrap();
        assert_eq!(issues, vec![DriftIssue::UncommittedChanges]);
        assert!(c.reporter.warns.borrow().iter().any(|w| w.contains("uncommitted")));
        assert_eq!(c.reporter.fails.borrow().as_slice(), &["FAIL"]);
    }

    #[test]
    fn stow_conflict_returns_stow_conflict_issue() {
        let c = checker(CleanGit, WithConflicts(vec!["zsh".into()]));
        let issues = c.check(&["zsh".into()]).unwrap();
        assert_eq!(issues, vec![DriftIssue::StowConflict("zsh".into())]);
        assert!(c.reporter.warns.borrow().iter().any(|w| w.contains("zsh")));
        assert_eq!(c.reporter.fails.borrow().as_slice(), &["FAIL"]);
    }

    #[test]
    fn multiple_stow_conflicts_all_reported() {
        let c = checker(CleanGit, WithConflicts(vec!["zsh".into(), "git".into()]));
        let issues = c.check(&["zsh".into(), "git".into()]).unwrap();
        assert_eq!(issues.len(), 2);
        assert!(issues.contains(&DriftIssue::StowConflict("zsh".into())));
        assert!(issues.contains(&DriftIssue::StowConflict("git".into())));
    }

    #[test]
    fn dirty_git_plus_stow_conflict_both_reported() {
        let c = checker(DirtyGit, WithConflicts(vec!["vim".into()]));
        let issues = c.check(&["vim".into()]).unwrap();
        assert!(issues.contains(&DriftIssue::UncommittedChanges));
        assert!(issues.contains(&DriftIssue::StowConflict("vim".into())));
        assert_eq!(issues.len(), 2);
    }

    #[test]
    fn load_packages_skips_comments_and_blank_lines() {
        let input = "# comment\n\nzsh\ngit\n# another\nvim\n";
        let tmp = std::env::temp_dir().join("stow-packages-test.txt");
        std::fs::write(&tmp, input).unwrap();
        let pkgs = load_packages(tmp.to_str().unwrap());
        assert_eq!(pkgs, vec!["zsh", "git", "vim"]);
    }

    #[test]
    fn load_packages_returns_empty_for_missing_file() {
        let pkgs = load_packages("/nonexistent/path/packages.txt");
        assert!(pkgs.is_empty());
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let repo = resolve_repo(cli.repo);
    let stow_list = cli.stow_list
        .unwrap_or_else(|| format!("{repo}/config/stow-packages.txt"));

    let packages = load_packages(&stow_list);

    let git = ProcessGitChecker { repo: repo.clone() };
    let stow = ProcessStowChecker {
        repo: repo.clone(),
        home: std::env::var("HOME").unwrap_or_else(|_| "/root".into()),
    };

    let checker = DriftChecker::new(git, stow, ConsoleReporter, repo);
    let issues = checker.check(&packages)?;

    if !issues.is_empty() {
        std::process::exit(1);
    }

    Ok(())
}

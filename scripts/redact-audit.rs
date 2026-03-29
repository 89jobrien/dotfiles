#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//! serde_json = "1"
//! ```
//!
//! Scan files for sensitive data via obfsck and log findings as JSONL.
//! Always exits 0 — audit-only, never blocks.
//!
//! Usage:
//!   redact-audit [--verbose] [--hook NAME] [--staged] [FILE...]

// ---------------------------------------------------------------------------
// Domain — types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct AuditFinding {
    pub label: String,
    pub match_count: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AuditEntry {
    pub ts: String,
    pub hook: String,
    pub commit: String,
    pub file: String,
    pub tier: String,
    pub group: String,
    pub label: String,
    pub match_count: u32,
}

// ---------------------------------------------------------------------------
// Domain — ports
// ---------------------------------------------------------------------------

pub trait FileResolver {
    /// Return list of files to scan (staged or explicit).
    fn resolve(&self, explicit: &[String], staged: bool) -> Vec<String>;
}

pub trait TextFilter {
    /// True if the file path looks like a text file we should scan.
    fn is_text(&self, path: &str) -> bool;
}

pub trait ContentReader {
    /// Read file content (staged blob or disk).
    fn read(&self, path: &str, staged: bool) -> Option<String>;
}

pub trait AuditRunner {
    /// Run obfsck --audit on content, return findings.
    fn audit(&self, content: &str) -> Vec<AuditFinding>;
}

pub trait TierLookup {
    /// Map group name → tier string.
    fn tier(&self, group: &str) -> String;
    /// Map label → group name.
    fn group(&self, label: &str) -> String;
}

pub trait AuditLogger {
    fn log(&self, entry: &AuditEntry) -> anyhow::Result<()>;
}

pub trait Reporter {
    fn finding(&self, entry: &AuditEntry);
    fn summary(&self, total_hits: u32, log_path: &str);
}

// ---------------------------------------------------------------------------
// Domain — core logic
// ---------------------------------------------------------------------------

pub struct RedactAuditor<FR, TF, CR, AR, TL, AL, R>
where
    FR: FileResolver,
    TF: TextFilter,
    CR: ContentReader,
    AR: AuditRunner,
    TL: TierLookup,
    AL: AuditLogger,
    R: Reporter,
{
    resolver: FR,
    filter: TF,
    reader: CR,
    runner: AR,
    tiers: TL,
    logger: AL,
    reporter: R,
}

impl<FR, TF, CR, AR, TL, AL, R> RedactAuditor<FR, TF, CR, AR, TL, AL, R>
where
    FR: FileResolver,
    TF: TextFilter,
    CR: ContentReader,
    AR: AuditRunner,
    TL: TierLookup,
    AL: AuditLogger,
    R: Reporter,
{
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        resolver: FR, filter: TF, reader: CR, runner: AR,
        tiers: TL, logger: AL, reporter: R,
    ) -> Self {
        Self { resolver, filter, reader, runner, tiers, logger, reporter }
    }

    pub fn run(
        &self,
        explicit_files: &[String],
        staged: bool,
        verbose: bool,
        hook: &str,
        commit: &str,
        ts: &str,
        log_path: &str,
    ) -> anyhow::Result<u32> {
        let files = self.resolver.resolve(explicit_files, staged);
        if files.is_empty() {
            return Ok(0);
        }

        let mut total_hits = 0u32;

        for path in &files {
            if !self.filter.is_text(path) {
                continue;
            }

            let content = match self.reader.read(path, staged) {
                Some(c) if !c.is_empty() => c,
                _ => continue,
            };

            for finding in self.runner.audit(&content) {
                let group = self.tiers.group(&finding.label);
                let tier = self.tiers.tier(&group);

                let entry = AuditEntry {
                    ts: ts.to_string(),
                    hook: hook.to_string(),
                    commit: commit.to_string(),
                    file: path.clone(),
                    tier,
                    group,
                    label: finding.label.clone(),
                    match_count: finding.match_count,
                };

                self.logger.log(&entry)?;
                total_hits += finding.match_count;

                if verbose {
                    self.reporter.finding(&entry);
                }
            }
        }

        if verbose && total_hits > 0 {
            self.reporter.summary(total_hits, log_path);
        }

        Ok(total_hits)
    }
}

// ---------------------------------------------------------------------------
// Domain — text extension filter
// ---------------------------------------------------------------------------

const TEXT_EXTS: &[&str] = &[
    "md", "txt", "yaml", "yml", "toml", "json", "env", "conf",
    "log", "jsonl", "Justfile", "Makefile", "rs", "sh", "py",
];

const TEXT_BASENAMES: &[&str] = &[
    ".mise.toml", "mise.toml", "mise.local.toml",
    "Justfile", "Makefile",
];

pub struct DefaultTextFilter;

impl TextFilter for DefaultTextFilter {
    fn is_text(&self, path: &str) -> bool {
        let base = std::path::Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        if TEXT_BASENAMES.contains(&base.as_str()) {
            return true;
        }

        let ext = std::path::Path::new(&base)
            .extension()
            .map(|e| e.to_string_lossy().to_string())
            .unwrap_or_default();

        TEXT_EXTS.contains(&ext.as_str()) || TEXT_EXTS.contains(&base.as_str())
    }
}

// ---------------------------------------------------------------------------
// Domain — tier lookup
// ---------------------------------------------------------------------------

pub struct DefaultTierLookup;

impl TierLookup for DefaultTierLookup {
    fn group(&self, label: &str) -> String {
        // Strip [REDACTED-...] wrapper if present
        let label = label.trim_start_matches("[REDACTED-").trim_end_matches(']');
        // Heuristic group mapping by label prefix
        match label {
            l if l.starts_with("PRIVATE_KEY") || l.starts_with("CERTIFICATE") => "private_keys",
            l if l.starts_with("BEARER") || l.starts_with("JWT") => "bearer_tokens",
            l if l.starts_with("OPENAI") || l.starts_with("ANTHROPIC") || l.starts_with("GEMINI") => "ai_apis",
            l if l.starts_with("AWS") || l.starts_with("GCP") || l.starts_with("AZURE") => "cloud_credentials",
            l if l.starts_with("OP_") || l.starts_with("ONEPASSWORD") => "onepassword",
            l if l.starts_with("EMAIL") || l.starts_with("PHONE") || l.starts_with("SSN") => "pii",
            _ => "personal_env",
        }.to_string()
    }

    fn tier(&self, group: &str) -> String {
        match group {
            "private_keys" | "bearer_tokens" => "critical",
            "ai_apis" | "cloud_credentials" | "onepassword" => "high",
            "pii" => "medium",
            _ => "low",
        }.to_string()
    }
}

// ---------------------------------------------------------------------------
// Infrastructure adapters
// ---------------------------------------------------------------------------

use std::process::Command;

pub struct ProcessFileResolver {
    pub repo: String,
}

impl FileResolver for ProcessFileResolver {
    fn resolve(&self, explicit: &[String], staged: bool) -> Vec<String> {
        if !explicit.is_empty() {
            return explicit.to_vec();
        }
        if staged {
            let out = Command::new("git")
                .args(["-C", &self.repo, "diff", "--cached", "--name-only", "--diff-filter=ACM"])
                .output();
            let stdout = out.map(|o| o.stdout).unwrap_or_default();
            return String::from_utf8_lossy(&stdout)
                .lines()
                .filter(|l| !l.is_empty())
                .map(|l| l.to_string())
                .collect();
        }
        vec![]
    }
}

pub struct ProcessContentReader {
    pub repo: String,
}

impl ContentReader for ProcessContentReader {
    fn read(&self, path: &str, staged: bool) -> Option<String> {
        if staged && !path.starts_with('/') {
            let out = Command::new("git")
                .args(["-C", &self.repo, "show", &format!(":{path}")])
                .output().ok()?;
            if out.status.success() {
                return Some(String::from_utf8_lossy(&out.stdout).to_string());
            }
        }
        let abs = if path.starts_with('/') {
            path.to_string()
        } else {
            format!("{}/{path}", self.repo)
        };
        std::fs::read_to_string(&abs).ok()
    }
}

pub struct ObfsckAuditRunner {
    pub config: String,
}

impl AuditRunner for ObfsckAuditRunner {
    fn audit(&self, content: &str) -> Vec<AuditFinding> {
        let out = Command::new("obfsck")
            .args(["--config", &self.config, "--audit"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut child| {
                use std::io::Write;
                if let Some(stdin) = child.stdin.take() {
                    let mut stdin = stdin;
                    let _ = stdin.write_all(content.as_bytes());
                }
                child.wait_with_output()
            });

        let stderr = match out {
            Ok(o) => String::from_utf8_lossy(&o.stderr).to_string(),
            Err(_) => return vec![],
        };

        parse_audit_output(&stderr)
    }
}

/// Parse `  [REDACTED-LABEL]    N` lines from obfsck --audit stderr.
pub fn parse_audit_output(output: &str) -> Vec<AuditFinding> {
    output.lines().filter_map(|line| {
        let line = line.trim();
        // Match: [REDACTED-LABEL]    N
        let rest = line.strip_prefix('[')?.strip_prefix("REDACTED-")?;
        let (label, count_str) = rest.split_once(']')?;
        let count: u32 = count_str.trim().parse().ok()?;
        Some(AuditFinding { label: label.to_string(), match_count: count })
    }).collect()
}

pub struct JsonlAuditLogger {
    pub log_path: String,
}

impl AuditLogger for JsonlAuditLogger {
    fn log(&self, entry: &AuditEntry) -> anyhow::Result<()> {
        use std::io::Write;
        if let Some(parent) = std::path::Path::new(&self.log_path).parent() {
            std::fs::create_dir_all(parent)?;
        }
        let line = serde_json::json!({
            "ts": entry.ts,
            "hook": entry.hook,
            "commit": entry.commit,
            "file": entry.file,
            "tier": entry.tier,
            "group": entry.group,
            "label": entry.label,
            "match_count": entry.match_count,
        }).to_string();
        let mut f = std::fs::OpenOptions::new()
            .create(true).append(true).open(&self.log_path)?;
        writeln!(f, "{line}")?;
        Ok(())
    }
}

pub struct ConsoleReporter;

impl Reporter for ConsoleReporter {
    fn finding(&self, e: &AuditEntry) {
        eprintln!("[redact-audit] {} tier={} group={} label={} count={}",
            e.file, e.tier, e.group, e.label, e.match_count);
    }
    fn summary(&self, total: u32, log_path: &str) {
        eprintln!("[redact-audit] {total} total match(es) logged to {log_path}");
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

    struct StubResolver(Vec<String>);
    impl FileResolver for StubResolver {
        fn resolve(&self, _: &[String], _: bool) -> Vec<String> { self.0.clone() }
    }

    struct AllText;
    impl TextFilter for AllText {
        fn is_text(&self, _: &str) -> bool { true }
    }

    struct NoText;
    impl TextFilter for NoText {
        fn is_text(&self, _: &str) -> bool { false }
    }

    struct StubReader(Option<String>);
    impl ContentReader for StubReader {
        fn read(&self, _: &str, _: bool) -> Option<String> { self.0.clone() }
    }

    struct StubRunner(Vec<AuditFinding>);
    impl AuditRunner for StubRunner {
        fn audit(&self, _: &str) -> Vec<AuditFinding> { self.0.clone() }
    }

    struct StubTiers;
    impl TierLookup for StubTiers {
        fn group(&self, label: &str) -> String {
            if label.starts_with("OPENAI") { "ai_apis".into() } else { "personal_env".into() }
        }
        fn tier(&self, group: &str) -> String {
            if group == "ai_apis" { "high".into() } else { "low".into() }
        }
    }

    #[derive(Default)]
    struct CapturingLogger { entries: RefCell<Vec<AuditEntry>> }
    impl AuditLogger for CapturingLogger {
        fn log(&self, e: &AuditEntry) -> anyhow::Result<()> {
            self.entries.borrow_mut().push(e.clone()); Ok(())
        }
    }

    #[derive(Default)]
    struct CapturingReporter {
        findings: RefCell<Vec<AuditEntry>>,
        summaries: RefCell<Vec<(u32, String)>>,
    }
    impl Reporter for CapturingReporter {
        fn finding(&self, e: &AuditEntry) { self.findings.borrow_mut().push(e.clone()); }
        fn summary(&self, n: u32, p: &str) { self.summaries.borrow_mut().push((n, p.to_string())); }
    }

    fn finding(label: &str, count: u32) -> AuditFinding {
        AuditFinding { label: label.to_string(), match_count: count }
    }

    type TestAuditor = RedactAuditor<
        StubResolver, AllText, StubReader, StubRunner,
        StubTiers, CapturingLogger, CapturingReporter
    >;

    fn auditor(files: Vec<String>, content: Option<&str>, findings: Vec<AuditFinding>) -> TestAuditor {
        RedactAuditor::new(
            StubResolver(files),
            AllText,
            StubReader(content.map(str::to_string)),
            StubRunner(findings),
            StubTiers,
            CapturingLogger::default(),
            CapturingReporter::default(),
        )
    }

    fn run<FR: FileResolver, TF: TextFilter, CR: ContentReader, AR: AuditRunner, TL: TierLookup, AL: AuditLogger, R: Reporter>(
        a: &RedactAuditor<FR, TF, CR, AR, TL, AL, R>,
    ) -> u32 {
        a.run(&[], false, false, "test", "abc1234", "2026-03-29T00:00:00Z", ".logs/redact-audit.jsonl").unwrap()
    }

    fn run_verbose(a: &TestAuditor) -> u32 {
        a.run(&[], false, true, "test", "abc1234", "2026-03-29T00:00:00Z", ".logs/redact-audit.jsonl").unwrap()
    }

    // ── Core logic tests ──────────────────────────────────────────────────

    #[test]
    fn no_files_returns_zero_hits() {
        let a = auditor(vec![], Some("content"), vec![]);
        assert_eq!(run(&a), 0);
        assert!(a.logger.entries.borrow().is_empty());
    }

    #[test]
    fn empty_content_skips_file() {
        let a = auditor(vec!["file.md".into()], None, vec![finding("OPENAI_KEY", 1)]);
        assert_eq!(run(&a), 0);
        assert!(a.logger.entries.borrow().is_empty());
    }

    #[test]
    fn no_findings_logs_nothing() {
        let a = auditor(vec!["file.md".into()], Some("clean content"), vec![]);
        assert_eq!(run(&a), 0);
        assert!(a.logger.entries.borrow().is_empty());
    }

    #[test]
    fn finding_is_logged_with_correct_fields() {
        let a = auditor(vec!["secret.env".into()], Some("sk-..."), vec![finding("OPENAI_KEY", 2)]);
        assert_eq!(run(&a), 2);
        let entries = a.logger.entries.borrow();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].label, "OPENAI_KEY");
        assert_eq!(entries[0].match_count, 2);
        assert_eq!(entries[0].tier, "high");
        assert_eq!(entries[0].group, "ai_apis");
        assert_eq!(entries[0].file, "secret.env");
        assert_eq!(entries[0].commit, "abc1234");
        assert_eq!(entries[0].hook, "test");
    }

    #[test]
    fn multiple_findings_all_logged() {
        let a = auditor(
            vec!["f.env".into()],
            Some("content"),
            vec![finding("OPENAI_KEY", 1), finding("OTHER", 3)],
        );
        assert_eq!(run(&a), 4);
        assert_eq!(a.logger.entries.borrow().len(), 2);
    }

    #[test]
    fn non_text_files_skipped() {
        let a = RedactAuditor::new(
            StubResolver(vec!["image.png".into()]),
            NoText,
            StubReader(Some("content".into())),
            StubRunner(vec![finding("OPENAI_KEY", 1)]),
            StubTiers,
            CapturingLogger::default(),
            CapturingReporter::default(),
        );
        assert_eq!(run(&a), 0);
        assert!(a.logger.entries.borrow().is_empty());
    }

    #[test]
    fn verbose_mode_reports_each_finding() {
        let a = auditor(vec!["f.md".into()], Some("content"), vec![finding("OPENAI_KEY", 1)]);
        run_verbose(&a);
        assert_eq!(a.reporter.findings.borrow().len(), 1);
    }

    #[test]
    fn verbose_mode_reports_summary_when_hits_nonzero() {
        let a = auditor(vec!["f.md".into()], Some("content"), vec![finding("OPENAI_KEY", 2)]);
        run_verbose(&a);
        assert_eq!(a.reporter.summaries.borrow().len(), 1);
        assert_eq!(a.reporter.summaries.borrow()[0].0, 2);
    }

    #[test]
    fn non_verbose_mode_never_calls_reporter() {
        let a = auditor(vec!["f.md".into()], Some("content"), vec![finding("OPENAI_KEY", 5)]);
        run(&a);
        assert!(a.reporter.findings.borrow().is_empty());
        assert!(a.reporter.summaries.borrow().is_empty());
    }

    #[test]
    fn zero_hits_verbose_does_not_emit_summary() {
        let a = auditor(vec!["f.md".into()], Some("content"), vec![]);
        run_verbose(&a);
        assert!(a.reporter.summaries.borrow().is_empty());
    }

    // ── parse_audit_output tests ──────────────────────────────────────────

    #[test]
    fn parse_audit_output_empty_string_returns_empty() {
        assert!(parse_audit_output("").is_empty());
    }

    #[test]
    fn parse_audit_output_parses_single_finding() {
        let output = "  [REDACTED-OPENAI_KEY]    3";
        let findings = parse_audit_output(output);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].label, "OPENAI_KEY");
        assert_eq!(findings[0].match_count, 3);
    }

    #[test]
    fn parse_audit_output_parses_multiple_findings() {
        let output = "  [REDACTED-OPENAI_KEY]    2\n  [REDACTED-AWS_SECRET]    1";
        let findings = parse_audit_output(output);
        assert_eq!(findings.len(), 2);
    }

    #[test]
    fn parse_audit_output_ignores_non_matching_lines() {
        let output = "Redaction report:\n  [REDACTED-API_KEY]    1\n  Total: 1 redactions";
        let findings = parse_audit_output(output);
        assert_eq!(findings.len(), 1);
    }

    // ── DefaultTextFilter tests ───────────────────────────────────────────

    #[test]
    fn text_filter_accepts_md_extension() {
        assert!(DefaultTextFilter.is_text("README.md"));
    }

    #[test]
    fn text_filter_accepts_toml_extension() {
        assert!(DefaultTextFilter.is_text("config.toml"));
    }

    #[test]
    fn text_filter_accepts_mise_toml_basename() {
        assert!(DefaultTextFilter.is_text("path/to/.mise.toml"));
    }

    #[test]
    fn text_filter_rejects_binary_extension() {
        assert!(!DefaultTextFilter.is_text("binary.exe"));
        assert!(!DefaultTextFilter.is_text("image.png"));
        assert!(!DefaultTextFilter.is_text("archive.zip"));
    }

    // ── DefaultTierLookup tests ───────────────────────────────────────────

    #[test]
    fn tier_lookup_openai_maps_to_high() {
        let t = DefaultTierLookup;
        assert_eq!(t.group("OPENAI_KEY"), "ai_apis");
        assert_eq!(t.tier("ai_apis"), "high");
    }

    #[test]
    fn tier_lookup_private_key_maps_to_critical() {
        let t = DefaultTierLookup;
        assert_eq!(t.group("PRIVATE_KEY_RSA"), "private_keys");
        assert_eq!(t.tier("private_keys"), "critical");
    }

    #[test]
    fn tier_lookup_unknown_label_maps_to_low() {
        let t = DefaultTierLookup;
        let g = t.group("SOME_UNKNOWN_LABEL");
        assert_eq!(t.tier(&g), "low");
    }
}

// ---------------------------------------------------------------------------
// CLI + Main
// ---------------------------------------------------------------------------

use clap::Parser;

#[derive(Parser)]
#[command(
    name = "redact-audit",
    about = "Scan files for sensitive data and log findings as JSONL. Always exits 0."
)]
struct Cli {
    /// Print findings to stderr
    #[arg(long, short = 'v')]
    verbose: bool,

    /// Label for the hook field in audit log
    #[arg(long, default_value = "manual")]
    hook: String,

    /// Scan files currently staged in git
    #[arg(long)]
    staged: bool,

    /// Files to scan (default: staged files)
    files: Vec<String>,
}

fn git_commit(repo: &str) -> String {
    Command::new("git")
        .args(["-C", repo, "rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unborn".into())
}

fn now_iso() -> String {
    // Simple UTC timestamp without chrono
    let out = Command::new("date").arg("-u").arg("+%Y-%m-%dT%H:%M:%SZ").output();
    out.ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".into())
}

fn main() {
    let cli = Cli::parse();

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let repo = format!("{home}/dotfiles");
    let config = format!("{repo}/config/obfsck-secrets.yaml");
    let log_path = format!("{repo}/.logs/redact-audit.jsonl");

    let staged = cli.staged || cli.files.is_empty();
    let commit = git_commit(&repo);
    let ts = now_iso();

    let auditor = RedactAuditor::new(
        ProcessFileResolver { repo: repo.clone() },
        DefaultTextFilter,
        ProcessContentReader { repo: repo.clone() },
        ObfsckAuditRunner { config },
        DefaultTierLookup,
        JsonlAuditLogger { log_path: log_path.clone() },
        ConsoleReporter,
    );

    // Always exit 0
    let _ = auditor.run(
        &cli.files,
        staged,
        cli.verbose,
        &cli.hook,
        &commit,
        &ts,
        &log_path,
    );
}

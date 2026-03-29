#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//! ```
//!
//! System health summary and resource overview.
//!
//! Usage:
//!   system-health [summary|live|procs|disk]

// ---------------------------------------------------------------------------
// Domain — types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct HostInfo {
    pub time: String,
    pub uptime: String,
    pub kernel: String,
    pub memory: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiskLine {
    pub raw: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DirEntry {
    pub size: String,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcEntry {
    pub raw: String,
}

// ---------------------------------------------------------------------------
// Domain — ports
// ---------------------------------------------------------------------------

pub trait SystemInfo {
    fn host_info(&self) -> anyhow::Result<HostInfo>;
}

pub trait DiskInfo {
    fn disk_lines(&self) -> anyhow::Result<Vec<DiskLine>>;
}

pub trait DirSizer {
    fn largest_dirs(&self, path: &str, depth: usize, limit: usize) -> anyhow::Result<Vec<DirEntry>>;
}

pub trait ProcLister {
    fn top_procs(&self, limit: usize) -> anyhow::Result<Vec<ProcEntry>>;
}

pub trait Reporter {
    fn section(&self, title: &str);
    fn line(&self, text: &str);
    fn blank(&self);
}

pub trait Launcher {
    fn exec_interactive(&self, candidates: &[&str]) -> anyhow::Result<()>;
}

// ---------------------------------------------------------------------------
// Domain — core logic
// ---------------------------------------------------------------------------

pub struct HealthChecker<S, D, Z, P, R>
where
    S: SystemInfo,
    D: DiskInfo,
    Z: DirSizer,
    P: ProcLister,
    R: Reporter,
{
    sys: S,
    disk: D,
    sizer: Z,
    procs: P,
    reporter: R,
}

impl<S, D, Z, P, R> HealthChecker<S, D, Z, P, R>
where
    S: SystemInfo,
    D: DiskInfo,
    Z: DirSizer,
    P: ProcLister,
    R: Reporter,
{
    pub fn new(sys: S, disk: D, sizer: Z, procs: P, reporter: R) -> Self {
        Self { sys, disk, sizer, procs, reporter }
    }

    pub fn summary(&self, cwd: &str) -> anyhow::Result<()> {
        let info = self.sys.host_info()?;
        self.reporter.section("host summary");
        self.reporter.line(&format!("time: {}", info.time));
        self.reporter.line(&format!("uptime: {}", info.uptime));
        self.reporter.line(&format!("kernel: {}", info.kernel));
        if let Some(mem) = &info.memory {
            self.reporter.line(&format!("memory: {mem}"));
        } else {
            self.reporter.line("memory: unavailable");
        }

        self.reporter.blank();
        self.reporter.section("disk usage");
        for line in self.disk.disk_lines()? {
            self.reporter.line(&line.raw);
        }

        self.reporter.blank();
        self.reporter.section("largest directories (cwd)");
        for entry in self.sizer.largest_dirs(cwd, 2, 20)? {
            self.reporter.line(&format!("{:>8}  {}", entry.size, entry.path));
        }

        self.reporter.blank();
        self.reporter.section("top processes");
        for proc in self.procs.top_procs(25)? {
            self.reporter.line(&proc.raw);
        }

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Infrastructure adapters
// ---------------------------------------------------------------------------

use std::process::Command;

fn run_cmd(prog: &str, args: &[&str]) -> anyhow::Result<String> {
    let out = Command::new(prog).args(args).output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn cmd_exists(prog: &str) -> bool {
    Command::new("which").arg(prog).output().map(|o| o.status.success()).unwrap_or(false)
}

pub struct ProcessSystemInfo;

impl SystemInfo for ProcessSystemInfo {
    fn host_info(&self) -> anyhow::Result<HostInfo> {
        let time = run_cmd("date", &[]).unwrap_or_else(|_| "unknown".into());
        let uptime_raw = run_cmd("uptime", &[]).unwrap_or_else(|_| "unknown".into());
        let uptime = uptime_raw.trim_start().to_string();
        let kernel = run_cmd("uname", &["-srmo"])
            .or_else(|_| run_cmd("uname", &["-a"]))
            .unwrap_or_else(|_| "unknown".into());

        let memory = if cfg!(target_os = "macos") {
            Command::new("top").args(["-l", "1", "-n", "0"]).output().ok()
                .and_then(|o| {
                    String::from_utf8_lossy(&o.stdout)
                        .lines()
                        .find(|l| l.contains("PhysMem:"))
                        .and_then(|l| l.splitn(2, ": ").nth(1))
                        .map(|s| s.trim().to_string())
                })
        } else {
            None
        };

        Ok(HostInfo { time, uptime, kernel, memory })
    }
}

pub struct ProcessDiskInfo;

impl DiskInfo for ProcessDiskInfo {
    fn disk_lines(&self) -> anyhow::Result<Vec<DiskLine>> {
        let raw = if cmd_exists("duf") {
            run_cmd("duf", &[])?
        } else {
            run_cmd("df", &["-h"])?
        };
        Ok(raw.lines().map(|l| DiskLine { raw: l.to_string() }).collect())
    }
}

pub struct ProcessDirSizer;

impl DirSizer for ProcessDirSizer {
    fn largest_dirs(&self, path: &str, depth: usize, limit: usize) -> anyhow::Result<Vec<DirEntry>> {
        let raw = if cmd_exists("dust") {
            run_cmd("dust", &["-r", "-d", &depth.to_string(), path])?
        } else {
            let depth_str = depth.to_string();
            let out = Command::new("du").args(["-h", "-d", &depth_str, path]).output()?;
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let mut lines: Vec<&str> = stdout.lines().collect();
            lines.sort_by_key(|l| l.split_whitespace().next().unwrap_or("").to_string());
            lines.iter().rev().take(limit).cloned().collect::<Vec<_>>().join("\n")
        };
        Ok(raw.lines().map(|l| {
            let mut parts = l.splitn(2, '\t');
            let size = parts.next().unwrap_or("").trim().to_string();
            let path = parts.next().unwrap_or(l).trim().to_string();
            DirEntry { size, path }
        }).collect())
    }
}

pub struct ProcessProcLister;

impl ProcLister for ProcessProcLister {
    fn top_procs(&self, limit: usize) -> anyhow::Result<Vec<ProcEntry>> {
        let raw = if cmd_exists("procs") {
            run_cmd("procs", &["--sortd", "cpu"])?
        } else {
            run_cmd("ps", &["aux"])?
        };
        Ok(raw.lines().take(limit).map(|l| ProcEntry { raw: l.to_string() }).collect())
    }
}

pub struct ConsoleReporter;

impl Reporter for ConsoleReporter {
    fn section(&self, title: &str) { eprintln!("[health] {title}"); }
    fn line(&self, text: &str)     { println!("{text}"); }
    fn blank(&self)                { println!(); }
}

pub struct ProcessLauncher;

impl Launcher for ProcessLauncher {
    fn exec_interactive(&self, candidates: &[&str]) -> anyhow::Result<()> {
        use std::os::unix::process::CommandExt;
        for prog in candidates {
            if cmd_exists(prog) {
                let err = Command::new(prog).exec();
                anyhow::bail!("exec {prog}: {err}");
            }
        }
        anyhow::bail!("none of {:?} found in PATH", candidates)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct StubSysInfo(HostInfo);
    impl SystemInfo for StubSysInfo {
        fn host_info(&self) -> anyhow::Result<HostInfo> { Ok(self.0.clone()) }
    }

    struct StubDisk(Vec<DiskLine>);
    impl DiskInfo for StubDisk {
        fn disk_lines(&self) -> anyhow::Result<Vec<DiskLine>> { Ok(self.0.clone()) }
    }

    struct StubSizer(Vec<DirEntry>);
    impl DirSizer for StubSizer {
        fn largest_dirs(&self, _: &str, _: usize, _: usize) -> anyhow::Result<Vec<DirEntry>> {
            Ok(self.0.clone())
        }
    }

    struct StubProcs(Vec<ProcEntry>);
    impl ProcLister for StubProcs {
        fn top_procs(&self, _: usize) -> anyhow::Result<Vec<ProcEntry>> { Ok(self.0.clone()) }
    }

    #[derive(Default)]
    struct CapturingReporter {
        sections: RefCell<Vec<String>>,
        lines:    RefCell<Vec<String>>,
        blanks:   RefCell<usize>,
    }
    impl Reporter for CapturingReporter {
        fn section(&self, t: &str) { self.sections.borrow_mut().push(t.to_string()); }
        fn line(&self, t: &str)    { self.lines.borrow_mut().push(t.to_string()); }
        fn blank(&self)            { *self.blanks.borrow_mut() += 1; }
    }

    fn host(memory: Option<&str>) -> HostInfo {
        HostInfo {
            time:   "Sat Mar 29 12:00:00 EDT 2026".into(),
            uptime: "up 2 days".into(),
            kernel: "Darwin 25.4.0 arm64".into(),
            memory: memory.map(String::from),
        }
    }

    fn checker(
        info: HostInfo,
        disk: Vec<DiskLine>,
        dirs: Vec<DirEntry>,
        procs: Vec<ProcEntry>,
    ) -> HealthChecker<StubSysInfo, StubDisk, StubSizer, StubProcs, CapturingReporter> {
        HealthChecker::new(
            StubSysInfo(info),
            StubDisk(disk),
            StubSizer(dirs),
            StubProcs(procs),
            CapturingReporter::default(),
        )
    }

    #[test]
    fn summary_emits_four_sections() {
        let c = checker(host(None), vec![], vec![], vec![]);
        c.summary(".").unwrap();
        let sections = c.reporter.sections.borrow();
        assert!(sections.contains(&"host summary".to_string()));
        assert!(sections.contains(&"disk usage".to_string()));
        assert!(sections.contains(&"largest directories (cwd)".to_string()));
        assert!(sections.contains(&"top processes".to_string()));
    }

    #[test]
    fn summary_includes_host_fields() {
        let c = checker(host(Some("16G used")), vec![], vec![], vec![]);
        c.summary(".").unwrap();
        let lines = c.reporter.lines.borrow();
        assert!(lines.iter().any(|l| l.contains("Sat Mar 29")));
        assert!(lines.iter().any(|l| l.contains("up 2 days")));
        assert!(lines.iter().any(|l| l.contains("Darwin")));
        assert!(lines.iter().any(|l| l.contains("16G used")));
    }

    #[test]
    fn summary_shows_memory_unavailable_when_none() {
        let c = checker(host(None), vec![], vec![], vec![]);
        c.summary(".").unwrap();
        let lines = c.reporter.lines.borrow();
        assert!(lines.iter().any(|l| l.contains("memory: unavailable")));
    }

    #[test]
    fn summary_renders_disk_lines() {
        let disk = vec![
            DiskLine { raw: "/dev/disk1s1  100G  60G  40G".into() },
            DiskLine { raw: "/dev/disk1s2  200G  10G  190G".into() },
        ];
        let c = checker(host(None), disk, vec![], vec![]);
        c.summary(".").unwrap();
        let lines = c.reporter.lines.borrow();
        assert!(lines.iter().any(|l| l.contains("disk1s1")));
        assert!(lines.iter().any(|l| l.contains("disk1s2")));
    }

    #[test]
    fn summary_renders_dir_entries() {
        let dirs = vec![
            DirEntry { size: "1.2G".into(), path: "./dev".into() },
            DirEntry { size: "500M".into(), path: "./logs".into() },
        ];
        let c = checker(host(None), vec![], dirs, vec![]);
        c.summary(".").unwrap();
        let lines = c.reporter.lines.borrow();
        assert!(lines.iter().any(|l| l.contains("1.2G") && l.contains("./dev")));
        assert!(lines.iter().any(|l| l.contains("500M") && l.contains("./logs")));
    }

    #[test]
    fn summary_renders_proc_entries() {
        let procs = vec![
            ProcEntry { raw: "joe  1234  99.0  0.1  cargo".into() },
            ProcEntry { raw: "joe  5678  0.5   0.0  zsh".into() },
        ];
        let c = checker(host(None), vec![], vec![], procs);
        c.summary(".").unwrap();
        let lines = c.reporter.lines.borrow();
        assert!(lines.iter().any(|l| l.contains("cargo")));
        assert!(lines.iter().any(|l| l.contains("zsh")));
    }

    #[test]
    fn summary_emits_three_blank_separators() {
        let c = checker(host(None), vec![], vec![], vec![]);
        c.summary(".").unwrap();
        assert_eq!(*c.reporter.blanks.borrow(), 3);
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

use clap::Parser;

#[derive(Parser)]
#[command(name = "system-health", about = "System health summary and resource overview")]
struct Cli {
    #[arg(default_value = "summary")]
    mode: String,

    #[arg(long, default_value = ".")]
    cwd: String,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.mode.as_str() {
        "summary" => {
            HealthChecker::new(
                ProcessSystemInfo,
                ProcessDiskInfo,
                ProcessDirSizer,
                ProcessProcLister,
                ConsoleReporter,
            ).summary(&cli.cwd)?;
        }
        "live"  => { ProcessLauncher.exec_interactive(&["btm", "btop", "top"])?; }
        "procs" => { ProcessLauncher.exec_interactive(&["procs", "ps"])?; }
        "disk"  => { ProcessLauncher.exec_interactive(&["duf", "df"])?; }
        _ => {
            eprintln!("Usage: system-health [summary|live|procs|disk]");
            std::process::exit(1);
        }
    }

    Ok(())
}

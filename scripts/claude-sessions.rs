#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//! flate2 = "1"
//! serde_json = "1"
//! ```
//!
//! Query and analyse Claude Code session data from Vector JSONL shards.
//!
//! Usage:
//!   claude-sessions sessions              # list all sessions with stats
//!   claude-sessions tools                 # tool call frequency across all sessions
//!   claude-sessions agents                # subagent dispatch breakdown by type
//!   claude-sessions tree <session-id>     # print tool/subagent tree for one session
//!   claude-sessions show <session-id>     # full turn-by-turn timeline for a session

use anyhow::Result;
use clap::{Parser, Subcommand};
use flate2::read::GzDecoder;
use serde_json::Value;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

struct ToolCall {
    name: String,
    uuid: String,
    timestamp: String,
    is_sidechain: bool,
}

struct AgentDispatch {
    uuid: String,
    subagent_type: String,
    description: String,
    model: String,
    timestamp: String,
}

#[derive(Default)]
struct Session {
    session_id: String,
    cwd: String,
    slug: String,
    git_branch: String,
    first_ts: String,
    last_ts: String,
    events: Vec<Value>,
    tool_calls: Vec<ToolCall>,
    agent_dispatches: Vec<AgentDispatch>,
    sidechain_events: Vec<Value>,
    input_tokens: u64,
    output_tokens: u64,
    cache_read_tokens: u64,
    _cache_write_tokens: u64,
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(name = "claude-sessions", about = "Analyse Claude Code sessions from Vector logs")]
struct Cli {
    /// Vector JSONL shard directory (default: $INFRA_VECTOR_LOG_ROOT or ~/logs/ai/vector)
    #[arg(long)]
    vector_root: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List all sessions with stats
    Sessions {
        #[arg(long, default_value_t = 30)]
        limit: usize,
    },
    /// Tool call frequency across all sessions
    Tools,
    /// Subagent dispatch breakdown by type
    Agents {
        #[arg(long)]
        detail: bool,
    },
    /// Print tool/subagent tree for one session
    Tree { session_id: String },
    /// Full turn-by-turn timeline for a session
    Show { session_id: String },
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

fn iter_claude_events(vector_root: &Path) -> impl Iterator<Item = Value> {
    let mut shards: Vec<PathBuf> = std::fs::read_dir(vector_root)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            let name = p.file_name().unwrap_or_default().to_string_lossy();
            name.ends_with(".jsonl") || name.ends_with(".jsonl.gz")
        })
        .collect();
    shards.sort();

    shards.into_iter().flat_map(|shard| {
        let lines: Box<dyn Iterator<Item = String>> =
            if shard.extension().map_or(false, |e| e == "gz") {
                match File::open(&shard).map(|f| BufReader::new(GzDecoder::new(f))) {
                    Ok(r) => Box::new(r.lines().flatten()),
                    Err(_) => Box::new(std::iter::empty()),
                }
            } else {
                match File::open(&shard).map(BufReader::new) {
                    Ok(r) => Box::new(r.lines().flatten()),
                    Err(_) => Box::new(std::iter::empty()),
                }
            };

        lines.filter_map(|line| {
            let v: Value = serde_json::from_str(&line).ok()?;
            if v.get("source")?.as_str()? == "claude-code" {
                Some(v)
            } else {
                None
            }
        })
    })
}

fn parse_ts(raw: &Value) -> String {
    match raw {
        Value::Number(n) => {
            // ms epoch → ISO-ish string for lexicographic comparison
            let ms = n.as_u64().unwrap_or(0);
            let secs = ms / 1000;
            let ms_rem = ms % 1000;
            // Simple formatting without chrono: just produce a comparable string
            // Using RFC 3339-ish format via basic arithmetic
            // Numeric string padded for lexicographic sort compatibility
            format!("{secs:010}.{ms_rem:03}Z")
        }
        Value::String(s) => s.clone(),
        _ => String::new(),
    }
}

fn load_sessions(vector_root: &Path) -> HashMap<String, Session> {
    let mut sessions: HashMap<String, Session> = HashMap::new();

    for e in iter_claude_events(vector_root) {
        let sid = e
            .get("sessionId")
            .or_else(|| e.get("session"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if sid.is_empty() {
            continue;
        }

        let s = sessions.entry(sid.clone()).or_insert_with(|| Session {
            session_id: sid.clone(),
            ..Default::default()
        });

        let ts = parse_ts(e.get("timestamp").unwrap_or(&Value::Null));
        if !ts.is_empty() {
            if s.first_ts.is_empty() || ts < s.first_ts {
                s.first_ts = ts.clone();
            }
            if ts > s.last_ts {
                s.last_ts = ts.clone();
            }
        }

        if s.cwd.is_empty() {
            if let Some(v) = e.get("cwd").and_then(|v| v.as_str()) {
                s.cwd = v.to_string();
            }
        }
        if s.slug.is_empty() {
            if let Some(v) = e.get("slug").and_then(|v| v.as_str()) {
                s.slug = v.to_string();
            }
        }
        if s.git_branch.is_empty() {
            if let Some(v) = e.get("gitBranch").and_then(|v| v.as_str()) {
                s.git_branch = v.to_string();
            }
        }

        let is_sidechain = e.get("isSidechain").and_then(|v| v.as_bool()).unwrap_or(false);

        if e.get("type").and_then(|v| v.as_str()) == Some("assistant") {
            let msg = e.get("message").and_then(|v| v.as_object());
            if let Some(msg) = msg {
                let usage = msg.get("usage").and_then(|v| v.as_object());
                if let Some(u) = usage {
                    s.input_tokens += u.get("input_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
                    s.output_tokens += u.get("output_tokens").and_then(|v| v.as_u64()).unwrap_or(0);
                    s.cache_read_tokens += u
                        .get("cache_read_input_tokens")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);
                    s._cache_write_tokens += u
                        .get("cache_creation_input_tokens")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);
                }

                if let Some(content) = msg.get("content").and_then(|v| v.as_array()) {
                    let uuid = e.get("uuid").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    for block in content {
                        if block.get("type").and_then(|v| v.as_str()) != Some("tool_use") {
                            continue;
                        }
                        let name = block
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("?")
                            .to_string();
                        s.tool_calls.push(ToolCall {
                            name: name.clone(),
                            uuid: uuid.clone(),
                            timestamp: ts.clone(),
                            is_sidechain,
                        });
                        if name == "Agent" {
                            let input = block.get("input").and_then(|v| v.as_object());
                            s.agent_dispatches.push(AgentDispatch {
                                uuid: uuid.clone(),
                                subagent_type: input
                                    .and_then(|i| i.get("subagent_type"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("?")
                                    .to_string(),
                                description: input
                                    .and_then(|i| i.get("description"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                model: input
                                    .and_then(|i| i.get("model"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_string(),
                                timestamp: ts.clone(),
                            });
                        }
                    }
                }
            }
        }

        if is_sidechain {
            s.sidechain_events.push(e.clone());
        }
        s.events.push(e);
    }

    sessions
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

fn short_ts(ts: &str) -> String {
    if ts.is_empty() {
        return "n/a".to_string();
    }
    // Handle ISO: take first 16 chars "YYYY-MM-DDTHH:MM" → "YYYY-MM-DD HH:MM"
    let s = if ts.len() >= 16 { &ts[..16] } else { ts };
    s.replace('T', " ")
}

fn short_id(s: &str) -> &str {
    if s.len() >= 8 { &s[..8] } else { s }
}

fn fmt_tokens(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1}M", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.0}K", n as f64 / 1_000.0)
    } else {
        n.to_string()
    }
}

fn short_path(p: &str) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    if !home.is_empty() && p.starts_with(&home) {
        format!("~{}", &p[home.len()..])
    } else {
        p.to_string()
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmd_sessions(sessions: &HashMap<String, Session>, limit: usize) {
    let mut rows: Vec<&Session> = sessions.values().collect();
    rows.sort_by(|a, b| b.last_ts.cmp(&a.last_ts));
    rows.truncate(limit);

    println!(
        "{:>8}  {:<28}  {:>5}  {:>6}  {:>7}  {:>7}  {:>7}  {:<16}  {}",
        "SESSION", "SLUG", "TOOLS", "AGENTS", "IN", "OUT", "CR", "FIRST", "CWD"
    );
    println!("{}", "-".repeat(130));

    for s in &rows {
        let main_tools = s.tool_calls.iter().filter(|tc| !tc.is_sidechain).count();
        let side_tools = s.tool_calls.iter().filter(|tc| tc.is_sidechain).count();
        let tool_str = if side_tools == 0 {
            format!("{main_tools}")
        } else {
            format!("{main_tools}+{side_tools}s")
        };
        let slug = if s.slug.len() > 28 { &s.slug[..28] } else { &s.slug };
        println!(
            "{:>8}  {:<28}  {:>5}  {:>6}  {:>7}  {:>7}  {:>7}  {:<16}  {}",
            short_id(&s.session_id),
            slug,
            tool_str,
            s.agent_dispatches.len(),
            fmt_tokens(s.input_tokens),
            fmt_tokens(s.output_tokens),
            fmt_tokens(s.cache_read_tokens),
            short_ts(&s.first_ts),
            short_path(&s.cwd),
        );
    }
    println!("\n{} total sessions", sessions.len());
}

fn cmd_tools(sessions: &HashMap<String, Session>) {
    let mut counts: HashMap<&str, u64> = HashMap::new();
    let mut sidechain_counts: HashMap<&str, u64> = HashMap::new();

    for s in sessions.values() {
        for tc in &s.tool_calls {
            if tc.is_sidechain {
                *sidechain_counts.entry(tc.name.as_str()).or_default() += 1;
            } else {
                *counts.entry(tc.name.as_str()).or_default() += 1;
            }
        }
    }

    let mut all_tools: Vec<&str> = counts.keys().chain(sidechain_counts.keys()).copied().collect();
    all_tools.sort();
    all_tools.dedup();
    all_tools.sort_by_key(|t| std::cmp::Reverse(counts.get(t).unwrap_or(&0) + sidechain_counts.get(t).unwrap_or(&0)));

    println!("{:<30}  {:>6}  {:>9}  {:>6}", "TOOL", "MAIN", "SIDECHAIN", "TOTAL");
    println!("{}", "-".repeat(60));
    for tool in &all_tools {
        let m = counts.get(tool).copied().unwrap_or(0);
        let sc = sidechain_counts.get(tool).copied().unwrap_or(0);
        println!("{:<30}  {:>6}  {:>9}  {:>6}", tool, m, sc, m + sc);
    }
    let total_main: u64 = counts.values().sum();
    let total_side: u64 = sidechain_counts.values().sum();
    println!("\n{total_main} main + {total_side} sidechain tool calls");
}

fn cmd_agents(sessions: &HashMap<String, Session>, detail: bool) {
    let mut by_type: HashMap<&str, u64> = HashMap::new();
    let mut by_session: HashMap<&str, Vec<(&Session, &AgentDispatch)>> = HashMap::new();

    for s in sessions.values() {
        for d in &s.agent_dispatches {
            *by_type.entry(d.subagent_type.as_str()).or_default() += 1;
            by_session.entry(d.subagent_type.as_str()).or_default().push((s, d));
        }
    }

    let mut sorted: Vec<(&str, u64)> = by_type.iter().map(|(&k, &v)| (k, v)).collect();
    sorted.sort_by_key(|(_, n)| std::cmp::Reverse(*n));

    println!("{:<40}  {:>5}", "SUBAGENT TYPE", "COUNT");
    println!("{}", "-".repeat(50));
    for (t, n) in &sorted {
        println!("{:<40}  {:>5}", t, n);
    }

    if detail {
        println!();
        for (t, _) in &sorted {
            let rows = by_session.get(t).map(|v| v.as_slice()).unwrap_or(&[]);
            println!("\n── {t} ({} dispatches) ──", rows.len());
            for (s, d) in rows.iter().take(10) {
                println!("  [{}] {} {}", short_ts(&d.timestamp), short_id(&s.session_id), &s.slug.chars().take(20).collect::<String>());
                if !d.description.is_empty() {
                    println!("    {}", &d.description.chars().take(60).collect::<String>());
                }
            }
        }
    }
}

fn cmd_tree(sessions: &HashMap<String, Session>, target: &str) {
    let matches: Vec<&Session> = sessions
        .values()
        .filter(|s| s.session_id.starts_with(target) || s.slug == target)
        .collect();

    if matches.is_empty() {
        eprintln!("No session matching '{target}'");
        std::process::exit(1);
    }
    if matches.len() > 1 {
        eprintln!("Ambiguous: {} sessions match '{target}':", matches.len());
        for m in &matches {
            eprintln!("  {}  {}", m.session_id, m.slug);
        }
        std::process::exit(1);
    }
    let s = matches[0];

    println!("Session: {}", s.session_id);
    println!("  slug:    {}", s.slug);
    println!("  cwd:     {}", short_path(&s.cwd));
    println!("  branch:  {}", s.git_branch);
    println!("  period:  {} → {}", short_ts(&s.first_ts), short_ts(&s.last_ts));
    println!("  tokens:  in={} out={} cache_read={}", fmt_tokens(s.input_tokens), fmt_tokens(s.output_tokens), fmt_tokens(s.cache_read_tokens));
    println!();

    // Build uuid → dispatch map
    let uuid_to_dispatch: HashMap<&str, &AgentDispatch> =
        s.agent_dispatches.iter().map(|d| (d.uuid.as_str(), d)).collect();

    // Group sidechain events by parentUuid
    let mut sidechain_by_parent: HashMap<&str, Vec<&Value>> = HashMap::new();
    for e in &s.sidechain_events {
        let parent = e.get("parentUuid").and_then(|v| v.as_str()).unwrap_or("");
        sidechain_by_parent.entry(parent).or_default().push(e);
    }

    println!("Main timeline (sorted by time):");
    let mut main_calls: Vec<&ToolCall> = s.tool_calls.iter().filter(|tc| !tc.is_sidechain).collect();
    main_calls.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));

    for tc in &main_calls {
        println!("  [{}] {}", short_ts(&tc.timestamp), tc.name);
        if tc.name == "Agent" {
            if let Some(dispatch) = uuid_to_dispatch.get(tc.uuid.as_str()) {
                let model_str = if dispatch.model.is_empty() { String::new() } else { format!(" [{}]", dispatch.model) };
                println!("    └─ subagent_type: {}{model_str}", dispatch.subagent_type);
                if !dispatch.description.is_empty() {
                    println!("       desc: {}", &dispatch.description.chars().take(80).collect::<String>());
                }
            }
            if let Some(children) = sidechain_by_parent.get(tc.uuid.as_str()) {
                let mut child_tools: Vec<String> = Vec::new();
                for ce in children {
                    if ce.get("type").and_then(|v| v.as_str()) == Some("assistant") {
                        if let Some(content) = ce.get("message").and_then(|m| m.get("content")).and_then(|v| v.as_array()) {
                            for block in content {
                                if block.get("type").and_then(|v| v.as_str()) == Some("tool_use") {
                                    if let Some(name) = block.get("name").and_then(|v| v.as_str()) {
                                        child_tools.push(name.to_string());
                                    }
                                }
                            }
                        }
                    }
                }
                if !child_tools.is_empty() {
                    let mut counts: HashMap<&str, usize> = HashMap::new();
                    for t in &child_tools { *counts.entry(t.as_str()).or_default() += 1; }
                    let mut summary: Vec<_> = counts.iter().collect();
                    summary.sort_by_key(|(_, n)| std::cmp::Reverse(**n));
                    let s = summary.iter().take(6).map(|(k, n)| format!("{n}×{k}")).collect::<Vec<_>>().join(", ");
                    println!("       tools: {s}");
                }
            }
        }
    }

    println!();
    let mut tool_counts: HashMap<&str, usize> = HashMap::new();
    for tc in s.tool_calls.iter().filter(|tc| !tc.is_sidechain) {
        *tool_counts.entry(tc.name.as_str()).or_default() += 1;
    }
    let mut tc_sorted: Vec<_> = tool_counts.iter().collect();
    tc_sorted.sort_by_key(|(_, n)| std::cmp::Reverse(**n));
    let tc_str: Vec<_> = tc_sorted.iter().take(10).map(|(k, v)| format!("{k}: {v}")).collect();
    println!("Main tool counts: {{{}}}", tc_str.join(", "));
    println!("Agent dispatches: {}", s.agent_dispatches.len());

    let mut sc_counts: HashMap<&str, usize> = HashMap::new();
    for tc in s.tool_calls.iter().filter(|tc| tc.is_sidechain) {
        *sc_counts.entry(tc.name.as_str()).or_default() += 1;
    }
    if !sc_counts.is_empty() {
        let mut sc_sorted: Vec<_> = sc_counts.iter().collect();
        sc_sorted.sort_by_key(|(_, n)| std::cmp::Reverse(**n));
        let sc_str: Vec<_> = sc_sorted.iter().take(10).map(|(k, v)| format!("{k}: {v}")).collect();
        println!("Sidechain tool counts: {{{}}}", sc_str.join(", "));
    }
}

fn cmd_show(sessions: &HashMap<String, Session>, target: &str) {
    let matches: Vec<&Session> = sessions
        .values()
        .filter(|s| s.session_id.starts_with(target) || s.slug == target)
        .collect();

    if matches.is_empty() {
        eprintln!("No session matching '{target}'");
        std::process::exit(1);
    }
    let s = matches[0];

    let mut events: Vec<&Value> = s.events.iter().collect();
    events.sort_by_key(|e| e.get("timestamp").map(|v| v.to_string()).unwrap_or_default());

    for e in events {
        let ts = short_ts(&parse_ts(e.get("timestamp").unwrap_or(&Value::Null)));
        let t = e.get("type").and_then(|v| v.as_str()).unwrap_or("?");
        let side = if e.get("isSidechain").and_then(|v| v.as_bool()).unwrap_or(false) { " [sidechain]" } else { "" };
        let prefix = format!("[{ts}] {t:<20}{side}");

        match t {
            "user" => {
                let text = e.get("message")
                    .and_then(|m| m.get("content"))
                    .map(|c| match c {
                        Value::Array(arr) => arr.iter()
                            .filter_map(|b| if b.get("type").and_then(|v| v.as_str()) == Some("text") { b.get("text").and_then(|v| v.as_str()) } else { None })
                            .collect::<Vec<_>>()
                            .join(" "),
                        Value::String(s) => s.clone(),
                        _ => String::new(),
                    })
                    .unwrap_or_default();
                println!("{}  {}", prefix, &text.chars().take(100).collect::<String>());
            }
            "assistant" => {
                let msg = e.get("message");
                let mut tools: Vec<String> = Vec::new();
                if let Some(content) = msg.and_then(|m| m.get("content")).and_then(|v| v.as_array()) {
                    for block in content {
                        if block.get("type").and_then(|v| v.as_str()) == Some("tool_use") {
                            let name = block.get("name").and_then(|v| v.as_str()).unwrap_or("?");
                            if name == "Agent" {
                                let st = block.get("input").and_then(|i| i.get("subagent_type")).and_then(|v| v.as_str()).unwrap_or("?");
                                tools.push(format!("Agent({st})"));
                            } else {
                                tools.push(name.to_string());
                            }
                        }
                    }
                }
                let usage = msg.and_then(|m| m.get("usage"));
                let inp = usage.and_then(|u| u.get("input_tokens")).and_then(|v| v.as_u64()).unwrap_or(0);
                let out = usage.and_then(|u| u.get("output_tokens")).and_then(|v| v.as_u64()).unwrap_or(0);
                println!("{}  tools=[{}]  in={inp} out={out}", prefix, tools.join(", "));
            }
            "progress" => {
                let tool_id = e.get("toolUseID").and_then(|v| v.as_str()).unwrap_or("");
                let tid = if tool_id.len() > 12 { &tool_id[..12] } else { tool_id };
                println!("{prefix}  toolUseID={tid}");
            }
            _ => println!("{prefix}"),
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    let cli = Cli::parse();

    let raw = cli.vector_root
        .or_else(|| std::env::var("INFRA_VECTOR_LOG_ROOT").ok())
        .unwrap_or_else(|| "~/logs/ai/vector".to_string());
    let root = raw.replace('~', &std::env::var("HOME").unwrap_or_default());
    let vector_root = PathBuf::from(&root);

    if !vector_root.exists() {
        eprintln!("Vector root not found: {}", vector_root.display());
        std::process::exit(1);
    }

    let sessions = load_sessions(&vector_root);

    match cli.command {
        Command::Sessions { limit } => cmd_sessions(&sessions, limit),
        Command::Tools => cmd_tools(&sessions),
        Command::Agents { detail } => cmd_agents(&sessions, detail),
        Command::Tree { session_id } => cmd_tree(&sessions, &session_id),
        Command::Show { session_id } => cmd_show(&sessions, &session_id),
    }

    Ok(())
}

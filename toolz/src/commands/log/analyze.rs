use anyhow::{Context, Result};
use bytesize::ByteSize;
use chrono::NaiveDateTime;
use regex::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

pub fn run(path: &str) -> Result<()> {
    let file_path = Path::new(path);
    let metadata = std::fs::metadata(file_path)
        .with_context(|| format!("cannot read {path}"))?;
    let file = File::open(file_path).with_context(|| format!("opening {path}"))?;
    let reader = BufReader::new(file);

    let mut total_lines = 0usize;
    let mut error_lines = 0usize;
    let mut warn_lines = 0usize;
    let mut level_counts: HashMap<String, usize> = HashMap::new();
    let mut first_ts: Option<String> = None;
    let mut last_ts: Option<String> = None;

    // Common timestamp patterns
    let ts_re = Regex::new(
        r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}",
    )?;
    let level_re = Regex::new(
        r"\b(ERROR|WARN(?:ING)?|INFO|DEBUG|TRACE|CRIT(?:ICAL)?|FATAL)\b",
    )?;
    let error_re = Regex::new(r"(?i)\b(error|err|exception|fail(?:ed)?|fatal|crit)\b")?;
    let warn_re = Regex::new(r"(?i)\b(warn(?:ing)?)\b")?;

    for line in reader.lines() {
        let line = line?;
        total_lines += 1;

        if error_re.is_match(&line) {
            error_lines += 1;
        }
        if warn_re.is_match(&line) {
            warn_lines += 1;
        }

        if let Some(m) = level_re.find(&line) {
            let level = m.as_str().to_uppercase();
            *level_counts.entry(level).or_insert(0) += 1;
        }

        if let Some(m) = ts_re.find(&line) {
            let ts = m.as_str().to_string();
            if first_ts.is_none() {
                first_ts = Some(ts.clone());
            }
            last_ts = Some(ts);
        }
    }

    println!("\n── Log Summary: {path} ──");
    println!("  Size:        {}", ByteSize::b(metadata.len()));
    println!("  Total lines: {total_lines}");
    println!("  Errors:      {error_lines}");
    println!("  Warnings:    {warn_lines}");

    if !level_counts.is_empty() {
        println!("\n  Log levels:");
        let mut sorted: Vec<_> = level_counts.iter().collect();
        sorted.sort_by_key(|(_, v)| std::cmp::Reverse(**v));
        for (level, count) in sorted {
            println!("    {level:<10} {count}");
        }
    }

    if let (Some(first), Some(last)) = (first_ts, last_ts) {
        println!("\n  First entry: {first}");
        println!("  Last entry:  {last}");

        // Attempt to compute duration
        let fmt = "%Y-%m-%dT%H:%M:%S";
        let fmt2 = "%Y-%m-%d %H:%M:%S";
        if let (Ok(t0), Ok(t1)) = (
            NaiveDateTime::parse_from_str(&first, fmt)
                .or_else(|_| NaiveDateTime::parse_from_str(&first, fmt2)),
            NaiveDateTime::parse_from_str(&last, fmt)
                .or_else(|_| NaiveDateTime::parse_from_str(&last, fmt2)),
        ) {
            let dur = t1 - t0;
            println!(
                "  Duration:    {}h {}m {}s",
                dur.num_hours(),
                dur.num_minutes() % 60,
                dur.num_seconds() % 60
            );
        }
    }

    println!();
    Ok(())
}

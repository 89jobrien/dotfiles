use anyhow::{Context, Result};
use regex::Regex;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

const DEFAULT_PATTERN: &str = r"(?i)\b(error|warn(?:ing)?|exception|fatal|crit(?:ical)?|ERRO|WARN)\b";

pub fn run(path: &str, pattern: Option<&str>) -> Result<()> {
    let file_path = Path::new(path);
    let file = File::open(file_path).with_context(|| format!("opening {path}"))?;
    let reader = BufReader::new(file);

    let pat = pattern.unwrap_or(DEFAULT_PATTERN);
    let re = Regex::new(pat).with_context(|| format!("invalid regex: {pat}"))?;

    let mut matches = 0usize;
    println!("\n── Matching lines in {path} (pattern: {pat}) ──\n");

    for (lineno, line) in reader.lines().enumerate() {
        let line = line?;
        if re.is_match(&line) {
            matches += 1;
            // Highlight matches in the output
            let highlighted = re.replace_all(&line, |caps: &regex::Captures| {
                format!("\x1b[31m{}\x1b[0m", &caps[0])
            });
            println!("{:>6}: {highlighted}", lineno + 1);
        }
    }

    println!("\n── {matches} matching line(s) ──\n");
    Ok(())
}

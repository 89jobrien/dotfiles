use indicatif::{ProgressBar, ProgressStyle};
use std::time::Duration;

pub fn spinner(msg: &str) -> ProgressBar {
    let pb = ProgressBar::new_spinner();
    pb.set_style(
        ProgressStyle::with_template("{spinner:.cyan} {msg}")
            .unwrap()
            .tick_strings(&["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]),
    );
    pb.set_message(msg.to_string());
    pb.enable_steady_tick(Duration::from_millis(80));
    pb
}

pub fn ok(msg: &str) {
    println!("\x1b[32m✓\x1b[0m {msg}");
}

pub fn warn(msg: &str) {
    println!("\x1b[33m!\x1b[0m {msg}");
}

#[allow(dead_code)]
pub fn err(msg: &str) {
    eprintln!("\x1b[31m✗\x1b[0m {msg}");
}

pub fn info(msg: &str) {
    println!("\x1b[36m→\x1b[0m {msg}");
}

pub fn section(title: &str) {
    println!("\n\x1b[1;34m── {title} ──\x1b[0m");
}

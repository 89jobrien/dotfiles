---
name: rust-script
description: Use when writing any standalone Rust script, one-off utility, or when tempted to reach for a shell script with complex logic. Covers rust-script shebang, inline Cargo manifest, and dependency declaration.
---

## The Pattern

```rust
#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! ```

fn main() -> anyhow::Result<()> {
    println!("hello");
    Ok(())
}
```

Run with: `rust-script script.rs` or just `./script.rs` (if `chmod +x`)

## No-Dependency Script

```rust
#!/usr/bin/env rust-script

fn main() {
    println!("hello");
}
```

## Common Packages (copy-paste ready)

| Package | Use |
|---------|-----|
| `anyhow` | Error handling |
| `clap` | CLI argument parsing |
| `serde` + `serde_json` | JSON parsing |
| `reqwest` | HTTP (blocking feature) |
| `tokio` | Async runtime |
| `colored` | Terminal color output |
| `indicatif` | Progress bars |

## Async Script

```rust
#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! tokio = { version = "1", features = ["full"] }
//! reqwest = "0.12"
//! ```

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let body = reqwest::get("https://example.com").await?.text().await?;
    println!("{body}");
    Ok(())
}
```

## Installation

```bash
cargo install rust-script
# or via mise
mise use -g rust-script
```

## Script vs Tool Decision

| Need | Use |
|------|-----|
| Transform JSON | `jq` |
| Quick calc / string | shell arithmetic or `awk` |
| Complex logic, Rust types | `rust-script` |
| Reusable binary | proper `cargo new` project |
| Never use for scripts | `cargo run` in a throwaway project |

## Notes

- First run compiles and caches — subsequent runs are fast
- Cache lives at `~/.cache/rust-script/`
- `cargo -Zscript` (RFC 3424) is the future stable path but still nightly-only as of 2026

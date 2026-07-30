---
name: review
description: Review staged or recent changes for correctness, style, and Rust conventions before committing
trigger: /review
tags: [git, rust, code-quality]
---

# Review Skill

Review the current diff for issues before committing.

## Steps

1. Run `git diff HEAD` (or `git diff --staged` if changes are staged) to see what changed.

2. For each changed file, check:
   - **Correctness**: Logic errors, off-by-one, wrong assumptions
   - **Rust conventions**: Proper error handling (`?` vs `unwrap`), no unnecessary clones, lifetimes make sense
   - **SOLID / hexagonal**: No leaking of infra types into domain, traits used correctly
   - **Tests**: Are new behaviors covered? Are existing tests still valid?
   - **Security**: No hardcoded secrets, no SQL injection, no unvalidated input at boundaries

3. If in a Rust workspace, run:
   - `cargo clippy --all-targets 2>&1` — report any warnings
   - `cargo test --quiet 2>&1` — report any failures

4. Produce a concise report:
   - **Issues** (must fix before committing)
   - **Suggestions** (optional improvements)
   - **Verdict**: Ready to commit / Fix required

## Rules

- Be direct. Lead with issues, not praise.
- Do not make changes unless the user explicitly asks.
- If the diff is clean, say so in one sentence.

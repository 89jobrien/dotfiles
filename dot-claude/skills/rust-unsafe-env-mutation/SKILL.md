---
name: rust-unsafe-env-mutation
description: Use when writing Rust tests that call set_var or remove_var, seeing "use of unsafe function" errors in Rust 2024 edition, or when tests pass individually but fail randomly in parallel CI runs due to environment variable races.
---

# Rust Unsafe Env Mutation

## Overview

In Rust 2024 edition, `std::env::set_var` and `remove_var` are `unsafe` (process-wide mutation). `unsafe {}` alone is not enough — parallel test threads still race. You need **both**: `unsafe {}` to satisfy the compiler AND a `static Mutex<()>` to serialize access.

## Pattern

```rust
use std::sync::Mutex;

// One mutex per module (or shared across the crate via a common test helper)
static ENV_MUTEX: Mutex<()> = Mutex::new(());

#[test]
fn test_reads_env_var() {
    let _guard = ENV_MUTEX.lock().unwrap();  // serializes all env-touching tests
    unsafe { std::env::set_var("MY_VAR", "value") };

    // ... test body ...

    unsafe { std::env::remove_var("MY_VAR") };
    // _guard drops here, releasing the lock
}
```

For cleanup on panic, wrap the test body in a closure or use `defer!` pattern so `remove_var` always runs.

## Why Both Are Required

| Missing | Consequence |
|---|---|
| No `unsafe {}` | Compile error in Rust 2024: "use of unsafe function" |
| No `Mutex` | Race condition — tests pass in isolation, flaky in `cargo test` (parallel threads) |
| Both present | Compiler satisfied, tests serialized |

## Sharing the Mutex Across Tests

All tests that read or write the same env vars must use the **same** mutex instance. If tests live in different files, put the mutex in a shared test helper module:

```rust
// tests/common/mod.rs
use std::sync::Mutex;
pub static ENV_MUTEX: Mutex<()> = Mutex::new(());

// tests/foo_tests.rs
mod common;
#[test]
fn test_something() {
    let _guard = common::ENV_MUTEX.lock().unwrap();
    unsafe { std::env::set_var("FOO", "bar") };
    // ...
}
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| `unsafe` without `Mutex` | Add `static ENV_MUTEX` and lock before mutating |
| Different mutex per test file | Use shared module-level mutex |
| `remove_var` only at end (panics leave var set) | Consider `scopeguard::defer!` or check+reset pattern |
| Forgetting `remove_var` for unrelated tests | Leaked env vars cause mysterious failures in later tests |

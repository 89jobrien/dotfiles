---
name: doob-new-provider
description: Use when implementing a new sync provider adapter for doob — creating a new IssueTracker trait implementation, wiring config, and writing tests. Symptoms - "add GitHub Issues sync", "implement Linear adapter", "new sync provider".
---

# doob: New Sync Provider

## Overview

All sync providers implement the `IssueTracker` trait in `src/sync/domain.rs`. Follow the BeadsAdapter (`src/sync/adapters/beads.rs`) as the canonical reference.

## Checklist

1. **Create adapter file** `src/sync/adapters/<name>.rs`
2. **Implement `IssueTracker` trait** — `create_issue`, `is_available`, `provider_name`
3. **Add to `src/sync/adapters/mod.rs`**
4. **Add config entry** in `~/.doob/sync_providers.toml` schema doc
5. **Write 3-tier tests** (unit mock, service integration, CLI integration)
6. **Add to README** provider table

## IssueTracker Trait

```rust
#[async_trait]
pub trait IssueTracker: Send + Sync {
    fn provider_name(&self) -> &str;
    async fn is_available(&self) -> bool;
    async fn create_issue(&self, todo: &SyncableTodo) -> Result<SyncRecord, SyncError>;
}
```

## SyncableTodo Fields

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | doob UUID |
| `title` | `String` | todo content |
| `priority` | `u8` | 0–255 |
| `tags` | `Vec<String>` | todo tags |
| `project` | `Option<String>` | git-detected project |
| `due_date` | `Option<NaiveDate>` | |

## BeadsAdapter Pattern (CLI delegation)

```rust
pub struct BeadsAdapter;

impl BeadsAdapter {
    fn map_priority(p: u8) -> u8 { p / 64 }  // 0-255 → 0-4
}

#[async_trait]
impl IssueTracker for BeadsAdapter {
    fn provider_name(&self) -> &str { "beads" }

    async fn is_available(&self) -> bool {
        Command::new("bd").arg("--version")
            .output().await.map(|o| o.status.success()).unwrap_or(false)
    }

    async fn create_issue(&self, todo: &SyncableTodo) -> Result<SyncRecord, SyncError> {
        let output = Command::new("bd")
            .args(["create", &todo.title])
            .output().await
            .map_err(|_| SyncError::ProviderUnavailable("bd not found".into()))?;
        // parse output for external ID
    }
}
```

## Test Requirements

**Unit** — mock `IssueTracker`, verify `SyncService` calls it correctly
**Service integration** — real adapter, mock CLI (or env var gate)
**CLI integration** — requires actual CLI installed (`#[ignore]` or feature gate)

## SyncError Variants

`ProviderUnavailable` | `InvalidConfiguration` | `ExternalApiError` | `NetworkError` | `AuthenticationError` | `RateLimitError`

## Config Schema

Add entry to `~/.doob/sync_providers.toml`:
```toml
[providers.<name>]
enabled = true
# provider-specific fields
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Calling blocking CLI in async context | Use `tokio::process::Command`, not `std::process::Command` |
| Panicking on CLI parse failure | Return `SyncError::ExternalApiError` with context |
| Skipping `is_available` check | SyncService calls it before `create_issue` — implement it |
| Missing `#[async_trait]` | Trait has async methods — attribute is required |

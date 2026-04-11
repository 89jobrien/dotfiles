---
name: async-sync-bridge
description: Use when mixing Tokio async code with synchronous blocking I/O libraries (tar, flate2, zip, csv), or when seeing "cannot block the current thread from within the async context" panics, or needing to stream async bytes into a sync reader.
---

# Async/Sync Bridge with Tokio

## Overview

Sync I/O libraries (tar, flate2, zip) expect `impl Read`, but async HTTP streams give you `impl Stream<Item=Bytes>`. Bridge them with `SyncIoBridge` from `tokio-util` inside `spawn_blocking`. The `Handle::current()` must be captured **before** entering `spawn_blocking` — not inside it.

## Pattern

```rust
use tokio::runtime::Handle;
use tokio::task;
use tokio_util::io::{StreamReader, SyncIoBridge};
use futures::TryStreamExt;
use std::io;

async fn process_streaming_response(resp: reqwest::Response) -> anyhow::Result<()> {
    // 1. Build the async stream reader
    let stream = resp.bytes_stream().map_err(io::Error::other);
    let async_reader = StreamReader::new(stream);

    // 2. Capture the handle BEFORE spawn_blocking
    let handle = Handle::current();

    // 3. Move into blocking thread; bridge async→sync inside
    task::spawn_blocking(move || {
        let sync_reader = SyncIoBridge::new_with_handle(async_reader, handle);

        // Now hand sync_reader to any library expecting impl Read
        let mut decoder = flate2::read::GzDecoder::new(sync_reader);
        let mut archive = tar::Archive::new(&mut decoder);
        archive.unpack("/dest")?;
        Ok::<_, anyhow::Error>(())
    })
    .await??;

    Ok(())
}
```

## Why `Handle::current()` Must Be Captured Outside

`SyncIoBridge` drives the async reader by blocking on a Tokio runtime. Inside `spawn_blocking`, the thread has no Tokio context — `Handle::current()` would panic. Capturing it before the closure carries the existing runtime handle into the blocking thread.

```rust
// ❌ WRONG — panics: "no current Tokio runtime"
task::spawn_blocking(move || {
    let handle = Handle::current();  // too late
    let bridge = SyncIoBridge::new_with_handle(reader, handle);
})

// ✅ CORRECT — capture before
let handle = Handle::current();
task::spawn_blocking(move || {
    let bridge = SyncIoBridge::new_with_handle(reader, handle);
})
```

## Composing with Transparent Readers

Stack wrappers between the bridge and the sync consumer:

```rust
let handle = Handle::current();
task::spawn_blocking(move || {
    let bridge = SyncIoBridge::new_with_handle(async_reader, handle);
    let hashing = HashingReader::new(bridge);        // hash compressed bytes
    let decoder = GzDecoder::new(hashing);           // decompress
    let mut archive = Archive::new(decoder);
    archive.unpack(dest)?;
    let (digest, size) = archive.into_inner()        // retrieve digest
        .into_inner().finalize();
    Ok((digest, size))
})
```

See `transparent-reader` skill for the `HashingReader` pattern.

## Dependencies

```toml
tokio-util = { version = "0.7", features = ["io", "io-util"] }
tokio = { features = ["rt-multi-thread"] }
futures = "0.3"
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| `Handle::current()` inside `spawn_blocking` | Capture before the closure |
| `SyncIoBridge::new()` (no handle) | Use `new_with_handle()` to carry the runtime context |
| Calling `.await` inside `spawn_blocking` | Not possible — that's the point of the bridge |
| Using `block_in_place` instead | Works but holds the async thread; `spawn_blocking` is safer |
| `spawn_blocking` without `??` | Returns `Result<Result<_>>` — double `?` to unwrap both layers |

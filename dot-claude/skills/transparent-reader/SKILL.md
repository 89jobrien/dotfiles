---
name: transparent-reader
description: Use when needing to compute a side effect (hash, checksum, byte count, progress) on streaming bytes without buffering, or when a function accepts impl Read and you need to intercept the bytes passing through it.
---

# Transparent Reader Wrapper

## Overview

Implement `std::io::Read` as a pass-through that computes a side effect while bytes flow through — hashing, counting, progress tracking — without buffering the entire stream. The wrapper is invisible to the consumer.

## Pattern

```rust
use std::io::{self, Read};
use sha2::{Digest, Sha256};

pub struct HashingReader<R: Read> {
    inner: R,
    hasher: Sha256,
    bytes_read: u64,
}

impl<R: Read> HashingReader<R> {
    pub fn new(inner: R) -> Self {
        Self { inner, hasher: Sha256::new(), bytes_read: 0 }
    }

    /// Consume the wrapper, returning the digest and byte count.
    pub fn finalize(self) -> ([u8; 32], u64) {
        (self.hasher.finalize().into(), self.bytes_read)
    }
}

impl<R: Read> Read for HashingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.inner.read(buf)?;
        if n > 0 {
            self.hasher.update(&buf[..n]);
            self.bytes_read += n as u64;
        }
        Ok(n)
    }
}
```

Usage — compose with any `Read` consumer:

```rust
let stream = reqwest::get(url).await?.bytes_stream();
let reader = StreamReader::new(stream.map_err(io::Error::other));
let hashing = HashingReader::new(SyncIoBridge::new(reader));
let mut decoder = GzDecoder::new(hashing);

// Extract tar — bytes pass through HashingReader invisibly
let mut archive = Archive::new(&mut decoder);
archive.unpack(dest)?;

// Retrieve digest after extraction
let (digest, size) = decoder.into_inner().finalize();
```

## Key Design Decisions

**Hash compressed bytes, not decompressed** — place `HashingReader` *before* `GzDecoder` to match the OCI layer digest (which is over the compressed blob). After `GzDecoder` gives wrong digest.

**`finalize()` consumes `self`** — forces explicit extraction of the result; no silent discard.

**Zero extra allocation** — bytes are hashed in the same `buf` already allocated by the consumer. No double-buffering.

## Composability

Stack multiple wrappers for multiple side effects:

```rust
let reader = CountingReader::new(HashingReader::new(SyncIoBridge::new(stream)));
```

Each wrapper only sees bytes that actually pass through `read()`, so partial reads and retry loops are handled correctly.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Wrapping after `GzDecoder` | Digest is over compressed bytes — wrap before decompressor |
| Forgetting to call `finalize()` | Result silently dropped; add `#[must_use]` to the type |
| Buffering all bytes first, then hashing | Defeats the purpose — use this pattern instead |
| Not forwarding `read_vectored` | Default impl works but is slower; override if performance matters |

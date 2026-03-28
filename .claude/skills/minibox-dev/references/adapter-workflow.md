# Adapter Workflow

## Hexagonal Architecture in Minibox

Domain traits (ports) live in `minibox-lib/src/domain.rs`:

- `ResourceLimiter` — cgroup resource limits
- `FilesystemProvider` — overlay/copy filesystem
- `ContainerRuntime` — container lifecycle (create, start, stop)
- `ImageRegistry` — image pull/push

Adapters implement these traits for specific platforms:

| Adapter Suite | Platform | Wired? | Location |
|---|---|---|---|
| `native` | Linux (namespaces, overlay, cgroups v2) | Yes | `adapters/` root modules |
| `gke` | GKE (proot, copy FS, no-op limiter) | Yes | `adapters/` |
| `colima` | macOS (limactl/nerdctl) | Yes | `adapters/colima.rs` |
| `vf` | macOS (Virtualization.framework) | No | `adapters/vf.rs` |
| `wsl2` | Windows (WSL2) | No | `adapters/wsl2.rs` |
| `hcs` | Windows (HCS) | No | `adapters/hcs.rs` |
| `docker_desktop` | Docker Desktop | No | `adapters/` |

Selection via `MINIBOX_ADAPTER` env var → wired in `miniboxd/src/main.rs`.

## Adding a New Adapter

### 1. Create the Adapter Module

```rust
// minibox-lib/src/adapters/my_platform.rs

pub struct MyPlatformRuntime { /* ... */ }

impl ContainerRuntime for MyPlatformRuntime {
    fn create(&self, config: &ContainerConfig) -> Result<ContainerHandle> { /* ... */ }
    // ...
}
```

### 2. Add Mock Tests

Use `adapters::mocks` for unit testing. Real adapter tests go in integration test files.

### 3. Scaffold Tests with gen-tests

```bash
just gen-tests MyPlatformRuntime
```

Generates test scaffolding for all trait methods.

### 4. Wire Into miniboxd (if ready)

Add the adapter suite to `miniboxd/src/main.rs` match on `MINIBOX_ADAPTER`.

### 5. Add Conformance Tests

Conformance tests in `crates/daemonbox/tests/` verify adapters satisfy the trait contract. Add your adapter to the conformance test matrix.

## Executor Injection Pattern

For adapters that shell out to external tools (limactl, nerdctl, wsl.exe), use an executor trait for testability:

```rust
pub trait LimaExecutor: Send + Sync {
    fn run(&self, args: &[&str]) -> Result<String>;
}

pub struct RealLimaExecutor;
impl LimaExecutor for RealLimaExecutor { /* ... */ }

pub struct MockLimaExecutor { /* ... */ }
impl LimaExecutor for MockLimaExecutor { /* ... */ }
```

This is how `ColimaRuntime` works — the same pattern should be used for WSL2/Docker Desktop adapters.

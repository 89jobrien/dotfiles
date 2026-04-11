# Maestro Dev Tool Versions

Last verified: 2026-03-14

## Required Tools

| Tool | Tested Version | Min Version | Notes |
|------|---------------|-------------|-------|
| Rust | 1.91.1 | 1.80+ | Via rustup; check `rust-toolchain.toml` in repo |
| Docker | 29.3.0 | 24+ | Via Colima on macOS |
| kubectl | 1.35.2 | 1.28+ | Must match GKE cluster ±1 minor version |
| gcloud | 560.0.0 | 450+ | Homebrew cask install on macOS |
| Helm | 4.1.3 | 3.12+ | For deploying to GKE |
| gh | 2.88.1 | 2.0+ | GitHub CLI |
| Node.js | 25.8.1 | 20+ | For maestro-ui |
| npm | 11.11.0 | 9+ | Bundled with Node.js |
| jq | 1.8.1 | 1.6+ | JSON processing |
| cargo-nextest | 0.9.130 | 0.9+ | Test runner |
| cargo-watch | 8.5.3 | 8+ | Dev auto-reload |

## Optional Tools

| Tool | Purpose | Install |
|------|---------|---------|
| cargo-llvm-cov | Coverage reports | `cargo install cargo-llvm-cov` |
| cargo-machete | Unused dependency detection | `cargo install cargo-machete` |
| sccache | Shared compilation cache | `cargo install sccache` |

## GKE Cluster

| Property | Value |
|----------|-------|
| Cluster | `main-0` |
| Region | `us-east1` |
| Project | `toptal-maestro` |
| Context | `gke_toptal-maestro_us-east1_main-0` |
| Namespace | `team-maestro` |

## API Endpoints

| Environment | URL |
|-------------|-----|
| Staging | `https://api.maestro-staging.toptal.net` |
| Production | `https://api.maestro.toptal.net` |
| Local | `http://localhost:8080` |

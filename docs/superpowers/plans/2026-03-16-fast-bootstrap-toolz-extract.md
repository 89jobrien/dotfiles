# Fast Bootstrap + Toolz Extract Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split bootstrap into a fast configs/dotfiles path and a separate slow tools path; extract the `toolz` Rust crate into its own companion repo at `~/dev/tools`.

**Architecture:** Bootstrap becomes two phases: (1) `mise run dot` / `./install.sh --dot-only` handles stow symlinks + shell/AI/macOS configs (seconds), (2) full `./install.sh` handles packages + nix + toolchains + slow tools (minutes, run once). Rust compilation moves to a separate `mise run rust-tools` step. The `toolz/` directory is deleted from dotfiles and becomes a companion repo cloned to `~/dev/tools`.

**Tech Stack:** bash, GNU Stow, mise, cargo, gh CLI

---

## Chunk 1: Extract toolz into companion repo

### Task 1: Create the `89jobrien/tools` GitHub repo and update dotfiles references

**Files:**
- Delete: `toolz/` (entire directory)
- Modify: `scripts/setup-companion-repos.sh` — add `~/dev/tools` entry
- Modify: `scripts/setup-dev-tools.sh` — remove embedded toolz build (obfsck block stays for now, removed in Task 2)
- Modify: `.mise.toml` — update `toolz-install` and `toolz-dev` tasks
- Modify: `Justfile` — update toolz recipes
- Modify: `CLAUDE.md` — update companion projects table

- [ ] **Step 1: Create the new repo and push toolz contents**

```bash
cd /Users/joe/dotfiles
gh repo create 89jobrien/tools --private --description "Personal swiss-army CLI (sys, log, ai, db)"
mkdir -p ~/dev/tools
cp -r toolz/. ~/dev/tools/
cd ~/dev/tools
git init
git add .
git commit -m "feat: initial toolz crate extracted from dotfiles"
git branch -M main
git remote add origin git@github.com:89jobrien/tools.git
git push -u origin main
cd /Users/joe/dotfiles
```

- [ ] **Step 2: Verify repo is accessible**

```bash
gh repo view 89jobrien/tools --json name,url
ls ~/dev/tools/src/
```
Expected: repo exists, `src/` contains `main.rs`, `cli.rs`, etc.

- [ ] **Step 3: Add `~/dev/tools` to companion repos**

In `scripts/setup-companion-repos.sh`, add to the `REPOS` array (before the closing parenthesis):
```bash
"$HOME/dev/tools          89jobrien/tools"
```

- [ ] **Step 4: Remove embedded toolz build from `setup-dev-tools.sh`**

Delete lines 64–75 (the toolz section):
```bash
# Toolz — personal swiss-army CLI (embedded crate at dotfiles/toolz/).
if has_cmd cargo; then
  log "building toolz..."
  if cargo install --path "${ROOT_DIR}/toolz" ...
  ...
fi
```
The obfsck section (lines 77–86) stays in place for now — it will be moved to `setup-rust-tools.sh` in Task 2.

- [ ] **Step 5: Update `.mise.toml` toolz tasks**

Replace the `[tasks.toolz-install]` and `[tasks.toolz-dev]` entries:
```toml
[tasks.toolz-install]
description = "Build and install toolz CLI from ~/dev/tools to ~/.local/bin/toolz"
run = "cargo install --path ${HOME}/dev/tools --root ${HOME}/.local --force"

[tasks.toolz-dev]
description = "Build toolz in dev mode (no install)"
run = "cd ${HOME}/dev/tools && cargo build"
```

- [ ] **Step 6: Update `Justfile` toolz recipes**

Replace:
```makefile
toolz-install:
    cargo install --path ~/dev/tools --root "${HOME}/.local" --force

toolz-dev:
    cd ~/dev/tools && cargo build
```

- [ ] **Step 7: Update CLAUDE.md companion projects table**

Change the toolz row from "embedded crate" to:
```
| tools | `~/dev/tools` | `89jobrien/tools` | Rust | `cargo`/`rust` (mise) |
```
Remove the note about `toolz/` being an embedded crate from the toolz Crate section; replace with a pointer to the companion project.

- [ ] **Step 8: Delete `toolz/` from dotfiles**

```bash
cd /Users/joe/dotfiles
rm -rf toolz/
```

- [ ] **Step 9: Verify shellcheck and commit**

```bash
mise run shellcheck
```
Expected: no output, exit 0.

```bash
git add -A
git commit -m "feat(toolz): extract toolz crate to companion repo 89jobrien/tools"
```

---

## Chunk 2: Create `setup-rust-tools.sh` and strip cargo from `setup-dev-tools.sh`

### Task 2: Move all cargo compilation to a dedicated script

**Files:**
- Create: `scripts/setup-rust-tools.sh`
- Modify: `scripts/setup-dev-tools.sh` — remove ALL cargo blocks (tools + obfsck), keep only bun/npm tools
- Modify: `.mise.toml` — add `rust-tools` task, update `dev-tools` description
- Modify: `Justfile` — add `rust-tools` recipe

- [ ] **Step 1: Create `scripts/setup-rust-tools.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="rust-tools"

failed_optional=()

if has_cmd rustup; then
  rustup component add rustfmt clippy llvm-tools-preview >/dev/null 2>&1 || true
fi

if ! has_cmd cargo; then
  log_warn "cargo not found; skipping rust tools"
  exit 0
fi

# Resolve cargo runner (prefer mise-managed rust for correct toolchain)
if has_cmd mise; then
  cargo_cmd="mise exec -- cargo"
else
  cargo_cmd="cargo"
fi

tools=(
  alacritty
  bacon
  trunk
  sccache
  cargo-chef
  cargo-llvm-cov
  cargo-deny
  cargo-audit
  cargo-expand
  cargo-machete
  cargo-criterion
  hyperfine
  cargo-sweep
  cargo-clean-all
)

for tool in "${tools[@]}"; do
  ensure_cmd "${tool}" "${cargo_cmd} install --locked ${tool}" "failed_optional" || true
done

# Companion repo builds (toolz, obfsck)
for repo_path in "${HOME}/dev/tools" "${HOME}/dev/obfsck"; do
  if [[ -d "${repo_path}" ]]; then
    name="$(basename "${repo_path}")"
    log "building ${name}..."
    if ${cargo_cmd} install --path "${repo_path}" --root "${HOME}/.local" --force >/dev/null 2>&1; then
      log_ok "${name} installed to ~/.local/bin/${name}"
    else
      log_warn "${name} build failed — skipping"
      failed_optional+=("${name}")
    fi
  fi
done

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "rust tools setup complete"
```

```bash
chmod +x scripts/setup-rust-tools.sh
```

- [ ] **Step 2: Strip `setup-dev-tools.sh` down to non-cargo tools only**

Replace the entire file with (note: the `uv` availability log is intentionally dropped — uv is a runtime managed by mise, not a tool to install here):

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="dev-tools"

failed_optional=()

# JS workflow baseline — BAML CLI for AI boundary definitions.
if has_cmd bun; then
  ensure_cmd "baml-cli" "bun add -g @boundaryml/baml" "failed_optional" || true
elif has_cmd npm; then
  log_warn "bun missing; using npm fallback for BAML CLI"
  ensure_cmd "baml-cli" "npm install -g @boundaryml/baml" "failed_optional" || true
else
  log_skip "neither bun nor npm found; skipping baml-cli"
fi

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "dev tools setup complete"
```

- [ ] **Step 3: Update `.mise.toml`**

Update `dev-tools` description and add `rust-tools`:
```toml
[tasks.dev-tools]
description = "Install non-cargo dev tools (baml-cli via bun/npm)"
run = "./scripts/setup-dev-tools.sh"

[tasks.rust-tools]
description = "Compile and install Rust tools (alacritty, bacon, toolz, obfsck, etc.) — run after bootstrap"
run = "./scripts/setup-rust-tools.sh"
```

- [ ] **Step 4: Add `rust-tools` to `Justfile`**

```makefile
rust-tools:
    ./scripts/setup-rust-tools.sh
```

- [ ] **Step 5: Verify shellcheck**

```bash
mise run shellcheck
```
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/setup-rust-tools.sh scripts/setup-dev-tools.sh .mise.toml Justfile
git commit -m "feat(bootstrap): move cargo installs to separate rust-tools step"
```

---

## Chunk 3: Split bootstrap into fast (dot) + full paths

### Task 3: Add `--dot-only` flag and `run_dot_hooks` / `run_setup_hooks` split

**Files:**
- Modify: `scripts/bootstrap.sh` — split `run_post_hooks`, add `--dot-only` flag
- Modify: `.mise.toml` — add `dot` task
- Modify: `Justfile` — add `dot` recipe
- Modify: `Makefile` — add `dot`, `rust-tools` targets
- Modify: `CLAUDE.md` — update Key Commands

- [ ] **Step 1: Add `DOT_ONLY=0` initializer alongside existing flags in `bootstrap.sh`**

The existing flag defaults (around line 16) look like:
```bash
DO_PACKAGES=1
DO_STOW=1
DO_POST=1
```
Add `DOT_ONLY=0` immediately after those three lines:
```bash
DO_PACKAGES=1
DO_STOW=1
DO_POST=1
DOT_ONLY=0
```

- [ ] **Step 2: Add `--dot-only` to the flag-parsing `case` statement**

The existing `case "$arg" in` block has a `*)` catch-all at the end. Insert `--dot-only` **before** the `*)` entry:
```bash
    --dot-only)  DOT_ONLY=1 ;;
    *)
      log_err "unknown option: $arg"
      usage
      exit 1
      ;;
```

- [ ] **Step 3: Update `usage()` to document the new flag**

Add `--dot-only` to the usage string in the `usage()` function:
```bash
  echo "  --dot-only       Stow + config hooks only (no packages, no compilation)"
```

- [ ] **Step 4: Split `run_post_hooks` into `run_dot_hooks`, `run_setup_hooks`, and a combined `run_post_hooks`**

Replace the existing `run_post_hooks()` function with three functions:

```bash
# Fast hooks — configs/dotfiles only (no packages, no compilation, ~seconds)
run_dot_hooks() {
  if [[ "$DO_POST" -ne 1 ]]; then
    log_skip "post hooks"
    return 0
  fi

  section "Shell"
  run_hook "Shell" "${ROOT_DIR}/scripts/setup-git-config.sh"
  run_hook "Oh-My-Zsh" "${ROOT_DIR}/scripts/setup-oh-my-zsh.sh"

  section "Secrets"
  run_hook "Secrets" "${ROOT_DIR}/scripts/setup-secrets.sh"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    section "macOS"
    run_hook "macOS" "${ROOT_DIR}/scripts/setup-macos.sh"
  fi

  section "AI Tools"
  run_hook "AI Tools" "${ROOT_DIR}/scripts/setup-ai-tools.sh"
  run_hook "Hooks" "${ROOT_DIR}/scripts/setup-hooks.sh"
}

# Slow hooks — packages, runtimes, compilation (run once on new machines)
run_setup_hooks() {
  if [[ "$DO_POST" -ne 1 ]]; then
    log_skip "post hooks"
    return 0
  fi

  section "Nix"
  run_hook "Nix" "${ROOT_DIR}/scripts/setup-nix.sh"

  section "Maestro"
  run_hook "Maestro" "${ROOT_DIR}/scripts/setup-maestro.sh"

  section "Companion Repos"
  run_hook "Companion Repos" "${ROOT_DIR}/scripts/setup-companion-repos.sh"

  section "Dev Tools"
  if has_cmd mise && [[ -f "${ROOT_DIR}/.mise.toml" ]]; then
    run_hook "Dev Tools" sh -c "cd '${ROOT_DIR}' && mise run dev-tools"
  else
    run_hook "Dev Tools" "${ROOT_DIR}/scripts/setup-dev-tools.sh"
  fi

  section "Editor"
  run_hook "Editor" "${ROOT_DIR}/scripts/setup-nvchad-avante.sh"

  if [[ -x "${ROOT_DIR}/scripts/post-bootstrap.local.sh" ]]; then
    section "Local"
    run_hook "Local" "${ROOT_DIR}/scripts/post-bootstrap.local.sh"
  fi
}

# Full post-hooks — dot + setup combined (original behavior)
run_post_hooks() {
  run_dot_hooks
  run_setup_hooks
}
```

- [ ] **Step 5: Update `main()` to branch on `DOT_ONLY`**

Replace `main()`:
```bash
main() {
  cd "${ROOT_DIR}"
  record_start_time
  log "starting bootstrap on $(uname -s)"
  check_env

  if [[ "${DOT_ONLY}" -eq 1 ]]; then
    stow_packages
    run_dot_hooks
    print_summary
    log_ok "dot install complete"
    return 0
  fi

  spin_with_msg "Setting up zerobrew..." "${ROOT_DIR}/scripts/setup-zerobrew.sh" || true
  ensure_homebrew || true
  check_homebrew_writable
  install_packages
  stow_packages
  install_mise_toolchain
  run_post_hooks
  print_summary
  log_ok "bootstrap complete"
}
```

- [ ] **Step 6: Verify `install.sh` passes `$@` to `bootstrap.sh`**

```bash
grep 'bootstrap' install.sh
```
Expected: a line like `exec "${ROOT_DIR}/scripts/bootstrap.sh" "$@"` — confirming `--dot-only` will pass through automatically.

- [ ] **Step 7: Add `dot` task to `.mise.toml`**

```toml
[tasks.dot]
description = "Fast install — stow symlinks + configs only (no packages, no compilation)"
run = "./install.sh --dot-only"
```

- [ ] **Step 8: Add `dot` and `rust-tools` to `Justfile` and `Makefile`**

`Justfile`:
```makefile
dot:
    ./install.sh --dot-only

rust-tools:
    ./scripts/setup-rust-tools.sh
```

`Makefile`:
```makefile
dot:
	./install.sh --dot-only

rust-tools:
	./scripts/setup-rust-tools.sh
```

- [ ] **Step 9: Update CLAUDE.md Key Commands section**

Add at the top of the commands block:
```bash
# Fast path — configs & dotfiles only (seconds, re-run anytime)
mise run dot                              # stow + shell/AI/macOS configs
ALLOW_DIRECT_DOTFILES_INSTALL=1 ./install.sh --dot-only
```

Add below the existing bootstrap commands:
```bash
# Rust tools (slow — run once after bootstrap, or in background)
mise run rust-tools          # compile alacritty, bacon, toolz, obfsck, etc.
mise run rust-tools &        # background variant
```

- [ ] **Step 10: Verify shellcheck**

```bash
mise run shellcheck
```
Expected: no output, exit 0.

- [ ] **Step 11: Smoke test the dot-only path**

```bash
ALLOW_DIRECT_DOTFILES_INSTALL=1 ./install.sh --dot-only 2>&1 | tail -20
```
Expected: completes in seconds; summary shows Shell / Secrets / macOS / AI Tools only — no Nix, Maestro, Companion Repos, Dev Tools, or Editor sections.

- [ ] **Step 12: Run test suite**

```bash
mise run test-lib
```
Expected: all tests pass, 0 failures.

- [ ] **Step 13: Commit**

```bash
git add scripts/bootstrap.sh .mise.toml Justfile Makefile CLAUDE.md
git commit -m "feat(bootstrap): add --dot-only fast path; split run_post_hooks into dot + setup"
```

- [ ] **Step 14: Push**

```bash
git pull --rebase && bd sync && git push
```

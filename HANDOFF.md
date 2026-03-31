# HANDOFF.md

State of the `dotfiles` repo as of 2026-03-31.

## Recent Work

- Built `notfiles` Rust workspace (`~/dev/notfiles`) — 5-crate workspace replacing GNU Stow + shell bootstrap scripts. See `~/dev/notfiles/HANDOFF.md` for details.
- Claude Code hooks, skills, and superpowers infrastructure actively developed under `.claude/` and `.superpowers/`.

## Uncommitted Changes

```
M  .claude/CLAUDE.md
M  .claude/settings.json
M  mise/.config/mise/config.toml
M  zed/.config/zed/settings.json
?? .claude/.claude/
?? .claude/hooks/nu/post/post-edit-cargo-check.nu
?? .superpowers/
```

These should be reviewed and committed. Notable items:
- `post-edit-cargo-check.nu` — new post-edit hook that runs `cargo check` after Rust file edits (non-blocking)
- `.superpowers/` — new directory, contents unknown — review before committing
- `.claude/.claude/` — nested `.claude` dir, may be stale artifact

## Pending Issues

### 1. Commit outstanding changes
Review the modified/untracked files above and commit what belongs. Be careful with `.claude/.claude/` — this looks like an accidental nested directory.

### 2. notfiles not yet wired into dotfiles bootstrap
The new `notstrap` binary exists but dotfiles repo still uses the old `install.sh` / `Makefile` bootstrap flow. Next step: integrate `notstrap` into the dotfiles bootstrap process and retire the shell scripts.

### 3. scripts-refactoring-analysis.md
A `scripts-refactoring-analysis.md` exists at repo root — appears to be an in-progress analysis artifact. Either act on it or delete it.

### 4. install.sh / install.ps1 still shell-based
The Rust `notstrap` binary is the intended replacement. These scripts remain as fallback but should be deprecated once `notstrap` is stable.

### 5. RTK.md and skills are symlinks
`RTK.md` and `skills` are symlinks pointing inside `dotfiles/`. This works when stowed but may break if the repo is used standalone. Document this dependency clearly in README.

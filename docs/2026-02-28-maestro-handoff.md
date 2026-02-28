# Maestro Setup Handoff (2026-02-28)

## Scope
This handoff captures the current state of your bootstrap/tooling work before starting Maestro local environment setup.

## Current Baseline
- Dotfiles repo: `~/dotfiles`
- PJ CLI repo: `~/dev/pj`
- Both repos are pushed to `origin/main`.

## Recent Delivered Work
- Dotfiles:
  - Mise-first bootstrap flow with `pj dot install` entrypoint.
  - Alacritty source install path, Raycast script wiring, Zed default editor setup.
  - Container stack (`colima`, `k3d`, `kind`, `tilt`) + observability scripts.
  - Secret hygiene checks + hook install during bootstrap.
  - Git defaults now include:
    - GH credential helper for GitHub remotes
    - `push.autoSetupRemote=true`
    - `push.default=current`
    - `fetch.prune=true`
  - Git Flow switched to maintained `git-flow-next`.
- PJ:
  - Added `ctx`, `dot`, `cache`, `secret`, `update`, `sync`, and expanded TUI actions.
  - Added TUI 3-row layout with bottom status/event buffer.
  - Added smarter secret scanner heuristics to reduce false positives.

## Important Commands (Known Good)
- Full sync path:
  - `pj sync`
  - Optional: `pj sync --doctor-only`
- Dotfiles direct:
  - `pj dot install`
  - `cd ~/dotfiles && mise run doctor`
  - `cd ~/dotfiles && mise run up`

## Config Notes
- TUI event-stream defaults are now managed in dotfiles mise env:
  - `PJ_TUI_EVENT_STREAM=app`
  - `PJ_TUI_EVENT_MAX_CHARS=140`
- Local overrides live in:
  - `~/dotfiles/mise.local.toml` (from `mise.local.toml.example`)

## Known Gotchas
- Global pre-commit hook may still run an older `pj` binary in some shells.
  - If behavior looks stale, run `pj update --pull`.
- `git-flow-avh` was removed; `git-flow-next` is the supported variant.

## Start Point For Maestro Work
1. Confirm Maestro repo path and default branch.
2. Run context scan in Maestro repo:
   - `pj ctx --json`
3. Detect project tooling:
   - `mise.toml` / `package.json` / `Cargo.toml` / `go.mod` / Docker/K8s markers.
4. Generate a Maestro-specific local bootstrap task list:
   - install/build/test/run/dev-up commands
   - required env/secrets sources
   - container/runtime dependencies
5. Add Maestro task wrappers to `pj` or dotfiles scripts only after local run succeeds.

## File References
- Dotfiles README: `~/dotfiles/README.md`
- Dotfiles mise config: `~/dotfiles/.mise.toml`
- PJ README: `~/dev/pj/README.md`
- Previous runbook: `~/dotfiles/docs/2026-02-27-bootstrap-runbook.md`

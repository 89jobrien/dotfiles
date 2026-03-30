# fish

**Stow package:** `fish/`
**Entry point:** `fish/.config/fish/config.fish` → `~/.config/fish/config.fish`
**Framework:** none (vanilla fish)

All configuration is guarded by `status is-interactive` — nothing runs in script/non-interactive contexts.

## PATH (prepended, highest priority first)

| Path | Condition |
|---|---|
| `~/.local/share/mise/shims` | always (if dir exists) |
| `~/.local/bin` | always (if dir exists) |
| `~/.zerobrew/bin` | always (if dir exists) |

Set via `fish_add_path` (persistent, deduped across sessions).

## Secrets & Environment

| Behavior | Detail |
|---|---|
| `SOPS_AGE_KEY_FILE` | Set if `~/.config/sops/age/keys.txt` exists |
| `VISUAL` | `zed --wait` if `zed` available, else unset |
| `RUSTC_WRAPPER` | `sccache` if available |
| History filtering | `fish_should_add_to_history` blocks lines matching API keys, tokens, passwords |

> **Note:** Fish does not auto-load `~/.secrets` or `~/.config/dev-bootstrap/secrets.env`. The `claude` function wraps `op run` to inject secrets for Claude Code specifically.

## Tool Integrations

| Tool | Integration |
|---|---|
| mise | shims on PATH (no `mise activate` — fish uses shims only) |
| zoxide | `zoxide init fish | source` (interactive only) |

## Custom Functions

### `claude` (`functions/claude.fish`)
Wraps `claude` with `op run` to inject secrets from `~/.secrets`:
```fish
op run --account=my.1password.com --env-file=$HOME/.secrets -- /opt/homebrew/bin/claude $argv
```
This is the primary mechanism for resolving `op://` API keys (e.g., `ANTHROPIC_API_KEY`) when running Claude Code from fish.

### `n` (`functions/n.fish`)
Quick note capture via `doob`:
- `n` → list last 10 notes
- `n <text>` → `doob note add <text>`

### `dfr [task]`
Run a `mise run` task from `~/dotfiles`.

### `dfj [recipe]`
Run a `just` recipe from `~/dotfiles`.

### `klogs [pattern]`
`stern <pattern> -A` across all namespaces. Default pattern: `.`

### `obfsrun [cmd]`
Run a command and pipe output through `pj secret redact`.

### `gp / gl / gpf`
Git push / pull (`--ff-only`) / push (`--force-with-lease`) via `gh auth git-credential` helper.

## Aliases

### mise
`m`, `mr`, `mi`, `mt` → `mise`, `mise run`, `mise install`, `mise tasks ls`

### Git
`g`, `gs`, `ga`, `gc`, `gco`, `gb`, `gd` — standard git shortcuts.

git-flow: `gfi`, `gffs`, `gfff`, `gfrs`, `gfrf`, `gfhs`, `gfhf` — loaded if `git flow` available.

### GitHub CLI
`ghst`, `ghrepo`, `ghpr`, `ghprv`, `ghprw`, `ghiss`, `ghrun`

### Package managers
`pip`/`pip3` → `uv pip`, `py` → `uv run python`
`npm`/`npx`/`pnpm`/`yarn` → `bun`/`bunx`
`zbi`/`zbs`/`zbl`/`zbu` → zerobrew shortcuts

### Dotfiles
`dot`, `dotgs`, `dotpull`, `dotpush`, `dotopen`

### Kubernetes
`kctx`, `kpods`, `updev`, `obs`, `obsk`, `obsl`

### Misc
`ide` → `zed .` / `nvim .`, `obfs` → `pj secret redact`

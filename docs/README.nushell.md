# nushell

**Stow package:** `nushell/`
**Entry point:** `nushell/.config/nushell/` → `~/.config/nushell/`
**Framework:** none (vanilla nushell)

Config is split across four files, all sourced from `config.nu`:

| File | Purpose |
|---|---|
| `env.nu` | Environment variables, PATH, secrets |
| `aliases.nu` | Short aliases |
| `functions.nu` | Custom `def` commands |
| `settings.nu` | `$env.config` settings |

## PATH order (highest priority first)

| Path | Purpose |
|---|---|
| `/opt/homebrew/opt/openjdk/bin` | Java |
| `/opt/homebrew/share/google-cloud-sdk/bin` | gcloud |
| `/opt/homebrew/bin` + `/opt/homebrew/sbin` | Homebrew |
| `~/.bun/bin` | Bun JS runtime |
| `~/.zerobrew/bin` | zerobrew (zb) |
| `~/.local/share/mise/shims` | mise runtime shims |
| `~/.local/bin` | personal tools (RTK, devloop, toolz…) |

## Secrets & Environment

| Behavior | Detail |
|---|---|
| Bootstrap secrets | Parsed from `~/.config/dev-bootstrap/secrets.env` (dotenv format, key=value) |
| `~/.secrets` | Lines piped through `op inject`, parsed and loaded as env vars |
| `SOPS_AGE_KEY_FILE` | Set if `~/.config/sops/age/keys.txt` exists |
| `OPENAI_API_KEY` | Loaded via `op read` at startup (interactive only) |
| `DOCKER_HOST` | Auto-detected Colima socket at startup |
| `RTK_HOOK_AUDIT` | `1` — enables RTK hook audit log at `~/.local/share/rtk/hook-audit.log` |

## Tool Integrations

| Tool | Integration | Notes |
|---|---|---|
| mise | `MISE_SHELL=nu` + shims on PATH | Full `mise activate nu` must be sourced in `config.nu` |
| zoxide | — | `zoxide init nushell` output must be sourced in `config.nu` |
| direnv | — | `direnv hook nu` output must be sourced in `config.nu` |

These three tools emit nushell code that can't be eval'd inline. Standard pattern for `config.nu`:
```nu
mise activate nu | save -f /tmp/mise-activate.nu
source /tmp/mise-activate.nu
```

## History

Stored in SQLite: `~/.config/nushell/history.sqlite3`

Schema: `id`, `command_line`, `start_timestamp`, `hostname`, `cwd`, `duration_ms`, `exit_status`

Query recent history:
```bash
sqlite3 ~/.config/nushell/history.sqlite3 \
  "select command_line, start_timestamp from history order by id desc limit 20"
```

> **Gap vs zsh/fish:** No pre-write hook to filter secrets from history. Nushell doesn't support a `fish_should_add_to_history` equivalent. Scrub manually if needed.

## Shell reload

```nu
nunu   # re-sources ~/.config/nushell/env.nu
```

## Custom Functions (`functions.nu`)

| Function | Description |
|---|---|
| `dirsize` | List current directory sorted by size |
| `mkcd [dir]` | `mkdir` + `cd` in one step |
| `dfr [...args]` | Run `mise run` task from `~/dotfiles` |
| `dfj [...args]` | Run `just` recipe from `~/dotfiles` |
| `klogs [pattern]` | `stern <pattern> -A` across all namespaces (default: `.`) |
| `obfsrun [...cmd]` | Run command and pipe output through `pj secret redact` |
| `docker [...args]` | Wraps `docker` — auto-starts Colima before delegating |
| `docker-compose [...args]` | Wraps `docker-compose` — auto-starts Colima before delegating |
| `mnpm [...args]` | Real `npm` (bypasses the `bun` alias — needed for maestro-ui) |
| `_git_gh [...args]` | `git` with `gh auth git-credential` helper injected |

## Aliases (`aliases.nu`)

### Shell
| Alias | Action |
|---|---|
| `nunu` | Re-source `env.nu` (reload env in current session) |

### mise
`m`, `mr`, `mi`, `mt` → `mise`, `mise run`, `mise install`, `mise tasks ls`

### Git
| Alias | Command |
|---|---|
| `g` | `git` |
| `gs` | `git status -sb` |
| `ga` | `git add` |
| `gc` | `git commit` |
| `gco` | `git checkout` |
| `gb` | `git branch` |
| `gd` | `git diff` |
| `gl` | `git pull --ff-only` |
| `gp` | `git push` |
| `gpf` | `git push --force-with-lease` |

### GitHub CLI
`ghst`, `ghrepo`, `ghpr`, `ghprv`, `ghprw`, `ghiss`, `ghrun`

### Package managers
`pip`/`pip3` → `uv pip`, `py` → `uv run python`
`npm`/`npx`/`pnpm`/`yarn` → `bun`/`bunx`
`zbi`/`zbs`/`zbl`/`zbu` → zerobrew shortcuts

### Dotfiles
`dot`, `dotgs`, `dotpull`, `dotpush`, `dotopen`

### Docker / Colima
`dps`, `dpsa`, `di`, `dstop`, `drm`, `drmi`, `drmif`
`colima-start`, `colima-stop`, `colima-status`, `colima-restart`

### Kubernetes
`kctx`, `kpods`, `kmpods`, `kmlogs`, `kmexec` (last three scoped to `gke_toptal-maestro_us-east1_main-0 / team-maestro`)

### Maestro
`ms`, `mst`, `ml`, `mlogs`, `mwork`, `mcfg`, `mpurge`, `mauth`, `maestro-attach`

### Misc
| Alias | Action |
|---|---|
| `ide` | `zed .` |
| `obfs` | `pj secret redact` |
| `ocm` | `opencode -m ollama/gpt-mbx` |

## Settings (`settings.nu`)

| Setting | Value |
|---|---|
| `show_banner` | `false` |
| `history.file_format` | `sqlite` |
| `history.max_size` | `100_000` |
| `completions.external.enable` | `true` |
| `edit_mode` | `emacs` |

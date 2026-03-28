# zsh

**Stow package:** `zsh/`
**Entry point:** `zsh/.zshrc` → `~/.zshrc`
**Framework:** Oh My Zsh (`robbyrussell` theme, `git` plugin)

## PATH order (highest priority first)

| Path | Source |
|---|---|
| `~/.local/bin` | personal tools, RTK, devloop |
| `~/.local/share/mise/shims` | mise runtime shims |
| `~/.bun/bin` | Bun JS runtime |
| `~/.zerobrew/bin` | zerobrew (zb) |
| `/opt/homebrew/bin` | Homebrew |
| `/opt/homebrew/share/google-cloud-sdk/bin` | gcloud |
| `/opt/homebrew/opt/openjdk/bin` | Java |

## Secrets & Environment

| Behavior | Detail |
|---|---|
| Bootstrap secrets | Auto-loaded from `~/.config/dev-bootstrap/secrets.env` on startup (`set -a; source`) |
| `~/.secrets` | Resolved via `op inject` if `op` is available; otherwise plain sourced |
| `SOPS_AGE_KEY_FILE` | Set to `~/.config/sops/age/keys.txt` if present |
| History filtering | `zshaddhistory` blocks lines matching API keys, tokens, passwords from being saved |

## Tool Integrations

| Tool | Integration |
|---|---|
| mise | `mise activate zsh` + shims on PATH |
| zoxide | `zoxide init zsh` |
| direnv | `direnv hook zsh` |
| zsh-autosuggestions | Sourced from Homebrew if present |
| zsh-autopair | Sourced from Homebrew if present |
| sccache | `RUSTC_WRAPPER=sccache` if available (unset at end — causes issues in some projects) |

## Aliases

### mise
| Alias | Command |
|---|---|
| `m` | `mise` |
| `mr` | `mise run` |
| `mi` | `mise install` |
| `mt` | `mise tasks ls` |

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
| `gp` | `git push` (via gh credential helper) |
| `gl` | `git pull --ff-only` (via gh credential helper) |
| `gpf` | `git push --force-with-lease` (via gh credential helper) |

git-flow aliases (`gfi`, `gffs`, `gfff`, `gfrs`, `gfrf`, `gfhs`, `gfhf`) loaded if `git flow` is available.

### GitHub CLI
| Alias | Command |
|---|---|
| `ghst` | `gh auth status` |
| `ghrepo` | `gh repo view --web` |
| `ghpr` | `gh pr create` |
| `ghprv` | `gh pr view` |
| `ghprw` | `gh pr view --web` |
| `ghiss` | `gh issue list` |
| `ghrun` | `gh run list` |

### Package managers (override defaults)
| Alias | Routes to |
|---|---|
| `pip`, `pip3` | `uv pip` |
| `py` | `uv run python` |
| `npm`, `npx`, `pnpm`, `yarn` | `bun` / `bunx` |
| `zbi/zbs/zbl/zbu` | `zb install/search/list/update` |

### Dotfiles
| Alias | Action |
|---|---|
| `dot` | `cd ~/dotfiles` |
| `dotgs` | status in dotfiles repo |
| `dotpull` | `git pull --ff-only` in dotfiles |
| `dotpush` | `git push` in dotfiles |
| `dotopen` | open dotfiles repo in browser |

### Docker / Colima
`docker` and `docker-compose` are wrapped functions that auto-start Colima before delegating to the real binary.

| Alias | Command |
|---|---|
| `dps` / `dpsa` | `docker ps` / `docker ps -a` |
| `di` / `drmi` / `drmif` | image management |
| `dstop` / `drm` | container management |
| `colima-start/stop/restart/status` | Colima profile `dev` management |

`DOCKER_HOST` is set automatically based on detected socket (`~/.colima/dev/docker.sock` or `~/.config/colima/default/docker.sock`).

### Kubernetes
| Alias | Context |
|---|---|
| `kctx` | current context |
| `kpods` | all pods, all namespaces |
| `kmpods/kmlogs/kmexec` | scoped to `gke_toptal-maestro_us-east1_main-0 / team-maestro` |

### Maestro
`ms`, `mst`, `ml`, `mlogs`, `mwork`, `mcfg`, `mpurge`, `mauth` — all guarded by `command -v maestro`.
`maestro-attach` — attaches to the running maestro dev container via tmux.

### Misc
| Alias | Action |
|---|---|
| `ide` | `zed .` (falls back to `nvim .`) |
| `obfs` | `pj secret redact` |
| `ocm` | `opencode -m ollama/gpt-mbx` |
| `mnpm` | real `npm` (bypasses the bun alias — needed for maestro-ui) |

## Functions

| Function | Description |
|---|---|
| `dfr [task]` | Run a `mise run` task from `~/dotfiles` |
| `dfj [recipe]` | Run a `just` recipe from `~/dotfiles` |
| `klogs [pattern]` | `stern <pattern> -A` across all namespaces (default pattern: `.`) |
| `obfsrun [cmd]` | Run command and pipe stdout+stderr through `pj secret redact` |
| `brew()` | Routes `install/bundle/uninstall/list/info` to `zb` first, falls back to Homebrew |
| `docker()` | Auto-starts Colima then delegates to real `docker` |
| `docker-compose()` | Auto-starts Colima then delegates to real `docker-compose` |
| `gp/gl/gpf` | Git push/pull/force-push via `gh auth git-credential` helper |

## Local overrides

`~/.zshrc.local` is sourced at the end if present (gitignored, not managed by stow).

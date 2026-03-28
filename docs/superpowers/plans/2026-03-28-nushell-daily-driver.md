# Nushell Daily Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace zsh with nushell as the daily driver login shell, with full tool integration (mise, zoxide, direnv, starship, atuin, carapace) and a two-line starship prompt.

**Architecture:** Install nu via mise's cargo backend for auto-updates; configure via stow-managed files in `nushell/.config/nushell/`; generate vendor init scripts at shell startup into `$nu.data-dir/vendor/autoload/`; set the mise shim as the login shell.

**Tech Stack:** Nushell, mise (cargo backend), starship, atuin, carapace-bin, zoxide, direnv, GNU Stow, Nix flake

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `flake.nix` | Modify | Add `atuin` and `carapace-bin` to `cliPackages` |
| `nushell/.config/nushell/env.nu` | Modify | Add PATH entries, ENV_CONVERSIONS, Homebrew vars, 1Password SSH socket |
| `nushell/.config/nushell/config.nu` | Create | Vendor seeding, keybindings, hooks, completions |
| `nushell/.config/nushell/autoload/aliases.nu` | Create (move) | Aliases — moved from root so nushell auto-sources |
| `nushell/.config/nushell/autoload/functions.nu` | Create (move) | Functions — moved from root |
| `nushell/.config/nushell/autoload/settings.nu` | Create (move) | Settings patches — moved from root |
| `starship/.config/starship.toml` | Create | Two-line prompt with `→` on line 2 |
| `config/stow-packages.txt` | Modify | Add `starship` package |
| `.mise.toml` | Modify | Fix `nix-install` PATH issue |

---

## Task 1: Add atuin and carapace-bin to Nix flake

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Open flake.nix and locate cliPackages**

  Read `flake.nix`. Find the `cliPackages = with pkgs; [` block (around line 36). The list currently ends with `stern`.

- [ ] **Step 2: Add atuin and carapace-bin**

  In `flake.nix`, add after `nil`:

  ```nix
              nil
              atuin
              carapace-bin
  ```

- [ ] **Step 3: Apply the updated flake**

  ```bash
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix profile install .#default --impure 2>&1 | tail -5
  ```

  Expected: profile reinstalls with new packages. No error output.

- [ ] **Step 4: Verify both tools are available**

  ```bash
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && which atuin && atuin --version && which carapace && carapace --version
  ```

  Expected: both print a version string.

- [ ] **Step 5: Commit**

  ```bash
  git add flake.nix
  git commit -m "feat(nix): add atuin and carapace-bin to cliPackages"
  ```

---

## Task 2: Fix nix-install mise task PATH

**Files:**
- Modify: `.mise.toml` (line ~60)

- [ ] **Step 1: Update the nix-install task**

  In `.mise.toml`, find:

  ```toml
  [tasks.nix-install]
  description = "Install Nix and apply flake packages"
  run = "./scripts/setup-nix.sh"
  ```

  Replace with:

  ```toml
  [tasks.nix-install]
  description = "Install Nix and apply flake packages"
  run = ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && ./scripts/setup-nix.sh"
  ```

- [ ] **Step 2: Verify task runs without PATH error**

  ```bash
  mise run nix-install 2>&1 | head -5
  ```

  Expected: `[nix] ok: nix installed` or `[nix] skip: nix already installed`. No `sh: nix: command not found`.

- [ ] **Step 3: Commit**

  ```bash
  git add .mise.toml
  git commit -m "fix(mise): source nix-daemon.sh in nix-install task"
  ```

---

## Task 3: Install nushell via mise cargo backend

**Files:** none (runtime install, no dotfiles change)

- [ ] **Step 1: Uninstall nu from Homebrew**

  ```bash
  brew uninstall nu
  ```

  Expected: `Uninstalling /opt/homebrew/Cellar/nushell/...`

- [ ] **Step 2: Install nu via mise cargo backend**

  ```bash
  mise use -g cargo:nu
  ```

  This compiles nushell from crates.io. Takes 3-10 minutes. Expected final line: something like `mise cargo:nu@0.x.x ✓`.

- [ ] **Step 3: Verify the shim exists and works**

  ```bash
  ~/.local/share/mise/shims/nu --version
  ```

  Expected: `nushell 0.x.x`

- [ ] **Step 4: Add shim to /etc/shells**

  ```bash
  echo "$HOME/.local/share/mise/shims/nu" | sudo tee -a /etc/shells
  ```

  Expected: prints the path.

- [ ] **Step 5: Set as login shell**

  ```bash
  chsh -s "$HOME/.local/share/mise/shims/nu"
  ```

  Enter your macOS user password when prompted.

- [ ] **Step 6: Verify chsh took effect**

  ```bash
  dscl . -read /Users/$USER UserShell
  ```

  Expected: `UserShell: /Users/joe/.local/share/mise/shims/nu`

---

## Task 4: Update env.nu

**Files:**
- Modify: `nushell/.config/nushell/env.nu`

- [ ] **Step 1: Add nix and cargo PATH entries**

  In `nushell/.config/nushell/env.nu`, find the PATH block:

  ```nushell
  $env.PATH = (
      $env.PATH
      | prepend ($env.HOME | path join ".local/bin")
  ```

  Add two new prepend lines so the block becomes:

  ```nushell
  $env.PATH = (
      $env.PATH
      | prepend ($env.HOME | path join ".local/bin")
      | prepend ($env.HOME | path join ".local/share/mise/shims")
      | prepend ($env.HOME | path join ".bun/bin")
      | prepend ($env.HOME | path join ".zerobrew/bin")
      | prepend ($env.HOME | path join ".nix-profile/bin")
      | prepend ($env.HOME | path join ".cargo/bin")
      | prepend "/opt/homebrew/bin"
      | prepend "/opt/homebrew/sbin"
      | prepend "/opt/homebrew/opt/openjdk/bin"
      | prepend "/opt/homebrew/share/google-cloud-sdk/bin"
      | uniq
  )
  ```

- [ ] **Step 2: Add ENV_CONVERSIONS after the PATH block**

  After the closing `)` of the PATH block, add:

  ```nushell
  # ── ENV_CONVERSIONS ──────────────────────────────────────────────────────────
  # Teach nushell to handle colon-separated vars from external tools
  $env.ENV_CONVERSIONS = {
    PATH: {
      from_string: { |s| $s | split row (char esep) | path expand -n }
      to_string:   { |v| $v | str join (char esep) }
    }
    XDG_DATA_DIRS: {
      from_string: { |s| $s | split row ':' }
      to_string:   { |v| $v | str join ':' }
    }
  }
  ```

- [ ] **Step 3: Add Homebrew environment variables**

  After ENV_CONVERSIONS, add:

  ```nushell
  # ── Homebrew ──────────────────────────────────────────────────────────────────
  $env.HOMEBREW_PREFIX     = "/opt/homebrew"
  $env.HOMEBREW_CELLAR     = "/opt/homebrew/Cellar"
  $env.HOMEBREW_REPOSITORY = "/opt/homebrew"
  ```

- [ ] **Step 4: Add 1Password SSH agent socket**

  After Homebrew vars, add:

  ```nushell
  # ── 1Password SSH agent ───────────────────────────────────────────────────────
  $env.SSH_AUTH_SOCK = (
    $env.HOME | path join "Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  )
  ```

- [ ] **Step 5: Verify env.nu parses without error**

  ```bash
  ~/.local/share/mise/shims/nu --commands "source ~/.config/nushell/env.nu; echo 'ok'"
  ```

  Expected: `ok`

- [ ] **Step 6: Commit**

  ```bash
  git add nushell/.config/nushell/env.nu
  git commit -m "feat(nushell): add nix/cargo PATH, ENV_CONVERSIONS, Homebrew, 1Password env"
  ```

---

## Task 5: Move aliases, functions, settings to autoload/

**Files:**
- Create: `nushell/.config/nushell/autoload/aliases.nu` (content from root)
- Create: `nushell/.config/nushell/autoload/functions.nu` (content from root)
- Create: `nushell/.config/nushell/autoload/settings.nu` (content from root)
- Delete: `nushell/.config/nushell/aliases.nu`
- Delete: `nushell/.config/nushell/functions.nu`
- Delete: `nushell/.config/nushell/settings.nu`

Nushell auto-sources everything in `~/.config/nushell/autoload/` — no explicit `source` needed.

- [ ] **Step 1: Create the autoload directory**

  ```bash
  mkdir -p nushell/.config/nushell/autoload
  ```

- [ ] **Step 2: Move aliases.nu — update the nunu alias**

  Copy `nushell/.config/nushell/aliases.nu` to `nushell/.config/nushell/autoload/aliases.nu`.

  In the new file, find and remove the `nunu` alias (env.nu is auto-loaded by nushell; a manual reload alias is no longer needed):

  ```nushell
  alias nunu = source ~/.config/nushell/env.nu
  ```

  Delete that line entirely.

- [ ] **Step 3: Move functions.nu**

  Copy `nushell/.config/nushell/functions.nu` to `nushell/.config/nushell/autoload/functions.nu`. No content changes needed.

- [ ] **Step 4: Move settings.nu — remove the comment block**

  Copy `nushell/.config/nushell/settings.nu` to `nushell/.config/nushell/autoload/settings.nu`.

  Remove the large comment block (lines 9–31) that says "Recommended ~/.config/nushell/config.nu additions" — that guidance is now implemented in config.nu.

  The file should contain only:

  ```nushell
  # Shell settings

  $env.config.show_banner = false
  $env.config.history.file_format = "sqlite"
  $env.config.history.max_size = 100_000
  $env.config.completions.external.enable = true
  $env.config.edit_mode = "emacs"  # or "vi"
  ```

- [ ] **Step 5: Delete the three root-level files**

  ```bash
  git rm nushell/.config/nushell/aliases.nu nushell/.config/nushell/functions.nu nushell/.config/nushell/settings.nu
  ```

- [ ] **Step 6: Re-stow the nushell package to update symlinks**

  ```bash
  stow --restow --dir ~/dotfiles --target ~ nushell
  ```

  Expected: no conflict errors. Old symlinks removed, new `~/.config/nushell/autoload/` symlinks created.

- [ ] **Step 7: Verify autoload files are symlinked**

  ```bash
  ls -la ~/.config/nushell/autoload/
  ```

  Expected: `aliases.nu`, `functions.nu`, `settings.nu` as symlinks into `~/dotfiles/nushell/`.

- [ ] **Step 8: Verify nushell loads without error**

  ```bash
  ~/.local/share/mise/shims/nu --commands "echo 'ok'"
  ```

  Expected: `ok` with no errors about missing files.

- [ ] **Step 9: Commit**

  ```bash
  git add nushell/.config/nushell/autoload/
  git commit -m "refactor(nushell): move aliases/functions/settings to autoload/"
  ```

---

## Task 6: Create config.nu

**Files:**
- Create: `nushell/.config/nushell/config.nu`

- [ ] **Step 1: Create config.nu**

  Create `nushell/.config/nushell/config.nu` with the following content:

  ```nushell
  # config.nu — main nushell configuration
  # env.nu and autoload/ are sourced automatically by nushell before this file.

  # ── Vendor/autoload seeding ───────────────────────────────────────────────────
  # Generates tool init scripts into $nu.data-dir/vendor/autoload/ on every
  # shell startup. Nushell auto-sources everything in that directory.

  let vendor = $nu.data-dir | path join "vendor/autoload"
  mkdir $vendor

  starship  init nu             | save -f ($vendor | path join "starship.nu")
  zoxide    init nushell        | save -f ($vendor | path join "zoxide.nu")
  ^mise     activate nu         | save -f ($vendor | path join "mise.nu")
  atuin     init nu             | save -f ($vendor | path join "atuin.nu")
  carapace  _carapace nushell   | save -f ($vendor | path join "carapace.nu")

  # ── Keybindings ───────────────────────────────────────────────────────────────

  $env.config.keybindings = ($env.config.keybindings? | default [] | append [
    # Ctrl+F — fzf file picker, inserts selected path at cursor
    {
      name: fzf_file_picker
      modifier: control
      keycode: char_f
      mode: [emacs, vi_insert]
      event: {
        send: executehostcommand
        cmd: "commandline edit --insert (fd --type f | fzf | str trim)"
      }
    }
    # Alt+D — fzf directory jump
    {
      name: fzf_cd
      modifier: alt
      keycode: char_d
      mode: [emacs, vi_insert]
      event: {
        send: executehostcommand
        cmd: "cd (fd --type d | fzf | str trim)"
      }
    }
    # Alt+E — open current commandline in $EDITOR
    {
      name: edit_in_editor
      modifier: alt
      keycode: char_e
      mode: [emacs, vi_insert]
      event: { send: openeditor }
    }
  ])

  # ── Hooks ─────────────────────────────────────────────────────────────────────
  # Always append — never replace — to avoid clobbering hooks set by atuin, etc.

  # direnv: fires on directory change only (not every prompt render)
  $env.config.hooks.env_change.PWD = (
    $env.config.hooks.env_change.PWD? | default [] | append {||
      if (which direnv | is-empty) { return }
      direnv export json | from json | default {} | load-env
    }
  )

  # display_output: expand table columns on wide terminals
  $env.config.hooks.display_output = {||
    if (term size).columns >= 100 { table -e } else { table }
  }

  # command_not_found: helpful fallback message
  $env.config.hooks.command_not_found = {|cmd|
    $"Command '($cmd)' not found. Is it a mise tool? Try: mise use ($cmd)"
  }
  ```

- [ ] **Step 2: Stow the new file**

  ```bash
  stow --restow --dir ~/dotfiles --target ~ nushell
  ```

  Expected: `~/.config/nushell/config.nu` symlink created.

- [ ] **Step 3: Verify nushell loads config.nu without error**

  ```bash
  ~/.local/share/mise/shims/nu --commands "echo 'config loaded ok'"
  ```

  Expected: `config loaded ok` with no errors. If any tool (atuin, carapace, etc.) is missing it will error — check Task 1 was completed first.

- [ ] **Step 4: Verify vendor/autoload was seeded**

  ```bash
  ls ~/.local/share/nushell/vendor/autoload/
  ```

  Expected: `starship.nu`, `zoxide.nu`, `mise.nu`, `atuin.nu`, `carapace.nu`

- [ ] **Step 5: Commit**

  ```bash
  git add nushell/.config/nushell/config.nu
  git commit -m "feat(nushell): add config.nu with vendor seeding, keybindings, and hooks"
  ```

---

## Task 7: Create starship stow package and prompt config

**Files:**
- Create: `starship/.config/starship.toml`
- Modify: `config/stow-packages.txt`

- [ ] **Step 1: Create the starship stow package directory**

  ```bash
  mkdir -p starship/.config
  ```

- [ ] **Step 2: Create starship.toml**

  Create `starship/.config/starship.toml` with the following content:

  ```toml
  # Starship prompt — two-line layout
  # Line 1: directory, git, languages, duration, time
  # Line 2: → (green on success, red on error)

  add_newline = true

  format = """
  $directory\
  $git_branch\
  $git_status\
  $rust\
  $golang\
  $nodejs\
  $cmd_duration\
  $fill\
  $time\
  $line_break\
  $character"""

  [fill]
  symbol = " "

  [character]
  success_symbol = "[→](bold green)"
  error_symbol   = "[→](bold red)"
  vimcmd_symbol  = "[←](bold green)"

  [directory]
  truncation_length = 4
  truncate_to_repo  = true
  style             = "bold blue"

  [git_branch]
  format = "[$symbol$branch]($style) "
  style  = "bold purple"

  [git_status]
  format    = "([$all_status$ahead_behind]($style) )"
  style     = "bold red"
  conflicted = "⚡"
  ahead      = "⇡${count}"
  behind     = "⇣${count}"
  diverged   = "⇕⇡${ahead_count}⇣${behind_count}"
  untracked  = "?"
  stashed    = "$"
  modified   = "!"
  staged     = "+"
  renamed    = "»"
  deleted    = "✘"

  [rust]
  format = "[$symbol$version]($style) "
  style  = "bold red"

  [golang]
  format = "[$symbol$version]($style) "
  style  = "bold cyan"

  [nodejs]
  format = "[$symbol$version]($style) "
  style  = "bold green"

  [cmd_duration]
  min_time = 2_000
  format   = "[⏱ $duration]($style) "
  style    = "yellow"

  [time]
  disabled = false
  format   = "[$time]($style)"
  style    = "dimmed white"
  ```

- [ ] **Step 3: Add starship to stow-packages.txt**

  In `config/stow-packages.txt`, add a new line:

  ```
  starship
  ```

- [ ] **Step 4: Stow the starship package**

  ```bash
  stow --dir ~/dotfiles --target ~ starship
  ```

  Expected: `~/.config/starship.toml` symlink created.

- [ ] **Step 5: Verify starship renders the prompt**

  ```bash
  STARSHIP_SHELL=nu starship prompt
  ```

  Expected: a formatted prompt line ending with `→` on a new line.

- [ ] **Step 6: Commit**

  ```bash
  git add starship/ config/stow-packages.txt
  git commit -m "feat(starship): add two-line prompt config with → on line 2"
  ```

---

## Task 8: Smoke test the full shell

- [ ] **Step 1: Open a new terminal window**

  Open a fresh terminal (Ghostty, iTerm2, or whichever you use). It should launch nushell as the login shell.

- [ ] **Step 2: Verify login shell**

  ```nushell
  $nu.current-exe
  ```

  Expected: path ending in `nu`

- [ ] **Step 3: Verify PATH includes nix and cargo**

  ```nushell
  $env.PATH | where { |p| ($p | str contains "nix") or ($p | str contains "cargo") }
  ```

  Expected: at least one nix-profile path and one cargo path.

- [ ] **Step 4: Verify nil is available (for Zed)**

  ```nushell
  which nil
  ```

  Expected: path under `~/.nix-profile/bin/nil`

- [ ] **Step 5: Verify mise activates correctly**

  ```nushell
  mise current
  ```

  Expected: table of active tool versions.

- [ ] **Step 6: Verify zoxide works**

  ```nushell
  z --help
  ```

  Expected: zoxide help output.

- [ ] **Step 7: Verify atuin history search**

  Press `Ctrl+R`. Expected: atuin TUI opens with searchable history.

- [ ] **Step 8: Verify carapace completions**

  Type `git ` and press Tab. Expected: completions for git subcommands appear.

- [ ] **Step 9: Verify starship prompt layout**

  The prompt should show repo/path/git info on line 1, then `→` on line 2.

- [ ] **Step 10: Verify direnv works in a project directory**

  ```nushell
  cd ~/dotfiles
  ```

  Expected: no error. If a `.envrc` exists, direnv output appears.

- [ ] **Step 11: Verify fzf file picker**

  Press `Ctrl+F`. Expected: fzf file picker opens; selecting a file inserts its path.

- [ ] **Step 12: Final commit if any tweaks were needed**

  ```bash
  git add -p
  git commit -m "fix(nushell): smoke test fixes"
  ```

---

## Upgrade path (post-setup reference)

To update nushell in the future:

```bash
mise upgrade nu
```

No `/etc/shells` or `chsh` changes needed — the shim path is stable.

To update nix tools (atuin, carapace, starship, etc.):

```bash
mise run nix-update
```

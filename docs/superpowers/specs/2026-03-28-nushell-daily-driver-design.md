# Nushell Daily Driver Design

**Date:** 2026-03-28
**Repo:** `~/dotfiles`
**Status:** Approved

---

## Overview

Replace zsh as the daily driver shell with nushell (nu), installed via mise's cargo backend for automatic updates. Wire all tool integrations (mise, zoxide, direnv, starship, atuin, carapace) using the vendor/autoload pattern. Set nushell as the login shell.

---

## 1. Installation

### Nushell binary

- Remove `nu` from Homebrew (`brew uninstall nu`)
- Install via mise cargo backend: `mise use -g cargo:nu`
  - Installs from crates.io; `mise upgrade nu` keeps it current
  - Binary lives under `~/.local/share/mise/installs/cargo-nu/<version>/bin/nu`
  - Shim at `~/.local/share/mise/shims/nu` — stable path across upgrades

### Login shell

```bash
mise use -g cargo:nu
echo ~/.local/share/mise/shims/nu | sudo tee -a /etc/shells
chsh -s ~/.local/share/mise/shims/nu
```

### New tools (add to `flake.nix` `cliPackages`)

- `atuin` — searchable shell history (replaces Ctrl+R)
- `carapace-bin` — completion bridge for 500+ CLIs (nixpkgs attr: `carapace-bin`)

---

## 2. Stow Package Structure

```
nushell/.config/nushell/
  env.nu          # modified — PATH, ENV_CONVERSIONS, Homebrew, 1Password, Nix
  config.nu       # new — vendor seeding, keybindings, hooks, completions
  autoload/
    aliases.nu    # moved from nushell/.config/nushell/aliases.nu
    functions.nu  # moved from nushell/.config/nushell/functions.nu
    settings.nu   # moved from nushell/.config/nushell/settings.nu
```

Nushell auto-sources all files in `~/.config/nushell/autoload/` — no explicit `source` calls needed in `config.nu`.

`$nu.data-dir/vendor/autoload/` (typically `~/.local/share/nushell/vendor/autoload/`) holds machine-generated init scripts. This directory is **not stowed** — it is seeded by `config.nu` at shell startup.

---

## 3. env.nu Changes

### PATH additions

```nushell
| prepend ($env.HOME | path join ".nix-profile/bin")
| prepend ($env.HOME | path join ".cargo/bin")
```

Both appended to the existing PATH construction block.

### ENV_CONVERSIONS

Teach nushell to handle colon-separated environment variables from external tools:

```nushell
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

### Homebrew environment

```nushell
$env.HOMEBREW_PREFIX     = "/opt/homebrew"
$env.HOMEBREW_CELLAR     = "/opt/homebrew/Cellar"
$env.HOMEBREW_REPOSITORY = "/opt/homebrew"
```

### 1Password SSH agent socket

```nushell
$env.SSH_AUTH_SOCK = (
  $env.HOME | path join "Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
)
```

---

## 4. config.nu (new file)

### Vendor/autoload seeding

Runs at every shell startup. Idempotent — overwrites the cached init scripts.

```nushell
let vendor = $nu.data-dir | path join "vendor/autoload"
mkdir $vendor

starship  init nu               | save -f ($vendor | path join "starship.nu")
zoxide    init nushell          | save -f ($vendor | path join "zoxide.nu")
^mise     activate nu           | save -f ($vendor | path join "mise.nu")
atuin     init nu               | save -f ($vendor | path join "atuin.nu")
carapace  _carapace nushell     | save -f ($vendor | path join "carapace.nu")
```

Note: `^mise` uses caret to bypass any nu alias and call the binary directly.

Direnv is handled via a hook (see below) rather than an init script.

### Keybindings

```nushell
$env.config.keybindings = ($env.config.keybindings? | default [] | append [
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
  {
    name: edit_in_editor
    modifier: alt
    keycode: char_e
    mode: [emacs, vi_insert]
    event: { send: openeditor }
  }
])
```

### Hooks

All hooks use the append pattern to avoid clobbering hooks set by atuin, starship, etc.

**direnv** (fires on directory change only, not every prompt):

```nushell
$env.config.hooks.env_change.PWD = (
  $env.config.hooks.env_change.PWD? | default [] | append {||
    if (which direnv | is-empty) { return }
    direnv export json | from json | default {} | load-env
  }
)
```

**display_output** (expanded tables on wide terminals):

```nushell
$env.config.hooks.display_output = {||
  if (term size).columns >= 100 { table -e } else { table }
}
```

**command_not_found** (helpful fallback):

```nushell
$env.config.hooks.command_not_found = {|cmd|
  $"Command '($cmd)' not found. Is it a mise tool? Try: mise use ($cmd)"
}
```

### External completions

Carapace's generated `carapace.nu` (in vendor/autoload) sets up `$env.config.completions.external.completer` automatically.

---

## 5. autoload/ directory

Move the three files:

| From | To |
|---|---|
| `nushell/.config/nushell/aliases.nu` | `nushell/.config/nushell/autoload/aliases.nu` |
| `nushell/.config/nushell/functions.nu` | `nushell/.config/nushell/autoload/functions.nu` |
| `nushell/.config/nushell/settings.nu` | `nushell/.config/nushell/autoload/settings.nu` |

Update the `nunu` alias in `aliases.nu` (currently `source ~/.config/nushell/env.nu`) — env.nu is auto-loaded by nushell so this alias can be removed or updated to reload all autoload files.

---

## 6. Prompt (starship)

Two-line layout. No existing `starship.toml` in the repo — create a new `starship` stow package at `starship/.config/starship.toml`. Add `starship` to `config/stow-packages.txt`.

**Line 1 modules (left):** `directory`, `git_branch`, `git_status`, `rust`, `golang`, `nodejs`, `cmd_duration`
**Line 1 modules (right):** `time`
**Line 2:** `character` module with `→` symbol

```toml
add_newline = true

[line_break]
disabled = false

[character]
success_symbol = "[→](green)"
error_symbol   = "[→](red)"

[time]
disabled = false
format   = "[$time]($style) "
style    = "dimmed white"
```

All informational modules on line 1; cursor lands on line 2 after `→`.

---

## 7. mise task fixes

`nix-install` task has the same PATH issue as `nix-update`. Already fixed for `nix-update`; apply same fix:

```toml
[tasks.nix-install]
run = ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && ./scripts/setup-nix.sh"
```

---

## Out of Scope

- Windows/NixOS-WSL nushell config (separate concern)
- Migrating zsh history to atuin (can be done post-setup with `atuin import zsh`)
- Nushell plugin system (`nu_plugin_*`) — separate iteration

---

## Success Criteria

- `nu` launches as login shell from a fresh terminal
- `mise`, `zoxide`, `atuin`, `direnv`, `starship`, `carapace` all functional
- `nil` available in PATH (via `~/.nix-profile/bin`)
- Two-line starship prompt with `→` on line 2
- Ctrl+R opens atuin history search
- Tab completion works for `git`, `cargo`, `kubectl`, `gh` via carapace
- `mise upgrade nu` updates the binary with no config changes needed

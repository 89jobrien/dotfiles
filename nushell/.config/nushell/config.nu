# config.nu — main nushell configuration
# env.nu and autoload/ are sourced automatically by nushell before this file.

# ── Vendor/autoload seeding ───────────────────────────────────────────────────
# Generates tool init scripts into $nu.data-dir/vendor/autoload/ on every
# shell startup. Nushell auto-sources everything in that directory.

let vendor = $nu.data-dir | path join "vendor/autoload"
mkdir $vendor

# Ensure nix and mise are on PATH for vendor seeding — may already be set by env.nu
$env.PATH = ($env.PATH | prepend [
  ($env.HOME | path join ".nix-profile/bin")
  ($env.HOME | path join ".local/share/mise/shims")
] | uniq)

try { starship  init nu           | save -f ($vendor | path join "starship.nu") }
try { zoxide    init nushell      | save -f ($vendor | path join "zoxide.nu") }
try { ^mise     activate nu       | save -f ($vendor | path join "mise.nu") }
try { atuin     init nu           | save -f ($vendor | path join "atuin.nu") }
try { carapace  _carapace nushell | save -f ($vendor | path join "carapace.nu") }

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

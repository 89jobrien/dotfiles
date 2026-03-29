#!/usr/bin/env nu
# hooks-menu.nu — CLI + interactive TUI for managing Claude Code nu hooks.
#
# Usage:
#   nu scripts/hooks-menu.nu              # interactive picker
#   nu scripts/hooks-menu.nu list         # table of all hooks
#   nu scripts/hooks-menu.nu status       # health check
#   nu scripts/hooks-menu.nu test [name]  # run hook with sample input
#   nu scripts/hooks-menu.nu view [name]  # print hook source

const HOOKS_DIR = "/Users/joe/.claude/hooks/nu"
const SETTINGS_FILE = "/Users/joe/.claude/settings.json"

# Sample test payloads per hook category
def sample-payload [category: string]: nothing -> string {
    match $category {
        "pre" => ('{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_response":{}}' ),
        "post" => ('{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_response":{"exit_code":0,"stdout":"hello\n"}}'),
        "post-write" => ('{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.py","content":"print(1)"},"tool_response":{}}'),
        "post-agent" => ('{"tool_name":"Agent","tool_input":{"prompt":"test"},"tool_response":{}}'),
        "session" => ('{"tool_name":"","tool_input":{},"tool_response":{}}'),
        "doob" => ('{"tool_name":"Bash","tool_input":{"command":"git commit -m test"},"tool_response":{"exit_code":0,"stdout":""}}'),
        _ => ('{"tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"exit_code":0}}'),
    }
}

# Infer the test category for a hook based on its name and directory
def hook-category [name: string, dir: string]: nothing -> string {
    if $dir == "session" { return "session" }
    if $dir == "doob" { return "doob" }
    if ($name | str starts-with "post-agent") { return "post-agent" }
    if ($name | str starts-with "post-edit") or ($name | str starts-with "post-baml") or ($name | str starts-with "skill-") or ($name | str starts-with "sync_") or ($name | str starts-with "uv-") {
        return "post-write"
    }
    if $dir == "pre" { return "pre" }
    "post"
}

# Check if a hook file path appears in settings.json (match by basename to handle symlinks)
def is-active [file_path: string]: nothing -> bool {
    let basename = $file_path | path basename
    let settings = try { open $SETTINGS_FILE } catch { return false }
    let hooks_json = $settings | get -i hooks | default {}
    let all_commands = $hooks_json
        | values
        | each { |group| $group | each { |entry| $entry | get -i hooks | default [] } | flatten }
        | flatten
        | each { |h| $h | get -i command | default "" }
    $all_commands | any { |cmd| $cmd | str ends-with $basename }
}

# Check if a .py or .sh fallback exists for a hook
def has-fallback [name: string]: nothing -> string {
    let py = $"/Users/joe/.claude/hooks/($name).py"
    let sh = $"/Users/joe/.claude/hooks/($name).sh"
    if ($py | path exists) { return ".py" }
    if ($sh | path exists) { return ".sh" }
    ""
}

# Discover all nu hooks
def discover-hooks []: nothing -> table {
    glob $"($HOOKS_DIR)/**/*.nu"
    | each { |f|
        let name = $f | path basename | str replace ".nu" ""
        let dir = $f | path dirname | path basename
        let cat = hook-category $name $dir
        let active = is-active $f
        let fallback = has-fallback $name
        {
            name: $name
            dir: $dir
            category: $cat
            path: $f
            active: $active
            fallback: $fallback
        }
    }
    | sort-by dir name
}

# ── Subcommands ──────────────────────────────────────────────────────

def cmd-list [] {
    let hooks = discover-hooks
    let active_count = $hooks | where active == true | length
    let total = $hooks | length
    print $"($active_count)/($total) hooks active\n"
    $hooks
    | select name dir active fallback
    | rename name directory active fallback
    | table --expand
    | print
}

def cmd-status [] {
    let hooks = discover-hooks
    let total = $hooks | length
    let active_count = $hooks | where active == true | length
    let inactive = $hooks | where active == false
    let with_fallback = $hooks | where fallback != "" | length

    print $"Hooks directory: ($HOOKS_DIR)"
    print $"Settings file:   ($SETTINGS_FILE)\n"
    print $"Total hooks:     ($total)"
    print $"Active:          ($active_count)"
    print $"Inactive:        ($total - $active_count)"
    print $"With fallback:   ($with_fallback)\n"

    # Parse check
    print "Parse check:"
    let results = $hooks | each { |h|
        let result = do { nu --ide-check 10 $h.path } | complete
        let ok = $result.exit_code == 0
        let status = if $ok { "ok" } else { "FAIL" }
        print $"  ($status)  ($h.name)"
        { name: $h.name, ok: $ok, error: (if $ok { "" } else { $result.stderr | str trim }) }
    }
    let failed = $results | where ok == false
    if ($failed | length) > 0 {
        print $"\n($failed | length) hook(s) failed parse:"
        $failed | each { |f| print $"  ($f.name): ($f.error)" } | ignore
    } else {
        print $"\nAll ($total) hooks parse cleanly."
    }

    if ($inactive | length) > 0 {
        print "\nInactive hooks (not in settings.json):"
        $inactive | each { |h| print $"  ($h.name) \(($h.dir))" } | ignore
    }
}

def cmd-test [name?: string] {
    let hooks = discover-hooks
    let target_name = if $name != null { $name } else {
        let choices = $hooks | get name
        $choices | input list "Select hook to test:"
    }
    let hook = $hooks | where name == $target_name | first
    let payload = sample-payload $hook.category
    let active_label = if $hook.active { "active" } else { "inactive" }
    print $"Testing: ($hook.name) \(($hook.dir), ($active_label))"
    print $"Payload: ($payload | str substring 0..80)..."
    print "---"
    let result = $payload | nu $hook.path | complete
    if $result.exit_code == 0 {
        let out = $result.stdout | str trim
        if $out != "" { print $"stdout: ($out)" } else { print "stdout: (empty)" }
        print "exit: 0 (allow)"
    } else {
        if ($result.stdout | str trim) != "" { print $"stdout: ($result.stdout | str trim)" }
        if ($result.stderr | str trim) != "" { print $"stderr: ($result.stderr | str trim)" }
        let code = $result.exit_code
        print $"exit: ($code) \(deny)"
    }
}

def cmd-view [name?: string] {
    let hooks = discover-hooks
    let target_name = if $name != null { $name } else {
        let choices = $hooks | get name
        $choices | input list "Select hook to view:"
    }
    let hook = $hooks | where name == $target_name | first
    let active_label = if $hook.active { "active" } else { "inactive" }
    let fb = if $hook.fallback != "" { $", fallback: ($hook.fallback)" } else { "" }
    print $"# ($hook.name) \(($hook.dir), ($active_label)($fb))"
    print $"# ($hook.path)\n"
    open --raw $hook.path | print
}

# ── Interactive mode ─────────────────────────────────────────────────

def cmd-interactive [] {
    let actions = ["list" "status" "test" "view" "quit"]
    loop {
        let choice = $actions | input list "hooks-menu:"
        match $choice {
            "list" => { cmd-list }
            "status" => { cmd-status }
            "test" => { cmd-test }
            "view" => { cmd-view }
            "quit" => { return }
            _ => { return }
        }
        print ""
    }
}

# ── Main dispatch ────────────────────────────────────────────────────

def main [...args: string] {
    let cmd = $args | get -i 0 | default ""
    let arg = $args | get -i 1

    match $cmd {
        "list" => { cmd-list }
        "status" => { cmd-status }
        "test" => { cmd-test $arg }
        "view" => { cmd-view $arg }
        "" => { cmd-interactive }
        _ => {
            print $"Unknown command: ($cmd)"
            print "Usage: hooks-menu [list|status|test|view] [name]"
            exit 1
        }
    }
}

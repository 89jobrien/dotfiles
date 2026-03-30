#!/usr/bin/env nu
# uv-shebang-enforcer.nu — PostToolUse hook (Write|Edit)
# Warns if Python scripts use bare python3/python shebangs instead of the preferred uv PEP 723 pattern.

const HOOKS_DIRS = [
    "/Users/joe/.claude/hooks/"
    "/Users/joe/dotfiles/.claude/hooks/"
]

const WARNING_TEMPLATE = "[uv-shebang-enforcer] {file_path} uses a python3 shebang. Prefer the uv pattern:

For scripts with dependencies:
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = \">=3.11\"
# dependencies = [\"requests\", \"rich\"]
# ///

For scripts with no dependencies:
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = \">=3.11\"
# dependencies = []
# ///

This enables: uv run script.py (auto-installs deps, no venv needed)
Consider updating the shebang if this script will be run standalone."

def has_old_shebang [lines: list<string>] {
    let first3 = $lines | first 3
    $first3 | any { |line|
        let s = $line | str trim
        ($s | str starts-with "#!/usr/bin/env python") or
        ($s | str starts-with "#!/usr/bin/python") or
        ($s | str starts-with "#!/usr/local/bin/python") or
        ($s =~ '^#!.*(python3\.\d+|python\d*)')
    }
}

def has_pep723_metadata [lines: list<string>] {
    $lines | first 20 | any { |line| ($line | str trim) == "# /// script" }
}

def is_hooks_file [file_path: string] {
    $HOOKS_DIRS | any { |dir| $file_path | str starts-with $dir }
}

def main [] {
    let input = try { $in | from json } catch { exit 0 }

    let tool_name = $input | get -i tool_name | default ""
    if $tool_name not-in ["Write" "Edit"] { exit 0 }

    let file_path = $input | get -i tool_input.file_path | default ""
    if not ($file_path | str ends-with ".py") { exit 0 }
    if (is_hooks_file $file_path) { exit 0 }

    let lines = if $tool_name == "Write" {
        ($input | get -i tool_input.content | default "") | lines
    } else {
        try { open $file_path | lines } catch { exit 0 }
    }

    if (has_old_shebang $lines) and not (has_pep723_metadata $lines) {
        print ($WARNING_TEMPLATE | str replace "{file_path}" $file_path)
    }
}

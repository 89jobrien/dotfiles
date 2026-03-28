#!/usr/bin/env nu
# sync_memory_to_vault.nu — PostToolUse hook (Write|Edit)
# Syncs Claude session memory files to Obsidian vault KG.
# Triggered on Write|Edit. Exits immediately for non-memory writes.

const PROJECTS_ROOT = ($env.HOME | path join ".claude" "projects")

const PROJECT_MAP = {
    "-Users-joe-dev-devloop": {
        vault_rel: "02_Projects/devloop/CONTEXT.devloop.md"
        project_name: "devloop"
        wikilinks: ["PROJECT.devloop", "STRUCTURE.devloop"]
    }
    "-Users-joe-dev-minibox": {
        vault_rel: "02_Projects/minibox/CONTEXT.minibox.md"
        project_name: "minibox"
        wikilinks: ["PROJECT.minibox", "STRUCTURE.minibox"]
    }
    "-Users-joe-Documents-Obsidian-Vault": {
        vault_rel: "03_Area-Systems/CONTEXT.obsidian-vault.md"
        project_name: "obsidian-vault"
        wikilinks: ["GitHub Repos - Assessment", "Project Backlink Map"]
    }
    "-Users-joe-dev-pieces-ob": {
        vault_rel: "02_Projects/pieces-ob/CONTEXT.pieces-ob.md"
        project_name: "pieces-ob"
        wikilinks: ["Project Backlink Map"]
    }
    "-Users-joe--claude": {
        vault_rel: "03_Area-Systems/CONTEXT.claude-config.md"
        project_name: "claude-config"
        wikilinks: []
    }
}

const KNOWN_PREFIXES = ["feedback_" "project_" "reference_" "user_" "infra_"]

def is_memory_file [file_path: string] {
    let parts = $file_path | split row "/"
    let mem_idx = $parts | enumerate | where { |e| $e.item == "memory" } | first? | get -i index
    if $mem_idx == null { return false }
    if $mem_idx < 2 { return false }
    let projects_idx = $mem_idx - 2
    ($parts | get $projects_idx) == "projects" and ($file_path | str ends-with ".md")
}

def extract_slug [file_path: string] {
    $file_path | path dirname | path dirname | path basename
}

def derive_topic [filename: string] {
    mut stem = $filename | path parse | get stem
    for prefix in $KNOWN_PREFIXES {
        if ($stem | str starts-with $prefix) {
            $stem = ($stem | str substring ($prefix | str length)..)
            break
        }
    }
    $stem | str replace --all "_" "-"
}

def render_context_note [slug: string, project_name: string, files: list, wikilinks: list] {
    let topics = ($files | each { |f| derive_topic $f.stem })
    let topic_yaml = $"[($topics | str join ", ")]"
    let tags_yaml = $"[claude-memory, ($project_name), session-context]"

    mut lines = [
        "---"
        "type: research"
        "source_type: claude-session-memory"
        $"citation: \"~/.claude/projects/($slug)/memory\""
        $"topic: ($topic_yaml)"
        "status: active"
        $"tags: ($tags_yaml)"
        "---"
        ""
        $"# Claude Session Context — ($project_name)"
        ""
        "> Auto-generated from Claude Code session memory. Do not edit manually."
        $"> Source: `~/.claude/projects/($slug)/memory/`"
    ]

    for f in $files {
        $lines = ($lines ++ ["" "---" "" $"## ($f.stem)" "" ($f.content | str trim)])
    }

    if not ($wikilinks | is-empty) {
        $lines = ($lines ++ ["" "---" "" "## Links" ""])
        for wl in $wikilinks {
            $lines = ($lines ++ [$"[[$wl]]"])
        }
    }

    $lines ++ [""] | str join "\n"
}

def main [] {
    let input = try { $in | from json } catch { exit 0 }

    let file_path = $input | get -i tool_input.file_path | default ""
    if not (is_memory_file $file_path) { exit 0 }

    let slug = extract_slug $file_path

    let map_entry = $PROJECT_MAP | get -i $slug
    let vault_rel = if $map_entry != null { $map_entry.vault_rel } else {
        let name = $slug | split row "-" | last
        $"02_Projects/($name)/CONTEXT.($name).md"
    }
    let project_name = if $map_entry != null { $map_entry.project_name } else {
        $slug | split row "-" | last
    }
    let wikilinks = if $map_entry != null { $map_entry.wikilinks } else { [] }

    let memory_dir = $PROJECTS_ROOT | path join $slug "memory"
    if not ($memory_dir | path exists) { exit 0 }

    let files = try {
        ls ($"($memory_dir)/*.md")
            | where { |f| ($f.name | path basename) != "MEMORY.md" }
            | sort-by name
            | each { |f| {stem: ($f.name | path basename | path parse | get stem), content: (open $f.name)} }
    } catch { [] }

    if ($files | is-empty) { exit 0 }

    let vault_root = $env | get -i OBSIDIAN_VAULT_PATH | default ($env.HOME | path join "Documents" "Obsidian Vault")
    if not ($vault_root | path exists) { exit 0 }

    let note_content = render_context_note $slug $project_name $files $wikilinks
    let vault_path = $vault_root | path join $vault_rel

    mkdir ($vault_path | path dirname)
    $note_content | save --force $vault_path
}

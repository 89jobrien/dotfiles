#!/usr/bin/env nu
# skill-frontmatter-validator.nu — PostToolUse hook (Write|Edit)
# Validates that SKILL.md files have proper frontmatter after being written/edited.

def has_valid_frontmatter [content: string] {
    let lines = $content | lines
    if ($lines | is-empty) { return false }
    if ($lines | first | str trim) != "---" { return false }

    # Collect lines until the closing fence
    let rest = $lines | skip 1
    let close_idx = $rest | enumerate | where { |e| $e.item | str trim | $in == "---" } | first?

    if $close_idx == null { return false }

    let block = $rest | first $close_idx.index

    let has_name = ($block | where { |l| $l | str trim | str starts-with "name:" } | is-empty | not $in)
    let has_desc = ($block | where { |l| $l | str trim | str starts-with "description:" } | is-empty | not $in)

    $has_name and $has_desc
}

def main [] {
    let input = try { $in | from json } catch { exit 0 }

    let tool_name = $input | get -i tool_name | default ""
    if $tool_name not-in ["Write" "Edit"] { exit 0 }

    let file_path = $input | get -i tool_input.file_path | default ""
    if $file_path == "" { exit 0 }
    if not ($file_path | str ends-with "SKILL.md") { exit 0 }

    let content = try { open $file_path } catch { exit 0 }

    let valid = try { has_valid_frontmatter $content } catch { exit 0 }

    if $valid { exit 0 }

    print $"[JOEHOOK] [skill-frontmatter-validator] WARNING: ($file_path) is missing required frontmatter.

A valid SKILL.md must start with:
---
name: your-skill-name
description: Use when ... Symptoms - ...
---

The skill will not be discoverable without this. Edit the file to add frontmatter."
}

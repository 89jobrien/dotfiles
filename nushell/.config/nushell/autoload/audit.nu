# Redaction audit helpers — wraps scripts/redact-audit.sh and .logs/redact-audit.jsonl

# ── Internal ─────────────────────────────────────────────────────────────────

def _dotfiles [] { $env.HOME | path join "dotfiles" }
def _audit_log [] { $env.HOME | path join "dotfiles/.logs/redact-audit.jsonl" }

def _read_audit_log [] {
    let log = _audit_log
    if not ($log | path exists) { return [] }
    open $log
    | lines
    | where { |l| ($l | str trim) != "" }
    | each { |l| $l | from json }
    | update ts { |r| $r.ts | into datetime }
}

# ── audit-log ────────────────────────────────────────────────────────────────

# Read the redaction audit log as a table.
# Filter by --tier, --file, --hook, or --since (e.g. "1day", "2hr", "30min")
def audit-log [
    --tier: string   # Filter to a specific tier (critical, high, medium, low)
    --file: string   # Filter by file path substring
    --hook: string   # Filter by hook name (pre-commit, manual, ...)
    --since: string  # Only show entries newer than this duration (e.g. 1day, 2hr)
] {
    mut rows = _read_audit_log

    if ($tier | is-not-empty) {
        $rows = ($rows | where tier == $tier)
    }
    if ($file | is-not-empty) {
        $rows = ($rows | where { |r| $r.file | str contains $file })
    }
    if ($hook | is-not-empty) {
        $rows = ($rows | where hook == $hook)
    }
    if ($since | is-not-empty) {
        let cutoff = (date now) - ($since | into duration)
        $rows = ($rows | where ts > $cutoff)
    }

    $rows | select ts hook commit file tier group label match_count
}

# ── audit-summary ─────────────────────────────────────────────────────────────

# Summarise audit log hits grouped by tier and group.
# Pass --since to limit to a recent window (e.g. "7day").
def audit-summary [
    --since: string  # Limit to entries newer than this duration (e.g. 7day)
] {
    mut rows = _read_audit_log

    if ($since | is-not-empty) {
        let cutoff = (date now) - ($since | into duration)
        $rows = ($rows | where ts > $cutoff)
    }

    if ($rows | is-empty) {
        print "No audit entries found."
        return
    }

    $rows
    | group-by tier
    | transpose tier entries
    | each { |t|
        let total = ($t.entries | get match_count | math sum)
        let by_group = (
            $t.entries
            | group-by group
            | transpose group rows
            | each { |g| { group: $g.group, hits: ($g.rows | get match_count | math sum) } }
            | sort-by hits -r
        )
        { tier: $t.tier, total_hits: $total, breakdown: $by_group }
    }
    | sort-by total_hits -r
}

# ── audit-scan ───────────────────────────────────────────────────────────────

# Scan files through the redaction auditor and log findings.
# With no args, scans staged git files (same as pre-commit hook).
# Pass file paths to scan specific files.
def audit-scan [
    ...files: string  # Files to scan (default: staged git files)
    --verbose (-v)    # Print findings to terminal as well as logging
] {
    let script = (_dotfiles | path join "scripts/redact-audit.sh")

    if not ($script | path exists) {
        error make { msg: $"audit script not found: ($script)" }
    }

    mut args = ["--hook", "manual"]

    if $verbose { $args = ($args | append "--verbose") }

    if ($files | is-empty) {
        $args = ($args | append "--staged")
    } else {
        $args = ($args | append $files)
    }

    ^bash $script ...$args
}

# ── audit-top ─────────────────────────────────────────────────────────────────

# Show the most frequently hit files in the audit log.
def audit-top [
    --n: int = 10    # Number of results to show
    --since: string  # Limit to entries newer than this duration (e.g. 7day)
] {
    mut rows = _read_audit_log

    if ($since | is-not-empty) {
        let cutoff = (date now) - ($since | into duration)
        $rows = ($rows | where ts > $cutoff)
    }

    $rows
    | group-by file
    | transpose file entries
    | each { |f| { file: $f.file, hits: ($f.entries | get match_count | math sum), scans: ($f.entries | length) } }
    | sort-by hits -r
    | first $n
}

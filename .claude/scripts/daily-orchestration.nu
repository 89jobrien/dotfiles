#!/usr/bin/env nu
# daily-orchestration.nu — Headless wrapper for /daily-orchestration skill
#
# Runs the daily orchestration workflow non-interactively via `claude -p`.
# Designed for cron or manual invocation outside a Claude Code session.
#
# Usage:
#   nu ~/.claude/scripts/daily-orchestration.nu
#   nu ~/.claude/scripts/daily-orchestration.nu --dry-run
#
# Prerequisites:
#   - `claude` CLI in PATH (Claude Code)
#   - Claude CLI already authenticated or otherwise configured in the current environment

def main [--dry-run] {
    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")
    print $"[daily-orchestration] Starting at ($timestamp)"

    if $dry_run {
        print "[daily-orchestration] DRY RUN — would invoke: claude -p '/daily-orchestration'"
        exit 0
    }


    # Verify claude CLI is available
    if (which claude | is-empty) {
        print --stderr "[daily-orchestration] ERROR: `claude` CLI not found in PATH"
        exit 1
    }
    # Run orchestration headlessly using the current environment/auth.
    # Do not wrap the whole process in `op run --env-file`: a stale or unrelated
    # 1Password reference in the env file should not block the workflow.
    # The prompt invokes the /daily-orchestration skill which handles all phases.
    let prompt = "Run the daily orchestration workflow across all repos. Follow the /daily-orchestration skill exactly: pull all repos, analyze health, fix P0s, write Obsidian daily note, push. Do not prompt for confirmation — this is a non-interactive run."
    let result = (do {
        ^claude --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Agent" -p $prompt
    } | complete)

    let end_timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")

    if $result.exit_code != 0 {
        print --stderr $"[daily-orchestration] FAILED at ($end_timestamp)"
        print --stderr $result.stdout
        print --stderr $result.stderr
        exit 1
    }

    print $result.stdout
    print $"[daily-orchestration] Completed at ($end_timestamp)"
}

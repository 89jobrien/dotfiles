#!/usr/bin/env nu
# doob-overdue-alert.nu — SessionStart hook
# On session start in the doob project, checks for overdue todos and stale in-progress items.

def main [] {
    let cwd = $env.PWD
    let log_file = "/tmp/doob-session-alert.log"

    if not ($cwd | str contains "/dev/doob") { exit 0 }

    if (which doob | is-empty) { exit 0 }

    let today = (date now | format date "%Y-%m-%d")

    # Fetch all pending todos with due dates
    let todos_result = (do { ^doob todo list --status pending --json } | complete)
    if $todos_result.exit_code != 0 { exit 0 }

    let todos = try { $todos_result.stdout | from json | get -i todos | default [] } catch { [] }

    let overdue = ($todos
        | where { |t|
            let due = $t | get -i due_date | default null
            $due != null and $due < $today
        }
        | each { |t|
            let uuid_short = $t.uuid | str substring 0..8
            $"  [($uuid_short)] ($t.content) \(due: ($t.due_date)\)"
        })

    # Fetch stale in-progress (updated > 7 days ago)
    let ip_result = (do { ^doob todo list --status in_progress --json } | complete)
    let in_progress = if $ip_result.exit_code == 0 {
        try { $ip_result.stdout | from json | get -i todos | default [] } catch { [] }
    } else { [] }

    # Cutoff: 7 days ago in ISO format
    let cutoff = ((date now) - 7day | format date "%Y-%m-%dT%H:%M:%S")

    let stale = ($in_progress
        | where { |t|
            let updated = $t | get -i updated_at | default ""
            $updated != "" and $updated < $cutoff
        }
        | each { |t|
            let uuid_short = $t.uuid | str substring 0..8
            let stale_date = $t.updated_at | str substring 0..10
            $"  [($uuid_short)] ($t.content) \(stale since ($stale_date)\)"
        })

    let overdue_section = if ($overdue | is-empty) { "" } else {
        "OVERDUE todos:\n" + ($overdue | str join "\n")
    }
    let stale_section = if ($stale | is-empty) { "" } else {
        "STALE in-progress todos \(>7 days\):\n" + ($stale | str join "\n")
    }
    let status_msg = if ($overdue | is-empty) and ($stale | is-empty) {
        "No overdue or stale todos."
    } else { "" }

    let output = [
        ""
        $"=== doob session alert: ($today) ==="
        $overdue_section
        $stale_section
        $status_msg
        "==================================="
        ""
    ] | where { |l| $l != "" } | str join "\n"

    $"($output)\n" | save --append $log_file
}

#!/usr/bin/env nu
# post-push-ci-watch.nu — PostToolUse hook (Bash)
# After git push, looks up the CI run for the pushed branch and reports status.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    if not ($cmd | str contains "git push") { exit 0 }

    if (which gh | is-empty) { exit 0 }

    let branch_result = (do { ^git branch --show-current } | complete)
    if $branch_result.exit_code != 0 { exit 0 }
    let branch = $branch_result.stdout | str trim
    if $branch == "" { exit 0 }

    # Poll up to 5 times with 2s between attempts
    mut run_info = null
    for attempt in 1..5 {
        sleep 2sec
        let result = (do {
            ^gh run list --branch $branch --limit 1 --json databaseId,status,conclusion,name,url,updatedAt
        } | complete)
        if $result.exit_code == 0 {
            let parsed = try { $result.stdout | from json } catch { [] }
            if ($parsed | length) > 0 {
                $run_info = ($parsed | first)
                break
            }
        }
    }

    if $run_info == null { exit 0 }

    let run_id = $run_info.databaseId
    let run_status = $run_info.status
    let run_conclusion = $run_info | get -i conclusion | default ""
    let run_url = $run_info.url

    print ""
    if $run_status == "completed" {
        if $run_conclusion == "success" {
            print $"[ok] CI \(($branch)\): ($run_conclusion) -- ($run_url)"
        } else {
            print $"[fail] CI \(($branch)\): ($run_conclusion) -- ($run_url)"
        }
    } else {
        print $"[running] CI \(($branch)\): ($run_status) -- ($run_url)"
        print $"   Watch: gh run watch ($run_id)"
    }
}

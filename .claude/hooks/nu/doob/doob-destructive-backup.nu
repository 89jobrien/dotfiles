#!/usr/bin/env nu
# doob-destructive-backup.nu — PreToolUse hook (Bash)
# Before `doob todo remove` or `doob note remove`, backs up the SurrealDB database.
# Keeps the 10 most recent backups.

def main [] {
    let input = open --raw /dev/stdin | from json
    let cmd = $input | get -i tool_input.command | default ""

    let is_remove = ($cmd | str contains "doob todo remove") or ($cmd | str contains "doob note remove")
    if not $is_remove { exit 0 }

    let db_path = $env | get -i DOOB_DB_PATH | default ($env.HOME | path join ".claude" "data" "doob.db")
    let backup_dir = $env.HOME | path join ".doob" "backups"

    if not ($db_path | path exists) { exit 0 }

    mkdir $backup_dir

    let timestamp = (date now | format date "%Y%m%d-%H%M%S")
    let backup_path = $backup_dir | path join $"doob-($timestamp).db"

    ^cp -r $db_path $backup_path

    # Trim to 10 most recent backups
    let backups = (ls $"($backup_dir)/doob-*.db" | sort-by modified --reverse | skip 10 | get name)
    for b in $backups {
        rm -rf $b
    }

    let log_file = "/tmp/doob-backup.log"
    let ts = (date now | format date "%Y-%m-%d %H:%M:%S")
    $"[($ts)] Backup created: ($backup_path) \(command: ($cmd)\)\n" | save --append $log_file
}

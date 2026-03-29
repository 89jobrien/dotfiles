#!/usr/bin/env nu
# destructive-service-guardian.nu — PreToolUse hook
# Intercepts Bash commands matching known destructive patterns and blocks them.

# Destructive patterns: [id, pattern, description, impact]
const PATTERNS = [
    {id: "gitea-password-reset",  pattern: 'gitea\s+admin\s+user\s+(change-password|reset-password|create)',  description: "Gitea admin user credential operation",       impact: "May set must_change_password=true and break API tokens"}
    {id: "op-item-edit",          pattern: 'op\s+item\s+(edit|delete|create|update)',                          description: "1Password item modification",                impact: "Permanently modifies or deletes credential store entries"}
    {id: "docker-passwd",         pattern: 'docker\s+exec.+passwd\s+|docker\s+exec.+chpasswd',                description: "Container password change",                  impact: "Changes credentials inside a running container"}
    {id: "psql-alter-user",       pattern: '(?i)ALTER\s+(USER|ROLE)',                                          description: "PostgreSQL user/role modification",           impact: "Changes database credentials or permissions"}
    {id: "systemctl-shared",      pattern: 'systemctl\s+(restart|stop|disable|mask)\s+(gitea|postgres|mysql|nginx|caddy|traefik)', description: "Shared service restart/stop", impact: "Interrupts a shared infrastructure service"}
    {id: "git-push-force",        pattern: 'git\s+push.+--force(?!-with-lease)|git\s+push.+-f\b',             description: "Force push (destructive git history rewrite)", impact: "Overwrites remote history, may destroy teammates' work"}
    {id: "drop-database",         pattern: '(?i)DROP\s+(DATABASE|TABLE|SCHEMA)\s+(?!IF\s+EXISTS\s+test|IF\s+EXISTS\s+dev)', description: "Database/table drop", impact: "Permanently destroys data"}
]

def deny [message: string] {
    let payload = {
        hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}
        systemMessage: $"[JOEHOOK] ($message)"
    }
    print --stderr ($payload | to json)
    exit 2
}

def main [] {
    let input = try { open --raw /dev/stdin | from json } catch { exit 0 }

    if ($input | get -i tool_name | default "") != "Bash" { exit 0 }

    let command = $input | get -i tool_input.command | default ""
    if $command == "" { exit 0 }

    let matched = ($PATTERNS | where { |entry|
        $command =~ $entry.pattern
    } | do { |rows| try { $rows | first } catch { null } } $in)

    if $matched == null { exit 0 }

    let preview = if ($command | str length) > 120 {
        $"($command | str substring 0..120)…"
    } else {
        $command
    }

    let message = $"[destructive-guardian] STOP — destructive operation detected.\n\nPattern: ($matched.description)\nRisk: ($matched.impact)\nCommand: ($preview)\n\nThis action may be irreversible. Do NOT proceed until the user explicitly confirms with something like \"yes, go ahead\" or \"confirmed\". Ask the user first."

    deny $message
}

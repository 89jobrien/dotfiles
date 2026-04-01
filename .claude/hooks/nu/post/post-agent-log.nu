#!/usr/bin/env nu
# post-agent-log.nu — PostToolUse hook
# Logs joe suite agent dispatches (forge, sentinel, navigator, conductor) to ~/.claude/logs/agent-sessions.jsonl

def main [] {
    let input = open --raw /dev/stdin | from json

    let log_dir = $env.HOME | path join ".claude" "logs"
    let log_file = $log_dir | path join "agent-sessions.jsonl"
    mkdir $log_dir

    let params = $input | get -i tool_input | default {}
    let suite = ["forge" "sentinel" "navigator" "conductor"]

    let agent_type = $params | get -i subagent_type | default ""
    let description = $params | get -i description | default ""
    let prompt = $params | get -i prompt | default ""

    # Detect suite agent: explicit subagent_type, or name in description/prompt
    let agent = if $agent_type in $suite {
        $agent_type
    } else {
        let found = ($suite | where { |name|
            (($description | str downcase | str contains $name) or ($prompt | str downcase | str contains $"@($name)"))
        })
        if ($found | is-empty) { null } else { $found | first }
    }

    if $agent == null { exit 0 }

    let entry = {
        ts: (date now | format date "%Y-%m-%dT%H:%M:%S%z")
        agent: $agent
        description: (if ($description | str length) > 200 { $description | str substring 0..200 } else { $description })
        cwd: ($env | get -i PWD | default "")
    }

    $"($entry | to json)\n" | save --append $log_file

    {decision: "allow"} | to json | print
}

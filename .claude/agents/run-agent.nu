#!/usr/bin/env nu
# Usage: run-agent.nu <agent-name> [prompt] [--dir <path>]
# Loads agents from maintenance.yaml, converts to JSON, runs via claude --print

def main [
    agent: string         # agent name from maintenance.yaml
    prompt?: string       # optional override prompt
    --dir: string = "."   # working directory
    --model: string = "haiku"  # default to haiku
] {
    let yaml_path = $"($env.HOME)/.claude/agents/maintenance.yaml"
    let agents_yaml = open $yaml_path | get agents

    if not ($agents_yaml | columns | any { |c| $c == $agent }) {
        error make { msg: $"Unknown agent: ($agent). Available: ($agents_yaml | columns | str join ', ')" }
    }

    let agent_def = $agents_yaml | get $agent
    let agents_json = { $agent: $agent_def } | to json --raw

    let user_prompt = if ($prompt | is-empty) {
        $"Run your maintenance task in ($dir)"
    } else {
        $prompt
    }

    cd $dir
    claude --print --model $model --agents $agents_json --dangerously-skip-permissions $user_prompt
}

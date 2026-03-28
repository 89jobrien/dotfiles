#!/usr/bin/env nu
# session-start.nu — SessionStart hook
# Emits a navigator hint when starting a session in any ~/dev/* project.

def main [] {
    let cwd = $env.PWD
    let dev_dir = $env.HOME | path join "dev"

    if ($cwd | str starts-with $"($dev_dir)/") {
        let remainder = $cwd | str substring (($dev_dir | str length) + 1)..
        let project = $remainder | split row "/" | first
        if $project != "" {
            print $"Navigator available: run /navigate ($project) for an architecture briefing."
        }
    }

    # Run rtk learn in the background
    if not (which rtk | is-empty) {
        job spawn { ^rtk learn --quiet }
    }
}

#!/usr/bin/env nu

# Session Guard: Validates config/env file hashes and expected env keys at shell startup
# Runs at every nushell startup to detect configuration drift.

def validate_session [] {
  let baseline_path = $"($env.HOME)/.config/nushell/.session-baseline.json"
  let files_to_check = [
    $"($env.HOME)/.config/nushell/env.nu"
    $"($env.HOME)/.config/nushell/config.nu"
    $"($env.HOME)/dev/.envrc"
    $"($env.HOME)/dev/.env"
    $"($env.HOME)/.mise.toml"
  ]
  let required_env_keys = [
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "GITHUB_TOKEN"
  ]

  # Check if baseline exists
  if not ($baseline_path | path exists) {
    print "[session-guard] No baseline found. Run session-baseline.nu to initialize."
    return
  }

  # Load baseline
  let baseline = (open --raw $baseline_path | from json)

  # Check file hashes
  for file_path in $files_to_check {
    if ($file_path | path exists) {
      let current_hash = (open --raw $file_path | hash sha256)
      let file_name = ($file_path | path basename)

      if ($baseline.files | get -i $file_name) != $current_hash {
        print $"[session-guard] DRIFT: ($file_name) hash changed"
      }
    }
  }

  # Check required env vars
  for key in $required_env_keys {
    if ($env | get -i $key) == null {
      print $"[session-guard] MISSING ENV: ($key)"
    }
  }
}

# Run validation (silent if all OK)
validate_session

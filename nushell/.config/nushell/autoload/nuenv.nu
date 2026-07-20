# nuenv.nu — secure .env.nu loader (replaces direnv for Nu-native projects)
# Source: nushell/nu_scripts (nu-hooks/nuenv), adapted for local conventions.
#
# Usage:
#   source autoload/nuenv.nu
#   # In config.nu hooks section:
#   $env.config.hooks.env_change.PWD = (... | append (nuenv-hook))
#   # Then in any project dir:
#   nuenv allow    # approve .env.nu (sha256 allowlist)
#   nuenv disallow # revoke

const NUENV_FILE = ($nu.cache-dir | path join 'nuenv' 'allowed.txt')

def get-allowed []: [ nothing -> list<string> ] {
  if ($NUENV_FILE | path exists) {
    open $NUENV_FILE | lines
  } else {
    []
  }
}

# Returns the PWD-change hook record for use in env_change.PWD
export def nuenv-hook []: [ nothing -> record<condition: closure, code: string> ] {
  {
    condition: {|_, after| $after | path join '.env.nu' | path exists }
    code: $"
      let allowed = if \('($NUENV_FILE)' | path exists\) {
        open ($NUENV_FILE) | lines
      } else {
        []
      }

      if \(open .env.nu | hash sha256\) not-in $allowed {
        error make --unspanned {
          msg: $'\(ansi purple\)\('.env.nu' | path expand\)\(ansi reset\) is not allowed',
          help: $'please run \(ansi default_dimmed\)nuenv allow\(ansi reset\) first',
        }
      }

      print $'[\(ansi yellow_bold\)nuenv\(ansi reset\)] loading \(ansi purple\)\('.env.nu' | path expand\)\(ansi reset\)'
      source .env.nu
    "
  }
}

def _log [msg: string, color: string] {
  print $'[(ansi $color)nuenv(ansi reset)] (ansi purple)(".env.nu" | path expand)(ansi reset) ($msg)'
}

def check-env-file [] {
  if not (".env.nu" | path exists) {
    error make --unspanned {
      msg: $"(ansi red_bold)env file not found(ansi reset)",
      help: $"no (ansi yellow).env.nu(ansi reset) in (ansi purple)(pwd)(ansi reset)",
    }
  }
}

# Adds ./.env.nu to the allowlist
export def "nuenv allow" [] {
  check-env-file
  let allowed = get-allowed
  let hash = open .env.nu | hash sha256
  if $hash in $allowed {
    _log "is already allowed" "yellow_bold"
    return
  }
  mkdir ($nu.cache-dir | path join "nuenv")
  $hash | $in + "\n" out>> $NUENV_FILE
  _log "has been allowed" "green_bold"
}

# Removes ./.env.nu from the allowlist
export def "nuenv disallow" [] {
  check-env-file
  let allowed = get-allowed
  let hash = open .env.nu | hash sha256
  if $hash not-in $allowed {
    _log "is already disallowed" "yellow_bold"
    return
  }
  $allowed | find --invert $hash | to text | save --force $NUENV_FILE
  _log "has been disallowed" "green_bold"
}

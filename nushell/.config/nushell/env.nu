# Environment variables

# Guard: reset PWD to $HOME if inherited value is not an absolute path.
# Prevents "× $env.PWD is not an absolute path" on startup when launched
# from tools (tmux, IDE terminals, launchers) that don't set PWD correctly.
if not ($env.PWD | str starts-with "/") {
    $env.PWD = $env.HOME
}

$env.EDITOR = "vim"
# $env.PATH = ($env.PATH | prepend "/some/custom/path")
$env.PATH = ($env.PATH | prepend ($env.HOME | path join ".local/bin"))

# API keys from 1Password
$env.OPENAI_API_KEY = (op read "op://cli/OpenAI/credential" --account=my.1password.com)

# PowerShell profile — part of dotfiles
# Managed by: windows/powershell/Microsoft.PowerShell_profile.ps1
# Linked to $PROFILE by scripts/setup-windows.ps1

# ── Path additions ────────────────────────────────────────────────────────────
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'
if (Test-Path $LocalBin) { $env:PATH = "$LocalBin;$env:PATH" }

# ── Mise (runtime version manager) ───────────────────────────────────────────
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Out-String | Invoke-Expression
}

# ── Zoxide (smart cd) ─────────────────────────────────────────────────────────
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ── Starship prompt ───────────────────────────────────────────────────────────
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# ── Aliases ───────────────────────────────────────────────────────────────────
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function l  { eza --icons @args }
    function ll { eza -l --icons --git @args }
    function la { eza -la --icons --git @args }
    function lt { eza --tree --icons @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias cat bat
}

if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias grep rg
}

# ── WSL shortcuts ─────────────────────────────────────────────────────────────
# Open a WSL shell quickly
function wsl-here {
    $wslPath = (wsl wslpath ($PWD.Path -replace '\\', '/')) 2>$null
    if ($wslPath) { wsl -d Ubuntu --cd $wslPath }
    else { wsl -d Ubuntu }
}
Set-Alias wh wsl-here

# Run a command inside the default WSL distro
function wrun { wsl -d Ubuntu -- @args }

# ── Git shortcuts ─────────────────────────────────────────────────────────────
function gs  { git status @args }
function gd  { git diff @args }
function gco { git checkout @args }
function gp  { git pull @args }

# ── Environment ───────────────────────────────────────────────────────────────
$env:EDITOR = if (Get-Command zed -ErrorAction SilentlyContinue) { 'zed' }
              elseif (Get-Command code -ErrorAction SilentlyContinue) { 'code' }
              else { 'notepad' }

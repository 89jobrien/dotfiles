#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a Windows machine with WSL2 and dev tools.

.DESCRIPTION
    1. Optionally self-elevates to Administrator
    2. Installs WSL2 + Ubuntu (unless -SkipWSL)
    3. Installs native Windows packages via winget (unless -SkipPackages)
    4. Clones dotfiles into WSL and runs the Linux bootstrap inside it (unless -SkipBootstrap)
    5. Sets up a PowerShell profile

.NOTES
    Requires Windows 10 2004+ (build 19041+) or Windows 11.
    Run from the repo root or via install.ps1.
#>
[CmdletBinding()]
param(
    [switch]$SkipWSL,
    [switch]$SkipPackages,
    [switch]$SkipBootstrap,
    [switch]$DryRun,
    [string]$WslDistro = 'Ubuntu',
    [string]$DotfilesRepo = 'https://github.com/89jobrien/dotfiles.git',
    [string]$DotfilesWslPath = '/root/dotfiles'
)

$ErrorActionPreference = 'Stop'
$ScriptDir  = $PSScriptRoot
$RepoRoot   = Split-Path $ScriptDir -Parent
$PackageList = Join-Path $RepoRoot 'winget\packages.txt'

# ── Colour helpers ────────────────────────────────────────────────────────────

function Write-Step  { param($msg) Write-Host "  --> $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  [ok] $msg" -ForegroundColor Green }
function Write-Skip  { param($msg) Write-Host " [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn  { param($msg) Write-Host " [warn] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [err] $msg" -ForegroundColor Red }
function Write-Section { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Magenta }

function Invoke-Step {
    param([string]$Label, [scriptblock]$Block)
    Write-Step $Label
    if ($DryRun) { Write-Skip "dry-run: skipped"; return }
    & $Block
}

# ── Elevation ─────────────────────────────────────────────────────────────────

function Assert-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if ($current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    Write-Warn 'Not running as Administrator — relaunching elevated...'
    $args_ = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v) { $args_ += " -$k" } }
        else { $args_ += " -$k `"$v`"" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args_
    exit 0
}

# ── Windows version check ─────────────────────────────────────────────────────

function Assert-WindowsVersion {
    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -lt 19041) {
        Write-Err "WSL2 requires Windows 10 build 19041+ (current: $build). Update Windows first."
        exit 1
    }
    Write-Ok "Windows build $build — WSL2 supported"
}

# ── WSL2 install ──────────────────────────────────────────────────────────────

function Install-WSL {
    Write-Section 'WSL2'

    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $distros = wsl --list --quiet 2>$null
        if ($distros -match $WslDistro) {
            Write-Skip "$WslDistro already installed"
            return
        }
    }

    Invoke-Step "Enable WSL2 and install $WslDistro" {
        # wsl --install handles: WSL feature, VirtualMachinePlatform, WSL2 default, distro download
        wsl --install --distribution $WslDistro
        Write-Ok "WSL2 + $WslDistro installed"
        Write-Warn 'A reboot may be required. Re-run this script after rebooting if bootstrap fails.'
    }
}

# ── winget packages ───────────────────────────────────────────────────────────

function Install-WingetPackages {
    Write-Section 'Native Windows packages (winget)'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        return
    }

    if (-not (Test-Path $PackageList)) {
        Write-Warn "Package list not found: $PackageList"
        return
    }

    $ids = Get-Content $PackageList |
        Where-Object { $_ -match '^\s*[A-Za-z]' } |
        ForEach-Object { ($_ -split '#')[0].Trim() } |
        Where-Object { $_ }

    foreach ($id in $ids) {
        Write-Step "winget install $id"
        if ($DryRun) { Write-Skip 'dry-run'; continue }
        winget install --id $id -e --accept-source-agreements --accept-package-agreements --silent 2>&1 |
            Where-Object { $_ -notmatch 'Found an existing package' } |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            Write-Ok $id
        } else {
            Write-Warn "winget install $id exited $LASTEXITCODE (may already be installed)"
        }
    }
}

# ── Dotfiles bootstrap inside WSL ────────────────────────────────────────────

function Invoke-WslBootstrap {
    Write-Section 'Dotfiles bootstrap inside WSL'

    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Warn 'wsl not available — skipping Linux bootstrap'
        return
    }

    $distros = wsl --list --quiet 2>$null
    if ($distros -notmatch $WslDistro) {
        Write-Warn "$WslDistro not found in WSL — skipping bootstrap"
        return
    }

    Invoke-Step "Clone dotfiles into WSL at $DotfilesWslPath" {
        wsl -d $WslDistro -- bash -c @"
set -e
if [ ! -d '$DotfilesWslPath/.git' ]; then
    git clone '$DotfilesRepo' '$DotfilesWslPath'
fi
"@
    }

    Invoke-Step 'Run Linux bootstrap inside WSL' {
        wsl -d $WslDistro -- bash -c @"
set -e
cd '$DotfilesWslPath'
export ALLOW_DIRECT_DOTFILES_INSTALL=1
bash install.sh
"@
    }

    Write-Ok 'WSL bootstrap complete'
}

# ── PowerShell profile ────────────────────────────────────────────────────────

function Install-PsProfile {
    Write-Section 'PowerShell profile'

    $profileDir = Split-Path $PROFILE -Parent
    $profileSrc = Join-Path $RepoRoot 'windows\powershell\Microsoft.PowerShell_profile.ps1'

    if (-not (Test-Path $profileSrc)) {
        Write-Skip 'No windows/powershell profile in repo'
        return
    }

    Invoke-Step "Link PowerShell profile to $PROFILE" {
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        if (Test-Path $PROFILE) {
            Write-Warn "Existing profile at $PROFILE — backing up to $PROFILE.bak"
            Copy-Item $PROFILE "$PROFILE.bak" -Force
        }
        New-Item -ItemType SymbolicLink -Path $PROFILE -Target $profileSrc -Force | Out-Null
        Write-Ok "Profile linked: $PROFILE -> $profileSrc"
    }
}

# ── Git config (Windows-side) ─────────────────────────────────────────────────

function Set-GitConfig {
    Write-Section 'Git config (Windows)'

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Skip 'git not in PATH — skipping (install via winget first)'
        return
    }

    Invoke-Step 'Set core.autocrlf = input' {
        git config --global core.autocrlf input
        Write-Ok 'core.autocrlf = input'
    }

    Invoke-Step 'Set core.symlinks = true' {
        git config --global core.symlinks true
        Write-Ok 'core.symlinks = true (requires Developer Mode or admin git operations)'
    }
}

# ── Windows Terminal config ───────────────────────────────────────────────────

function Set-WindowsTerminalConfig {
    Write-Section 'Windows Terminal'

    $wtSettingsSrc = Join-Path $RepoRoot 'windows\terminal\settings.json'
    if (-not (Test-Path $wtSettingsSrc)) {
        Write-Skip 'No windows/terminal/settings.json in repo'
        return
    }

    $wtDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    if (-not (Test-Path $wtDir)) {
        Write-Skip 'Windows Terminal not installed yet — run again after package install'
        return
    }

    Invoke-Step "Copy Windows Terminal settings" {
        Copy-Item $wtSettingsSrc (Join-Path $wtDir 'settings.json') -Force
        Write-Ok 'Windows Terminal settings applied'
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────

Assert-Admin
Assert-WindowsVersion

Write-Host ''
Write-Host '  dotfiles — Windows bootstrap' -ForegroundColor White
Write-Host "  Repo: $RepoRoot" -ForegroundColor DarkGray
if ($DryRun) { Write-Host '  [DRY RUN]' -ForegroundColor Yellow }
Write-Host ''

if (-not $SkipWSL)       { Install-WSL }
if (-not $SkipPackages)  { Install-WingetPackages }
Set-GitConfig
if (-not $SkipBootstrap) { Invoke-WslBootstrap }
Install-PsProfile
Set-WindowsTerminalConfig

Write-Host ''
Write-Ok 'Bootstrap complete.'
Write-Host ''
Write-Host '  Next steps:' -ForegroundColor White
Write-Host '    1. Reboot if WSL was just installed' -ForegroundColor DarkGray
Write-Host '    2. Open Windows Terminal and select the Ubuntu profile' -ForegroundColor DarkGray
Write-Host '    3. Your Linux dev environment is in WSL at ~/dotfiles' -ForegroundColor DarkGray
Write-Host ''

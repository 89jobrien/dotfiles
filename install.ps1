#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a Windows dev environment from this dotfiles repo.

.DESCRIPTION
    Entry point for Windows bootstrap. Delegates to scripts/setup-windows.ps1.
    Run from an elevated PowerShell prompt, or let the script self-elevate.

.EXAMPLE
    # From PowerShell (elevated):
    .\install.ps1

    # One-liner from a fresh machine (replace with your repo URL):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    irm https://raw.githubusercontent.com/89jobrien/dotfiles/main/install.ps1 | iex

.NOTES
    Requires Windows 10 2004+ or Windows 11 for WSL2.
    Requires internet access.
#>
[CmdletBinding()]
param(
    [switch]$SkipWSL,
    [switch]$SkipPackages,
    [switch]$SkipBootstrap,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

# When invoked via iex (no $PSScriptRoot), clone the repo first
if (-not $ScriptDir) {
    $RepoUrl = 'https://github.com/89jobrien/dotfiles.git'
    $ClonePath = Join-Path $env:USERPROFILE 'dotfiles'
    if (-not (Test-Path $ClonePath)) {
        Write-Host 'Cloning dotfiles...' -ForegroundColor Cyan
        git clone $RepoUrl $ClonePath
    }
    & "$ClonePath\install.ps1" @PSBoundParameters
    exit $LASTEXITCODE
}

& "$ScriptDir\scripts\setup-windows.ps1" `
    -SkipWSL:$SkipWSL `
    -SkipPackages:$SkipPackages `
    -SkipBootstrap:$SkipBootstrap `
    -DryRun:$DryRun

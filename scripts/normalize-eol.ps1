# scripts/normalize-eol.ps1 - Normalizes line endings across tracked text files
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-GitAvailable)) {
    throw "git is required to normalize line endings."
}

$entries = @(Get-UnnormalizedTextEolEntries $repoRoot)
if ($entries.Count -eq 0) {
    Write-Host "All tracked text files are already LF-normalized." -ForegroundColor Green
    return
}

$candidatePaths = @($entries | ForEach-Object { $_.Path })
$indexPaths = @($entries | Where-Object { $_.Index -in @("crlf", "mixed") } | ForEach-Object { $_.Path })
if ($indexPaths.Count -gt 0) {
    $null = Invoke-Git $repoRoot (@("add", "--renormalize", "--") + $indexPaths) -Checked
    Write-Host "Renormalized $($indexPaths.Count) committed CRLF file(s) in index: $($indexPaths -join ', ')" -ForegroundColor Cyan
}

Write-Host "Line ending normalization completed." -ForegroundColor Green

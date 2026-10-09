# scripts/release.ps1 - One-Click Release Pipeline for SwiftDeck
# Delegates to scripts/sign.ps1 for standard digital signing and artifact staging.

[CmdletBinding()]
param(
    [string]$CertificateThumbprint = "E9C72CF5090840A1805296525D56BE680622A7FD",
    [string]$PrimaryTimestamp = "http://timestamp.digicert.com",
    [string]$FallbackTimestamp = "http://time.certum.pl",
    [switch]$SkipSigning,
    [switch]$Publish
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

if ($SkipSigning) {
    if ($Publish) { throw 'Unsigned builds cannot be published.' }
    Write-Host "Running unsigned build..." -ForegroundColor Cyan
    $buildScript = Join-Path $PSScriptRoot "build.ps1"
    & $buildScript -OutputDirectory "dist"
} else {
    $signScript = Join-Path $PSScriptRoot "sign.ps1"
    $signArgs = @{
        CertificateThumbprint = $CertificateThumbprint
        PrimaryTimestamp      = $PrimaryTimestamp
        FallbackTimestamp     = $FallbackTimestamp
    }
    if ($Publish) {
        $signArgs["Publish"] = $true
    }
    & $signScript @signArgs
}


[CmdletBinding()]
param(
    [string]$InstallerPath,
    [string]$CurrentExecutable,
    [switch]$LibraryOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-SwiftDeckUpdateSignatures {
    param($InstallerSignature, $CurrentSignature)
    foreach ($signature in @($InstallerSignature, $CurrentSignature)) {
        if (-not $signature -or $signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or -not $signature.TimeStamperCertificate) {
            throw 'A valid, timestamped Authenticode signature is required for both the installed app and its update.'
        }
    }
    if ($InstallerSignature.SignerCertificate.Thumbprint -cne $CurrentSignature.SignerCertificate.Thumbprint) {
        throw 'Update publisher certificate differs from the installed app. Use a reviewed manual installer for certificate rotation.'
    }
}

if ($LibraryOnly) { return }
try {
    if (-not $InstallerPath -or -not $CurrentExecutable -or -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf) -or -not (Test-Path -LiteralPath $CurrentExecutable -PathType Leaf)) {
        throw 'Update and installed executable paths must both exist.'
    }
    Assert-SwiftDeckUpdateSignatures (Get-AuthenticodeSignature -LiteralPath $InstallerPath) (Get-AuthenticodeSignature -LiteralPath $CurrentExecutable)
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 13
}

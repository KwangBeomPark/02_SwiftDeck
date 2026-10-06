# scripts/publish.ps1 - Automated GitHub Release publishing pipeline for SwiftDeck.
# Run this script to publish official release artifacts to GitHub Releases.

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param(
    [string]$OutputDirectory = "release",
    [switch]$AllowUnsigned,
    [switch]$NoPush,
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\SwiftDeck.ahk"
$version = Get-AppVersion $sourcePath
$tag = "v$version"

foreach ($tool in @("git", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is required to publish."
    }
}

$notesPath = $null
Push-Location -LiteralPath $repoRoot
try {
    $branchQuery = Invoke-Native git @("branch", "--show-current")
    $branch = if ($branchQuery.StdOut.Count -gt 0) { $branchQuery.StdOut[0] } else { "" }
    if ($branchQuery.ExitCode -ne 0 -or $branch -ne "main") {
        throw "Publishing is allowed only from main; current branch is '$branch'."
    }
    $treeDirty = Test-GitWorkingTreeDirty $repoRoot
    if ($null -eq $treeDirty) {
        throw "Could not read the working-tree status."
    }
    if ($treeDirty) {
        throw "Commit or remove working-tree changes before publishing. publish.ps1 never commits automatically."
    }
    $targetCommit = Get-GitHeadCommit $repoRoot
    if (-not $targetCommit) {
        throw "Could not resolve HEAD."
    }

    $null = Invoke-NativeChecked gh @("auth", "status") "GitHub CLI authentication" -Quiet -FailureHint "Run 'gh auth login'."

    # Check for existing releases
    $releaseQuery = Invoke-NativeChecked gh @("release", "list", "--limit", "1000", "--json", "tagName,isDraft") "GitHub release query" -Quiet
    $releases = @()
    $releaseJson = $releaseQuery.StdOut -join "`n"
    if ($releaseJson) {
        $releases = @(ConvertFrom-Json $releaseJson | ForEach-Object { $_ })
    }
    $existingRelease = @($releases | Where-Object { $_.tagName -eq $tag })
    if ($existingRelease.Count -gt 0) {
        if ($existingRelease[0].isDraft) {
            throw "A draft release $tag already exists (probably a failed earlier publish). Review it, then run 'gh release delete $tag --yes' and retry."
        }
        throw "GitHub release $tag already exists. Bump g_appVersion instead of replacing it."
    }

    # Verify remote tag
    $tagQuery = Invoke-NativeChecked git @("ls-remote", "--tags", "origin", "refs/tags/$tag", "refs/tags/$tag^{}") "Remote tag query" -Quiet
    $remoteTagCommit = $null
    foreach ($line in $tagQuery.StdOut) {
        if ($line -match "^([0-9a-f]{40})\s+refs/tags/$([regex]::Escape($tag))(\^\{\})?$") {
            if ($null -eq $remoteTagCommit -or $Matches[2]) {
                $remoteTagCommit = $Matches[1]
            }
        }
    }
    if ($null -ne $remoteTagCommit -and $remoteTagCommit -ne $targetCommit) {
        throw "Tag $tag already exists on origin at $remoteTagCommit, not at HEAD ($targetCommit). Move or delete the tag before publishing."
    }

    $outputRoot = Resolve-RepoPath $repoRoot $OutputDirectory
    $setupExe = Join-Path $outputRoot "SwiftDeck-Setup.v$version.exe"
    $enterpriseSetup = Join-Path $outputRoot "App02_SwiftDeck-Setup_v$version.exe"
    $versionedExe = Join-Path $outputRoot "SwiftDeck.v$version.exe"
    $versionedZip = Join-Path $outputRoot "SwiftDeck.v$version.zip"
    $checksumsPath = Join-Path $outputRoot "SHA256SUMS.txt"
    $manifestPath = Join-Path $outputRoot "build-manifest.json"

    if (-not (Test-Path -LiteralPath $setupExe) -or -not (Test-Path -LiteralPath $versionedExe)) {
        Write-Host "Running build.ps1 to produce release artifacts..." -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot "build.ps1") -OutputDirectory $OutputDirectory
    } else {
        Write-Host "Using existing verified release artifacts in $outputRoot..." -ForegroundColor Cyan
    }

    if (-not $AllowUnsigned) {
        $sig = Get-AuthenticodeSignature -LiteralPath $setupExe
        if ($sig.Status -ne "Valid") {
            throw "Artifact $setupExe is not digitally signed (Status: $($sig.Status)). Run release.ps1 first, or pass -AllowUnsigned for testing."
        }
        Write-Host "Verified Authenticode signature: $($sig.SignerCertificate.Subject)" -ForegroundColor Green
    }

    $uploadFiles = @($setupExe, $enterpriseSetup, $versionedExe, $versionedZip, $checksumsPath, $manifestPath)

    foreach ($f in $uploadFiles) {
        if (-not (Test-Path -LiteralPath $f)) {
            throw "Release artifact missing: $f"
        }
    }

    $releaseTitle = "SwiftDeck v$version"
    $createArgs = @("release", "create", $tag) + $uploadFiles + @("--target", $targetCommit, "--title", $releaseTitle, "--generate-notes")
    if ($Draft) {
        $createArgs += "--draft"
    }

    Write-Host "`nCreating GitHub Release $tag..." -ForegroundColor Cyan
    Invoke-NativeChecked gh $createArgs "Create GitHub Release"

    Write-Host "`n[SUCCESS] GitHub Release $tag published successfully!" -ForegroundColor Green
} finally {
    Pop-Location
}

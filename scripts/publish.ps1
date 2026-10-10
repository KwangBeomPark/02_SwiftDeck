# Publication is explicit and consumes a completed signed set. It never builds.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputDirectory = 'release',
    [switch]$AllowUnsigned,
    [switch]$NoPush,
    [switch]$Draft,
    [switch]$Resume
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ReleaseSafety.ps1')
if ($AllowUnsigned) { throw 'Unsigned official publication is prohibited.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = Get-AppVersion (Join-Path $repoRoot 'src\SwiftDeck.ahk')
$tag = "v$version"
Push-Location -LiteralPath $repoRoot
try {
    $branchQuery = Invoke-Git $repoRoot @('branch', '--show-current') -Checked
    if ($branchQuery.StdOut.Count -ne 1 -or $branchQuery.StdOut[0] -ne 'main') { throw 'Publication requires main.' }
    if ((Test-GitWorkingTreeDirty $repoRoot) -ne $false) { throw 'Commit the reviewed source before building and publishing. This script never commits.' }
    $commit = Get-GitHeadCommit $repoRoot
    if (-not $commit) { throw 'Cannot resolve HEAD.' }
    $outputRoot = Resolve-RepoPath $repoRoot $OutputDirectory
    if ($outputRoot -ne (Join-Path $repoRoot 'release')) { throw 'Publication requires the official repository release directory.' }
    $repository = 'KwangBeomPark/02_SwiftDeck'
    $ghRepository = "github.com/$repository"
    Assert-SuiteOrigin $repoRoot $repository
    $remoteMain = Invoke-Git $repoRoot @('ls-remote', 'origin', 'refs/heads/main') -Checked
    if ($remoteMain.StdOut.Count -ne 1 -or $remoteMain.StdOut[0] -notmatch "^$commit\s+refs/heads/main$") { throw 'Push the reviewed source commit to origin/main before publication. This script never pushes.' }
    $null = Assert-SuiteRelease $outputRoot $version $commit (Get-SuiteSourceDigest $repoRoot) -RequireClean
    $uploadPaths = @(@(Get-SuiteArtifactNames $version) + @('SHA256SUMS.txt', 'build-manifest.json') | ForEach-Object { Join-Path $outputRoot $_ })
    $null = Invoke-NativeChecked gh @('auth', 'status', '--hostname', 'github.com') 'GitHub authentication' -Quiet
    $publicationRequested = $false
    $tagQuery = Invoke-Git $repoRoot @('ls-remote', '--tags', 'origin', "refs/tags/$tag", "refs/tags/$tag^{}") -Checked
    $remoteCommit = $null
    foreach ($line in $tagQuery.StdOut) {
        if ($line -match '^([0-9a-f]{40})\s+(.+)$') {
            if (-not $remoteCommit -or $Matches[2].EndsWith('^{}')) { $remoteCommit = $Matches[1] }
        }
    }
    if ($remoteCommit -and $remoteCommit -ne $commit) { throw 'Existing tag points to another commit. Tags are never moved or deleted.' }
    $remote = Get-SuiteRemoteRelease $repository $tag
    if ($remote) {
        if (-not $remote.draft) { throw "Public release $tag already exists. Bump APP_VERSION instead of replacing it." }
        if (-not $Resume) { throw 'A draft release already exists. Use a new version, or specify -Resume to complete it.' }
        if ($remoteCommit -ne $commit -and -not (-not $remoteCommit -and $remote.draft -and $remote.target_commitish -ceq $commit)) { throw 'Resume requires the verified commit on the existing tag or unpublished draft target.' }
        if ($remote.tag_name -ne $tag) { throw 'Unexpected remote release identity.' }
        $missing = @(Get-SuiteMissingAssets $uploadPaths $remote.assets)
        if ($missing.Count -gt 0) {
            if (-not $PSCmdlet.ShouldProcess($tag, 'Upload only verified missing release assets')) { return }
            $null = Invoke-NativeChecked gh (@('release', 'upload', $tag, '--repo', $ghRepository) + $missing) 'Missing asset upload'
        } else {
            Write-Host 'All assets already match existing draft.'
        }
        $publicationRequested = $true
    } else {
        # Only a successful complete list can establish absence.
        if ($Resume) { throw 'Cannot resume a release that does not exist.' }
        if ($PSCmdlet.ShouldProcess($tag, 'Create release from the verified commit and signed set')) {
            $arguments = @('release', 'create', $tag) + $uploadPaths + @('--repo', $ghRepository, '--target', $commit, '--title', "SwiftDeck v$version", '--generate-notes', '--draft')
            $null = Invoke-NativeChecked gh $arguments 'Release creation'
            $publicationRequested = $true
        }
    }
    if ($publicationRequested) {
        $verifiedRemote = Get-SuiteRemoteRelease $repository $tag
        if (-not $verifiedRemote -or $verifiedRemote.tag_name -ne $tag -or $verifiedRemote.draft -ne $true -or $verifiedRemote.prerelease -ne $false -or @($verifiedRemote.assets).Count -ne $uploadPaths.Count -or @(Get-SuiteMissingAssets $uploadPaths $verifiedRemote.assets).Count -ne 0) { throw 'Published asset set is incomplete. Existing remote files are preserved; resume only this verified set.' }
        Write-Host 'Remote asset digests and sizes match the verified local set.'
        if (-not $Draft) {
            if (-not $PSCmdlet.ShouldProcess($tag, 'Publish the verified draft release')) { return }
            $null = Invoke-NativeChecked gh @('release', 'edit', $tag, '--draft=false', '--latest', '--repo', $ghRepository) 'Publishing verified draft'
            $published = Get-SuiteRemoteRelease $repository $tag
            if (-not $published -or $published.tag_name -ne $tag -or $published.draft -ne $false -or $published.prerelease -ne $false -or @($published.assets).Count -ne $uploadPaths.Count -or @(Get-SuiteMissingAssets $uploadPaths $published.assets).Count -ne 0) { throw 'Public release state or assets could not be verified. Preserve the existing release.' }
            Write-Host "Published and verified: $tag."
        } else {
            Write-Host "Draft release $tag is verified and ready at $commit; publish it when appropriate."
        }
    }
} finally { Pop-Location }

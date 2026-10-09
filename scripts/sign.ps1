# Run in the user's interactive SimplySign signing session.
[CmdletBinding()]
param(
    [string]$CertificateThumbprint = "E9C72CF5090840A1805296525D56BE680622A7FD",
    [string]$PrimaryTimestamp = "http://timestamp.digicert.com",
    [string]$FallbackTimestamp = "http://time.certum.pl",
    [string]$BuildOutputDir = "dist",
    [string]$ReleaseDir = "release",
    [string]$SignToolPath = $env:SIGNTOOL_PATH,
    [switch]$SkipBuild,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ReleaseSafety.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
function Find-SuiteSignTool {
    param([string]$RequestedPath)
    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw 'The specified SignTool path does not exist.'
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    $candidates = @()
    $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $candidates += Join-Path $projectRoot 'tools\signtool\signtool.exe'
    foreach ($sdkRoot in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $sdkRoot) { continue }
        $sdkBin = Join-Path $sdkRoot 'Windows Kits\10\bin'
        $versions = @(Get-ChildItem -LiteralPath $sdkBin -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending)
        foreach ($directory in $versions) {
            $candidates += Join-Path $directory.FullName 'x64\signtool.exe'
        }
        $candidates += Join-Path $sdkBin 'x64\signtool.exe'
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'Provide -SignToolPath, SIGNTOOL_PATH, SignTool on PATH, or install the Windows SDK.'
}
function Invoke-SignBinary {
    param([string]$FilePath, [string]$Description = 'SwiftDeck')
    foreach ($timestamp in @($PrimaryTimestamp, $FallbackTimestamp)) {
        $arguments = @('sign', '/s', 'my', '/sha1', $thumbprint, '/fd', 'sha256', '/tr', $timestamp, '/td', 'sha256', '/d', $Description)
        if ($certificateStore -eq 'LocalMachine') { $arguments += '/sm' }
        $result = Invoke-Native $signtool ($arguments + $FilePath) -MergeStdErr
        if ($result.ExitCode -eq 0) {
            $verified = Assert-SuiteSignature $FilePath
            if ($verified.signerThumbprint -ne $thumbprint) { throw 'Unexpected signing certificate.' }
            return
        }
        Write-Warning "Signing failed with timestamp endpoint $timestamp : $($result.Text)"
    }
    throw "Signing failed: $FilePath"
}
$releasePath = Resolve-RepoPath $projectRoot $ReleaseDir
if ($releasePath -ne (Join-Path $projectRoot 'release')) { throw 'The official output must be the repository release directory.' }
if ((Test-GitWorkingTreeDirty $projectRoot) -ne $false) { throw 'Commit reviewed changes and choose the next version before building an official signed release.' }
$version = Get-AppVersion (Join-Path $projectRoot 'src\SwiftDeck.ahk')
$thumbprint = ConvertTo-CertificateThumbprint $CertificateThumbprint
$certificateStore = 'CurrentUser'
$cert = Get-Item "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
if (-not $cert) {
    $certificateStore = 'LocalMachine'
    $cert = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
}
if (-not $cert -or -not $cert.HasPrivateKey -or $cert.NotAfter -lt (Get-Date)) { throw 'The selected valid signing certificate/private key is unavailable. Open SimplySign in the interactive signing session.' }
$signtool = Find-SuiteSignTool $SignToolPath
$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$isccPaths = @((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'), (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'))
if ($isccCommand) { $isccPaths = @($isccCommand.Source) + $isccPaths }
$iscc = $isccPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup compiler is unavailable.' }
$stagePath = Join-Path $projectRoot ('build\release-stage-' + [guid]::NewGuid().ToString('N'))
Assert-SuiteWorkspacePath $projectRoot $stagePath
Assert-SuiteWorkspacePath $projectRoot $releasePath
New-Item -ItemType Directory -Path $stagePath | Out-Null
try {
    $exe = Join-Path $stagePath "SwiftDeck.v$version.exe"
    if ($SkipBuild) {
        $inputRoot = Resolve-RepoPath $projectRoot $BuildOutputDir
        $inputExe = Join-Path $inputRoot "SwiftDeck.v$version.exe"
        $inputManifest = Get-Content -LiteralPath (Join-Path $inputRoot 'build-provenance.json') -Raw | ConvertFrom-Json
        if ($inputManifest.version -ne $version -or $inputManifest.provenance.testsPassed -ne $true -or $inputManifest.provenance.commit -ne (Get-GitHeadCommit $projectRoot) -or $inputManifest.provenance.sourceDigest -ne (Get-SuiteSourceDigest $projectRoot) -or $inputManifest.executableSha256 -ne (Get-FileHash -LiteralPath $inputExe -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'Existing executable lacks matching successful build provenance. Rebuild without -SkipBuild.' }
        Copy-Item -LiteralPath $inputExe -Destination $exe
        $provenance = $inputManifest.provenance
    } else {
        & (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory $stagePath -ExecutableOnly
        $buildRecord = Get-Content -LiteralPath (Join-Path $stagePath 'build-provenance.json') -Raw | ConvertFrom-Json
        $provenance = $buildRecord.provenance
    }
    if ($provenance.testsPassed -ne $true -or $provenance.commit -ne (Get-GitHeadCommit $projectRoot) -or $provenance.sourceDigest -ne (Get-SuiteSourceDigest $projectRoot)) { throw 'Build provenance changed before packaging.' }
    Invoke-SignBinary $exe
    $null = Invoke-NativeChecked $iscc @("/DMyAppVersion=$version", "/DMyAppExeSource=$exe", "/O$stagePath", (Join-Path $projectRoot 'installer\setup.iss')) 'Installer compilation'
    $setup = Join-Path $stagePath "App02_SwiftDeck_Setup_v$version.exe"
    Invoke-SignBinary $setup 'SwiftDeck Setup'
    Remove-Item -LiteralPath $exe
    Write-SuiteReleaseMetadata $stagePath $version $provenance -Signed
    Remove-Item -LiteralPath (Join-Path $stagePath 'build-provenance.json')
    $validation = { param($directory) Assert-SuiteRelease $directory $version (Get-GitHeadCommit $projectRoot) (Get-SuiteSourceDigest $projectRoot) }.GetNewClosure()
    Move-SuiteRelease $projectRoot $stagePath $releasePath $validation
} catch {
    Write-Warning "Release failed; diagnostic stage is retained: $stagePath. Review the error for restoration status if promotion had started."
    throw
}
Write-Host "Verified signed release staged at $releasePath"
if ($Publish) { & (Join-Path $PSScriptRoot 'publish.ps1') -OutputDirectory $ReleaseDir }

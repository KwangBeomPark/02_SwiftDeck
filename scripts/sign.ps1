# SwiftDeck One-Click Digital Signing & Release Pipeline Script
# Run in an ELEVATED (Administrator) PowerShell window:
# powershell -ExecutionPolicy Bypass -File scripts\sign.ps1

[CmdletBinding()]
param(
    [string]$CertificateThumbprint = "E9C72CF5090840A1805296525D56BE680622A7FD",
    [string]$PrimaryTimestamp = "http://timestamp.digicert.com",
    [string]$FallbackTimestamp = "http://time.certum.pl",
    [string]$BuildOutputDir = "dist",
    [string]$ReleaseDir = "release",
    [switch]$SkipBuild,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " SwiftDeck (App02) Digital Sign Pipeline " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Administrator Check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "PowerShell is not running as Administrator. Smart Card / SimplySign token private key access may fail."
    Write-Warning "If signing fails, please right-click PowerShell -> 'Run as Administrator'."
}

# 2. Ensure Smart Card Services are active
Write-Host "`n[1/7] Ensuring Smart Card services are active..." -ForegroundColor Yellow
Start-Service SCardSvr, CertPropSvc, ScDeviceEnum -ErrorAction SilentlyContinue
$scardStatus = Get-Service -Name SCardSvr -ErrorAction SilentlyContinue
if ($null -ne $scardStatus) {
    Write-Host "  SCardSvr service status: $($scardStatus.Status)" -ForegroundColor Gray
}

# 3. Locate Certificate
Write-Host "[2/7] Locating code signing certificate..." -ForegroundColor Yellow
$thumbprint = ($CertificateThumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
$cert = Get-Item "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
if (-not $cert) {
    $cert = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
}

# Auto-match code signing certificate if specific thumbprint not matched
if (-not $cert) {
    $codeCerts = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.NotAfter -gt (Get-Date) })
    if ($codeCerts.Count -gt 0) {
        $cert = $codeCerts[0]
        $thumbprint = $cert.Thumbprint
        Write-Host "  Auto-matched code signing certificate: $($cert.Subject)" -ForegroundColor Gray
    }
}

if (-not $cert) {
    throw "Code signing certificate [$thumbprint] not found in Cert: store. Please ensure SimplySign Desktop or smart card reader is logged in."
}

if ($cert.NotAfter -lt (Get-Date)) {
    throw "Code signing certificate [$thumbprint] has expired on $($cert.NotAfter.ToString('yyyy-MM-dd'))."
}
Write-Host "  Certificate found: $($cert.Subject)" -ForegroundColor Green
Write-Host "  Thumbprint: $thumbprint" -ForegroundColor Gray
Write-Host "  Valid until: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

# 4. Locate Tools (signtool.exe and iscc.exe)
Write-Host "[3/7] Locating signing and installer tools..." -ForegroundColor Yellow
$signtoolPaths = @(
    "C:\Dev\GitHub\06_Stepwise\release\build\signtool\signtool.exe",
    "C:\Users\parkk\.codex\worktrees\antigravity-aggregation-review\04_DataRefinery\release\build\windows-sdk-buildtools-10.0.28000.2705\package\bin\10.0.28000.0\x64\signtool.exe",
    (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x64\signtool.exe"),
    (Join-Path $env:ProgramFiles "Windows Kits\10\bin\x64\signtool.exe"),
    (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
)
$signtool = $signtoolPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $signtool) {
    throw "signtool.exe not found. Please verify Windows SDK or Stepwise buildtools path."
}
Write-Host "  SignTool: $signtool" -ForegroundColor Green

$isccPaths = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\ProgramData\Chocolatey\bin\ISCC.exe",
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
)
$iscc = $isccPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    throw "Inno Setup compiler (ISCC.exe) not found. Please install Inno Setup 6."
}
Write-Host "  ISCC: $iscc" -ForegroundColor Green

# Read Version from src/SwiftDeck.ahk
$ahkPath = Join-Path $projectRoot "src\SwiftDeck.ahk"
$ahkContent = Get-Content -LiteralPath $ahkPath -Raw
if ($ahkContent -notmatch 'global g_appVersion\s*:=\s*"([^"]+)"') {
    throw "Could not find g_appVersion in src/SwiftDeck.ahk"
}
$version = $Matches[1]
Write-Host "  Target Version: v$version" -ForegroundColor Green

# 5. Build Stage in dist/
$distPath = Join-Path $projectRoot $BuildOutputDir
$distExe = Join-Path $distPath "SwiftDeck.v$version.exe"
$distZip = Join-Path $distPath "SwiftDeck.v$version.zip"
$distSetup = Join-Path $distPath "SwiftDeck-Setup.v$version.exe"
$distEnterpriseSetup = Join-Path $distPath "App02_SwiftDeck-Setup_v$version.exe"

if (-not $SkipBuild -or -not (Test-Path -LiteralPath $distExe)) {
    Write-Host "`n[4/7] Running clean build to $BuildOutputDir..." -ForegroundColor Yellow
    $buildScript = Join-Path $PSScriptRoot "build.ps1"
    & $buildScript -OutputDirectory $BuildOutputDir -SkipSigning -SkipTests:$false
    if ($LASTEXITCODE -ne 0) {
        throw "build.ps1 failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Host "`n[4/7] Skipping initial build (-SkipBuild specified and binary exists)" -ForegroundColor Yellow
}

# Helper function to sign a binary with fallback timestamp
function Invoke-SignBinary {
    param(
        [string]$FilePath,
        [string]$Description = "SwiftDeck"
    )

    $fileName = Split-Path -Leaf $FilePath
    Write-Host "  Signing $fileName..." -ForegroundColor Cyan

    $signArgs = @(
        "sign",
        "/debug",
        "/s", "my",
        "/sha1", $thumbprint,
        "/fd", "sha256",
        "/tr", $PrimaryTimestamp,
        "/td", "sha256",
        "/d", $Description,
        $FilePath
    )

    & $signtool $signArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Primary timestamp ($PrimaryTimestamp) failed, retrying with fallback ($FallbackTimestamp)..."
        $signArgs[7] = $FallbackTimestamp
        & $signtool $signArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to sign $fileName with signtool (Exit code: $LASTEXITCODE)"
        }
    }
}

# 6. Digital Signing & Installer Packaging
Write-Host "`n[5/7] Signing binaries and generating installer..." -ForegroundColor Yellow

# Step 6a: Sign main executable
Invoke-SignBinary -FilePath $distExe -Description "SwiftDeck"

# Step 6b: Refresh portable ZIP package with signed executable
Write-Host "  Repackaging portable ZIP with signed executable..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $distZip) { Remove-Item -LiteralPath $distZip -Force }
Compress-Archive -LiteralPath $distExe -DestinationPath $distZip -Force

# Step 6c: Compile Inno Setup installer using the signed executable
Write-Host "  Compiling Inno Setup installer..." -ForegroundColor Cyan
$setupIssPath = Join-Path $projectRoot "installer\setup.iss"
$isccArgs = @(
    "/DMyAppVersion=$version",
    "/DMyAppExeSource=$distExe",
    "/O$distPath",
    $setupIssPath
)
$compileProcess = Start-Process -FilePath $iscc -ArgumentList $isccArgs -Wait -PassThru -NoNewWindow
if ($compileProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $distSetup)) {
    throw "Inno Setup compilation failed with exit code $($compileProcess.ExitCode)"
}

# Step 6d: Generate enterprise alias installer
Copy-Item -LiteralPath $distSetup -Destination $distEnterpriseSetup -Force

# Step 6e: Sign installers
Invoke-SignBinary -FilePath $distSetup -Description "SwiftDeck Setup"
Invoke-SignBinary -FilePath $distEnterpriseSetup -Description "App02 SwiftDeck Setup"

# Step 6f: Verify all signatures
Write-Host "`n  Verifying Authenticode signatures..." -ForegroundColor Yellow
$signedBinaries = @($distExe, $distSetup, $distEnterpriseSetup)
foreach ($bin in $signedBinaries) {
    $sig = Get-AuthenticodeSignature -LiteralPath $bin
    if ($sig.Status -ne "Valid") {
        throw "Signature verification failed for $(Split-Path -Leaf $bin): $($sig.StatusMessage)"
    }
    Write-Host "  [VERIFIED] $(Split-Path -Leaf $bin) | Timestamp: $($sig.TimeStamperCertificate.Subject)" -ForegroundColor Green
}

# 7. Clean and Stage to release/ Directory
Write-Host "`n[6/7] Staging artifacts to $ReleaseDir..." -ForegroundColor Yellow
$releasePath = Join-Path $projectRoot $ReleaseDir
if (-not (Test-Path -LiteralPath $releasePath)) {
    New-Item -ItemType Directory -Path $releasePath -Force | Out-Null
} else {
    # Clean previous release artifacts completely
    Get-ChildItem -LiteralPath $releasePath -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { }
    }
}

# Copy the 4 essential artifacts to release/
$essentialArtifacts = @($distEnterpriseSetup, $distSetup, $distExe, $distZip)
$stagedArtifactPaths = @()
foreach ($src in $essentialArtifacts) {
    $dst = Join-Path $releasePath (Split-Path -Leaf $src)
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $stagedArtifactPaths += $dst
}

# Generate SHA256SUMS.txt in release/
$checksumLines = @()
$artifactInfo = foreach ($path in $stagedArtifactPaths) {
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLines += "$hash  $($item.Name)"
    [pscustomobject]@{
        name   = $item.Name
        bytes  = $item.Length
        sha256 = $hash
    }
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
$checksumPath = Join-Path $releasePath "SHA256SUMS.txt"
[IO.File]::WriteAllText($checksumPath, (($checksumLines -join "`n") + "`n"), $utf8NoBom)

# Generate build-manifest.json in release/
$manifest = [ordered]@{
    application = "SwiftDeck"
    version     = $version
    fileVersion = "$version.0"
    builtAtUtc  = [DateTime]::UtcNow.ToString("o")
    artifacts   = @($artifactInfo)
}
$manifestPath = Join-Path $releasePath "build-manifest.json"
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 5) + "`n"), $utf8NoBom)

# Also update dist/ manifests for parity
Copy-Item -LiteralPath $checksumPath -Destination (Join-Path $distPath "SHA256SUMS.txt") -Force
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $distPath "build-manifest.json") -Force

Write-Host "  Artifacts successfully staged to $ReleaseDir:" -ForegroundColor Green
Get-ChildItem -LiteralPath $releasePath | Format-Table Name, Length, LastWriteTime -AutoSize

# 8. GitHub Release Upload (Optional)
if ($Publish) {
    Write-Host "`n[7/7] Publishing to GitHub Releases..." -ForegroundColor Yellow
    $tag = "v$version"
    $ghCli = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghCli) {
        Write-Warning "GitHub CLI (gh) not found. Skipping GitHub Release upload."
    } else {
        $uploadFiles = @($stagedArtifactPaths) + @($checksumPath, $manifestPath)
        $releaseList = & gh release list --limit 50 2>$null
        $releaseExists = ($releaseList -match "\b$([regex]::Escape($tag))\b")

        if (-not $releaseExists) {
            Write-Host "  Creating release $tag..." -ForegroundColor Cyan
            & gh release create $tag @uploadFiles --title "v$version - SwiftDeck Release" --generate-notes
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Successfully created GitHub Release $tag!" -ForegroundColor Green
            } else {
                Write-Warning "  Failed to create GitHub Release $tag. Check gh auth status."
            }
        } else {
            Write-Host "  Uploading assets to release $tag..." -ForegroundColor Cyan
            & gh release upload $tag @uploadFiles --clobber
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Successfully uploaded assets to GitHub Release $tag!" -ForegroundColor Green
            } else {
                Write-Warning "  Failed to upload assets. Check gh auth status."
            }
        }
    }
} else {
    Write-Host "`n[7/7] GitHub Release publish skipped (use -Publish to upload)." -ForegroundColor Gray
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host " Signing & Release Staging Completed!   " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Release Artifacts in '$ReleaseDir':"
Get-Content -LiteralPath $checksumPath | ForEach-Object { Write-Host "  $_" }

param(
    [switch]$Publish,

    # Skips the test gate. For getting an emergency build out when a test is
    # itself broken — not for ignoring a real failure.
    [switch]$SkipTests,

    # Authenticode signing. Import the certificate into your personal
    # certificate store once, then pass its thumbprint here:
    #
    #   .\scripts\build.ps1 -CertificateThumbprint AB12...CD
    #
    # Deliberately thumbprint-only: a .pfx path would mean handling its password,
    # and the store keeps the private key out of the build command line and out
    # of shell history. Without this the build is unsigned, exactly as before.
    [string]$CertificateThumbprint,

    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

# SwiftDeck build, packaging, and optional GitHub Release publishing pipeline.
# Publishing is opt-in so a local build can never modify GitHub by accident.
$ErrorActionPreference = "Stop"

# Runs every tests\*Tests.ahk and fails the build if any of them does. Each
# script exits non-zero on a failed assertion, and a load-time error leaves the
# process sitting on a modal dialog — which is why there is a timeout rather
# than an open-ended wait.
function Invoke-TestSuite {
    param(
        [string]$TestsDir,
        [string]$Interpreter,
        [int]$TimeoutMs = 120000
    )

    $scripts = @(Get-ChildItem -LiteralPath $TestsDir -Filter "*Tests.ahk" -File | Sort-Object Name)
    if ($scripts.Count -eq 0) {
        throw "No test scripts found in $TestsDir. Expected files named *Tests.ahk."
    }

    Write-Host "Running $($scripts.Count) test script(s)..."
    $failed = @()
    foreach ($script in $scripts) {
        # Driven through .NET rather than Start-Process for two reasons. Output
        # has to be redirected at all — AutoHotkey is a GUI-subsystem program
        # with no console, so the harness writing its result to stdout blocks
        # forever otherwise, and a failed assertion looks like a hang instead of
        # naming itself. And Start-Process -PassThru does not reliably surface
        # ExitCode once output is redirected, which made passing tests read as
        # failures.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Interpreter
        $psi.Arguments = "`"$($script.FullName)`""
        $psi.WorkingDirectory = $TestsDir
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        # Read asynchronously, or a script that fills the pipe buffer deadlocks.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch { }
            Write-Host ("  {0,-28} TIMED OUT" -f $script.Name)
            $failed += "$($script.Name) (timed out; a load error may be showing a dialog)"
            continue
        }

        $output = (($stdoutTask.Result + $stderrTask.Result) -replace "`r", "").Trim()
        if ($proc.ExitCode -ne 0) {
            Write-Host ("  {0,-28} FAILED" -f $script.Name)
            foreach ($line in ($output -split "`n")) {
                if ($line.Trim()) { Write-Host "      $line" }
            }
            $detail = if ($output) { $output -replace "`n", " / " } else { "exit $($proc.ExitCode)" }
            $failed += "$($script.Name): $detail"
        } else {
            Write-Host ("  {0,-28} ok" -f $script.Name)
        }
    }

    if ($failed.Count -gt 0) {
        throw "Tests failed, build stopped:`n  - " + ($failed -join "`n  - ")
    }
}

function Get-SigningCertificate {
    param([string]$Thumbprint)

    $normalized = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($normalized.Length -eq 0) {
        throw "The certificate thumbprint contains no hexadecimal characters."
    }

    foreach ($store in @("Cert:\CurrentUser\My", "Cert:\LocalMachine\My")) {
        $match = Get-ChildItem -Path $store -CodeSigningCert -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $normalized }
        if ($match) {
            return @($match)[0]
        }
    }

    throw ("No code-signing certificate with thumbprint $normalized was found in " +
        "Cert:\CurrentUser\My or Cert:\LocalMachine\My. Import the certificate first, " +
        "then run: Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert")
}

function Invoke-ArtifactSigning {
    param(
        [string[]]$Paths,
        $Certificate,
        [string]$TimestampUrl
    )

    foreach ($path in $Paths) {
        # Timestamping is what lets the signature stay valid after the
        # certificate itself expires, so a failure here is fatal, not a warning.
        $result = Set-AuthenticodeSignature -FilePath $path -Certificate $Certificate `
            -HashAlgorithm SHA256 -TimestampServer $TimestampUrl
        if ($result.Status -ne "Valid") {
            throw "Signing failed for $path : $($result.Status) - $($result.StatusMessage)"
        }
        Write-Host ("  signed: {0}" -f (Split-Path $path -Leaf))
    }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location $repoRoot
try {
    $ahkPath = Join-Path $repoRoot "src\SwiftDeck.ahk"
    if (-not (Test-Path -LiteralPath $ahkPath)) {
        throw "Could not find src/SwiftDeck.ahk"
    }

    $ahkContent = Get-Content -LiteralPath $ahkPath -Raw
    if ($ahkContent -notmatch 'global g_appVersion\s*:=\s*"([^"]+)"') {
        throw "Could not find g_appVersion in the script."
    }
    $version = $Matches[1]
    if ($version -notmatch '^\d+\.\d+\.\d+$') {
        throw "g_appVersion must use X.Y.Z format."
    }
    if ($ahkContent -notmatch ';@Ahk2Exe-SetVersion\s+(\d+\.\d+\.\d+\.\d+)') {
        throw "Could not find the Ahk2Exe file version directive."
    }
    $fileVersion = $Matches[1]
    if ($fileVersion -ne "$version.0") {
        throw "g_appVersion ($version) and file version ($fileVersion) do not match."
    }

    $compilerPath = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
    $baseAhk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    $iconPath = Join-Path $repoRoot "assets\SwiftDeck.ico"
    foreach ($requiredPath in @($compilerPath, $baseAhk, $iconPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required build dependency was not found: $requiredPath"
        }
    }

    # Resolved here, with the other dependencies, so an unusable thumbprint stops
    # the run before any existing release artifact is deleted or rebuilt.
    $signingCertificate = $null
    if ($CertificateThumbprint) {
        $signingCertificate = Get-SigningCertificate -Thumbprint $CertificateThumbprint
        Write-Host ("Signing certificate: {0}" -f $signingCertificate.Subject)
        Write-Host ("  expires: {0:yyyy-MM-dd}" -f $signingCertificate.NotAfter)
        if ($signingCertificate.NotAfter -lt (Get-Date)) {
            throw "That code-signing certificate expired on $($signingCertificate.NotAfter.ToString('yyyy-MM-dd'))."
        }
    }

    # Before anything is deleted or built: a failing test should stop the run
    # while the previous release artifacts are still intact.
    if ($SkipTests) {
        Write-Warning "Test gate skipped (-SkipTests)."
    } else {
        Invoke-TestSuite -TestsDir (Join-Path $repoRoot "tests") -Interpreter $baseAhk
    }

    $releaseDir = Join-Path $repoRoot "release"
    $distDir = Join-Path $repoRoot "dist"
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null

    # The version-stamped .exe is the asset humans download from the Releases page.
    # SwiftDeck.exe carries the identical bytes under the fixed name that updaters
    # in v1.3.1 and earlier require, so auto-update keeps working across this change.
    $versionedName = "SwiftDeck.v$version"
    $releaseExe = Join-Path $releaseDir "$versionedName.exe"
    $releaseZip = Join-Path $releaseDir "$versionedName.zip"
    $compatExe = Join-Path $releaseDir "SwiftDeck.exe"
    $releaseManifest = Join-Path $releaseDir "SwiftDeck.update.ini"
    $localVersionedExe = Join-Path $distDir "$versionedName.exe"
    # SwiftDeck.zip was the pre-v1.3.2 archive name and is no longer produced;
    # clearing it keeps release/ from mixing versions when it is uploaded.
    $retiredOutputs = @((Join-Path $releaseDir "SwiftDeck.zip"))
    foreach ($ownedOutput in @($releaseExe, $releaseZip, $compatExe, $releaseManifest, $localVersionedExe) + $retiredOutputs) {
        if (Test-Path -LiteralPath $ownedOutput) {
            Remove-Item -LiteralPath $ownedOutput -Force
        }
    }

    Write-Host "Building SwiftDeck v$version..."
    $compile = Start-Process -FilePath $compilerPath -ArgumentList @(
        "/in", "`"$ahkPath`"",
        "/out", "`"$releaseExe`"",
        "/icon", "`"$iconPath`"",
        "/base", "`"$baseAhk`""
    ) -Wait -PassThru
    if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $releaseExe)) {
        throw "Ahk2Exe compilation failed with exit code $($compile.ExitCode)."
    }

    # Order matters. Signing rewrites the executable, so it has to happen before
    # the copies are taken and before the SHA-256 goes into the manifest —
    # otherwise the updater would verify a digest of the unsigned bytes and
    # reject every download.
    if ($signingCertificate) {
        Write-Host "Signing $versionedName.exe..."
        Invoke-ArtifactSigning -Paths @($releaseExe) -Certificate $signingCertificate -TimestampUrl $TimestampUrl
    }
    elseif ($Publish) {
        Write-Warning "Publishing an UNSIGNED release. SmartScreen will warn users on first run."
    }

    Compress-Archive -LiteralPath $releaseExe -DestinationPath $releaseZip -CompressionLevel Optimal
    Copy-Item -LiteralPath $releaseExe -Destination $compatExe -Force
    Copy-Item -LiteralPath $releaseExe -Destination $localVersionedExe -Force

    $releaseHash = (Get-FileHash -LiteralPath $releaseExe -Algorithm SHA256).Hash.ToUpperInvariant()
    $releaseSize = (Get-Item -LiteralPath $releaseExe).Length
    $manifestLines = @(
        "[Release]",
        "Version=$version",
        "Asset=SwiftDeck.exe",
        "AssetVersioned=$versionedName.exe",
        "Sha256=$releaseHash",
        "Size=$releaseSize"
    )
    Set-Content -LiteralPath $releaseManifest -Value $manifestLines -Encoding utf8

    # Drop version-stamped artifacts left behind by earlier builds so the release
    # folder only ever holds the assets for the version just built.
    Get-ChildItem -LiteralPath $releaseDir -File |
        Where-Object {
            $_.Name -match '^SwiftDeck\.v\d+\.\d+\.\d+\.(exe|zip)$' -and
            $_.Name -ne "$versionedName.exe" -and $_.Name -ne "$versionedName.zip"
        } |
        Remove-Item -Force

    # The manifest advertises one digest for both executables, and the updater
    # falls back from the versioned name to SwiftDeck.exe. If those two ever
    # differ the fallback would fail SHA-256 verification, so assert it here
    # rather than discovering it from a user's failed update.
    $compatHash = (Get-FileHash -LiteralPath $compatExe -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($compatHash -ne $releaseHash) {
        throw "SwiftDeck.exe and $versionedName.exe differ; the manifest digest would only match one of them."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $releaseExe
    $compatSignature = Get-AuthenticodeSignature -LiteralPath $compatExe
    if ($signature.Status -ne $compatSignature.Status) {
        throw "Signature state differs between the two executables: $($signature.Status) vs $($compatSignature.Status)."
    }

    Write-Host "Build completed:"
    Get-Item -LiteralPath $releaseExe, $releaseZip, $compatExe, $releaseManifest, $localVersionedExe |
        Select-Object FullName, Length
    Write-Host "SHA256: $releaseHash"
    if ($signature.Status -eq "Valid") {
        Write-Host ("Signature: Valid - {0}" -f $signature.SignerCertificate.Subject)
    } else {
        Write-Host "Signature: $($signature.Status) (unsigned build)"
    }

    if ($Publish) {
        Write-Host "Publishing GitHub Release v$version..."
        & gh auth status | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI is not authenticated."
        }

        & gh release view "v$version" *> $null
        if ($LASTEXITCODE -eq 0) {
            throw "Release v$version already exists. Published releases are never replaced."
        }

        $gitStatus = & git status --porcelain
        if ($gitStatus) {
            throw "The Git worktree must be clean before publishing a release."
        }
        & git fetch origin main | Out-Null
        $localHead = (& git rev-parse HEAD).Trim()
        $remoteHead = (& git rev-parse origin/main).Trim()
        if ($localHead -ne $remoteHead) {
            throw "Local main and origin/main must match before publishing."
        }

        & gh release create "v$version" $releaseExe $releaseZip $compatExe $releaseManifest `
            --draft --target main --title "SwiftDeck v$version" --generate-notes
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the draft GitHub Release."
        }

        & gh release edit "v$version" --draft=false --latest
        if ($LASTEXITCODE -ne 0) {
            throw "Could not publish GitHub Release v$version."
        }
        Write-Host "Published GitHub Release v$version."
    }
} finally {
    Pop-Location
}

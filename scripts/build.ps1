[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$AutoHotkeyPath = $env:AUTOHOTKEY_EXE_PATH,
    [string]$CompilerPath = $env:AHK2EXE_PATH,

    # Skips the test gate. For getting an emergency build out when a test is
    # itself broken -- not for ignoring a real failure.
    [switch]$SkipTests,

    # Authenticode signing. Import the certificate into your personal
    # certificate store once, then pass its thumbprint here:
    #
    #   .\scripts\build.ps1 -CertificateThumbprint AB12...CD
    [string]$CertificateThumbprint,

    [string]$TimestampUrl = "http://time.certum.pl",

    [switch]$Publish,
    [switch]$ExecutableOnly
)

# SwiftDeck build, packaging, and optional GitHub Release publishing pipeline.
# Publishing is opt-in so a local build can never modify GitHub by accident.
#
# Keep this file pure ASCII. It has no BOM, so Windows PowerShell 5.1 reads it in
# the system ANSI codepage: a UTF-8 em dash arrives as bytes that end in a smart
# closing quote, which inside a string literal terminates it early and stops the
# whole script from parsing. Measured -- one em dash in a release-notes string
# made build.ps1 fail to parse in its entirety.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot "ReleaseSafety.ps1")
$buildRepoRoot = Split-Path -Parent $PSScriptRoot
$buildOutput = Resolve-RepoPath $buildRepoRoot $OutputDirectory
Assert-SuiteWorkspacePath $buildRepoRoot $buildOutput
$allowedOutput = $false
foreach ($folder in @('build', 'dist', 'out')) {
    $allowedRoot = Join-Path $buildRepoRoot $folder
    if ($buildOutput -eq $allowedRoot -or $buildOutput.StartsWith(($allowedRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) { $allowedOutput = $true }
}
if (-not $allowedOutput) { throw 'Local build output must be inside build, dist or out.' }
$officialRoot = Join-Path $buildRepoRoot 'release'
if ($buildOutput -eq $officialRoot -or $buildOutput.StartsWith(($officialRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'build.ps1 cannot write official release files. Use sign.ps1; unsigned builds belong in dist/build.'
}
if ($Publish) { throw 'Use publish.ps1 explicitly after a signed, verified release. build.ps1 never publishes.' }
if ($ExecutableOnly -and $CertificateThumbprint) { throw 'Executable-only builds are unsigned input for sign.ps1.' }

# Runs every tests\*Tests.ahk and fails the build if any of them does. Each
# script exits non-zero on a failed assertion, and a load-time error leaves the
# process sitting on a modal dialog -- which is why there is a timeout rather
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
        # has to be redirected at all -- AutoHotkey is a GUI-subsystem program
        # with no console, so the harness writing its result to stdout blocks
        # forever otherwise, and a failed assertion looks like a hang instead of
        # naming itself. And Start-Process -PassThru does not reliably surface
        # ExitCode once output is redirected, which made passing tests read as
        # failures.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Interpreter
        # /ErrorStdOut sends a load-time error (a syntax error in the test or in
        # anything it includes) to stdout instead of a modal dialog. Without it
        # such a script just sits on the dialog until the timeout, reporting a
        # hang rather than the line number.
        $psi.Arguments = "/ErrorStdOut `"$($script.FullName)`""
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
        } elseif ($output -notmatch '(?m)^ok\s+\S') {
            # Exit code 0 alone is not proof that anything ran. A script that
            # returns early, or ends without reaching its assertions, exits 0 and
            # would be reported as passing. Every suite ends by printing
            # "ok <name>", so require that line as the actual pass signal.
            Write-Host ("  {0,-28} NO RESULT" -f $script.Name)
            $failed += "$($script.Name): exited 0 without reporting a result (expected an 'ok <suite>' line)"
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

function Find-SignTool {
    param([string]$ConfiguredPath = "")

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return Resolve-ExistingFile $ConfiguredPath $ConfiguredPath "signtool.exe"
    }
    $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -ne $onPath) {
        return $onPath.Source
    }
    $localSignTool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\signtool\signtool.exe'
    if (Test-Path -LiteralPath $localSignTool -PathType Leaf) { return $localSignTool }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        return $null
    }
    $kitsRoot = Join-Path $programFilesX86 "Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitsRoot)) {
        return $null
    }
    $versionDirs = @(Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' } |
        Sort-Object { [version]$_.Name } -Descending)
    foreach ($dir in $versionDirs) {
        $candidate = Join-Path $dir.FullName "x64\signtool.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    $legacy = Join-Path $kitsRoot "x64\signtool.exe"
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        return $legacy
    }
    return $null
}

function Invoke-ArtifactSigning {
    param(
        [string[]]$Paths,
        $Certificate,
        [string]$Thumbprint = "",
        [string]$TimestampUrl = "http://time.certum.pl"
    )

    $signtool = Find-SignTool
    foreach ($path in $Paths) {
        if ($signtool -and $Thumbprint) {
            $signArgs = @(
                "sign",
                "/debug",
                "/s", "my",
                "/sha1", $Thumbprint,
                "/fd", "sha256",
                "/tr", $TimestampUrl,
                "/td", "sha256",
                "/d", "SwiftDeck"
            )
            $signArgs += $path
            & $signtool $signArgs
            if ($LASTEXITCODE -ne 0) {
                throw "signtool signing failed for $path with exit code $LASTEXITCODE."
            }
        } elseif ($Certificate) {
            $result = Set-AuthenticodeSignature -FilePath $path -Certificate $Certificate `
                -HashAlgorithm SHA256 -TimestampServer $TimestampUrl
            if ($result.Status -ne "Valid") {
                throw "Signing failed for $path : $($result.Status) - $($result.StatusMessage)"
            }
        } else {
            throw "Neither signtool/thumbprint nor certificate object available for signing $path."
        }
        Write-Host ("  signed: {0}" -f (Split-Path $path -Leaf))
    }
}

function Find-InnoSetupCompiler {
    $onPath = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($null -ne $onPath) {
        return $onPath.Source
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        "C:\ProgramData\Chocolatey\bin\ISCC.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            return $cand
        }
    }
    return $null
}

function Resolve-ExistingFile {
    param([string]$ConfiguredPath, [string[]]$CandidatePaths, [string]$Description)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
        return $ConfiguredPath
    }
    foreach ($cand in $CandidatePaths) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            return $cand
        }
    }
    throw "Required build dependency was not found ($Description): $ConfiguredPath"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
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

$compilerCandidates = @(
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\Compiler\Ahk2Exe.exe")
)
$ahkCandidates = @(
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey64.exe")
)

$compilerPath = Resolve-ExistingFile $CompilerPath $compilerCandidates "Ahk2Exe compiler"
$baseAhk = Resolve-ExistingFile $AutoHotkeyPath $ahkCandidates "AutoHotkey v2 runtime"
$iconPath = Join-Path $repoRoot "assets\SwiftDeck.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Required build dependency was not found: $iconPath"
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
    $null = Invoke-NativeChecked powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'static-check.ps1')) 'Static checks'
    foreach ($test in @('Test-ReleaseSafety.ps1', 'Test-SignToolDiscovery.ps1', 'Test-UpdateInstallerSignature.ps1')) {
        $null = Invoke-NativeChecked powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoRoot "tests\$test")) $test
    }
    $null = Invoke-NativeChecked powershell.exe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'test_user_data_backup.ps1')) 'User data backup tests'
}
$provenance = [ordered]@{ commit = Get-GitHeadCommit $repoRoot; workingTreeDirty = Test-GitWorkingTreeDirty $repoRoot; sourceDigest = Get-SuiteSourceDigest $repoRoot; testsPassed = -not [bool]$SkipTests; testGate = 'AHK regression suites + static checks + release safety/discovery'; testedAtUtc = [DateTime]::UtcNow.ToString('o') }

$targetOutputDir = Resolve-RepoPath $repoRoot $OutputDirectory
New-Item -ItemType Directory -Path $targetOutputDir -Force | Out-Null

$versionedName = "SwiftDeck.v$version"
$localVersionedExe = Join-Path $targetOutputDir "$versionedName.exe"
$versionedZip = Join-Path $targetOutputDir "$versionedName.zip"
$setupExe = Join-Path $targetOutputDir "SwiftDeck-Setup.v$version.exe"
$enterpriseSetup = Join-Path $targetOutputDir "App02_SwiftDeck_Setup_v$version.exe"
$releaseChecksums = Join-Path $targetOutputDir "SHA256SUMS.txt"
$manifestPath = Join-Path $targetOutputDir "build-manifest.json"

# Clean previous build artifacts in target output directory
foreach ($ownedOutput in @($localVersionedExe, $versionedZip, $setupExe, $enterpriseSetup, $releaseChecksums, $manifestPath)) {
    if (Test-Path -LiteralPath $ownedOutput) {
        Remove-Item -LiteralPath $ownedOutput -Force
    }
}

Write-Host "[1/4] Building SwiftDeck v$version with Ahk2Exe..."
$compile = Start-Process -FilePath $compilerPath -ArgumentList @(
    "/in", "`"$ahkPath`"",
    "/out", "`"$localVersionedExe`"",
    "/icon", "`"$iconPath`"",
    "/base", "`"$baseAhk`""
) -Wait -PassThru -WindowStyle Hidden
if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $localVersionedExe)) {
    throw "Ahk2Exe compilation failed with exit code $($compile.ExitCode)."
}
if ($provenance.sourceDigest -ne (Get-SuiteSourceDigest $repoRoot) -or $provenance.commit -ne (Get-GitHeadCommit $repoRoot)) { throw 'Sources changed during the build. Rebuild before signing.' }
$buildRecord = [ordered]@{ version = $version; executableSha256 = (Get-FileHash -LiteralPath $localVersionedExe -Algorithm SHA256).Hash.ToLowerInvariant(); provenance = $provenance }
[IO.File]::WriteAllText((Join-Path $targetOutputDir 'build-provenance.json'), (($buildRecord | ConvertTo-Json -Depth 5) + "`n"), [Text.UTF8Encoding]::new($false))
if ($ExecutableOnly) { Write-Host "Executable built for signing: $localVersionedExe"; return }

    if ($CertificateThumbprint) {
        Write-Host "Signing $versionedName.exe..."
        Invoke-ArtifactSigning -Paths @($localVersionedExe) -Certificate $signingCertificate -Thumbprint $CertificateThumbprint -TimestampUrl $TimestampUrl
    } else {
        Write-Host "  (Executable is unsigned; run release.ps1 to build and sign with Certum/SimplySign)" -ForegroundColor Yellow
    }

    Write-Host "[2/4] Building Per-User Windows Installer with Inno Setup..."
    $iscc = Find-InnoSetupCompiler
    if ($null -eq $iscc) {
        throw "Inno Setup compiler (ISCC.exe) was not found. Please install Inno Setup 6."
    }
    $setupIssPath = Join-Path $repoRoot "installer\setup.iss"
    $isccArgs = @("/DMyAppVersion=$version", "/DMyAppExeSource=$localVersionedExe", "/O$targetOutputDir", $setupIssPath)
    Write-Host "  Compiling: $iscc $isccArgs"
    $null = Invoke-NativeChecked $iscc $isccArgs 'Inno Setup compilation'
    if (-not (Test-Path -LiteralPath $enterpriseSetup)) { throw 'Inno Setup did not produce the expected installer.' }

    if ($CertificateThumbprint) {
        Write-Host "Signing installer binary..."
        Invoke-ArtifactSigning -Paths @($enterpriseSetup) -Certificate $signingCertificate -Thumbprint $CertificateThumbprint -TimestampUrl $TimestampUrl
    }

Write-Host "[3/4] Preparing release artifacts..."
$artifactPaths = [System.Collections.Generic.List[string]]::new()
$artifactPaths.Add($enterpriseSetup)

# Clean up local binaries from targetOutputDir if they should not be in release
foreach ($excludedFile in @($localVersionedExe, $versionedZip, $setupExe)) {
    if (Test-Path -LiteralPath $excludedFile) {
        Remove-Item -LiteralPath $excludedFile -Force -ErrorAction SilentlyContinue
    }
}

Write-SuiteReleaseMetadata $targetOutputDir $version $provenance -Signed:([bool]$CertificateThumbprint)
Remove-Item -LiteralPath (Join-Path $targetOutputDir 'build-provenance.json')

Write-Host "`n[4/4] Build completed successfully: $targetOutputDir" -ForegroundColor Green
Get-Item -LiteralPath (@($artifactPaths) + @($releaseChecksums, $manifestPath)) |
    Select-Object Name, Length
Write-Host "`nChecksums:"
Get-Content -LiteralPath $releaseChecksums | ForEach-Object { Write-Host "  $_" }

# scripts/static-check.ps1 - Static quality and contract checks for SwiftDeck
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Assert-Project {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

Write-Host "Running static checks for SwiftDeck..." -ForegroundColor Cyan

# 1. PowerShell Script Syntax Verification
$psScripts = @(
    (Join-Path $PSScriptRoot "Common.ps1"),
    (Join-Path $PSScriptRoot "normalize-eol.ps1"),
    (Join-Path $PSScriptRoot "build.ps1"),
    (Join-Path $PSScriptRoot "publish.ps1"),
    (Join-Path $PSScriptRoot "release.ps1"),
    $PSCommandPath
)
foreach ($scriptPath in $psScripts) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        Assert-Project ($parseErrors.Count -eq 0) "PowerShell syntax errors in $scriptPath"
    }
}

# 1.1 Git Attributes and EOL Policy Verification
$gitAttributesPath = Join-Path $repoRoot ".gitattributes"
$gitAttributes = if (Test-Path -LiteralPath $gitAttributesPath -PathType Leaf) { Get-Content -Raw -LiteralPath $gitAttributesPath } else { "" }
Assert-Project ($gitAttributes -match '(?m)^\*\s+text=auto\s+eol=lf') ".gitattributes must exist and pin '* text=auto eol=lf'."

# 2. Main Script Version and Directive Consistency
$mainPath = Join-Path $repoRoot "src\SwiftDeck.ahk"
$mainText = Get-Content -Raw -LiteralPath $mainPath
$appVersion = $null
if ($mainText -match 'global g_appVersion\s*:=\s*"([^"]+)"') {
    $appVersion = $Matches[1]
}
Assert-Project ($null -ne $appVersion) "g_appVersion is missing in src\SwiftDeck.ahk."

$fileVersion = $null
if ($mainText -match ';@Ahk2Exe-SetVersion\s+(\d+\.\d+\.\d+\.\d+)') {
    $fileVersion = $Matches[1]
}
Assert-Project ($null -ne $fileVersion) "Ahk2Exe file version directive is missing in src\SwiftDeck.ahk."

if ($null -ne $appVersion -and $null -ne $fileVersion) {
    Assert-Project ($fileVersion -eq "$appVersion.0") "g_appVersion ($appVersion) and file version ($fileVersion) do not match."
}

# 3. SettingsManager Module Verification
Assert-Project ($mainText -match '(?m)^#Include SettingsManager\.ahk') "SettingsManager.ahk is not included in src\SwiftDeck.ahk."
$settingsManagerPath = Join-Path $repoRoot "src\SettingsManager.ahk"
Assert-Project (Test-Path -LiteralPath $settingsManagerPath) "src\SettingsManager.ahk does not exist."
if (Test-Path -LiteralPath $settingsManagerPath) {
    $smText = Get-Content -Raw -LiteralPath $settingsManagerPath
    Assert-Project ($smText -match 'EnsureSettingsMigration\(') "EnsureSettingsMigration is missing in SettingsManager.ahk."
    Assert-Project ($smText -match 'TryReadLocalSetting\(') "TryReadLocalSetting is missing in SettingsManager.ahk."
    Assert-Project ($smText -match 'SafeWriteLocalSetting\(') "SafeWriteLocalSetting is missing in SettingsManager.ahk."
    Assert-Project ($smText -match 'CleanLegacyShortcuts\(') "CleanLegacyShortcuts is missing in SettingsManager.ahk."
}

# 4. Inno Setup Configuration Verification
$setupIssPath = Join-Path $repoRoot "installer\setup.iss"
Assert-Project (Test-Path -LiteralPath $setupIssPath) "installer\setup.iss does not exist."
if (Test-Path -LiteralPath $setupIssPath) {
    $issText = Get-Content -Raw -LiteralPath $setupIssPath
    Assert-Project ($issText -match 'DefaultDirName=\{localappdata\}\\Programs\\SwiftDeck') "Setup DefaultDirName is not set to {localappdata}\Programs\SwiftDeck."
    Assert-Project ($issText -match 'PrivilegesRequired=lowest') "Setup PrivilegesRequired is not set to lowest."
    Assert-Project ($issText -match '\{app\}\\UserSetting.*uninsneveruninstall') "Setup does not preserve {app}\UserSetting directory."
    Assert-Project ($issText -match 'MyAppExeSource') "Setup does not define dynamic MyAppExeSource macro."
}

# 5. AutoHotkey v2 Syntax Validation
$baseAhk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (Test-Path -LiteralPath $baseAhk) {
    $validateRes = Invoke-Native $baseAhk @("/Validate", $mainPath)
    Assert-Project ($validateRes.ExitCode -eq 0) "AutoHotkey syntax validation failed for src\SwiftDeck.ahk."
} else {
    Write-Warning "AutoHotkey64.exe not found for syntax validation."
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        [Console]::Error.WriteLine("FAIL: $failure")
    }
    exit 1
}

Write-Host "SwiftDeck static checks: ALL PASSED" -ForegroundColor Green

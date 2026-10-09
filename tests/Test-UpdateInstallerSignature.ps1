[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\Verify-UpdateInstaller.ps1') -LibraryOnly
$count = 0
function Assert-Test { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message }; $script:count++ }
function Expect-Failure { param([scriptblock]$Action, [string]$Message); $failed = $false; try { & $Action } catch { $failed = $true }; Assert-Test $failed $Message }
function New-FixtureSignature {
    param([string]$Status = 'Valid', [string]$Publisher = 'publisher', [bool]$Timestamp = $true)
    [pscustomobject]@{ Status = $Status; SignerCertificate = [pscustomobject]@{ Thumbprint = $Publisher }; TimeStamperCertificate = $(if ($Timestamp) { [pscustomobject]@{ Thumbprint = 'timestamp' } } else { $null }) }
}
$valid = New-FixtureSignature
Assert-SwiftDeckUpdateSignatures $valid $valid
Assert-Test $true 'Matching valid timestamped publishers must pass.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures (New-FixtureSignature 'NotSigned') $valid } 'Unsigned update accepted.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures (New-FixtureSignature 'HashMismatch') $valid } 'Tampered update accepted.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures (New-FixtureSignature -Timestamp $false) $valid } 'Missing timestamp accepted.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures (New-FixtureSignature -Publisher 'another-publisher') $valid } 'Different publisher accepted.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures $valid (New-FixtureSignature 'NotSigned') } 'Unsigned installed app accepted.'
Expect-Failure { Assert-SwiftDeckUpdateSignatures $valid $null } 'Missing installed signature accepted.'
$updater = Get-Content -LiteralPath (Join-Path $repo 'src\lib\UpdateManager.ahk') -Raw
Assert-Test ($updater.IndexOf('this.VerifyInstallerPublisher(pendingPath)') -lt $updater.IndexOf('Run(pendingPath)')) 'Installer can launch before publisher validation.'
Assert-Test ($updater -match 'FileInstall\("\.\.\\scripts\\Verify-UpdateInstaller\.ps1"') 'Compiled updater does not embed the verifier.'
Write-Host "Update installer signature: $count assertions passed (policy fixtures; no signing or installation)."

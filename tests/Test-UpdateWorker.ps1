# Exercises the self-update worker end to end in a throwaway folder.
#
# This is the code path every existing user hits when they take v1.3.2, and it
# had never been run. Note which binary plays which role: the *helper* that
# performs the swap is a copy of the OLD app, so upgrading from v1.3.1 runs
# v1.3.1's worker — testing with the new binary alone would prove nothing about
# real users.
param(
    [Parameter(Mandatory = $true)][string]$OldExe,
    [Parameter(Mandatory = $true)][string]$NewExe,
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [string]$Label = "update"
)

$ErrorActionPreference = "Stop"
$failures = 0

function Check {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host "PASS  $Label"
    } else {
        Write-Host "FAIL  $Label"
        $script:failures++
    }
}

$dir = Join-Path $WorkRoot $Label
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$target = Join-Path $dir "SwiftDeck.exe"
$token = "{0}-{1}" -f (Get-Date -Format "yyyyMMddHHmmss"), (Get-Random -Minimum 1000 -Maximum 99999)
$pending = "$target.update-$token.tmp"
$backup  = "$target.previous-$token.bak"
$marker  = "$target.update-$token.ok"
$helper  = "$target.updater-$token.exe"

Copy-Item -LiteralPath $OldExe -Destination $target -Force   # the installed app
Copy-Item -LiteralPath $NewExe -Destination $pending -Force  # the downloaded update
Copy-Item -LiteralPath $target -Destination $helper -Force   # BeginUpdate copies itself

$oldHash = (Get-FileHash -LiteralPath $OldExe -Algorithm SHA256).Hash
$newHash = (Get-FileHash -LiteralPath $NewExe -Algorithm SHA256).Hash

Write-Host "--- $Label ---"
Write-Host ("installed : {0}  ({1})" -f (Split-Path $OldExe -Leaf), $oldHash.Substring(0, 12))
Write-Host ("update    : {0}  ({1})" -f (Split-Path $NewExe -Leaf), $newHash.Substring(0, 12))

# A PID that has already exited, so ProcessWaitClose returns at once.
$dead = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "exit" -PassThru -WindowStyle Hidden
$dead.WaitForExit()
$deadPid = $dead.Id

$worker = Start-Process -FilePath $helper -ArgumentList @(
    "--apply-update", "$deadPid", "`"$target`"", "`"$pending`"", "`"$backup`"", "`"$token`"", "`"$marker`""
) -PassThru

if (-not $worker.WaitForExit(90000)) {
    Write-Host "FAIL  worker did not exit within 90s"
    Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
    $script:failures++
} else {
    Check ($worker.ExitCode -eq 0) "worker exited 0 (exit=$($worker.ExitCode))"
}

Start-Sleep -Seconds 2
$installedHash = if (Test-Path -LiteralPath $target) {
    (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
} else { "<missing>" }

Check ($installedHash -eq $newHash) "the installed exe is now the new build"
Check (-not (Test-Path -LiteralPath $pending)) "the downloaded temp file was consumed"
Check (-not (Test-Path -LiteralPath $backup))  "the backup was cleaned up after success"
Check (-not (Test-Path -LiteralPath $marker))  "the startup marker was cleaned up"

# The replaced app is now running from $target; stop it and let the helper's
# own delayed cleanup be observed.
$running = Get-Process | Where-Object { $_.Path -eq $target }
Check ($null -ne $running) "the updated app was launched by the worker"
if ($running) {
    Start-Sleep -Seconds 7   # CleanupFinishedHelper runs on a -5000 timer
    $helperGone = -not (Test-Path -LiteralPath $helper)
    Check $helperGone "the updated app removed the leftover helper exe"
    $running | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

Start-Sleep -Milliseconds 500
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($failures -gt 0) { Write-Host "RESULT: $failures FAILURE(S)" } else { Write-Host "RESULT: update worker path holds" }
exit $failures

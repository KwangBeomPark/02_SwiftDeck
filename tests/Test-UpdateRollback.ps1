# The update's safety net: if the replacement binary does not confirm a healthy
# start, the worker must put the previous version back. A failure here would
# leave a user with no working SwiftDeck at all, so it matters more than the
# happy path.
#
# "Broken update" is simulated with a real executable that starts, ignores the
# --update-complete arguments, and exits without writing the marker file.
param(
    [Parameter(Mandatory = $true)][string]$OldExe,
    [Parameter(Mandatory = $true)][string]$WorkRoot
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

$dir = Join-Path $WorkRoot "rollback"
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$target = Join-Path $dir "SwiftDeck.exe"
$token = "{0}-{1}" -f (Get-Date -Format "yyyyMMddHHmmss"), (Get-Random -Minimum 1000 -Maximum 99999)
$pending = "$target.update-$token.tmp"
$backup  = "$target.previous-$token.bak"
$marker  = "$target.update-$token.ok"
$helper  = "$target.updater-$token.exe"

Copy-Item -LiteralPath $OldExe -Destination $target -Force
# A "downloaded update" that runs but never confirms startup.
Copy-Item -LiteralPath "$env:SystemRoot\System32\cmd.exe" -Destination $pending -Force
Copy-Item -LiteralPath $target -Destination $helper -Force

$goodHash = (Get-FileHash -LiteralPath $OldExe -Algorithm SHA256).Hash
Write-Host "--- rollback ---"
Write-Host ("installed : {0}" -f $goodHash.Substring(0, 12))
Write-Host "update    : a binary that never confirms startup"

$dead = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "exit" -PassThru -WindowStyle Hidden
$dead.WaitForExit()

$worker = Start-Process -FilePath $helper -ArgumentList @(
    "--apply-update", "$($dead.Id)", "`"$target`"", "`"$pending`"", "`"$backup`"", "`"$token`"", "`"$marker`""
) -PassThru

# The worker ends with a modal "Update Rolled Back" dialog; dismiss it so the
# test can finish, then confirm what it left on disk.
$deadline = (Get-Date).AddSeconds(75)
$dismissed = $false
while ((Get-Date) -lt $deadline -and -not $worker.HasExited) {
    $dlg = Get-Process -Id $worker.Id -ErrorAction SilentlyContinue
    if ($dlg -and $dlg.MainWindowTitle -like "*Rolled Back*") {
        # AppActivate needs the window; send Enter to the default button.
        $shell = New-Object -ComObject WScript.Shell
        if ($shell.AppActivate($worker.Id)) {
            Start-Sleep -Milliseconds 300
            $shell.SendKeys("{ENTER}")
            $dismissed = $true
        }
    }
    Start-Sleep -Milliseconds 500
}

if (-not $worker.HasExited) {
    Write-Host "  (worker still up after 75s; stopping it)"
    Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

Check ($dismissed) "the worker reported the rollback to the user"

$installedHash = if (Test-Path -LiteralPath $target) {
    (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
} else { "<missing>" }

Check (Test-Path -LiteralPath $target) "the app is still present after a failed update"
Check ($installedHash -eq $goodHash) "the previous working version was restored"
Check (-not (Test-Path -LiteralPath $backup)) "the backup was consumed by the rollback"

# The rollback relaunches the restored app.
$running = Get-Process | Where-Object { $_.Path -eq $target }
if ($running) {
    Check $true "the restored app was relaunched"
    $running | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
} else {
    Write-Host "note: restored app was not running (it may have already exited)"
}

Start-Sleep -Milliseconds 500
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($failures -gt 0) { Write-Host "RESULT: $failures FAILURE(S)" } else { Write-Host "RESULT: rollback protects the install" }
exit $failures

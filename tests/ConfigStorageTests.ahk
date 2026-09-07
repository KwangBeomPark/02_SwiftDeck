#Requires AutoHotkey v2.0
#Warn All, Off
; Backup retention, and the measured Windows INI ceilings the size guards assume.
;
; The scenario that used to destroy recovery: settings get corrupted, the user
; restarts, and the one .bak is overwritten with the corrupted content — so the
; backup that existed to save them is gone precisely when it is needed.
;
; The capacity checks are here because ConfigGetMaxValueLength/MaxSectionLength
; are magic numbers justified only by measurement. If a future Windows moves
; those ceilings, the guards silently become wrong, and this is what would say so.

global g_out := A_Temp . "\swiftdeck-storage-tests.txt"
global g_failures := 0

global g_targetFolder := A_Temp . "\swiftdeck-storage-tests\"
global g_fileName_Folder := "App02_01FavFolderSetting_v2_DoNotDelete.ini"
global g_fileName_Hotkey := "App02_02HotkeySetting_v2_DoNotDelete.ini"
global g_fileName_Hotstring := "App02_03HotstringSetting_DoNotDelete.ini"
global g_fileName_KeyRemap := "App02_04KeyRemap_DoNotDelete.ini"
global g_filePath_Folder := g_targetFolder . g_fileName_Folder
global g_filePath_Hotkey := g_targetFolder . g_fileName_Hotkey
global g_filePath_Hotstring := g_targetFolder . g_fileName_Hotstring
global g_filePath_KeyRemap := g_targetFolder . g_fileName_KeyRemap
global g_registeredHotstrings := []
global g_registeredKeyRemaps := Map()
global g_appVersion := "storage-tests"

OnError(Report)
SetTimer(Run_, -200)

#Include ..\src\lib\Config.ahk

Log(line) {
    FileAppend(line . "`n", g_out, "UTF-8")
}

Check(cond, label) {
    global g_failures
    if (cond) {
        Log("PASS  " . label)
    } else {
        g_failures++
        Log("FAIL  " . label)
    }
}

Report(err, mode) {
    Log("UNCAUGHT " . Type(err) . ": " . err.Message . " @ " . err.File . ":" . err.Line)
    FileAppend("FAIL  ConfigStorage: " . err.Message . "`n", "*")
    ExitApp(3)
}

Filler(n) {
    return StrReplace(Format("{:" . n . "}", ""), " ", "x")
}

BackupDir() {
    return g_targetFolder . "Backups\"
}

; A Windows wildcard of "name.bak.*" also matches "name.bak" itself, because a
; trailing "." matches an empty extension — so the dated suffix is matched
; explicitly here, the same way the production prune does it.
ListGenerations() {
    names := []
    loop files BackupDir() . g_fileName_Folder . ".bak.*", "F"
        if RegExMatch(A_LoopFileName, "\.\d{8}$")
            names.Push(A_LoopFileName)
    return names
}

CountGenerations() {
    return ListGenerations().Length
}

Run_() {
    if FileExist(g_out)
        FileDelete(g_out)
    if DirExist(g_targetFolder)
        DirDelete(g_targetFolder, true)
    DirCreate(g_targetFolder)

    ; ---------- Backup retention ----------
    Log("--- Backup retention ---")
    FileAppend("[FolderMenu]`nReports=C:\good`n", g_filePath_Folder, "UTF-8")
    for f in [g_filePath_Hotkey, g_filePath_Hotstring, g_filePath_KeyRemap]
        FileAppend("[Settings]`n", f, "UTF-8")

    ; First start: the .bak is created from good settings.
    BackupConfigs()
    bak := ConfigGetBackupPath(BackupDir(), g_filePath_Folder)
    Check(FileExist(bak) != "", "First start creates the .bak")
    Check(InStr(FileRead(bak, "UTF-8"), "C:\good") > 0, "The .bak holds the good settings")
    Check(CountGenerations() == 0, "No dated generation yet, because nothing needed preserving")

    ; The settings get corrupted, and the user restarts.
    FileDelete(g_filePath_Folder)
    FileAppend("[FolderMenu]`n", g_filePath_Folder, "UTF-8")   ; every entry gone
    BackupConfigs()
    Check(CountGenerations() == 1, "The outgoing good .bak is preserved as a dated generation")

    recovered := false
    for name in ListGenerations() {
        if InStr(FileRead(BackupDir() . name, "UTF-8"), "C:\good")
            recovered := true
    }
    Check(recovered, "The good settings are still recoverable after the corrupted restart")

    ; Restarting repeatedly on the same day must not consume the retention budget.
    BackupConfigs()
    BackupConfigs()
    Check(CountGenerations() == 1, "Repeated same-day restarts keep a single generation")

    ; Retention cap: older generations are pruned, not accumulated forever.
    loop 8 {
        stamp := FormatTime(DateAdd(A_Now, -A_Index, "Days"), "yyyyMMdd")
        p := BackupDir() . g_fileName_Folder . ".bak." . stamp
        if !FileExist(p)
            FileAppend("old " . A_Index, p, "UTF-8")
    }
    before := CountGenerations()
    ConfigPruneBackupGenerations(RTrim(BackupDir(), "\"), g_fileName_Folder . ".bak")
    after := CountGenerations()
    Log("  generations " . before . " -> " . after . " after prune")
    ; Min(), so that raising the retention constant above the number seeded here
    ; reports "nothing to prune" rather than a spurious failure.
    Check(after == Min(before, ConfigGetBackupGenerationCount()), "Prune keeps exactly the retention count")

    ; The newest generations are the ones worth keeping.
    kept := ListGenerations()
    todayStamp := FormatTime(A_Now, "yyyyMMdd")
    hasToday := false
    for name in kept {
        if InStr(name, "." . todayStamp)
            hasToday := true
    }
    Check(hasToday, "Prune keeps the newest generation, not an arbitrary set")

    ; ---------- The INI ceilings the size guards are built on ----------
    Log("")
    Log("--- Measured INI capacity ---")
    valueLimit := ConfigGetMaxValueLength()
    sectionLimit := ConfigGetMaxSectionLength()
    Log("  configured: per-value " . valueLimit . ", per-section " . sectionLimit)

    probe := g_targetFolder . "probe-value.ini"
    IniWrite(Filler(valueLimit), probe, "Probe", "Key")
    valueBack := ""
    try valueBack := IniRead(probe, "Probe", "Key", "")
    Log("  single value: wrote " . valueLimit . ", read back " . StrLen(valueBack))
    Check(StrLen(valueBack) == valueLimit, "A value at the per-prompt limit round-trips intact")

    ; Windows returns a section that is too large as completely empty rather than
    ; truncated, so a limit set above the real ceiling loses an entire slot at once.
    probe2 := g_targetFolder . "probe-section.ini"
    body := ""
    i := 0
    while (StrLen(body) < sectionLimit) {
        i++
        body .= "K" . i . "=" . Filler(200) . "`n"
    }
    body := SubStr(body, 1, sectionLimit)
    IniWrite(body, probe2, "Probe")
    sectionBack := ""
    try sectionBack := IniRead(probe2, "Probe", , "")
    Log("  section: wrote " . StrLen(body) . ", read back " . StrLen(sectionBack))
    Check(StrLen(sectionBack) >= StrLen(body) - 50, "A section at the slot limit round-trips intact")
    Check(sectionLimit > valueLimit, "The section limit leaves room for more than one prompt")

    try DirDelete(g_targetFolder, true)
    Log("")
    Log(g_failures ? ("RESULT: " . g_failures . " FAILURE(S)") : "RESULT: storage guards hold")
    if (g_failures)
        FileAppend("FAIL  ConfigStorage: " . g_failures . " failure(s); see " . g_out . "`n", "*")
    else
        FileAppend("ok    ConfigStorage`n", "*")
    ExitApp(g_failures ? 1 : 0)
}

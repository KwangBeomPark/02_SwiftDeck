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

global g_targetFolder := A_Temp . "\swiftdeck-storage-tests-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "\"
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
#Include _FixtureIsolation.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder . "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" . DllCall("GetCurrentProcessId")

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

RecoverMessage(target, backup, cause := "") {
    try SettingsRecoverReplaced(target, backup, cause is Error ? cause : Error("swap failed"))
    catch Error as err
        return err.Message . (err.HasOwnProp("KeptBackup") ? " [kept]" : "")
    return "(did not throw)"
}

LeftoverWriteFiles() {
    names := ""
    loop files g_targetFolder . "*", "F"
        if RegExMatch(A_LoopFileName, "\.(pending|prev)\.")
            names .= A_LoopFileName . " "
    return Trim(names)
}

Run_() {
    if FileExist(g_out)
        FileDelete(g_out)
    if DirExist(g_targetFolder)
        TestFinishDirectory(g_targetFolder)
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

    ; ---------- Multi-section saves are all or nothing ----------
    Log("")
    Log("--- All-or-nothing saves ---")
    ; The last change fails validation (Windows strips the quotes on read).
    ; Written section by section, the first change would already be on disk.
    badChanges := [{ Section: "Added", SectionText: "a=1" }, { Section: "Keep", Key: "q", Value: '"quoted"' }]
    probe3 := g_targetFolder . "probe-atomic.ini"
    FileAppend("[Keep]`nk=1`n", probe3, "UTF-16")
    FileCopy(probe3, probe3 . ".expect")
    threw := false
    try SettingsWriteIniValues(probe3, badChanges)
    catch
        threw := true
    Check(threw, "A change that fails validation refuses the whole write")
    Check(ConfigFilesHaveSameBytes(probe3, probe3 . ".expect"), "The earlier change in the same write is not on disk")
    probe4 := g_targetFolder . "probe-new.ini"
    try SettingsWriteIniValues(probe4, badChanges)
    Check(!FileExist(probe4), "A refused write to a new file creates no file")

    ; A file that appears while a new one is being written (a sync client
    ; restoring it) is a conflict, not something to overwrite.
    arrived := g_targetFolder . "probe-arrived.ini"
    FileAppend("[Synced]`ns=1`n", arrived, "UTF-16")
    FileCopy(arrived, arrived . ".expect")
    temp := SettingsTempPath(arrived)
    FileAppend("[Mine]`nm=1`n", temp, "UTF-16")
    threw := false
    try SettingsCommitTemp(temp, arrived, true)
    catch
        threw := true
    try FileDelete(temp)
    Check(threw && ConfigFilesHaveSameBytes(arrived, arrived . ".expect"),
        "A new file does not overwrite one that appeared meanwhile")

    ; After a swap Windows could not finish, the old file is moved back from
    ; its backup name, or kept there and named in the error.
    swapTarget := g_targetFolder . "probe-swap.ini"
    swapBackup := SettingsTempPath(swapTarget, "prev")
    FileAppend("[Old]`no=1`n", swapBackup, "UTF-16")
    FileCopy(swapBackup, swapTarget . ".expect")
    Check(RecoverMessage(swapTarget, swapBackup) == "swap failed"
        && ConfigFilesHaveSameBytes(swapTarget, swapTarget . ".expect") && !FileExist(swapBackup),
        "A file left only as its backup is moved back")
    FileAppend("[Old]`no=1`n", swapBackup, "UTF-16")
    Check(InStr(RecoverMessage(swapTarget, swapBackup), swapBackup) && FileExist(swapBackup),
        "A backup that cannot be moved back is kept and named in the error")
    FileDelete(swapBackup)
    Check(RecoverMessage(swapTarget, swapBackup) == "swap failed", "Without a backup the original error stands")
    ; Error 1177 means the old file is at the backup path even when a dropped
    ; share cannot show it, so the path is reported and the error is not retried.
    FileDelete(swapTarget)
    lostMessage := RecoverMessage(swapTarget, swapBackup, OSError(1177))
    Check(InStr(lostMessage, swapBackup) && InStr(lostMessage, "[kept]"),
        "After error 1177 the backup path is reported even if it cannot be seen")

    ; Sections to remove are listed from the private copy, matched without case.
    clearProbe := g_targetFolder . "probe-clear.ini"
    FileAppend("[Meta]`nv=4`n[Old1]`na=1`n[Old2]`nb=2`n", clearProbe, "UTF-16")
    SettingsWriteIniValues(clearProbe, [{ ClearSectionsExcept: ["meta"] }, { Section: "New", SectionText: "c=3" }])
    Check(StrReplace(IniRead(clearProbe), "`n", ",") == "Meta,New", "Clearing keeps the listed sections and adds the new ones")

    ; Creating a file that already exists is refused at once, not retried over.
    createProbe := g_targetFolder . "probe-create.ini"
    FileAppend("[Synced]`ns=1`n", createProbe, "UTF-16")
    FileCopy(createProbe, createProbe . ".expect")
    started := A_TickCount
    createError := ""
    try ConfigWriteTextFileSafely(createProbe, "[Defaults]`n", "UTF-16", true)
    catch Error as err
        createError := err
    elapsed := A_TickCount - started
    Check(createError != "" && ConfigFilesHaveSameBytes(createProbe, createProbe . ".expect") && elapsed < 100,
        "Creating defaults keeps a file that already exists and does not retry (" . elapsed . " ms)")
    ; InitializeConfig stays quiet only for this "already exists" error.
    createCode := (createError is OSError) ? createError.Number : -1
    Check(createCode == 80 || createCode == 183, "That refusal is the 'file already exists' error (" . createCode . ")")

    ; The real savers, against a file a sync client or scanner holds open.
    promptPath := GetConfigPath("Prompts")
    hotstringPath := GetConfigPath("Hotstrings")
    slots := Map()
    loop 10
        slots[A_Index - 1] := []
    slots[1].Push({ Title: "Kept", Msg: "before" })
    ConfigWritePromptData(slots)
    ConfigWritePromptSlotName(3, "Team")
    ConfigWriteHotstringData(Map("Group_Space_Kept", [{ Key: "k.k", Val: "K" }]), ["Group_Space_Kept"])
    slots[1][1].Msg := "after"
    saves := [
        { Label: "prompt", Path: promptPath, Save: () => ConfigWritePromptData(slots) },
        { Label: "hotstring", Path: hotstringPath,
          Save: () => ConfigWriteHotstringData(Map("Group_Space_New", [{ Key: "n.n", Val: "N" }]), ["Group_Space_New"]) }
    ]
    for save in saves {
        FileCopy(save.Path, save.Path . ".expect", true)
        lock := FileOpen(save.Path, "r -wd")
        threw := false
        try save.Save.Call()
        catch
            threw := true
        lock.Close()
        Check(threw, "A locked " . save.Label . " file refuses the save")
        Check(ConfigFilesHaveSameBytes(save.Path, save.Path . ".expect"), "The locked " . save.Label . " file is unchanged")
        FileDelete(save.Path . ".expect")
    }
    Check(ConfigReadPromptData()[1][1].Msg == "before", "The prompt reads back as before")
    Check(ConfigReadHotstringData().Data.Has("Group_Space_Kept"), "The hotstring groups read back as before")

    ; A successful save removes what it no longer holds, and nothing else.
    ConfigWriteHotstringData(Map("Group_Space_One", [{ Key: "o.o", Val: "1" }], "Group_Space_Two", [{ Key: "t.t", Val: "2" }]),
        ["Group_Space_One", "Group_Space_Two"])
    ConfigWriteHotstringData(Map("Group_Space_One", [{ Key: "o.o", Val: "1" }]), ["Group_Space_One"])
    Check(!InStr(ConfigReadSections("Hotstrings"), "Group002"), "A removed hotstring group leaves no section")
    slots[1] := []
    ConfigWritePromptData(slots)
    Check(!InStr(ConfigReadSections("Prompts"), "Numpad1"), "An emptied prompt slot leaves no section")
    Check(ConfigReadPromptSlotNames()[3] == "Team", "Saving prompts keeps the slot names")
    Check(LeftoverWriteFiles() == "", "Saves leave no temporary or backup file (" . LeftoverWriteFiles() . ")")

    try TestFinishDirectory(g_targetFolder)
    Log("")
    Log(g_failures ? ("RESULT: " . g_failures . " FAILURE(S)") : "RESULT: storage guards hold")
    if (g_failures)
        FileAppend("FAIL  ConfigStorage: " . g_failures . " failure(s); see " . g_out . "`n", "*")
    else
        FileAppend("ok    ConfigStorage`n", "*")
    ExitApp(g_failures ? 1 : 0)
}

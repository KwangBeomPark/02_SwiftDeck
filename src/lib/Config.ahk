#Requires AutoHotkey v2.0
#Include Utils.ahk
; NOTE: Global variables (g_targetFolder, g_filePath_*) are declared in SwiftDeck.ahk.
; =============================================================================
; --- Config File Initialization & Management ---
; =============================================================================

ConfigGetManagedFiles() {
    global g_fileName_Folder, g_fileName_Hotkey, g_fileName_Hotstring, g_fileName_KeyRemap
    global g_filePath_Folder, g_filePath_Hotkey, g_filePath_Hotstring, g_filePath_KeyRemap

    return [
        {
            CanonicalName: "Folders",
            Aliases: ["Settings", "Folders", "Favorites"],
            FileName: g_fileName_Folder,
            Path: g_filePath_Folder,
            ResetTarget: "Favorites",
            RequiredBackup: true
        },
        {
            CanonicalName: "Prompts",
            Aliases: ["Prompts", "Hotkeys"],
            FileName: g_fileName_Hotkey,
            Path: g_filePath_Hotkey,
            ResetTarget: "Prompts",
            RequiredBackup: true
        },
        {
            CanonicalName: "Hotstrings",
            Aliases: ["Hotstrings"],
            FileName: g_fileName_Hotstring,
            Path: g_filePath_Hotstring,
            ResetTarget: "Hotstrings",
            RequiredBackup: true
        },
        {
            CanonicalName: "KeyRemaps",
            Aliases: ["KeyRemaps", "Key Remaps"],
            FileName: g_fileName_KeyRemap,
            Path: g_filePath_KeyRemap,
            ResetTarget: "Key Remaps",
            RequiredBackup: false
        }
    ]
}

ConfigGetSettingsFolder() {
    global g_targetFolder
    return g_targetFolder
}

; Where unexpected errors are recorded so a user can report them without having
; to reproduce the raw AutoHotkey dialog.
ConfigGetErrorLogPath() {
    return ConfigGetSettingsFolder() . "SwiftDeck-error.log"
}

ConfigGetDefaultText(canonicalName) {
    switch canonicalName {
        case "Folders":
            return GetDefaultFolderData()
        case "Prompts":
            return GetDefaultHotkeyData()
        case "Hotstrings":
            return GetDefaultHotstringData()
        case "KeyRemaps":
            return GetDefaultKeyRemapData()
        default:
            throw Error("Unknown default config: " . canonicalName)
    }
}

ConfigManagedFileMatches(fileDef, configName) {
    for aliasName in fileDef.Aliases {
        if (aliasName == configName)
            return true
    }
    return false
}

ConfigGetManagedFile(configName) {
    for fileDef in ConfigGetManagedFiles() {
        if ConfigManagedFileMatches(fileDef, configName)
            return fileDef
    }
    throw Error("Unknown config file: " . configName)
}

ConfigIsFirstRun() {
    return !FileExist(GetConfigPath("Folders"))
}

InitializeAllConfigs() {
    for fileDef in ConfigGetManagedFiles() {
        InitializeConfig(fileDef.FileName, ConfigGetDefaultText(fileDef.CanonicalName))
    }
}

InitializeConfig(fileName, defaultText) {
    global g_targetFolder

    ConfigEnsureDir(g_targetFolder)

    targetFile := g_targetFolder . fileName

    if (FileExist(targetFile)) {
        return
    }

    try {
        ConfigWriteTextFileSafely(targetFile, defaultText, "UTF-16")
    } catch Error as err {
        MsgBox("⚠️ Cannot create file in the target drive.`n`nPath: " . targetFile . "`n`nError: " . err.Message, "Error", 262160)
    }
}

; How many dated backup generations to retain alongside the latest .bak.
ConfigGetBackupGenerationCount() {
    return 5
}

; The .bak is refreshed from the live settings on every start. On its own that
; means corrupted settings plus one restart overwrites the only good copy, so
; keep the outgoing .bak under a dated name first. One generation per calendar
; day, so frequent restarts do not churn the history.
ConfigPreserveBackupGeneration(backupPath) {
    if !FileExist(backupPath)
        return
    SplitPath(backupPath, &fileName, &dirPath)
    historyPath := dirPath . "\" . fileName . "." . FormatTime(A_Now, "yyyyMMdd")
    if FileExist(historyPath)
        return ; today's generation is already captured
    try {
        FileCopy(backupPath, historyPath, false)
        ConfigPruneBackupGenerations(dirPath, fileName)
    }
}

ConfigPruneBackupGenerations(dirPath, fileName) {
    paths := ""
    loop files dirPath . "\" . fileName . ".*", "F" {
        if RegExMatch(A_LoopFileName, "\.\d{8}$")
            paths .= A_LoopFileFullPath . "`n"
    }
    if (paths == "")
        return

    ; The names end in a yyyyMMdd stamp, so a reverse sort puts newest first.
    kept := 0
    loop parse, Sort(RTrim(paths, "`n"), "R"), "`n" {
        kept++
        if (kept > ConfigGetBackupGenerationCount())
            try FileDelete(A_LoopField)
    }
}

BackupConfigs(showMsg := false) {
    global g_targetFolder
    backupDir := g_targetFolder . "Backups\"

    try {
        ; Inside the try: creating the backup folder can fail on its own (a file
        ; already occupying that name, a read-only or full drive), and the caller
        ; should get the same handled message as a failed copy.
        ConfigEnsureDir(backupDir)
        for fileDef in ConfigGetManagedFiles() {
            if (fileDef.RequiredBackup || FileExist(fileDef.Path)) {
                backupPath := ConfigGetBackupPath(backupDir, fileDef.Path)
                ConfigPreserveBackupGeneration(backupPath)
                FileCopy(fileDef.Path, backupPath, true)
            }
        }
        if (showMsg)
            MsgBox("✅ Settings have been backed up successfully.", "Backup Complete", 262208)
    } catch {
        if (showMsg)
            MsgBox("❌ An error occurred during backup.", "Error", 262160)
    }
}

ConfigIsStartupEnabled() {
    return (FileExist(A_Startup . "\SwiftDeck.lnk")
        || FileExist(A_Startup . "\FolderHotKey.lnk")) ? 1 : 0
}

ConfigSetStartupEnabled(enabled, showMsg := true) {
    startupLnk := A_Startup . "\SwiftDeck.lnk"
    legacyLnk := A_Startup . "\FolderHotKey.lnk"

    try {
        if (enabled) {
            pendingLnk := A_Startup . "\SwiftDeck.pending." . A_TickCount . ".lnk"
            try {
                FileCreateShortcut(A_ScriptFullPath, pendingLnk, A_ScriptDir)
                if !FileExist(pendingLnk)
                    throw Error("The startup shortcut could not be verified.")
                FileMove(pendingLnk, startupLnk, true)
            } finally {
                if FileExist(pendingLnk)
                    try FileDelete(pendingLnk)
            }

            if FileExist(legacyLnk)
                FileDelete(legacyLnk)
            if !FileExist(startupLnk)
                throw Error("The startup shortcut is missing after registration.")

            if (showMsg)
                MsgBox("🚀 Auto-Start is enabled.`nSwiftDeck will run automatically when Windows starts.", "Startup Registration", 262208)
        } else {
            hadShortcut := FileExist(startupLnk) || FileExist(legacyLnk)
            if FileExist(startupLnk)
                FileDelete(startupLnk)
            if FileExist(legacyLnk)
                FileDelete(legacyLnk)
            if ConfigIsStartupEnabled()
                throw Error("A startup shortcut could not be removed.")

            if (showMsg) {
                msg := hadShortcut
                    ? "🗑️ Auto-Start is disabled.`nThe shortcut was removed from the Startup folder."
                    : "ℹ️ Auto-Start is already disabled."
                MsgBox(msg, "Startup Status", 262208)
            }
        }
        return true
    } catch Error as err {
        if (showMsg) {
            actionLabel := enabled ? "enable" : "disable"
            MsgBox("❌ Failed to " . actionLabel . " Auto-Start.`n`nError: " . err.Message, "Startup Error", 262160)
        }
        return false
    }
}

RestoreConfigs() {
    global g_targetFolder
    backupDir := g_targetFolder . "Backups\"
    managedFiles := ConfigGetManagedFiles()
    requiredBackups := []
    for fileDef in managedFiles {
        if fileDef.RequiredBackup
            requiredBackups.Push(ConfigGetBackupPath(backupDir, fileDef.Path))
    }

    missingBackups := ConfigListMissingFiles(requiredBackups)
    if (missingBackups != "") {
        MsgBox("❌ Cannot restore because required backup files are missing:`n`n" . missingBackups, "Restore Blocked", 262160)
        return
    }

    msgRes := MsgBox(
        "⚠️ Are you sure you want to restore the settings from the last backup?`nYour current settings will be overwritten.",
        "Restore Backup", 262180)
    if (msgRes != "Yes")
        return

    rollbackDir := g_targetFolder . "RestoreRollback_" . A_Now . "_" . A_TickCount . "\"
    currentPaths := []
    try {
        ConfigEnsureDir(rollbackDir)
        for fileDef in managedFiles {
            currentPaths.Push(fileDef.Path)
            ConfigBackupCurrentFileForRollback(rollbackDir, fileDef.Path)
        }

        for fileDef in managedFiles {
            backupPath := ConfigGetBackupPath(backupDir, fileDef.Path)
            if (fileDef.RequiredBackup || FileExist(backupPath))
                FileCopy(backupPath, fileDef.Path, true)
        }

        ConfigDeleteDirQuietly(rollbackDir)
        MsgBox("✅ Restoration complete. The app will now reload to apply changes.", "Restore Complete", 262208)
        Reload()
    } catch Error as err {
        ConfigRestoreFilesFromRollback(rollbackDir, currentPaths)
        ConfigDeleteDirQuietly(rollbackDir)
        MsgBox("❌ Restore failed and current settings were rolled back.`n`nError: " . err.Message, "Restore Error", 262160)
    }
}

ConfigGetBackupPath(backupDir, sourcePath) {
    SplitPath(sourcePath, &fileName)
    return backupDir . fileName . ".bak"
}

ConfigEnsureDir(dirPath) {
    if (dirPath != "" && !DirExist(dirPath))
        DirCreate(dirPath)
}

ConfigMakeTempPath(targetPath, tag := "tmp") {
    SplitPath(targetPath, &fileName, &dirPath)
    loop 50 {
        tempPath := dirPath . "\" . fileName . "." . tag . "." . A_Now . "." . A_TickCount . "." . A_Index
        if !FileExist(tempPath)
            return tempPath
    }
    throw Error("Cannot create a temporary file path for: " . targetPath)
}

ConfigWriteTextFileSafely(targetPath, content, encoding := "UTF-16") {
    SplitPath(targetPath, , &dirPath)
    ConfigEnsureDir(dirPath)

    tempPath := ConfigMakeTempPath(targetPath, "tmp")
    rollbackPath := ""
    maxRetries := 3
    lastErr := ""

    loop maxRetries {
        try {
            ; Write to a temp file first so a failed write does not destroy the current config.
            if FileExist(tempPath)
                FileDelete(tempPath)
            FileAppend(content, tempPath, encoding)
            ; Snapshot the target once and reuse it. Minting a fresh copy on each
            ; retry overwrote this variable, so only the last one was ever
            ; cleaned up — measured: two orphaned .rollback files left in the
            ; settings folder for every save that a sync client or scanner
            ; blocked, accumulating with no upper bound.
            if (rollbackPath == "" && FileExist(targetPath))
                rollbackPath := ConfigCreateRollbackCopy(targetPath)
            FileMove(tempPath, targetPath, true)
            ; Success — clean up and return
            ConfigDeleteFileQuietly(rollbackPath)
            ConfigDeleteFileQuietly(tempPath)
            return
        } catch Error as err {
            lastErr := err
            if (A_Index < maxRetries)
                Sleep(100 * A_Index)  ; Exponential backoff: 100ms, 200ms, 300ms
        }
    }

    ; All retries exhausted — restore rollback and propagate error
    ConfigRestoreRollbackCopy(targetPath, rollbackPath)
    ConfigDeleteFileQuietly(tempPath)
    ConfigDeleteFileQuietly(rollbackPath)
    throw lastErr
}

ConfigCreateRollbackCopy(targetPath) {
    if !FileExist(targetPath)
        return ""
    rollbackPath := ConfigMakeTempPath(targetPath, "rollback")
    FileCopy(targetPath, rollbackPath, true)
    return rollbackPath
}

ConfigRestoreRollbackCopy(targetPath, rollbackPath) {
    if (rollbackPath != "" && FileExist(rollbackPath))
        try FileCopy(rollbackPath, targetPath, true)
}

ConfigDeleteFileQuietly(path) {
    if (path != "" && FileExist(path))
        try FileDelete(path)
}

ConfigDeleteDirQuietly(path) {
    if (path != "" && DirExist(path))
        try DirDelete(path, true)
}

ConfigListMissingFiles(paths) {
    missing := ""
    for path in paths {
        if !FileExist(path)
            missing .= path . "`n"
    }
    return RTrim(missing, "`n")
}

ConfigBackupCurrentFileForRollback(rollbackDir, sourcePath) {
    if FileExist(sourcePath)
        FileCopy(sourcePath, ConfigGetBackupPath(rollbackDir, sourcePath), true)
}

ConfigRestoreFilesFromRollback(rollbackDir, sourcePaths) {
    for sourcePath in sourcePaths {
        rollbackPath := ConfigGetBackupPath(rollbackDir, sourcePath)
        if FileExist(rollbackPath)
            try FileCopy(rollbackPath, sourcePath, true)
    }
}

ResetToDefaults(target := "All") {
    ; Manual language is a display preference, so feature/factory resets keep the user's last choice.
    savedManualLanguage := ConfigReadValue("Settings", "Settings", "ManualLanguage", "EN")
    msg := ""
    if (target == "All")
        msg := "⚠️ Are you sure you want to FACTORY RESET ALL settings?`nAll your custom configurations will be deleted.`n(Backups will not be affected.)"
    else
        msg := "⚠️ Are you sure you want to reset " . target . " to default?`nYour current settings for this feature will be deleted.`n(Backups will not be affected.)"

    if (MsgBox(msg, "Confirm Reset", 262452) != "Yes")
        return

    try {
        for fileDef in ConfigGetManagedFiles() {
            if (target == "All" || target == fileDef.ResetTarget)
                ConfigWriteTextFileSafely(fileDef.Path, ConfigGetDefaultText(fileDef.CanonicalName), "UTF-16")
        }
        if (target == "All" || target == "Favorites")
            ConfigWriteValue("Settings", "Settings", "ManualLanguage", savedManualLanguage)
        MsgBox("✅ Reset complete. The app will now reload.", "Success", 262208)
        Reload()
    } catch Error as err {
        MsgBox("❌ An error occurred while resetting settings.`n`nError: " . err.Message, "Error", 262160)
    }
}

; =============================================================================
; SECTION: Central Config Gateway
; =============================================================================
GetConfigPath(configName) {
    return ConfigGetManagedFile(configName).Path
}

ConfigExists(configName) {
    return FileExist(GetConfigPath(configName))
}

ConfigReadValue(configName, section, key, defaultValue := "") {
    try {
        return IniRead(GetConfigPath(configName), section, key, defaultValue)
    } catch {
        return defaultValue
    }
}

ConfigWriteValue(configName, section, key, value) {
    configPath := GetConfigPath(configName)
    rollbackPath := ConfigCreateRollbackCopy(configPath)
    try {
        IniWrite(value, configPath, section, key)
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, rollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(rollbackPath)
    }
}

ConfigReadSection(configName, section, defaultValue := "") {
    try {
        return IniRead(GetConfigPath(configName), section, , defaultValue)
    } catch {
        return defaultValue
    }
}

ConfigWriteSection(configName, section, content) {
    configPath := GetConfigPath(configName)
    rollbackPath := ConfigCreateRollbackCopy(configPath)
    try {
        if (content != "") {
            IniWrite(content, configPath, section)
        } else {
            IniDelete(configPath, section)
        }
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, rollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(rollbackPath)
    }
}

ConfigDeleteSection(configName, section) {
    configPath := GetConfigPath(configName)
    rollbackPath := ConfigCreateRollbackCopy(configPath)
    try {
        IniDelete(configPath, section)
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, rollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(rollbackPath)
    }
}

ConfigReadSections(configName) {
    try {
        return IniRead(GetConfigPath(configName))
    } catch {
        return ""
    }
}

; IniRead hands back whatever text is stored and Integer() throws on anything
; non-numeric, including an existing-but-empty key. Unguarded, one hand-edited or
; half-written value would take down every ConfigReadAppSettings() caller — which
; includes the F1 handler, the prompt menu, and the settings window itself.
ConfigReadNumber(configName, section, key, defaultValue) {
    raw := ConfigReadValue(configName, section, key, defaultValue)
    try {
        return Integer(raw)
    } catch {
        return Integer(defaultValue)
    }
}

; Hotkey defaults in one place: the reader falls back to these per missing key,
; and startup recovery uses the whole set when the settings file is unreadable.
ConfigGetFallbackAppSettings() {
    return {
        MainHotkey: "F1",
        PromptModifier: "#",
        PromptUseNumpad: 1,
        EmojiHotkey: "^#Space",
        ExitHotkey: "^#Escape"
    }
}

ConfigReadAppSettings() {
    defaults := ConfigGetFallbackAppSettings()
    return {
        MainHotkey: ConfigReadValue("Settings", "Settings", "MainHotkey", defaults.MainHotkey),
        PromptModifier: ConfigReadValue("Settings", "Settings", "PromptModifier", defaults.PromptModifier),
        PromptUseNumpad: ConfigReadNumber("Settings", "Settings", "PromptUseNumpad", defaults.PromptUseNumpad),
        EmojiHotkey: ConfigReadValue("Settings", "Settings", "EmojiHotkey", defaults.EmojiHotkey),
        ExitHotkey: ConfigReadValue("Settings", "Settings", "ExitHotkey", defaults.ExitHotkey)
    }
}

; Emoji and Exit are optional so an older call site that only knows the first
; three values leaves the stored shortcuts untouched.
;
; These values are validated as a set — a main hotkey is only accepted after
; being checked against the exit hotkey, and so on — so a failure part-way
; through must not leave half of that set stored. A rollback copy taken up front
; and restored on any failure gives that, while still writing key by key.
;
; Rewriting the whole [Settings] section in one call would also be atomic, but
; IniRead's section mode does not return comment or blank lines, so the rewrite
; would quietly delete them; per-key writes leave the rest of the file alone.
ConfigWriteAppSettings(mainHotkey, promptModifier, promptUseNumpad, emojiHotkey := "", exitHotkey := "") {
    configPath := GetConfigPath("Settings")
    rollbackPath := ConfigCreateRollbackCopy(configPath)
    try {
        ConfigWriteValue("Settings", "Settings", "MainHotkey", mainHotkey)
        ConfigWriteValue("Settings", "Settings", "PromptModifier", promptModifier)
        ConfigWriteValue("Settings", "Settings", "PromptUseNumpad", promptUseNumpad)
        if (emojiHotkey != "")
            ConfigWriteValue("Settings", "Settings", "EmojiHotkey", emojiHotkey)
        if (exitHotkey != "")
            ConfigWriteValue("Settings", "Settings", "ExitHotkey", exitHotkey)
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, rollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(rollbackPath)
    }
}

ConfigReadFolderItems() {
    items := []
    content := ConfigReadSection("Folders", "FolderMenu", "")

    if (content != "") {
        loop parse, content, "`n", "`r" {
            pair := ParseIniKeyValuePairs(A_LoopField)
            if (pair.Key != "")
                items.Push({ Name: pair.Key, Path: pair.Val })
        }
    }

    return items
}

ConfigWriteFolderItems(items) {
    content := ""
    for item in items {
        content .= item.Name . "=" . item.Path . "`n"
    }
    ConfigWriteSection("Folders", "FolderMenu", content)
}

ConfigReadPromptData() {
    encodingVersion := ConfigReadPromptEncodingVersion()
    promptData := Map()
    loop 10 {
        num := A_Index - 1
        promptData[num] := []
        content := ConfigReadSection("Prompts", "Numpad" . num, "")

        if (content != "") {
            loop parse, content, "`n", "`r" {
                pair := ParseIniKeyValuePairs(A_LoopField)
                if (pair.Key != "") {
                    promptData[num].Push({ Title: pair.Key, Msg: ConfigDecodePromptText(pair.Val, encodingVersion) })
                }
            }
        }
    }
    return promptData
}

ConfigReadPromptItems(groupNum) {
    encodingVersion := ConfigReadPromptEncodingVersion()
    items := []
    content := ConfigReadSection("Prompts", "Numpad" . groupNum, "")

    if (content != "") {
        loop parse, content, "`n", "`r" {
            pair := ParseIniKeyValuePairs(A_LoopField)
            if (pair.Key != "") {
                items.Push({
                    fontSize: 11,
                    fontColor: "black",
                    label: pair.Key,
                    msg: ConfigDecodePromptText(pair.Val, encodingVersion)
                })
            }
        }
    }

    return items
}

; Windows caps INI reads at two different places, both measured on Windows 11:
;   - a whole section reads back intact at 65,000 characters but comes back
;     COMPLETELY EMPTY at 66,000, which the next save would persist as "the slot
;     is empty" — deleting every prompt in it
;   - a single value reads back intact at 32,000 and is silently truncated by
;     40,000 (the classic 32,767 limit)
; Both limits sit well below their cliff.
ConfigGetMaxSectionLength() {
    return 60000
}

ConfigGetMaxValueLength() {
    return 30000
}

; Prompts are stored one per INI line, so a real newline has to be encoded. The
; original encoding mapped a newline to the two characters \n but left a literal
; backslash untouched, so any prompt containing "\n" decoded into a line break:
; measured, "Save it to C:\new\report.xlsx" came back as
; "Save it to C:<newline>ew\report.xlsx". The shipped default prompts hit this
; too — their instruction text mentions (\n) literally.
;
; Version 2 escapes the backslash as well. Files from older versions carry no
; marker and keep being read with the original rule, so nothing changes for them
; until the next save rewrites the file in the new encoding.
ConfigGetPromptEncodingVersion() {
    return 2
}

ConfigReadPromptEncodingVersion() {
    return ConfigReadNumber("Prompts", "Meta", "PromptEncoding", 1)
}

ConfigEncodePromptText(text) {
    ; Backslashes first, or the "\n" produced below would be escaped in turn.
    encoded := StrReplace(text, "\", "\\")
    encoded := StrReplace(encoded, "`r`n", "\n")
    encoded := StrReplace(encoded, "`n", "\n")
    encoded := StrReplace(encoded, "`r", "\n")
    return encoded
}

ConfigDecodePromptText(encoded, encodingVersion) {
    if (encodingVersion < 2)
        return StrReplace(encoded, "\n", "`n") ; legacy rule, ambiguous by design

    ; One left-to-right pass: a backslash always consumes the character after
    ; it, so "\\n" is a backslash followed by n rather than a line break.
    result := ""
    pos := 1
    length := StrLen(encoded)
    while (pos <= length) {
        ch := SubStr(encoded, pos, 1)
        if (ch == "\" && pos < length) {
            next := SubStr(encoded, pos + 1, 1)
            if (next == "n")
                result .= "`n"
            else if (next == "\")
                result .= "\"
            else
                result .= ch . next ; unrecognized escape: keep it verbatim
            pos += 2
            continue
        }
        result .= ch
        pos++
    }
    return result
}

ConfigBuildPromptSectionText(items) {
    content := ""
    for item in items
        content .= item.Title . "=" . ConfigEncodePromptText(item.Msg) . "`n"
    return content
}

; Returns "" when the slot is safe to write, or a human-readable reason when it
; is not. Callers must refuse the edit rather than write something the reader
; cannot get back intact.
ConfigCheckPromptSlotLimit(items) {
    for item in items {
        ; Measure what actually gets written. Using the old formula here let a
        ; backslash-heavy prompt through: 20,000 backslashes measured as 20,004
        ; but were stored as 40,004 characters and read back truncated.
        encodedLength := StrLen(ConfigEncodePromptText(item.Msg))
        if (encodedLength > ConfigGetMaxValueLength())
            return "One prompt is " . encodedLength . " characters, over the "
                . ConfigGetMaxValueLength() . " character limit for a single prompt.`n`n"
                . "Windows silently cuts a settings value longer than that, so part of "
                . "the text would be lost. Please shorten it."
    }

    length := StrLen(ConfigBuildPromptSectionText(items))
    if (length > ConfigGetMaxSectionLength())
        return "This slot would hold " . length . " characters, over the "
            . ConfigGetMaxSectionLength() . " character limit for one slot.`n`n"
            . "Windows cannot read a settings section that large, and saving it would "
            . "discard every prompt in this slot. Shorten this prompt or move some to another slot."
    return ""
}

ConfigWritePromptData(promptData) {
    ; Validate every slot before writing any of them. Failing half-way used to
    ; leave slots already converted to the new encoding while the marker — written
    ; last — was still missing, so the next read applied the legacy rule and
    ; doubled every backslash, permanently, on the following save.
    loop 10 {
        num := A_Index - 1
        items := (promptData[num].Length > 0) ? promptData[num] : []
        limitWarning := ConfigCheckPromptSlotLimit(items)
        if (limitWarning != "")
            throw Error("Prompt slot " . num . ": " . limitWarning)
    }

    ; And roll the whole file back if a write fails part-way for any other
    ; reason — a locked or cloud-synced file, most likely.
    configPath := GetConfigPath("Prompts")
    rollbackPath := ConfigCreateRollbackCopy(configPath)
    try {
        loop 10 {
            num := A_Index - 1
            items := (promptData[num].Length > 0) ? promptData[num] : []
            ConfigWriteSection("Prompts", "Numpad" . num, ConfigBuildPromptSectionText(items))
        }
        ; Recorded after the slots: a reader that sees this marker knows every
        ; slot above is in the new encoding.
        ConfigWriteValue("Prompts", "Meta", "PromptEncoding", ConfigGetPromptEncodingVersion())
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, rollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(rollbackPath)
    }
}

; The measured point where storage stops working: 32,767 encoded characters read
; back intact, 32,768 makes the whole entry disappear, and 33,000 comes back as
; 232 characters — Windows wraps rather than truncating, and the next save writes
; the remnant.
ConfigGetHotstringValueCeiling() {
    return 32767
}

; What the editor asks of new text: the same conservative limit prompts use, so
; there is headroom rather than a value sitting one character from the cliff.
; Length is measured after encoding, because that is what gets stored — every
; line break costs 6 characters as %0D%0A, so a pasted block well under the raw
; limit can still cross it.
ConfigCheckHotstringValueLimit(text) {
    encodedLength := StrLen(HotstringEncodeIniValue(text))
    if (encodedLength <= ConfigGetMaxValueLength())
        return ""
    return "This replacement text is " . encodedLength . " characters once stored, over the "
        . ConfigGetMaxValueLength() . " character limit.`n`n"
        . "Windows cannot store a settings value that large, and saving it would "
        . "discard this entry entirely. Please shorten it."
}

; What the writer refuses. This is the hard ceiling, not the editor's limit: an
; entry saved by an earlier build can sit between the two, and it still stores
; and reads back correctly — refusing it here would lock that user out of saving
; any hotstring change at all.
ConfigCheckHotstringValueStorable(text) {
    encodedLength := StrLen(HotstringEncodeIniValue(text))
    if (encodedLength <= ConfigGetHotstringValueCeiling())
        return ""
    return "This replacement text is " . encodedLength . " characters once stored, over the "
        . ConfigGetHotstringValueCeiling() . " characters Windows can hold in one settings value."
}

ConfigReadHotstringData() {
    schemaVer := ConfigReadValue("Hotstrings", "Meta", "SchemaVersion", "1")
    if (schemaVer == "4")
        return ConfigReadHotstringDataV4()
    return ConfigReadHotstringDataLegacy()
}

ConfigReadHotstringDataV4() {
    localData := Map()
    groupOrder := []
    groupCount := ConfigReadIntegerValue("Hotstrings", "Groups", "Count", 0)

    loop groupCount {
        groupNo := Format("{:03}", A_Index)
        groupId := ConfigReadValue("Hotstrings", "Groups", "Group" . groupNo . "Id", "Group" . groupNo)
        groupType := ConfigReadValue("Hotstrings", "Groups", "Group" . groupNo . "Type", "Space")
        groupName := ConfigReadValue("Hotstrings", "Groups", "Group" . groupNo . "Name", "Default")
        groupSection := HotstringMakeRuntimeSection(groupType, HotstringDecodeIniValue(groupName))

        if (localData.Has(groupSection))
            groupSection := HotstringMakeRuntimeSection(groupType, HotstringDecodeIniValue(groupName) . "_" . groupId)

        localData[groupSection] := []
        groupOrder.Push(groupSection)

        itemCount := ConfigReadIntegerValue("Hotstrings", groupId, "ItemCount", 0)
        loop itemCount {
            itemNo := Format("{:03}", A_Index)
            triggerText := HotstringDecodeIniValue(ConfigReadValue("Hotstrings", groupId, "Item" . itemNo . "Key", ""))
            replacementText := HotstringDecodeIniValue(ConfigReadValue("Hotstrings", groupId, "Item" . itemNo . "Val", ""))
            if (triggerText != "" && replacementText != "") {
                localData[groupSection].Push({ Key: triggerText, Val: replacementText })
            }
        }
    }

    if (localData.Count == 0) {
        localData["Group_Space_Default"] := []
        groupOrder.Push("Group_Space_Default")
    }

    return { Data: localData, GroupOrder: groupOrder }
}

ConfigReadHotstringDataLegacy() {
    localData := Map()
    groupOrder := []
    discoveredOrder := []
    legacySectionMap := Map()
    sections := ConfigReadSections("Hotstrings")

    if (sections != "") {
        loop parse, sections, "`n", "`r" {
            legacySectionName := Trim(A_LoopField)
            if (legacySectionName == "" || legacySectionName == "Meta" || legacySectionName == "GroupOrder")
                continue

            runtimeSection := HotstringMapLegacySection(legacySectionName)
            if (runtimeSection == "")
                continue

            legacySectionMap[legacySectionName] := runtimeSection
            if (!localData.Has(runtimeSection)) {
                localData[runtimeSection] := []
                discoveredOrder.Push(runtimeSection)
            }

            content := ConfigReadSection("Hotstrings", legacySectionName, "")
            if (content != "") {
                loop parse, content, "`n", "`r" {
                    pair := ParseIniKeyValuePairs(A_LoopField)
                    if (pair.Key != "" && pair.Val != "") {
                        fixed := FixIniSpecialChars(pair.Key, pair.Val)
                        localData[runtimeSection].Push({ Key: fixed.Key, Val: StrReplace(fixed.Val, "\n", "`n") })
                    }
                }
            }
        }
    }

    savedOrder := ConfigReadValue("Hotstrings", "GroupOrder", "Order", "")
    if (savedOrder != "") {
        loop parse, savedOrder, "," {
            oldSecName := Trim(A_LoopField)
            if (oldSecName == "")
                continue
            groupSection := legacySectionMap.Has(oldSecName) ? legacySectionMap[oldSecName] : HotstringMapLegacySection(oldSecName)
            if (groupSection != "" && localData.Has(groupSection) && !ConfigArrayHasValue(groupOrder, groupSection))
                groupOrder.Push(groupSection)
        }
    }

    for groupSection in discoveredOrder {
        if !ConfigArrayHasValue(groupOrder, groupSection)
            groupOrder.Push(groupSection)
    }

    if (localData.Count == 0) {
        localData["Group_Space_Default"] := []
        groupOrder.Push("Group_Space_Default")
    }

    return { Data: localData, GroupOrder: groupOrder }
}

ConfigWriteHotstringData(localData, groupOrder) {
    ; Check every item before the file is touched, so an over-long entry is
    ; refused outright instead of being written and read back mangled.
    for groupSection in groupOrder {
        if !localData.Has(groupSection)
            continue
        for item in localData[groupSection] {
            reason := ConfigCheckHotstringValueStorable(Trim(item.Val))
            if (reason != "")
                throw Error("Hotstring '" . Trim(item.Key) . "': " . reason)
        }
    }

    configPath := GetConfigPath("Hotstrings")
    fullRollbackPath := ConfigCreateRollbackCopy(configPath)

    try {
        sections := ConfigReadSections("Hotstrings")
        if (sections != "") {
            loop parse, sections, "`n", "`r" {
                sectionName := Trim(A_LoopField)
                if (sectionName != "" && sectionName != "Meta")
                    ConfigDeleteSection("Hotstrings", sectionName)
            }
        }

        ConfigWriteValue("Hotstrings", "Meta", "SchemaVersion", "4")

        groupDefs := []
        for groupSection in groupOrder {
            if !localData.Has(groupSection)
                continue

            groupType := HotstringGetRuntimeGroupType(groupSection)
            groupName := HotstringGetRuntimeGroupName(groupSection)
            if (groupName == "")
                groupName := "Default"

            itemCount := 0
            itemContent := ""
            for item in localData[groupSection] {
                triggerText := Trim(item.Key)
                replacementText := Trim(item.Val)
                if (triggerText == "" || replacementText == "")
                    continue
                itemCount++
                itemNo := Format("{:03}", itemCount)
                itemContent .= "Item" . itemNo . "Key=" . HotstringEncodeIniValue(triggerText) . "`n"
                itemContent .= "Item" . itemNo . "Val=" . HotstringEncodeIniValue(replacementText) . "`n"
            }
            groupDefs.Push({ Type: groupType, Name: groupName, ItemContent: "ItemCount=" . itemCount . "`n" . itemContent })
        }

        if (groupDefs.Length == 0)
            groupDefs.Push({ Type: "Space", Name: "Default", ItemContent: "ItemCount=0`n" })

        groupsContent := "Count=" . groupDefs.Length . "`n"
        for idx, groupDef in groupDefs {
            groupNo := Format("{:03}", idx)
            groupId := "Group" . groupNo
            groupsContent .= "Group" . groupNo . "Id=" . groupId . "`n"
            groupsContent .= "Group" . groupNo . "Type=" . groupDef.Type . "`n"
            groupsContent .= "Group" . groupNo . "Name=" . HotstringEncodeIniValue(groupDef.Name) . "`n"
            ConfigWriteSection("Hotstrings", groupId, groupDef.ItemContent)
        }
        ConfigWriteSection("Hotstrings", "Groups", groupsContent)
    } catch Error as err {
        ConfigRestoreRollbackCopy(configPath, fullRollbackPath)
        throw err
    } finally {
        ConfigDeleteFileQuietly(fullRollbackPath)
    }
}

ConfigReadIntegerValue(configName, section, key, defaultValue := 0) {
    val := ConfigReadValue(configName, section, key, defaultValue)
    try {
        return Integer(val)
    } catch {
        return defaultValue
    }
}

HotstringMapLegacySection(sectionName) {
    if (SubStr(sectionName, 1, 12) == "Group_Space_")
        return sectionName
    if (SubStr(sectionName, 1, 11) == "Group_Menu_")
        return sectionName
    if (SubStr(sectionName, 1, 11) == "Group_Auto_")
        return "Group_Space_" . SubStr(sectionName, 12)
    if (SubStr(sectionName, 1, 6) == "Group_")
        return "Group_Space_" . SubStr(sectionName, 7)
    if (sectionName == "AutoReplace" || sectionName == "SpaceReplace")
        return "Group_Space_Default"
    return ""
}

HotstringMakeRuntimeSection(groupType, groupName) {
    normalizedType := (StrLower(Trim(groupType)) == "menu") ? "Menu" : "Space"
    normalizedName := Trim(groupName)
    if (normalizedName == "")
        normalizedName := "Default"
    return "Group_" . normalizedType . "_" . normalizedName
}

HotstringGetRuntimeGroupType(groupSection) {
    if (SubStr(groupSection, 1, 11) == "Group_Menu_")
        return "Menu"
    return "Space"
}

HotstringGetRuntimeGroupName(groupSection) {
    if (SubStr(groupSection, 1, 12) == "Group_Space_")
        return SubStr(groupSection, 13)
    if (SubStr(groupSection, 1, 11) == "Group_Menu_")
        return SubStr(groupSection, 12)
    return groupSection
}

; Hotstring values are read back one key at a time, and Windows strips a matched
; surrounding pair of quotes — double or single — from a key-mode read. Measured:
; "As discussed" comes back as As discussed and '확인' as 확인, and the next save
; then writes the stripped text, so the quotes are gone for good. A quote inside
; the text (say "hi" now, it's fine) is untouched, and only this codec is
; exposed: folders, prompts and key remaps are read in section mode, which
; returns the raw line.
; "%" is encoded first, so no escape sequence here can be produced by accident.
HotstringEncodeIniValue(value) {
    value := StrReplace(value, "%", "%25")
    value := StrReplace(value, '"', "%22")
    value := StrReplace(value, "'", "%27")
    value := StrReplace(value, "`r", "%0D")
    value := StrReplace(value, "`n", "%0A")
    return value
}

; Mirror image: "%25" must be decoded last, or it would revive the escapes above.
HotstringDecodeIniValue(value) {
    value := StrReplace(value, "%0D", "`r")
    value := StrReplace(value, "%0A", "`n")
    value := StrReplace(value, "%22", '"')
    value := StrReplace(value, "%27", "'")
    value := StrReplace(value, "%25", "%")
    return value
}

; How many hotstrings a read actually produced, across every group.
ConfigCountHotstringItems(hotstringData) {
    total := 0
    for groupSection in hotstringData.GroupOrder {
        if hotstringData.Data.Has(groupSection)
            total += hotstringData.Data[groupSection].Length
    }
    return total
}

; Whether a settings file holds anything beyond its bookkeeping section. Used to
; tell "this file is empty" apart from "this file has content nothing could
; read", which are the same to a reader but opposite when deciding to overwrite.
ConfigHasContentSections(configName) {
    sections := ConfigReadSections(configName)
    if (sections == "")
        return false
    loop parse, sections, "`n", "`r" {
        name := Trim(A_LoopField)
        if (name != "" && name != "Meta")
            return true
    }
    return false
}

ConfigCountHotstrings() {
    counts := { Space: 0, Menu: 0, Total: 0 }
    hotstringData := ConfigReadHotstringData()
    for groupSection in hotstringData.GroupOrder {
        if !hotstringData.Data.Has(groupSection)
            continue
        itemCount := hotstringData.Data[groupSection].Length
        if (HotstringGetRuntimeGroupType(groupSection) == "Menu")
            counts.Menu += itemCount
        else
            counts.Space += itemCount
        counts.Total += itemCount
    }
    return counts
}

ConfigReadKeyRemaps() {
    remaps := []
    content := ConfigReadSection("KeyRemaps", "Remaps", "")

    if (content != "") {
        loop parse, content, "`n", "`r" {
            pair := ParseIniKeyValuePairs(A_LoopField)
            if (pair.Key != "")
                remaps.Push({ Src: pair.Key, Dst: pair.Val })
        }
    }

    return remaps
}

ConfigWriteKeyRemaps(remaps) {
    content := ""
    for item in remaps {
        content .= item.Src . "=" . item.Dst . "`n"
    }
    ConfigWriteSection("KeyRemaps", "Remaps", content)
}

ConfigCountPairs(configName, section) {
    count := 0
    content := ConfigReadSection(configName, section, "")
    loop parse, content, "`n", "`r" {
        if (ParseIniKeyValuePairs(A_LoopField).Key != "")
            count++
    }
    return count
}

ConfigArrayHasValue(arr, val) {
    for item in arr {
        if (item == val)
            return true
    }
    return false
}

; =============================================================================
; SECTION: Default Config Data Templates
; =============================================================================
GetDefaultFolderData() {
    return "[Settings]`n"
    . "MainHotkey=F1`n"
    . "PromptModifier=#`n"
    . "PromptUseNumpad=1`n"
    . "ManualLanguage=EN`n`n"
    . "[FolderMenu]`n"
    . "💾 C-Drive=C:\`n"
    . "-=-`n"
    . "📥 Downloads=" . EnvGet("USERPROFILE") . "\Downloads`n"
        . "🖥️ Desktop=" . A_Desktop . "`n"
        . "📄 Documents=" . A_MyDocuments . "`n"
        . "-=-`n"
        . "🚀 Startup=" . A_Startup . "`n"
        . "⚙️ AppData (Roaming)=" . A_AppData . "`n"
}

GetDefaultHotkeyData() {
    return "[Meta]`n"
    . "PromptEncoding=2`n`n"
    . "[Numpad1]`n"
    . "1 Outlook Active Email Analyzer=Please analyze this email thread and provide a highly condensed, dense summary in Korean. 1. If I am in CC (Cc/참조), outline the full context, background discussion, and core consensus of the entire thread so I don't miss the big picture. 2. For Tax/Legal/Compliance issues, detail the precise root cause, legal grounds/clauses, and technical terms. 3. For IT System/Finance/Sales improvements, clearly list: Who, What, Why, and the Risks if ignored. Output Style: Keep it extremely compact and space-efficient. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines between sections, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "2 Outlook Draft Business Reply=Write a polite and professional reply email in Korean and in English based on the following key points: [insert]. Ensure a formal business tone suitable for corporate communications. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "3 Outlook Terminology & Abbreviation Decoder=Analyze the email and explain any industry-specific jargon, technical terms, or abbreviations in Korean with simple, clear definitions. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "4 Outlook Recipient & Org Analyzer=Please analyze the recipients (To, Cc) of this email thread and identify the [organizations] in Korean. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n`n"
    . "[Numpad2]`n"
    . "1 Edge Active Page Analyzer=Please analyze the active document/page and provide a concise summary in Korean. First, identify the document type and characteristics (e.g., action-oriented task, informational report, legal/regulatory clause). Then, dynamically highlight approximately three key takeaways tailored to its type: if it requires action, outline the specific next steps; if it is for information, summarize the core concepts to understand; if it carries legal or compliance requirements, point out the essential obligations. Adapt the focus flexibly based on the document's nature. Output Style: Keep it extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines between sections, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "2 Edge Terminology & Abbreviation Decoder=Analyze the active document and explain any industry-specific jargon, technical terms, or abbreviations in Korean with simple, clear definitions. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "3 Edge Contract & Risk Analysis=Please analyze this document or contract and provide a highly condensed review in Korean. First, identify the document type and characteristics. 1) B2B Commercial Transactions: Highlight payment terms, liability limits, termination, acceptance terms, and penalties. 2) Service Agreements (SLA): Focus on SOW, SLA targets, IP ownership, confidentiality, and performance penalties. 3) Tax/Transfer Pricing (TP/CIP/VAT): Focus on tax compliance risks, transfer pricing alignments, customs/declarations, and liabilities. 4) HR/Labor/General Legal: Focus on employment terms, non-competes, compliance with labor standards, and dispute resolution. Dynamically list critical risks (if any). Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n`n"
    . "[Numpad3]`n"
    . "1 AI C-Level Business Drafter=Act as a Top-Tier Management Consultant and Senior Executive Assistant. Draft a highly professional, persuasive, and diplomatically polite business email/proposal based on the following context: [목적 및 핵심 전달 사항 입력]. Structure it logically with a clear introduction, bulleted main points for readability, and a strong call-to-action (CTA). Ensure the tone is C-level appropriate, avoiding fluff. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "2 AI Report Synthesizer=Act as a Senior Business Analyst. Analyze the following raw data, meeting transcript, or complex report text: [방대한 데이터 또는 난해한 텍스트 입력]. Extract the signal from the noise and synthesize it into a structured Executive Summary. Provide: 1. Core Issue/Objective. 2. 3 Key Takeaways (Data-backed if possible). 3. Immediate Action Items (Who needs to do what). Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "3 AI Strategy CSO Reviewer=Act as a sharp, experienced Chief Strategy Officer (CSO). Review the following draft proposal/idea: [기획안/아이디어 초안 입력]. I want ruthless but constructive feedback. 1. Identify logical gaps, weak arguments, or unaddressed risks. 2. Suggest specific, actionable improvements to make it bulletproof. 3. Provide an optimized, polished version of the core pitch. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks.`n"
    . "4 AI Corporate Translator=Act as an Expert Corporate Bilingual Translator. Translate the following text into [Target Language, default: Korean]: [번역할 텍스트 입력]. Do not translate literally word-for-word. Instead, capture the underlying business nuance, industry standard terminology, and professional tone. Elevate informal source text to a formal corporate standard. Provide only the translated result without conversational filler. Output Style: Extremely compact. Use only single newlines (\\n) for line breaks. Never use double newlines (\\n\\n) or blank lines, so that when copied, the entire output pastes as a single, cohesive, tightly spaced text block while preserving the exact line breaks."
}

GetDefaultHotstringData() {
    return "[Meta]`n"
    . "SchemaVersion=4`n`n"
    . "[Groups]`n"
    . "Count=5`n"
    . "Group001Id=Group001`n"
    . "Group001Type=Space`n"
    . "Group001Name=Bullets_Indicators`n"
    . "Group002Id=Group002`n"
    . "Group002Type=Space`n"
    . "Group002Name=Math`n"
    . "Group003Id=Group003`n"
    . "Group003Type=Space`n"
    . "Group003Name=Arrows`n"
    . "Group004Id=Group004`n"
    . "Group004Type=Space`n"
    . "Group004Name=Currency`n"
    . "Group005Id=Group005`n"
    . "Group005Type=Space`n"
    . "Group005Name=For_Email`n`n"
    . "[Group001]`n"
    . "ItemCount=8`n"
    . "Item001Key=z.z`n"
    . "Item001Val=▣`n"
    . "Item002Key=x.x`n"
    . "Item002Val=※`n"
    . "Item003Key=c.c`n"
    . "Item003Val=⊙`n"
    . "Item004Key=***.`n"
    . "Item004Val=★`n"
    . "Item005Key=**.`n"
    . "Item005Val=☆`n"
    . "Item006Key=v.v`n"
    . "Item006Val=✓`n"
    . "Item007Key=q.q`n"
    . "Item007Val=☑`n"
    . "Item008Key=r.r`n"
    . "Item008Val=☞`n`n"
    . "[Group002]`n"
    . "ItemCount=5`n"
    . "Item001Key=d.d`n"
    . "Item001Val=Δ`n"
    ; Underscore-prefixed, like the Currency and Email groups. The obvious
    ; spellings (+-, !=, >=, <=) cannot ship on by default because they are real
    ; operators — "WHERE amount >= 1000" in SQL, or an Excel comparison, would be
    ; silently replaced. Dotted forms are no good either: these fire after an
    ; ending character, so "p.m" would trigger on "5:30 p.m." and "a.r" on
    ; "A.R. Smith", which is worse in the business email this app is aimed at.
    ; An underscore cannot begin inside a word.
    . "Item002Key=_pm`n"
    . "Item002Val=±`n"
    . "Item003Key=_ne`n"
    . "Item003Val=≠`n"
    . "Item004Key=_ge`n"
    . "Item004Val=≥`n"
    . "Item005Key=_le`n"
    . "Item005Val=≤`n`n"
    . "[Group003]`n"
    . "ItemCount=7`n"
    ; ">>" and "<<" are shell redirection, bit shifts and markdown quoting, so
    ; they cannot ship on by default either.
    . "Item001Key=_ar`n"
    . "Item001Val=→`n"
    . "Item002Key=_al`n"
    . "Item002Val=←`n"
    . "Item003Key=0++`n"
    . "Item003Val=↑`n"
    . "Item004Key=0--`n"
    . "Item004Val=↓`n"
    . "Item005Key=<->`n"
    . "Item005Val=↔`n"
    . "Item006Key=t.t`n"
    . "Item006Val=▶`n"
    . "Item007Key=y.y`n"
    . "Item007Val=▷`n`n"
    . "[Group004]`n"
    . "ItemCount=12`n"
    . "Item001Key=_usd`n"
    . "Item001Val=$`n"
    . "Item002Key=_eur`n"
    . "Item002Val=€`n"
    . "Item003Key=_gbp`n"
    . "Item003Val=£`n"
    . "Item004Key=_chf`n"
    . "Item004Val=₣`n"
    . "Item005Key=_pln`n"
    . "Item005Val=zł`n"
    . "Item006Key=_czk`n"
    . "Item006Val=Kč`n"
    . "Item007Key=_huf`n"
    . "Item007Val=Ft`n"
    . "Item008Key=_ron`n"
    . "Item008Val=lei`n"
    . "Item009Key=_bgn`n"
    . "Item009Val=лв`n"
    . "Item010Key=_try`n"
    . "Item010Val=₺`n"
    . "Item011Key=_rub`n"
    . "Item011Val=₽`n"
    . "Item012Key=_krw`n"
    . "Item012Val=₩`n`n"
    . "[Group005]`n"
    . "ItemCount=5`n"
    . "Item001Key=_br`n"
    . "Item001Val=Best regards,`n"
    . "Item002Key=_tr`n"
    . "Item002Val=Thanks and regards,`n"
    . "Item003Key=_fyi`n"
    . "Item003Val=For your information,`n"
    . "Item004Key=_fya`n"
    . "Item004Val=For your action,`n"
    . "Item005Key=_asap`n"
    . "Item005Val=as soon as possible"
}

GetDefaultKeyRemapData() {
    return "[Remaps]`n"
    . "; Format: SourceKey=DestinationKey`n"
    . "; Example: CapsLock=LButton`n"
    . "; Example: ScrollLock=Tab"
}

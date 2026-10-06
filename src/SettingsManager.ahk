; SettingsManager.ahk - Per-User file-based configuration manager.
; Standardized configuration layout for PL Suite applications (App01 ~ App10).
;
; Standard Layout:
; %LOCALAPPDATA%\Programs\SwiftDeck\UserSetting\config.ini

global CONFIG_DIR := A_ScriptDir "\UserSetting"
global CONFIG_FILE := CONFIG_DIR "\config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck"

GetSettingSection(key) {
    switch key {
        case "MainHotkey", "PromptModifier", "PromptUseNumpad", "EmojiHotkey", "ExitHotkey", "AddFolderHotkey":
            return "Shortcuts"
        case "MigratedFromRegistry":
            return "System"
        case "ManualLanguage", "AutoStart", "RunAtStartup", "Theme":
            return "General"
        default:
            return "General"
    }
}

EnsureSettingsMigration() {
    global CONFIG_DIR, CONFIG_FILE, REG_PATH
    ; If config.ini already exists, do not overwrite with legacy registry values.
    if FileExist(CONFIG_FILE)
        return false

    hasRegistry := false
    try {
        loop reg, REG_PATH, "V" {
            hasRegistry := true
            break
        }
    } catch {
        hasRegistry := false
    }

    if !hasRegistry
        return false

    try {
        if !DirExist(CONFIG_DIR)
            DirCreate(CONFIG_DIR)
    } catch {
        return false
    }

    migratedCount := 0
    try {
        loop reg, REG_PATH, "V" {
            valName := A_LoopRegName
            if (valName == "")
                continue
            try {
                val := RegRead(REG_PATH, valName)
                section := GetSettingSection(valName)
                IniWrite(String(val), CONFIG_FILE, section, valName)
                migratedCount++
            }
        }
        if (migratedCount > 0)
            IniWrite("1", CONFIG_FILE, "System", "MigratedFromRegistry")
    } catch {
        ; Ignore partial errors during migration
    }
    return migratedCount > 0
}

TryReadLocalSetting(key, &value) {
    global CONFIG_FILE, REG_PATH
    static NOT_FOUND := Chr(0x1F)

    ; 1. Try reading from UserSetting\config.ini first
    try {
        if FileExist(CONFIG_FILE) {
            section := GetSettingSection(key)
            val := IniRead(CONFIG_FILE, section, key, NOT_FOUND)
            if (val != NOT_FOUND) {
                value := val
                return true
            }
        }
    } catch {
        ; Fall through to legacy registry fallback
    }

    ; 2. Legacy registry fallback if not found in INI
    try {
        val := RegRead(REG_PATH, key)
        value := String(val)
        return true
    } catch {
        value := ""
        return false
    }
}

SafeWriteLocalSetting(value, key) {
    global CONFIG_DIR, CONFIG_FILE
    try {
        if !DirExist(CONFIG_DIR)
            DirCreate(CONFIG_DIR)
        section := GetSettingSection(key)
        IniWrite(String(value), CONFIG_FILE, section, key)
        return true
    } catch {
        return false
    }
}

; Backward-compatibility wrapper for existing SafeRegWriteString calls
SafeRegWriteString(value, regPath, valueName) {
    return SafeWriteLocalSetting(value, valueName)
}

DeleteLegacyStartupRegistry() {
    runKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    legacyNames := ["SwiftDeck", "App02_SwiftDeck", "FolderHotKey", "AHK_FolderHotKey"]
    for name in legacyNames {
        try RegDelete(runKey, name)
    }
}

CleanLegacyShortcuts() {
    legacyPaths := [
        A_Startup "\FolderHotKey.lnk",
        A_Startup "\AHK_FolderHotKey.lnk",
        A_Startup "\App02_SwiftDeck.lnk",
        A_Desktop "\FolderHotKey.lnk",
        A_Desktop "\AHK_FolderHotKey.lnk",
        A_Desktop "\App02_SwiftDeck.lnk",
        A_Programs "\FolderHotKey.lnk",
        A_Programs "\AHK_FolderHotKey.lnk",
        A_Programs "\App02_SwiftDeck.lnk"
    ]
    for p in legacyPaths {
        try {
            if FileExist(p)
                FileDelete(p)
        }
    }
    DeleteLegacyStartupRegistry()
}

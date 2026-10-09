#Requires AutoHotkey v2.0
#Include _TestHarness.ahk

global root := A_ScriptDir "\..\build\settings-tests-" DllCall("GetCurrentProcessId") "-" A_TickCount
global g_targetFolder := root "\new\"
global g_fileName_Folder := "App02_01FavFolderSetting_v2_DoNotDelete.ini"
global g_fileName_Hotkey := "App02_02HotkeySetting_v2_DoNotDelete.ini"
global g_fileName_Hotstring := "App02_03HotstringSetting_DoNotDelete.ini"
global g_fileName_KeyRemap := "App02_04KeyRemap_DoNotDelete.ini"
global g_filePath_Folder := g_targetFolder g_fileName_Folder
global g_filePath_Hotkey := g_targetFolder g_fileName_Hotkey
global g_filePath_Hotstring := g_targetFolder g_fileName_Hotstring
global g_filePath_KeyRemap := g_targetFolder g_fileName_KeyRemap
global g_appVersion := "migration-tests"

#Include ..\src\lib\Config.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" DllCall("GetCurrentProcessId")

legacy := root "\roaming\"
older := root "\older\"
DirCreate(legacy)
DirCreate(older)
DirCreate(g_targetFolder)
for fileDef in ConfigGetManagedFiles() {
    if fileDef.CanonicalName != "LocalSettings"
        FileAppend("[Settings]`nMainHotkey=F3`nExitHotkey=F7`n[Data]`nText=한글`n", legacy fileDef.FileName, "UTF-16")
}
FileAppend("[Settings]`nMainHotkey=F5`nExitHotkey=F6`n", g_filePath_Folder, "UTF-16")
SettingsWriteIniValues(CONFIG_FILE, [{Section: "Shortcuts", Key: "MainHotkey", Value: "F8"},
    {Section: "Shortcuts", Key: "PromptModifier", Value: ""}])
AssertTrue(ConfigMigrateLegacySettings([legacy, older]), "First copy migration completes")
AssertEqual(IniRead(g_filePath_Folder, "Settings", "MainHotkey"), "F5", "Destination file wins")
AssertTrue(ConfigFilesHaveSameBytes(legacy g_fileName_Hotkey, g_filePath_Hotkey), "Unicode source copied byte-for-byte")
AssertTrue(FileExist(legacy g_fileName_Hotkey), "Original Roaming settings retained")
ConfigMigrateLegacyAppSettings()
AssertEqual(IniRead(CONFIG_FILE, "Shortcuts", "MainHotkey"), "F8", "Existing local shortcut wins")
AssertEqual(IniRead(CONFIG_FILE, "Shortcuts", "ExitHotkey"), "F6", "Missing shortcut copied from selected folder file")
AssertEqual(ConfigReadAppSettings().PromptModifier, "", "Explicit empty modifier never replaced by legacy default")
FileDelete(g_filePath_Hotstring)
AssertEqual(ConfigMigrateLegacySettings([legacy]), false, "Completed migration is not repeated")
AssertEqual(FileExist(g_filePath_Hotstring), "", "Intentionally removed file is not reimported")
FileCopy(legacy g_fileName_Hotstring, g_filePath_Hotstring)

before := FileRead(CONFIG_FILE, "RAW")
legacyBefore := FileRead(g_filePath_Folder, "UTF-16")
locked := FileOpen(CONFIG_FILE, "r-wd")
failed := false
try ConfigWriteAppSettings("F9", "^", 0, "^Space", "^Escape")
catch
    failed := true
locked.Close()
AssertTrue(failed, "Locked destination reports batch save failure")
AssertEqual(IniRead(CONFIG_FILE, "Shortcuts", "MainHotkey"), "F8", "Failed batch keeps original first key")
AssertEqual(IniRead(CONFIG_FILE, "Shortcuts", "ExitHotkey"), "F6", "Failed batch keeps original last key")
ConfigWriteAppSettings("F9", "^", 0, "^Space", "^Escape")
AssertEqual(ConfigReadAppSettings().MainHotkey, "F9", "Single-store shortcut save succeeds")
AssertEqual(FileRead(g_filePath_Folder, "UTF-16"), legacyBefore, "Shortcut save does not dual-write legacy file")
BackupConfigs(false)
AssertTrue(FileExist(g_targetFolder "Backups\config.ini.bak"), "UI backup includes local shortcut settings")
AssertTrue(ConfigFilesHaveSameBytes(CONFIG_FILE, g_targetFolder "Backups\config.ini.bak"), "Shortcut backup contents verified")
rollbackDir := g_targetFolder "recovery-test\"
DirCreate(rollbackDir)
ConfigBackupCurrentFileForRollback(rollbackDir, CONFIG_FILE)
snapshot := [{Path: CONFIG_FILE, HadOriginal: true}]
ConfigWriteAppSettings("F10", "^", 0)
locked := FileOpen(CONFIG_FILE, "r-wd")
AssertEqual(ConfigRestoreFilesFromRollback(rollbackDir, snapshot), false, "Locked rollback explicitly fails")
locked.Close()
AssertTrue(FileExist(rollbackDir "config.ini.bak"), "Failed rollback retains the previous recovery copy")
AssertEqual(ConfigReadAppSettings().MainHotkey, "F10", "Failed rollback does not damage the current file")
AssertTrue(ConfigRestoreFilesFromRollback(rollbackDir, snapshot), "Recovery succeeds after the lock closes")
AssertEqual(ConfigReadAppSettings().MainHotkey, "F9", "Recovery restores original shortcut set")
created := g_targetFolder "newly-created.ini"
FileAppend("new", created)
AssertTrue(ConfigRestoreFilesFromRollback(rollbackDir, [{Path: created, HadOriginal: false}]), "Rollback removes a newly created managed file")
AssertEqual(FileExist(created), "", "Rollback returns an absent file to its original state")
ConfigMigrateLegacyAppSettings(true)
AssertEqual(ConfigReadAppSettings().MainHotkey, "F5", "Explicit legacy-backup restore imports old shortcuts")
AssertEqual(ConfigReadAppSettings().ExitHotkey, "F6", "Legacy restore preserves available shortcut set")
AssertTrue(InStr(ConfigGetDefaultText("LocalSettings"), "MainHotkey=F1"), "Factory reset writes explicit shortcuts rather than resurrecting registry")

; The isolated test registry key never points at the actual app's settings.
try {
    RegWrite("F2", "REG_SZ", REG_PATH, "MainHotkey")
    RegWrite("KO", "REG_SZ", REG_PATH, "ManualLanguage")
    locked := FileOpen(CONFIG_FILE, "r-wd")
    failed := false
    try EnsureSettingsMigration()
    catch
        failed := true
    locked.Close()
    AssertTrue(failed, "Registry migration propagates locked destination failure")
    AssertEqual(IniRead(CONFIG_FILE, "System", "MigratedFromRegistry", "0"), "0", "Failed registry migration does not mark completion")
    AssertTrue(EnsureSettingsMigration(), "Registry migration merges missing keys into an existing config")
    AssertEqual(ConfigReadAppSettings().MainHotkey, "F5", "Registry never replaces local shortcut")
    AssertEqual(IniRead(CONFIG_FILE, "General", "ManualLanguage"), "KO", "Missing registry setting joins the backup scope")
    RegWrite("DE", "REG_SZ", REG_PATH, "ManualLanguage")
    AssertEqual(EnsureSettingsMigration(), false, "Completed registry migration never repeats")
    AssertEqual(IniRead(CONFIG_FILE, "General", "ManualLanguage"), "KO", "Registry edits never override migrated settings")
} finally {
    RegDeleteKey(REG_PATH)
}

; A failed initial copy never creates the completion marker; no original is moved.
oldTarget := g_filePath_Hotkey
g_targetFolder := root "\blocked\"
DirCreate(g_targetFolder)
g_filePath_Folder := g_targetFolder g_fileName_Folder
g_filePath_Hotkey := g_targetFolder g_fileName_Hotkey
g_filePath_Hotstring := g_targetFolder g_fileName_Hotstring
g_filePath_KeyRemap := g_targetFolder g_fileName_KeyRemap
DirCreate(g_filePath_Hotkey)
failed := false
try ConfigMigrateLegacySettings([legacy])
catch
    failed := true
AssertTrue(failed, "Directory conflict rejects migration")
AssertEqual(FileExist(g_targetFolder ".legacy-files-migrated"), "", "Failed migration has no marker")
AssertTrue(FileExist(legacy g_fileName_Hotkey), "Failed migration retains original")
AssertTrue(ConfigFilesHaveSameBytes(legacy g_fileName_Folder, g_filePath_Folder), "Verified partial copy survives later failure")
DirMove(g_filePath_Hotkey, g_filePath_Hotkey ".retained", false)
AssertTrue(ConfigMigrateLegacySettings([legacy]), "Retry completes remaining files after conflict is resolved")
AssertTrue(ConfigFilesHaveSameBytes(legacy g_fileName_Hotkey, g_filePath_Hotkey), "Retry copy verified against original")

; Evidence remains in the unique build fixture folder.
TestsPassed("ConfigMigration (39 migration/save/backup checks)")

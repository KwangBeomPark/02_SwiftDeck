#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
#Include ..\src\SettingsManager.ahk

; Isolate test directory in temp
global testDir := A_Temp . "\swiftdeck-settings-test-" . A_TickCount
global CONFIG_DIR := testDir
global CONFIG_FILE := testDir . "\config.ini"

try {
    ; Test 1: GetSettingSection categorizes keys into correct sections
    AssertEqual(GetSettingSection("MainHotkey"), "Shortcuts", "MainHotkey section")
    AssertEqual(GetSettingSection("PromptModifier"), "Shortcuts", "PromptModifier section")
    AssertEqual(GetSettingSection("PromptUseNumpad"), "Shortcuts", "PromptUseNumpad section")
    AssertEqual(GetSettingSection("EmojiHotkey"), "Shortcuts", "EmojiHotkey section")
    AssertEqual(GetSettingSection("ExitHotkey"), "Shortcuts", "ExitHotkey section")
    AssertEqual(GetSettingSection("ManualLanguage"), "General", "ManualLanguage section")
    AssertEqual(GetSettingSection("RunAtStartup"), "General", "RunAtStartup section")
    AssertEqual(GetSettingSection("MigratedFromRegistry"), "System", "MigratedFromRegistry section")
    AssertEqual(GetSettingSection("UnknownCustomKey"), "General", "Unknown key defaults to General")

    ; Test 2: SafeWriteLocalSetting and TryReadLocalSetting roundtrip
    testKey := "TestRoundtripKey_" . A_TickCount
    testVal := "Value_" . A_TickCount
    AssertTrue(SafeWriteLocalSetting(testVal, testKey), "SafeWriteLocalSetting succeeded")

    readVal := ""
    AssertTrue(TryReadLocalSetting(testKey, &readVal), "TryReadLocalSetting succeeded")
    AssertEqual(readVal, testVal, "Roundtrip value matches")

    ; Test 3: EnsureSettingsMigration logic
    ; If config.ini exists, EnsureSettingsMigration returns false (does not overwrite)
    AssertEqual(EnsureSettingsMigration(), false, "EnsureSettingsMigration skips when config.ini exists")
} finally {
    if DirExist(testDir) {
        try DirDelete(testDir, 1)
    }
}

TestsPassed("SettingsManager")

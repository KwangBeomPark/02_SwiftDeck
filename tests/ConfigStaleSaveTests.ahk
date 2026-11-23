#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
; Stale saves. A settings tab is built once and only hidden on close, so its
; list can be older than the file: an edit made meanwhile (App Info opens the
; file in an editor; a sync program replaces it) used to be overwritten by the
; tab's next save. A list save now passes the fingerprint of the sections it
; rewrites, as last read, and is refused when the file no longer holds them.

global g_targetFolder := A_Temp . "\swiftdeck-stale-tests-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "\"
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
global g_appVersion := "stale-tests"

#Include ..\src\lib\Config.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder . "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" . DllCall("GetCurrentProcessId")

ExpectChanged(fn, label) {
    raised := ""
    try fn()
    catch ConfigChangedError as err
        raised := err.Message
    AssertTrue(raised != "", label . " is refused with ConfigChangedError")
    return raised
}

PromptTitles(slot) {
    s := ""
    for item in ConfigReadPromptData()[slot]
        s .= "[" . item.Title . "]"
    return s
}

DirCreate(g_targetFolder)
InitializeAllConfigs()

; --- Prompts ---
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
AssertEqual(read.Fingerprint, ConfigReadForSave("Prompts", ConfigReadPromptData).Fingerprint, "Two reads of an unchanged file agree")
ConfigWritePromptData(read.Data, , read.Fingerprint)
AssertTrue(true, "An unchanged prompt file saves")

read := ConfigReadForSave("Prompts", ConfigReadPromptData)
outside := ConfigReadPromptData()
outside[1].Push({ Title: "Added outside", Msg: "x" })
ConfigWritePromptData(outside)
mine := read.Data
mine[2].Push({ Title: "Added by the tab", Msg: "y" })
message := ExpectChanged(() => ConfigWritePromptData(mine, , read.Fingerprint), "Saving over a slot changed outside")
AssertTrue(InStr(message, "changed outside"), "The message says the file changed: " . message)
AssertTrue(InStr(PromptTitles(1), "[Added outside]"), "The outside change is kept")
AssertTrue(!InStr(PromptTitles(2), "[Added by the tab]"), "The refused change was not written")

; Sections the prompt save does not rewrite may change freely.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
ConfigWritePromptSlotName(3, "Renamed meanwhile")
mine := read.Data
mine[2].Push({ Title: "After a rename", Msg: "z" })
ConfigWritePromptData(mine, , read.Fingerprint)
AssertTrue(InStr(PromptTitles(2), "[After a rename]"), "A slot name changed meanwhile does not refuse the save")
AssertEqual(ConfigReadPromptSlotNames()[3], "Renamed meanwhile", "And the slot name is kept")

; A file that disappeared is not created again from the tab's list.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
FileMove(g_filePath_Hotkey, g_filePath_Hotkey . ".away")
try {
    message := ExpectChanged(() => ConfigWritePromptData(read.Data, , read.Fingerprint), "Saving to a removed prompt file")
    AssertTrue(InStr(message, "removed"), "The message says the file was removed: " . message)
    AssertTrue(!FileExist(g_filePath_Hotkey), "No new prompt file was created")
} finally {
    FileMove(g_filePath_Hotkey . ".away", g_filePath_Hotkey)
}

; Without a fingerprint (catalogs), a save behaves as before.
outside := ConfigReadPromptData()
outside[4].Push({ Title: "Unchecked save", Msg: "w" })
ConfigWritePromptData(outside)
AssertTrue(InStr(PromptTitles(4), "[Unchecked save]"), "A save without a fingerprint still writes")

; --- Hotstrings ---
read := ConfigReadForSave("Hotstrings", ConfigReadHotstringData)
outside := ConfigReadHotstringData()
firstGroup := outside.GroupOrder[1]
outside.Data[firstGroup].Push({ Key: "zqzq1outside", Val: "x", Mode: "" })
ConfigWriteHotstringData(outside.Data, outside.GroupOrder)
ExpectChanged(() => ConfigWriteHotstringData(read.Data.Data, read.Data.GroupOrder, read.Fingerprint), "Saving over hotstrings changed outside")
found := false
for item in ConfigReadHotstringData().Data[firstGroup]
    found := found || (item.Key == "zqzq1outside")
AssertTrue(found, "The outside hotstring is kept")

read := ConfigReadForSave("Hotstrings", ConfigReadHotstringData)
ConfigWriteValue("Hotstrings", "Meta", "Note", "changed meanwhile")
ConfigWriteHotstringData(read.Data.Data, read.Data.GroupOrder, read.Fingerprint)
AssertTrue(true, "A change to [Meta] alone does not refuse the hotstring save")

; --- Favorite folders: only [FolderMenu] counts ---
read := ConfigReadForSave("Folders", ConfigReadFolderItems)
ConfigWriteValue("Settings", "Settings", "ManualLanguage", "KO")
items := read.Data
items.Push({ Name: "Added by the tab", Path: "C:\" })
ConfigWriteFolderItems(items, read.Fingerprint)
names := ""
for item in ConfigReadFolderItems()
    names .= "[" . item.Name . "]"
AssertTrue(InStr(names, "[Added by the tab]"), "A settings value changed in the same file does not refuse the folder save")
AssertEqual(ConfigReadValue("Settings", "Settings", "ManualLanguage", ""), "KO", "And the settings value is kept")

read := ConfigReadForSave("Folders", ConfigReadFolderItems)
outside := ConfigReadFolderItems()
outside.Push({ Name: "Added outside", Path: "D:\" })
ConfigWriteFolderItems(outside)
ExpectChanged(() => ConfigWriteFolderItems(read.Data, read.Fingerprint), "Saving over folders changed outside")

; --- Key remapping ---
read := ConfigReadForSave("KeyRemaps", ConfigReadKeyRemaps)
outside := ConfigReadKeyRemaps()
outside.Push({ Src: "F13", Dst: "F14" })
ConfigWriteKeyRemaps(outside)
ExpectChanged(() => ConfigWriteKeyRemaps(read.Data, read.Fingerprint), "Saving over key mappings changed outside")
remapped := false
for item in ConfigReadKeyRemaps()
    remapped := remapped || (item.Src == "F13")
AssertTrue(remapped, "The outside key mapping is kept")

; How the slots read is part of the prompt list: a changed encoding marker refuses.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
ConfigWriteValue("Prompts", "Meta", "PromptEncoding", "1")
try {
    ExpectChanged(() => ConfigWritePromptData(read.Data, , read.Fingerprint), "Saving after the prompt encoding marker changed")
} finally {
    ConfigWriteValue("Prompts", "Meta", "PromptEncoding", String(ConfigGetPromptEncodingVersion()))
}

; A hotstring file holding only [Meta] is still checked.
SettingsWriteText(g_filePath_Hotstring, "[Meta]`r`nSchemaVersion=4`r`n")
read := ConfigReadForSave("Hotstrings", ConfigReadHotstringData)
AssertTrue(read.Fingerprint != "", "A file with no groups still has a fingerprint")
outside := ConfigReadHotstringData()
outside.Data["Group_Space_Added"] := [{ Key: "zqzq2outside", Val: "x", Mode: "" }]
outside.GroupOrder.Push("Group_Space_Added")
ConfigWriteHotstringData(outside.Data, outside.GroupOrder)
ExpectChanged(() => ConfigWriteHotstringData(read.Data.Data, read.Data.GroupOrder, read.Fingerprint),
    "Saving over a group added to an empty hotstring file")

; A change landing after the copy was checked, before the swap, is caught by
; the second check on the file itself.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
global g_hookCalls := 0
check := ConfigCheckUnchanged("Prompts", read.Fingerprint)
LateWriter(path, existed) {
    global g_hookCalls
    g_hookCalls++
    check(path, existed)
    if (g_hookCalls == 1) {
        late := ConfigReadPromptData()
        late[6].Push({ Title: "Landed late", Msg: "x" })
        ConfigWritePromptData(late)
    }
}
mine := read.Data
mine[7].Push({ Title: "Mine", Msg: "y" })
ExpectChanged(() => SettingsWriteIniValues(GetConfigPath("Prompts"), ConfigBuildPromptChanges(mine), LateWriter),
    "A change made between the copy and the swap")
AssertEqual(g_hookCalls, 2, "The check ran on the copy and again before the swap")
AssertTrue(InStr(PromptTitles(6), "[Landed late]"), "The late change is kept")

; Right before the swap the whole file must be as copied: the swap would also
; undo a change to a section this list does not cover.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
global g_hookCalls2 := 0
check2 := ConfigCheckUnchanged("Prompts", read.Fingerprint)
NameChangedMidSave(path, existed) {
    global g_hookCalls2
    g_hookCalls2++
    check2(path, existed)
    if (g_hookCalls2 == 1)
        ConfigWritePromptSlotName(5, "Named mid-save")
}
ExpectChanged(() => SettingsWriteIniValues(GetConfigPath("Prompts"), ConfigBuildPromptChanges(read.Data), NameChangedMidSave),
    "A slot name changed between the copy and the swap")
AssertEqual(ConfigReadPromptSlotNames()[5], "Named mid-save", "The slot name changed meanwhile is kept")

; A file gone after the last check is not created again by the swap.
read := ConfigReadForSave("KeyRemaps", ConfigReadKeyRemaps)
global g_hookCalls3 := 0
check3 := ConfigCheckUnchanged("KeyRemaps", read.Fingerprint)
RemovedAfterCheck(path, existed) {
    global g_hookCalls3
    g_hookCalls3++
    check3(path, existed)
    if (g_hookCalls3 == 2)
        FileMove(path, path . ".gone")
}
failedSwap := false
try SettingsWriteIniValues(GetConfigPath("KeyRemaps"), [{ Section: "Remaps", SectionText: "F19=F20`n" }], RemovedAfterCheck)
catch
    failedSwap := true
AssertTrue(failedSwap, "The swap fails when the file is gone")
AssertTrue(!FileExist(g_filePath_KeyRemap), "No key remap file was created")
FileMove(g_filePath_KeyRemap . ".gone", g_filePath_KeyRemap)

; A save reports what it wrote, from the copy that became the file, so the
; tab does not read the file again and take a later change for its own.
read := ConfigReadForSave("Prompts", ConfigReadPromptData)
mine := read.Data
mine[8].Push({ Title: "Written", Msg: "w" })
written := ConfigWritePromptData(mine, , read.Fingerprint)
AssertEqual(written.Fingerprint, ConfigReadForSave("Prompts", ConfigReadPromptData).Fingerprint,
    "The fingerprint a save reports is the file's")
late := ConfigReadPromptData()
late[9].Push({ Title: "Right after the save", Msg: "x" })
ConfigWritePromptData(late)
mine := ConfigReadParsed(Map("Prompts", written.Parsed), ConfigReadPromptData)
mine[8].Push({ Title: "Next save", Msg: "y" })
ExpectChanged(() => ConfigWritePromptData(mine, , written.Fingerprint), "The next save, after a change made right after the last one")
AssertTrue(InStr(PromptTitles(9), "[Right after the save]"), "The change made right after the save is kept")
for name in ["Folders", "Hotstrings", "KeyRemaps"] {
    reader := (name == "Folders") ? ConfigReadFolderItems : (name == "Hotstrings") ? ConfigReadHotstringData : ConfigReadKeyRemaps
    read := ConfigReadForSave(name, reader)
    written := (name == "Folders") ? ConfigWriteFolderItems(read.Data, read.Fingerprint)
        : (name == "Hotstrings") ? ConfigWriteHotstringData(read.Data.Data, read.Data.GroupOrder, read.Fingerprint)
        : ConfigWriteKeyRemaps(read.Data, read.Fingerprint)
    AssertEqual(written.Fingerprint, ConfigReadForSave(name, reader).Fingerprint, "The " . name . " save reports the file's fingerprint")
}

; The fingerprint covers what each save rewrites and nothing else.
parsed := IniParseText("[Numpad1]`na=1`n[SlotNames]`n1=x`n[Meta]`nPromptEncoding=2")
AssertTrue(!InStr(ConfigListFingerprint(parsed, "Prompts"), "SlotNames"), "Slot names are outside the prompt fingerprint")
parsed := IniParseText("[Meta]`nSchemaVersion=4`n[Groups]`nCount=1`n[Group001]`nItemCount=0")
fp := ConfigListFingerprint(parsed, "Hotstrings")
AssertTrue(InStr(fp, "[Groups]") && InStr(fp, "[Group001]") && !InStr(fp, "[Meta]"), "The hotstring fingerprint is every section but Meta")

TestFinishDirectory(g_targetFolder)
TestsPassed("ConfigStaleSave")

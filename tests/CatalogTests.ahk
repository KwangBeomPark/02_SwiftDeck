#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
; Catalogs: a .swiftdeck file has to carry prompts and hotstrings exactly as the
; live files hold them, a read may point the readers at it only while it runs,
; and adding or switching must change nothing but what was asked.

global g_targetFolder := A_Temp . "\swiftdeck-catalog-tests-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "\"
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
global g_appVersion := "catalog-tests"

#Include ..\src\lib\Catalog.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder . "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" . DllCall("GetCurrentProcessId")

PromptText(promptData) {
    text := ""
    loop 10 {
        num := A_Index - 1
        for item in promptData[num]
            text .= num . "|" . item.Title . "=" . item.Msg . "`n"
    }
    return text
}

HotstringText(hotstringData) {
    text := ""
    for section in hotstringData.GroupOrder {
        for item in hotstringData.Data[section]
            text .= section . "|" . item.Key . "=" . item.Val . "|" . HotstringGetMode(item) . "`n"
    }
    return text
}

EmptySlots() {
    slots := Map()
    loop 10
        slots[A_Index - 1] := []
    return slots
}

DirCreate(g_targetFolder)
InitializeAllConfigs()
backslash := Chr(92)
livePromptPath := GetConfigPath("Prompts")
liveHotstringPath := GetConfigPath("Hotstrings")

; My settings: a path, a newline with a key tag, quotes and a percent sign,
; a named slot, and an in-word hotstring.
mine := ConfigReadPromptData()
mine[1] := [{ Title: "Path", Msg: "Save to C:" . backslash . "new" . backslash . "report.xlsx" },
    { Title: "Two lines", Msg: "line one`nline two{Enter}" }]
mine[2] := [{ Title: "Quote", Msg: '"quoted" 100%' }]
ConfigWritePromptData(mine)
ConfigWritePromptSlotName(2, "Team & Co")
hot := ConfigReadHotstringData()
hot.Data["Group_Space_Mine"] := [{ Key: "s.s", Val: "Kind regards", Mode: "InWord" }]
hot.GroupOrder.Push("Group_Space_Mine")
ConfigWriteHotstringData(hot.Data, hot.GroupOrder)

; --- Saved and read back exactly ---
savedName := 'My "set" 100%'
savedPath := CatalogSaveCurrent(savedName).Path
AssertTrue(FileExist(savedPath) != "", "The catalog file is written")
AssertEqual(SubStr(savedPath, 1, StrLen(CatalogGetFolder())), CatalogGetFolder(), "It is kept in the catalog folder")
saved := CatalogRead(savedPath)
AssertEqual(saved.Info.Name, savedName, "The name survives the INI codec")
AssertEqual(GetConfigPath("Prompts"), livePromptPath, "Prompt reads point back at the live file afterwards")
AssertEqual(GetConfigPath("Hotstrings"), liveHotstringPath, "Hotstring reads point back at the live file afterwards")
AssertEqual(PromptText(saved.Prompts), PromptText(ConfigReadPromptData()), "Every prompt reads back as saved")
AssertEqual(saved.SlotNames[2], "Team & Co", "Slot names are kept")
AssertEqual(saved.SlotNames[1], "Outlook", "Default slot names are kept too")
AssertEqual(HotstringText(saved.Hotstrings), HotstringText(ConfigReadHotstringData()), "Every hotstring reads back with its mode")

; --- Files that are not catalogs this version reads ---
plain := g_targetFolder . "plain.ini"
FileAppend("[Other]`na=1`n", plain, "UTF-16")
AssertEqual(CatalogReadInfo(plain), "", "A plain INI file is not a catalog")
threw := false
try CatalogRead(plain)
catch
    threw := true
AssertTrue(threw, "Reading a non-catalog is refused")
AssertEqual(GetConfigPath("Prompts"), livePromptPath, "A refused read leaves the live paths alone")
newer := g_targetFolder . "newer.swiftdeck"
FileCopy(savedPath, newer)
IniWrite("2", newer, "Catalog", "Format")
AssertEqual(CatalogReadInfo(newer), "", "A catalog from a newer format is not read")
; Without the encoding and schema markers the readers would use the legacy
; rules: hotstrings read as none, a backslash-n in prompts read as a newline.
noSchema := g_targetFolder . "no-schema.swiftdeck"
FileCopy(savedPath, noSchema)
IniDelete(noSchema, "Meta", "SchemaVersion")
AssertEqual(CatalogReadInfo(noSchema), "", "A catalog without the hotstring schema is not read")
noEncoding := g_targetFolder . "no-encoding.swiftdeck"
FileCopy(savedPath, noEncoding)
IniDelete(noEncoding, "Meta", "PromptEncoding")
AssertEqual(CatalogReadInfo(noEncoding), "", "A catalog without the prompt encoding is not read")
; A damaged count is refused before anything loops over it.
huge := g_targetFolder . "huge.swiftdeck"
FileCopy(savedPath, huge)
IniWrite("99999999", huge, "Group001", "ItemCount")
started := A_TickCount
threw := false
try CatalogRead(huge)
catch
    threw := true
AssertTrue(threw && A_TickCount - started < 2000, "A catalog claiming millions of hotstrings is refused at once")
AssertEqual(GetConfigPath("Hotstrings"), liveHotstringPath, "A refused read leaves the live hotstring path alone")

; --- Listing: newest first, foreign files skipped ---
older := CatalogGetFolder() . "Older.swiftdeck"
CatalogWrite(older, "Older", EmptySlots(), Map(), { Data: Map(), GroupOrder: [] })
IniWrite("20200101000000", older, "Catalog", "Created")
FileAppend("[Junk]`n", CatalogGetFolder() . "junk.swiftdeck", "UTF-16")
listed := CatalogList()
AssertEqual(listed.Length, 2, "Only readable catalogs are listed")
AssertEqual(listed[1].Name . " / " . listed[2].Name, savedName . " / Older", "Newest first")
AssertEqual(CatalogFormatDate(listed[2].Created), "2020-01-01 00:00", "The date is shown readably")
emptyRead := CatalogRead(older)
AssertEqual(PromptText(emptyRead.Prompts) . HotstringText(emptyRead.Hotstrings), "", "An empty catalog reads as empty")

; --- Export only what was picked ---
picked := CatalogSelectForExport(ConfigReadPromptData(), ConfigReadPromptSlotNames(), ConfigReadHotstringData(),
    Map(2, true), Map("Group_Space_Mine", true))
exportPath := g_targetFolder . "Shared by me.swiftdeck"
CatalogWrite(exportPath, "Shared", picked.Prompts, picked.SlotNames, picked.Hotstrings)
shared := CatalogRead(exportPath)
AssertEqual(PromptText(shared.Prompts), "2|Quote=" . '"quoted" 100%' . "`n", "Only the picked slot is exported")
AssertEqual(shared.SlotNames[1] . "|" . shared.SlotNames[2], "|Team & Co", "Only the picked slot keeps its name")
AssertEqual(HotstringText(shared.Hotstrings), "Group_Space_Mine|s.s=Kind regards|InWord`n", "Only the picked group is exported")

; --- Import ---
target := CatalogImportTarget(exportPath)
AssertEqual(target, CatalogGetFolder() . "Shared by me.swiftdeck", "An import keeps the file's own name")
CatalogImport(exportPath, target)
AssertTrue(ConfigFilesHaveSameBytes(exportPath, target), "The imported copy is the file as received")
foreign := CatalogImportTarget(plain)
threw := false
try CatalogImport(plain, foreign)
catch
    threw := true
AssertTrue(threw && !FileExist(foreign), "A file that is not a catalog is refused and nothing is kept")
AssertEqual(CatalogSafeFileName('a/b:c*?"<>|'), "a_b_c______", "Characters Windows refuses are replaced")
AssertEqual(CatalogSafeFileName("  ..  "), "Catalog", "A name left empty falls back")
AssertEqual(CatalogSafeFileName("con"), "con_", "A reserved device name is not used as is")
longName := StrReplace(Format("{:59}", ""), " ", "a") . Chr(0x1F600)
AssertEqual(CatalogSafeFileName(longName), SubStr(longName, 1, 59), "A cut never keeps half of an emoji")

; Saving under a name that is taken never replaces that catalog.
firstSave := CatalogSaveCurrent("Same second")
FileCopy(firstSave.Path, g_targetFolder . "first-save.expect")
secondSave := CatalogSaveCurrent("Same second")
AssertEqual(secondSave.Name, "Same second (2)", "A taken name gets a number")
AssertTrue(firstSave.Path != secondSave.Path && ConfigFilesHaveSameBytes(firstSave.Path, g_targetFolder . "first-save.expect"),
    "The earlier catalog of that name is left as it was")

; --- Adding picked items plans a copy and keeps my triggers ---
other := { Prompts: EmptySlots(), SlotNames: Map(),
    Hotstrings: { Data: Map(
        "Group_Space_Arrows", [{ Key: ">>", Val: "⇒" }],
        "Group_Space_Team", [{ Key: "t.m", Val: "™", Mode: "InWord" }, { Key: "S.S", Val: "Cheers" }]),
        GroupOrder: ["Group_Space_Arrows", "Group_Space_Team"] } }
other.Prompts[3] := [{ Title: "Hello", Msg: "Hi{Tab}" }]
picks := [{ Kind: "Prompt", Slot: 3, Index: 1 },
    { Kind: "Hotstring", Section: "Group_Space_Arrows", Index: 1 },
    { Kind: "Hotstring", Section: "Group_Space_Team", Index: 1 },
    { Kind: "Hotstring", Section: "Group_Space_Team", Index: 2 }]
myPrompts := ConfigReadPromptData()
myHotstrings := ConfigReadHotstringData()
before := PromptText(myPrompts) . HotstringText(myHotstrings)
plan := CatalogPlanAdd(myPrompts, myHotstrings, other, picks)
AssertEqual(plan.AddedPrompts . " " . plan.AddedHotstrings, "1 1", "One prompt and one new hotstring are added")
AssertEqual(StrJoin(plan.Skipped), ">>, S.S", "Triggers I already have are skipped, ignoring case")
slot3 := plan.Prompts[3]
AssertEqual(slot3[slot3.Length].Title, "Hello", "The prompt goes to the end of its own slot")
team := plan.Hotstrings.Data["Group_Space_Team"]
AssertEqual(team.Length . " " . team[1].Key . " " . HotstringGetMode(team[1]), "1 t.m InWord", "A new hotstring keeps its mode")
AssertEqual(plan.Hotstrings.GroupOrder[plan.Hotstrings.GroupOrder.Length], "Group_Space_Team", "A new group goes last")
AssertEqual(PromptText(myPrompts) . HotstringText(myHotstrings), before, "Planning changes nothing it was given")
toSlot0 := CatalogPlanAdd(myPrompts, myHotstrings, other, [picks[1]], 0)
AssertEqual(toSlot0.Prompts[0][toSlot0.Prompts[0].Length].Title, "Hello", "A chosen slot takes the prompt instead")
; A menu-only group of a name I already use goes into my group of that name,
; and two triggers in the catalog that differ only in case add once.
menuOther := { Prompts: EmptySlots(), SlotNames: Map(),
    Hotstrings: { Data: Map("Group_Menu_mine", [{ Key: "k.k", Val: "K" }, { Key: "K.K", Val: "K2" }]),
        GroupOrder: ["Group_Menu_mine"] } }
menuPlan := CatalogPlanAdd(myPrompts, myHotstrings, menuOther,
    [{ Kind: "Hotstring", Section: "Group_Menu_mine", Index: 1 }, { Kind: "Hotstring", Section: "Group_Menu_mine", Index: 2 }])
AssertTrue(!menuPlan.Hotstrings.Data.Has("Group_Menu_mine"), "No second group of the same name is made")
mineGroup := menuPlan.Hotstrings.Data["Group_Space_Mine"]
AssertEqual(mineGroup[mineGroup.Length].Key . " " . StrJoin(menuPlan.Skipped), "k.k K.K", "Same-name items join my group; a case twin is skipped")

; --- Switching replaces prompts, slot names and hotstrings, and can go back ---
ConfigWritePromptData(shared.Prompts, shared.SlotNames)
ConfigWriteHotstringData(shared.Hotstrings.Data, shared.Hotstrings.GroupOrder)
names := ConfigReadPromptSlotNames()
AssertEqual(names[1] . "|" . names[2], "|Team & Co", "A switch replaces the slot names with the catalog's")
AssertEqual(PromptText(ConfigReadPromptData()), PromptText(shared.Prompts), "A switch replaces the prompts")
AssertEqual(HotstringText(ConfigReadHotstringData()), HotstringText(shared.Hotstrings), "A switch replaces the hotstrings")
back := CatalogRead(savedPath)
ConfigWritePromptData(back.Prompts, back.SlotNames)
ConfigWriteHotstringData(back.Hotstrings.Data, back.Hotstrings.GroupOrder)
AssertEqual(PromptText(ConfigReadPromptData()), PromptText(saved.Prompts), "The saved catalog brings the prompts back")
AssertEqual(HotstringText(ConfigReadHotstringData()), HotstringText(saved.Hotstrings), "The saved catalog brings the hotstrings back")
AssertEqual(ConfigReadPromptSlotNames()[1], "Outlook", "The saved catalog brings the slot names back")

TestFinishDirectory(g_targetFolder)
TestsPassed("Catalog")

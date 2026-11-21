#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
; The Emoji & Symbols menu used to list the built-in symbol sets and then every
; hotstring group beside them, so "Arrows" and "Math" each appeared twice and
; → ± ≠ ≥ ≤ ★ ☆ ※ ✓ ☑ $ € £ ₩ were offered in two places. Each category now takes
; in its hotstring groups, and a symbol is listed once.

global g_targetFolder := A_Temp . "\swiftdeck-emoji-tests-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "\"
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
global g_appVersion := "emoji-tests"

#Include ..\src\lib\EmojiPicker.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder . "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" . DllCall("GetCurrentProcessId")
#Include ..\src\lib\Migration.ahk

HotstringFixture(groups) {
    data := Map()
    order := []
    for group in groups {
        section := "Group_Space_" . group.Name
        items := []
        for pair in group.Items
            items.Push({ Key: pair[1], Val: pair[2] })
        data[section] := items
        order.Push(section)
    }
    return { Data: data, GroupOrder: order }
}

CategoryTitles(plan) {
    titles := []
    for category in plan.Categories
        titles.Push(category.Title)
    return StrJoin(titles, " | ")
}

FindCategory(plan, title) {
    for category in plan.Categories {
        if (category.Title == title)
            return category
    }
    throw Error("Category missing: " . title)
}

; Every symbol in the whole menu, in order, to check that none repeats.
CountTexts(plan) {
    counts := Map()
    for category in plan.Categories {
        for entry in category.Entries
            counts[entry.Text] := (counts.Has(entry.Text) ? counts[entry.Text] : 0) + 1
    }
    for group in plan.UserGroups {
        for entry in group.Entries
            counts[entry.Text] := (counts.Has(entry.Text) ? counts[entry.Text] : 0) + 1
    }
    return counts
}

AssertNoRepeats(plan, label) {
    for text, count in CountTexts(plan)
        AssertEqual(count, 1, label . ": '" . text . "' listed once")
}

; --- Shipped defaults ---
DirCreate(g_targetFolder)
InitializeAllConfigs()
defaults := ConfigReadHotstringData()

names := []
for section in defaults.GroupOrder
    names.Push(HotstringGetRuntimeGroupName(section))
AssertEqual(StrJoin(names), "Arrows, Math, Marks_Checks, Numbers, Currency, For_Email", "Default groups follow the menu categories")

seenKeys := Map()
seenKeys.CaseSense := false  ; hotstring triggers ignore case
seenVals := Map()
for section in defaults.GroupOrder {
    for item in defaults.Data[section] {
        AssertTrue(!seenKeys.Has(item.Key), "Default trigger '" . item.Key . "' is used once")
        AssertTrue(!seenVals.Has(item.Val), "Default value '" . item.Val . "' is used once")
        seenKeys[item.Key] := true
        seenVals[item.Val] := true
    }
}

; The owner's own triggers, not the underscore set 1.4.0 shipped.
math := defaults.Data["Group_Space_Math"]
AssertEqual(math[1].Key . " " . math[2].Key . " " . math[3].Key . " " . math[4].Key, "+- != >= <=", "Math keeps the operator triggers")
arrows := defaults.Data["Group_Space_Arrows"]
AssertEqual(arrows[1].Key . " " . arrows[2].Key, ">> <<", "Arrows keep the operator triggers")

numbers := defaults.Data["Group_Space_Numbers"]
AssertEqual(numbers.Length, 10, "Circled numbers stop at ten")
loop 10 {
    AssertEqual(numbers[A_Index].Key, A_Index . "..", "Trigger for circled " . A_Index)
    AssertEqual(Ord(numbers[A_Index].Val), 0x2460 + A_Index - 1, "Circled " . A_Index)
}

; --- Menu built from the defaults ---
plan := EmojiBuildMenuPlan(EmojiGetBuiltInGroups(), defaults)
AssertEqual(CategoryTitles(plan), "→  Arrows | ±  Math | ※  Marks & Checks | ①  Numbers | ₩  Currency & Units | 「  Brackets | 😀  Emoji",
    "One entry per category, in menu order")
AssertEqual(plan.UserGroups.Length, 1, "Only For_Email is left as its own group")
AssertEqual(plan.UserGroups[1].Name, "For_Email", "For_Email follows the categories")
AssertNoRepeats(plan, "Defaults")

arrowsMenu := FindCategory(plan, "→  Arrows").Entries
AssertEqual(arrowsMenu[1].Text . " " . arrowsMenu[1].Name . " " . arrowsMenu[1].Trigger, "→ Right >>", "A hotstring symbol keeps its name and trigger")
AssertEqual(EmojiEntryLabel(arrowsMenu[1]), "→   Right  [>>]", "Label of a symbol with a trigger")
lastArrow := arrowsMenu[arrowsMenu.Length]
AssertEqual(lastArrow.Text . " " . lastArrow.Trigger, "▼ ", "Built-in extras follow without a trigger")
AssertEqual(EmojiEntryLabel(lastArrow), "▼   Decrease", "Label of a symbol without a trigger")

numbersMenu := FindCategory(plan, "①  Numbers").Entries
AssertEqual(numbersMenu.Length, 10, "Numbers lists ① to ⑩ once")
AssertEqual(EmojiEntryLabel(numbersMenu[10]), "⑩   Ten  [10..]", "⑩ shows its trigger")

marks := FindCategory(plan, "※  Marks & Checks").Entries
AssertEqual(marks[1].Text . marks[1].Trigger, "※x.x", "Marks start with the hotstrings")
foundCircle := false
for entry in marks {
    if (entry.Text == "●")
        foundCircle := (entry.Trigger == "")
}
AssertTrue(foundCircle, "Marks still offer built-in symbols with no hotstring")

marksDefaults := defaults.Data["Group_Space_Marks_Checks"]
middleDot := marksDefaults[marksDefaults.Length]
AssertEqual(middleDot.Key . " " . Format("U+{:04X}", Ord(middleDot.Val)) . " " . HotstringGetMode(middleDot),
    "m.m U+00B7 InWord", "The middle dot is typed inside a word")
middleDotTrigger := ""
for entry in marks {
    if (entry.Text == "·")
        middleDotTrigger .= "[" . entry.Trigger . "]"
}
AssertEqual(middleDotTrigger, "[m.m]", "The menu lists the middle dot once, with its trigger")

; --- Files written before the regrouping ---
legacy := HotstringFixture([
    { Name: "Bullets_Indicators", Items: [["z.z", "▣"], ["x.x", "※"], ["v.v", "✓"]] },
    { Name: "math", Items: [["+-", "±"], ["_pm", "±"]] },
    { Name: "Mine", Items: [["->", "→"], ["sig", "Kind regards"]] }
])
plan := EmojiBuildMenuPlan(EmojiGetBuiltInGroups(), legacy)
marks := FindCategory(plan, "※  Marks & Checks").Entries
AssertEqual(marks[1].Text . marks[2].Text . marks[3].Text, "▣※✓", "The old bullet group joins Marks & Checks")
mathMenu := FindCategory(plan, "±  Math").Entries
AssertEqual(mathMenu[1].Trigger . " " . mathMenu[2].Trigger, "+- _pm", "Group names match without case; both triggers for ± stay")
AssertEqual(plan.UserGroups.Length, 1, "A group no category names stays separate")
AssertEqual(plan.UserGroups[1].Name, "Mine", "The user's own group keeps its name")
for entry in FindCategory(plan, "→  Arrows").Entries
    AssertTrue(entry.Text != "→", "→ is not repeated in Arrows when another group types it")

; --- No hotstrings at all ---
plan := EmojiBuildMenuPlan(EmojiGetBuiltInGroups(), { Data: Map(), GroupOrder: [] })
AssertEqual(plan.Categories.Length, 7, "Every category still has built-in symbols")
AssertEqual(FindCategory(plan, "①  Numbers").Entries.Length, 10, "① to ⑩ are offered without hotstrings")
AssertEqual(plan.UserGroups.Length, 0, "No user groups")

TestFinishDirectory(g_targetFolder)
TestsPassed("EmojiMenu")

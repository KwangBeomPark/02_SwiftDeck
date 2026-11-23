#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
; Strict settings reads. IniRead returns the caller's default when a file is
; locked, missing for a moment or holds a section too large for Windows, so a
; reader saw "empty" and the next save deleted the real content. The settings
; files are now read once as text and parsed by IniParseText; these tests hold
; that parser to IniRead's results, and the strict read to failing loudly.

global g_targetFolder := A_Temp . "\swiftdeck-strict-tests-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "\"
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
global g_appVersion := "strict-tests"

#Include ..\src\lib\HotstringRuntime.ahk
#Include ..\src\lib\Catalog.ahk
global CONFIG_DIR := RTrim(g_targetFolder, "\")
global CONFIG_FILE := g_targetFolder . "config.ini"
global REG_PATH := "HKCU\Software\SwiftDeck-Tests-NoUserSettings\" . DllCall("GetCurrentProcessId")

; AssertEqual compares with "!=", which ignores case. These must not.
SameText(actual, expected, label) {
    if (actual !== expected)
        throw Error(label . ":`n  expected [" . expected . "]`n  got      [" . actual . "]")
}

Visible(s) => StrReplace(StrReplace(StrReplace(s, "`r", "\r"), "`n", "\n"), "`t", "\t")

; Every read the settings code makes, done by IniRead on the file and by the
; parser on the same text, must agree.
CompareWithWindows(text, label, encoding := "UTF-16") {
    path := g_targetFolder . "compare.ini"
    try FileDelete(path)
    FileAppend(text, path, encoding)
    parsed := IniParseText(ConfigReadFileText(path))
    where := label . " (" . encoding . ") in`n" . Visible(text)

    names := ""
    try names := IniRead(path)
    SameText(IniTextReadSectionNames(parsed), names, "section names, " . where)

    sections := ["Missing", "", " A ", "a", "A", "B", "b", "Alpha", "alpha", "ALPHA", "Beta"]
    loop parse, names, "`n"
        sections.Push(A_LoopField, StrLower(A_LoopField), StrUpper(A_LoopField), " " . A_LoopField . " ")
    keys := ["missing", "k", "K", "dup"]
    loop parse, text, "`n", "`r" {
        line := A_LoopField
        if (eq := InStr(line, "=")) {
            raw := SubStr(line, 1, eq - 1)
            keys.Push(raw, Trim(raw), StrLower(Trim(raw)), StrUpper(Trim(raw)))
        }
    }
    ; For a file without a UTF-16 BOM, Windows converts the requested name to
    ; the ANSI code page too, so a name it cannot represent matches whatever
    ; became "?" in the file. The app only ever asks for ASCII names.
    ansiFile := (encoding != "UTF-16")
    for section in sections {
        if (ansiFile && RegExMatch(section, "[^\x00-\x7F]"))
            continue
        SameText(IniTextReadSection(parsed, section, "<d>"), IniRead(path, section, , "<d>"),
            "section [" . section . "], " . where)
        for key in keys {
            if (key == "" || (ansiFile && RegExMatch(key, "[^\x00-\x7F]")))
                continue
            SameText(IniTextReadValue(parsed, section, key, "<d>"), IniRead(path, section, key, "<d>"),
                "key [" . section . "] " . key . ", " . where)
        }
    }
}

DirCreate(g_targetFolder)

; --- Hand-written cases: the rules the parser documents ---
tricky := "
(
orphan=before any section
[Alpha]
plain=one
 spaced key = spaced value
quoted="in quotes"
single='single q'
half="open only
inner=a "b" c
padded="  inside  "
emptyq=""
mixed="ab'
eq=a=b=c
empty=
;comment line
 ; indented comment
#hash=not a comment
noequals line
=no key
UPPER=Case
dup=first
dup=second
	tabbed	=	tab value
한글키=한글 값 😀
  [ Beta ]
k=v
[alpha]
again=second alpha
dup=third
[Gamma]trailing junk
g=1
[Broken
b=2
[Delta]
)"
CompareWithWindows(tricky, "hand-written, LF")
CompareWithWindows(StrReplace(tricky, "`n", "`r`n"), "hand-written, CRLF")
CompareWithWindows(StrReplace(tricky, "`n", "`r"), "hand-written, lone CR")
CompareWithWindows("[A]`r`nk=a`rb`r`nj=2`n`r`n[B]`rm=3", "mixed line ends")
; Files without a UTF-16 BOM are read in the system ANSI code page, a UTF-8
; BOM included: its bytes then hide the first header from Windows.
for encoding in ["CP0", "UTF-8-RAW", "UTF-8"]
    CompareWithWindows(StrReplace(tricky, "`n", "`r`n"), "hand-written", encoding)
CompareWithWindows("", "empty file")
CompareWithWindows("[A]", "header only")
CompareWithWindows("[A]`nk=1`n[]`nk=2`n[B]`nk=3", "an empty section name ends the names list")

; --- Generated cases, reproducible: a fixed linear congruential sequence ---
global g_seed := 20261122
NextRandom(count) {
    global g_seed
    g_seed := Mod(g_seed * 1103515245 + 12345, 2147483648)
    return Mod(g_seed // 65536, count) + 1
}
fragments := ["[A]", "[ a ]", "[B]x", "[A", "[b]", "`; c", "  `;c", "", "   ", "k=v", " K = v ", "k=`"q`"",
    "k='q'", "k=`"", "k=a=b", "k=", "=v", "noeq", "dup=1", "dup=2", "k2=`" x `"", "#k=h", "k=한글", "`tk`t=`tv`t",
    "k=a`rb", "[C]`rc=1"]
loop 120 {
    text := ""
    loop NextRandom(14) + 2
        text .= fragments[NextRandom(fragments.Length)] . "`n"
    CompareWithWindows(text, "generated case " . A_Index)
}

; --- The real files, as the app writes them ---
InitializeAllConfigs()
for fileDef in ConfigGetManagedFiles() {
    if FileExist(fileDef.Path)
        CompareWithWindows(FileRead(fileDef.Path), "default " . fileDef.FileName)
}

; --- Strict reads ---
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
    for section in hotstringData.GroupOrder
        for item in hotstringData.Data[section]
            text .= section . "|" . item.Key . "=" . item.Val . "|" . HotstringGetMode(item) . "`n"
    return text
}

SameText(PromptText(ConfigReadStrict("Prompts", ConfigReadPromptData)), PromptText(ConfigReadPromptData()),
    "A strict read of a healthy prompt file equals the normal read")
SameText(HotstringText(ConfigReadStrict("Hotstrings", ConfigReadHotstringData)), HotstringText(ConfigReadHotstringData()),
    "A strict read of a healthy hotstring file equals the normal read")
both := ConfigReadStrict(["Prompts", "Hotstrings"], () => { P: ConfigReadPromptData(), H: ConfigReadHotstringData() })
AssertTrue(both.P[1].Length > 0 && both.H.GroupOrder.Length > 0, "Several files can be read strictly together")
AssertEqual(g_configSnapshots.Count, 0, "No snapshot is left behind after a strict read")

FailingReader() {
    ConfigReadPromptData()
    throw Error("reader failed")
}
failed := ""
try ConfigReadStrict("Prompts", FailingReader)
catch Error as err
    failed := err.Message
AssertEqual(failed, "reader failed", "A failing reader's error reaches the caller")
AssertEqual(g_configSnapshots.Count, 0, "A failing reader leaves no snapshot behind")

ExpectReadError(fn, label) {
    raised := ""
    try fn()
    catch ConfigReadError as err
        raised := err.Message
    AssertTrue(raised != "", label . " raises ConfigReadError")
    return raised
}

; A file another program holds without sharing.
held := FileOpen(g_filePath_Hotkey, "rw -rwd")
try {
    message := ExpectReadError(() => ConfigReadStrict("Prompts", ConfigReadPromptData), "A held prompt file")
    AssertTrue(InStr(message, "in use"), "The message says the file is in use: " . message)
    AssertEqual(PromptText(ConfigReadPromptData()), "", "Why: the normal read of a held file comes back empty")
    ExpectReadError(() => ConfigWritePromptSlotName(1, "Renamed"), "Renaming a slot while the file is held")
} finally {
    held.Close()
}
AssertTrue(ConfigReadPromptSlotNames()[1] != "Renamed", "The held file kept its slot names")

; A file another program has open for writing (an editor saving in place):
; reading it could return half of it, so the read waits and then fails.
writer := FileOpen(g_filePath_Hotkey, "rw")
try {
    ExpectReadError(() => ConfigReadStrict("Prompts", ConfigReadPromptData), "A prompt file open for writing elsewhere")
} finally {
    writer.Close()
}

; A file missing for a moment.
FileMove(g_filePath_Hotkey, g_filePath_Hotkey . ".away")
try {
    message := ExpectReadError(() => ConfigReadStrict("Prompts", ConfigReadPromptData), "A missing prompt file")
    AssertTrue(InStr(message, "not found"), "The message says the file was not found: " . message)
} finally {
    FileMove(g_filePath_Hotkey . ".away", g_filePath_Hotkey)
}

; A section too large for Windows reads whole.
big := "`n[Numpad5]`n"
loop 700
    big .= "Title" . A_Index . "=" . StrReplace(Format("{:100}", ""), " ", "x") . "`n"
beforeBig := ConfigReadFileText(g_filePath_Hotkey)
FileAppend(big, g_filePath_Hotkey)
AssertTrue(StrLen(big) > 70000, "The oversized section is over the Windows read limit")
AssertEqual(ConfigReadPromptData()[5].Length, 0, "Why: Windows reads the oversized slot as empty")
AssertEqual(ConfigReadStrict("Prompts", ConfigReadPromptData)[5].Length, 700, "A strict read returns the oversized slot whole")
; Saving it whole is refused by the size check, instead of the slot being
; written back empty.
refused := ""
try ConfigWritePromptData(ConfigReadStrict("Prompts", ConfigReadPromptData))
catch Error as err
    refused := err.Message
AssertTrue(InStr(refused, "slot"), "Saving the oversized slot is refused, not emptied: " . refused)
FileDelete(g_filePath_Hotkey)
FileAppend(beforeBig, g_filePath_Hotkey, "UTF-16")

; A held catalog says it cannot be read, rather than that it is no catalog.
catalogPath := g_targetFolder . "Held.swiftdeck"
mine := CatalogReadCurrentSettings()
CatalogWrite(catalogPath, "Held", mine.Prompts, mine.SlotNames, mine.Hotstrings)
AssertEqual(CatalogRead(catalogPath).Info.Name, "Held", "The catalog reads while free")
held := FileOpen(catalogPath, "rw -rwd")
try {
    ExpectReadError(() => CatalogRead(catalogPath), "Reading a held catalog")
} finally {
    held.Close()
}

; Hotstrings stay registered when their file cannot be read.
custom := Map("Group_Space_StrictTest", [{ Key: "zqzqx1strict", Val: "unused" }])
ConfigWriteHotstringData(custom, ["Group_Space_StrictTest"])
LoadHotstrings(false)
before := g_registeredHotstrings.Length
AssertEqual(before, 1, "The test hotstring is registered")
held := FileOpen(g_filePath_Hotstring, "rw -rwd")
try {
    ExpectReadError(() => LoadHotstrings(false), "Reloading hotstrings from a held file")
} finally {
    held.Close()
}
AssertEqual(g_registeredHotstrings.Length, before, "The running hotstrings were kept")
FileMove(g_filePath_Hotstring, g_filePath_Hotstring . ".away")
try {
    ExpectReadError(() => LoadHotstrings(false), "Reloading hotstrings while the file is missing for a moment")
} finally {
    FileMove(g_filePath_Hotstring . ".away", g_filePath_Hotstring)
}
AssertEqual(g_registeredHotstrings.Length, before, "The running hotstrings were kept while the file was missing")
for spec in g_registeredHotstrings
    try Hotstring(spec, , "Off")

; One damaged count must not keep a reader busy: the walk is capped, and the
; real entries are still found.
damaged := StrReplace(ConfigReadFileText(g_filePath_Hotstring), "ItemCount=1", "ItemCount=999999999")
AssertTrue(InStr(damaged, "ItemCount=999999999"), "The hotstring file has a damaged count to test with")
FileDelete(g_filePath_Hotstring)
FileAppend(damaged, g_filePath_Hotstring, "UTF-16")
started := A_TickCount
damagedRead := ConfigReadStrict("Hotstrings", ConfigReadHotstringData)
AssertTrue(A_TickCount - started < 3000, "A damaged count is read within 3 s, took " . (A_TickCount - started) . " ms")
AssertEqual(HotstringText(damagedRead), "Group_Space_StrictTest|zqzqx1strict=unused|`n", "The real entry is still found")

TestFinishDirectory(g_targetFolder)
TestsPassed("ConfigStrictRead")

#Requires AutoHotkey v2.0
#Warn All, Off
; Round-trips prompt text through the real Config codec, and checks that a file
; written by an older version still reads the way it always did.

global g_out := A_Temp . "\swiftdeck-prompt-tests.txt"
global g_failures := 0
global g_targetFolder := A_Temp . "\swiftdeck-prompt-tests\"
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
global g_appVersion := "pe"

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
    ExitApp(3)
}

Visible(text) {
    s := StrReplace(text, "`r`n", "<CRLF>")
    s := StrReplace(s, "`n", "<LF>")
    return s
}

Fresh() {
    if DirExist(g_targetFolder)
        DirDelete(g_targetFolder, true)
    DirCreate(g_targetFolder)
    InitializeAllConfigs()
}

Run_() {
    if FileExist(g_out)
        FileDelete(g_out)
    Fresh()

    backslash := Chr(92)
    cases := [
        { Label: "Windows path",      Text: "Save it to C:" . backslash . "new" . backslash . "report.xlsx" },
        { Label: "backslash then n",  Text: "regex: " . backslash . "name" },
        { Label: "literal escape text", Text: "use " . backslash . "n for a line break" },
        { Label: "real newline",      Text: "line one`nline two" },
        { Label: "UNC path",          Text: "open " . backslash . backslash . "server" . backslash . "share" },
        { Label: "trailing backslash", Text: "folder is C:" . backslash },
        { Label: "Korean + path",     Text: "보고서를 C:" . backslash . "news 에 저장" },
        { Label: "plain text",        Text: "nothing special here" }
    ]

    data := Map()
    loop 10
        data[A_Index - 1] := []
    for c in cases
        data[0].Push({ Title: "Case" . A_Index, Msg: c.Text })

    ConfigWritePromptData(data)
    readBack := ConfigReadPromptData()

    for i, c in cases {
        got := readBack[0][i].Msg
        Check(got == c.Text, c.Label)
        if (got != c.Text) {
            Log("        wrote: " . Visible(c.Text))
            Log("        read : " . Visible(got))
        }
    }

    ; The other read path must agree with the first.
    items := ConfigReadPromptItems(0)
    Check(items.Length == cases.Length, "Both read paths return the same count")
    same := true
    for i, c in cases {
        if (items[i].msg != c.Text)
            same := false
    }
    Check(same, "ConfigReadPromptItems decodes identically")

    Log("")
    Log("encoding marker after write: " . ConfigReadPromptEncodingVersion())
    Check(ConfigReadPromptEncodingVersion() == 2, "The file records the new encoding")

    ; --- A file written by an older version must keep its old meaning ---
    Fresh()
    ; Strip the marker the shipped defaults now carry, so this is exactly what an
    ; existing user's file looks like: prompts in the old encoding, no [Meta].
    ConfigWriteSection("Prompts", "Meta", "")
    legacyBody := "Legacy=line one\nline two`n"
    . "UncPath=open " . Chr(92) . Chr(92) . "server" . Chr(92) . "share`n"
    ConfigWriteSection("Prompts", "Numpad0", legacyBody)
    Check(ConfigReadPromptEncodingVersion() == 1, "A file with no marker reads as legacy")
    legacyRead := ConfigReadPromptData()[0][1].Msg
    Log("legacy value decodes to: " . Visible(legacyRead))
    Check(legacyRead == "line one`nline two", "Legacy newline encoding still decodes to a newline")

    legacyUnc := ConfigReadPromptData()[0][2].Msg
    Log("legacy UNC decodes to  : " . Visible(legacyUnc))
    Check(legacyUnc == "open " . Chr(92) . Chr(92) . "server" . Chr(92) . "share",
        "A legacy UNC path is unchanged under the legacy rule")

    ; And once it is saved again, it migrates — values must survive that.
    migrated := ConfigReadPromptData()
    ConfigWritePromptData(migrated)
    Check(ConfigReadPromptEncodingVersion() == 2, "Saving migrates the file to the new encoding")
    Check(ConfigReadPromptData()[0][1].Msg == "line one`nline two", "Newline value survives migration")
    Check(ConfigReadPromptData()[0][2].Msg == "open " . Chr(92) . Chr(92) . "server" . Chr(92) . "share",
        "UNC path survives migration (the case v2 encoding would otherwise change)")

    ; --- The shipped defaults must show their instruction text literally ---
    Fresh()
    defaults := ConfigReadPromptData()
    found := ""
    for slot, items2 in defaults {
        for item in items2 {
            if InStr(item.Msg, "single newlines")
                found := item.Msg
        }
    }
    Check(found != "", "Found a shipped default prompt mentioning newlines")
    if (found != "") {
        hasLiteral := InStr(found, "(" . backslash . "n)") > 0
        Check(hasLiteral, "Default prompt shows (\n) as literal text, not a line break")
        excerpt := SubStr(found, InStr(found, "Use only single"), 60)
        Log("  default excerpt: " . Visible(excerpt))
    }

    ; --- Length limits must measure what is actually written ---
    Fresh()
    heavy := ""
    loop 20000
        heavy .= backslash
    Check(ConfigCheckPromptSlotLimit([{ Title: "Heavy", Msg: heavy }]) != "",
        "A backslash-heavy prompt is measured after encoding, not before")

    ; Encoding doubles those backslashes, so the stored form is what must fit.
    Check(StrLen(ConfigEncodePromptText(heavy)) == 40000, "Encoding doubles every backslash")

    ; --- A rejected save must leave the file exactly as it was ---
    Fresh()
    good := ConfigReadPromptData()
    goodFirst := good[0].Length ? good[0][1].Msg : ""
    beforeVersion := ConfigReadPromptEncodingVersion()

    broken := ConfigReadPromptData()
    broken[3].Push({ Title: "TooBig", Msg: heavy })
    threw := false
    try ConfigWritePromptData(broken)
    catch
        threw := true
    Check(threw, "An over-long slot is refused")

    after := ConfigReadPromptData()
    afterFirst := after[0].Length ? after[0][1].Msg : ""
    Check(afterFirst == goodFirst, "A refused save leaves the other slots untouched")
    Check(after[3].Length == good[3].Length, "A refused save does not partially apply")
    Check(ConfigReadPromptEncodingVersion() == beforeVersion,
        "A refused save does not change the encoding marker")

    try DirDelete(g_targetFolder, true)
    Log("")
    Log(g_failures ? ("RESULT: " . g_failures . " FAILURE(S)") : "RESULT: prompt encoding holds")
    ExitApp(g_failures ? 1 : 0)
}

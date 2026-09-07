#Requires AutoHotkey v2.0
#Warn All, Off
; Round-trips every settings codec through real files in a temp folder.
;
; The prompt codec had a silent data-loss bug for two years — a prompt holding a
; Windows path decoded into a line break — and it was found by exactly this kind
; of write-then-read check. The other three codecs had no equivalent coverage:
; folders and key remaps apply no encoding at all, and hotstrings use a third,
; different scheme.

global g_out := A_Temp . "\swiftdeck-codec-tests.txt"
global g_failures := 0

global g_targetFolder := A_Temp . "\swiftdeck-codec-tests\"
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
global g_appVersion := "codec-tests"

OnError(Report)
SetTimer(Run_, -200)

#Include ..\src\lib\Config.ahk
#Include ..\src\lib\Migration.ahk

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
    FileAppend("FAIL  ConfigCodec: " . err.Message . "`n", "*")
    ExitApp(3)
}

Filler(n) {
    return StrReplace(Format("{:" . n . "}", ""), " ", "x")
}

Visible(text) {
    s := StrReplace(text, "`r`n", "<CRLF>")
    s := StrReplace(s, "`n", "<LF>")
    s := StrReplace(s, "`t", "<TAB>")
    return s
}

Fresh() {
    if DirExist(g_targetFolder)
        DirDelete(g_targetFolder, true)
    DirCreate(g_targetFolder)
    InitializeAllConfigs()
}

; Every codec routes its values through ParseIniKeyValuePairs or IniRead, and both
; trim surrounding whitespace. An INI file cannot represent edge whitespace, so
; this is the documented limit rather than a defect — asserted here so that it
; stays a known limit instead of drifting into a surprise.
RoundTripExpectation(text) {
    return Trim(text)
}

; Values that have historically broken INI-backed storage.
AdversarialValues() {
    backslash := Chr(92)
    return [
        { Label: "plain",             Text: "Quarterly Report" },
        { Label: "Korean",            Text: "회사 공용 폴더" },
        { Label: "percent",           Text: "100% complete" },
        { Label: "percent-encoded",   Text: "already %25 encoded" },
        { Label: "equals",            Text: "a=b" },
        { Label: "quoted",            Text: '"quoted value"' },
        { Label: "interior quote",    Text: 'say "hi" now' },
        { Label: "double quote pair", Text: '""double""' },
        ; Windows strips single quotes exactly like double ones, and a wrapped
        ; word is ordinary business phrasing: '확인', 'draft', 'as-is'.
        { Label: "single quoted",     Text: "'single quoted'" },
        { Label: "single quoted KR",  Text: "'확인'" },
        { Label: "empty quote pair",  Text: "''" },
        { Label: "apostrophe",        Text: "it's fine" },
        { Label: "ragged quotes",     Text: "'x'y'" },
        { Label: "leading space",     Text: "  indented" },
        { Label: "trailing space",    Text: "trailing  " },
        { Label: "backslash-n",       Text: "C:" . backslash . "new" . backslash . "report" },
        { Label: "double backslash",  Text: backslash . backslash . "server" . backslash . "share" },
        { Label: "emoji",             Text: "📂 folder " . Chr(0x1F4C2) },
        { Label: "semicolon inside",  Text: "note" . Chr(59) . " then more" },
        { Label: "bracket inside",    Text: "Draft [2] final" }
    ]
}

Run_() {
    if FileExist(g_out)
        FileDelete(g_out)

    ; ---------- Folders ----------
    Fresh()
    Log("--- Folders (no encoding applied by the codec) ---")
    items := []
    for v in AdversarialValues()
        items.Push({ Name: "Fav" . A_Index, Path: v.Text })
    ConfigWriteFolderItems(items)
    readItems := ConfigReadFolderItems()
    Check(readItems.Length == items.Length, "Folders: every entry survives")
    for i, v in AdversarialValues() {
        if (i > readItems.Length)
            continue
        got := readItems[i].Path
        want := RoundTripExpectation(v.Text)
        ok := (got == want)
        Check(ok, "Folders path: " . v.Label)
        if (!ok) {
            Log("        wrote: " . Visible(v.Text))
            Log("        want : " . Visible(want))
            Log("        read : " . Visible(got))
        }
    }

    ; A favorite's display name is the INI key, which is the constrained side.
    Fresh()
    ConfigWriteFolderItems([{ Name: "R&D 회의록", Path: "C:\rd" }])
    named := ConfigReadFolderItems()
    Check(named.Length == 1 && named[1].Name == "R&D 회의록", "Folders: name with & and Korean survives")

    ; ---------- Key remaps ----------
    Fresh()
    Log("")
    Log("--- Key remaps ---")
    ConfigWriteKeyRemaps([{ Src: "CapsLock", Dst: "Ctrl" }, { Src: "^!k", Dst: "^c" }])
    remaps := ConfigReadKeyRemaps()
    Check(remaps.Length == 2, "KeyRemaps: both entries survive")
    Check(remaps.Length >= 1 && remaps[1].Src == "CapsLock" && remaps[1].Dst == "Ctrl", "KeyRemaps: plain pair")
    Check(remaps.Length >= 2 && remaps[2].Src == "^!k" && remaps[2].Dst == "^c", "KeyRemaps: modifier syntax")

    ; ---------- Hotstrings ----------
    Fresh()
    Log("")
    Log("--- Hotstrings (percent-encoded values) ---")
    groupSection := "Group_Space_TestGroup"
    hotData := Map()
    hotItems := []
    for v in AdversarialValues()
        hotItems.Push({ Key: "t" . A_Index, Val: v.Text })
    ; Multi-line replacement text is the reason this codec encodes at all.
    hotItems.Push({ Key: "multi", Val: "line one`nline two" })
    hotData[groupSection] := hotItems
    ConfigWriteHotstringData(hotData, [groupSection])

    back := ConfigReadHotstringData()
    Check(back.Data.Has(groupSection), "Hotstrings: the group is written and read back")
    if (back.Data.Has(groupSection)) {
        readHot := back.Data[groupSection]
        Check(readHot.Length == hotItems.Length, "Hotstrings: every item survives")
        for i, expected in hotItems {
            if (i > readHot.Length)
                continue
            got := readHot[i].Val
            want := RoundTripExpectation(expected.Val)
            ok := (got == want)
            label := (i <= AdversarialValues().Length) ? AdversarialValues()[i].Label : "multiline"
            Check(ok, "Hotstring value: " . label)
            if (!ok) {
                Log("        wrote: " . Visible(expected.Val))
                Log("        want : " . Visible(want))
                Log("        read : " . Visible(got))
            }
        }
    }

    ; A group name goes through the same encoder, and it is also the identity the
    ; runtime section key is built from — so a quote there has to survive both.
    Fresh()
    ; The name has to be wholly wrapped in quotes to be at risk: Windows only
    ; strips a matched surrounding pair, so a name with a quote in the middle
    ; would pass this test even with the escape removed.
    quotedGroup := 'Group_Space_"Client replies"'
    ConfigWriteHotstringData(Map(quotedGroup, [{ Key: "_hi", Val: "Hello" }]), [quotedGroup])
    reread := ConfigReadHotstringData()
    Check(reread.Data.Has(quotedGroup), "Hotstrings: a group name containing quotes round-trips")
    Check(reread.GroupOrder.Length == 1 && reread.GroupOrder[1] == quotedGroup,
        "Hotstrings: the quoted group keeps its place in the order")

    ; ---------- Replacement text that is too large to store ----------
    Fresh()
    Log("")
    Log("--- Hotstring size guard ---")
    sec := "Group_Space_Sized"
    ; Just under the limit still saves and reads back whole.
    ok := Filler(ConfigGetMaxValueLength() - 10)
    Check(ConfigCheckHotstringValueLimit(ok) == "", "A replacement just under the limit is accepted")
    ConfigWriteHotstringData(Map(sec, [{ Key: "_ok", Val: ok }]), [sec])
    sized := ConfigReadHotstringData()
    Check(sized.Data.Has(sec) && sized.Data[sec].Length == 1
        && StrLen(sized.Data[sec][1].Val) == StrLen(ok), "A large but legal replacement round-trips whole")

    ; An entry an earlier build saved can sit between the editor's limit and the
    ; hard ceiling. It still stores and reads back correctly, so the writer must
    ; accept it — refusing would lock that user out of saving any change at all.
    legacyBig := Filler(ConfigGetHotstringValueCeiling() - 100)
    Check(ConfigCheckHotstringValueLimit(legacyBig) != "",
        "The editor would not accept a value this long as new input")
    Check(ConfigCheckHotstringValueStorable(legacyBig) == "",
        "But the writer still stores it, because Windows can hold it")
    ConfigWriteHotstringData(Map(sec, [{ Key: "_legacy", Val: legacyBig }]), [sec])
    legacyRead := ConfigReadHotstringData()
    Check(legacyRead.Data.Has(sec) && legacyRead.Data[sec].Length == 1
        && StrLen(legacyRead.Data[sec][1].Val) == StrLen(legacyBig),
        "An oversized entry from an older build round-trips instead of being dropped")

    ; Restore the ordinary entry for the assertions below.
    ConfigWriteHotstringData(Map(sec, [{ Key: "_ok", Val: ok }]), [sec])

    ; Over the hard ceiling the writer refuses instead of storing a value it
    ; cannot read back.
    tooBig := Filler(ConfigGetHotstringValueCeiling() + 100)
    Check(ConfigCheckHotstringValueStorable(tooBig) != "", "An unstorable replacement is refused")
    refused := false
    try ConfigWriteHotstringData(Map(sec, [{ Key: "_big", Val: tooBig }]), [sec])
    catch
        refused := true
    Check(refused, "ConfigWriteHotstringData refuses rather than writing a value it cannot read back")
    afterRefusal := ConfigReadHotstringData()
    Check(afterRefusal.Data.Has(sec) && afterRefusal.Data[sec].Length == 1
        && afterRefusal.Data[sec][1].Key == "_ok", "The refused save leaves the existing entry untouched")

    ; The limit has to be measured after encoding: line breaks cost 6 characters
    ; each, so text well under the limit raw can still be over it once stored.
    breaks := ""
    loop 2000
        breaks .= "line" . A_Index . "`r`n"
    Check(StrLen(HotstringEncodeIniValue(breaks)) > StrLen(breaks),
        "Encoding expands line breaks, so the stored form is what must fit")

    ; ---------- Migration must never rewrite what it could not read ----------
    Fresh()
    Log("")
    Log("--- Hotstring migration safety ---")
    shipped := ConfigCountHotstringItems(ConfigReadHotstringData())
    Check(shipped > 0, "The shipped defaults contain hotstrings to lose")

    ; A hand edit that drops the schema marker. App Info offers to open this very
    ; file, and settings files get shared between machines, so this is reachable.
    text := FileRead(g_filePath_Hotstring, "UTF-16")
    ConfigWriteTextFileSafely(g_filePath_Hotstring, StrReplace(text, "SchemaVersion=4", ""), "UTF-16")
    Check(ConfigCountHotstringItems(ConfigReadHotstringData()) == 0,
        "Without the marker the legacy reader understands none of it")

    MigrateHotstringIni()
    after := ConfigCountHotstringItems(ConfigReadHotstringData())
    Check(after == shipped, "Migration restores the marker instead of wiping the file")
    if (after != shipped)
        Log("        had " . shipped . " hotstrings, now " . after)

    ; A file neither reader understands must be left alone and reported, not
    ; replaced with an empty default.
    Fresh()
    ConfigWriteTextFileSafely(g_filePath_Hotstring, "[SomethingElse]`nkey=value`n", "UTF-16")
    reported := false
    try MigrateHotstringIni()
    catch
        reported := true
    Check(reported, "An unrecognised hotstring file is reported rather than migrated")
    Check(InStr(FileRead(g_filePath_Hotstring, "UTF-16"), "SomethingElse") > 0,
        "An unrecognised hotstring file is left on disk untouched")

    ; An genuinely empty file is not an error - there is nothing to lose.
    Fresh()
    ConfigWriteTextFileSafely(g_filePath_Hotstring, "[Meta]`nSchemaVersion=1`n", "UTF-16")
    quiet := true
    try MigrateHotstringIni()
    catch
        quiet := false
    Check(quiet, "An empty hotstring file migrates without complaint")

    ; ---------- Safe write ----------
    Fresh()
    Log("")
    Log("--- ConfigWriteTextFileSafely ---")
    probe := g_targetFolder . "safe-write.ini"
    ConfigWriteTextFileSafely(probe, "[A]`nkey=값`n", "UTF-16")
    Check(FileExist(probe) != "", "Safe write creates the file")
    Check(InStr(FileRead(probe, "UTF-16"), "값") > 0, "Safe write preserves Korean text")

    ; A failed write must leave the previous content in place, not a partial file
    ; or nothing at all. "r-wd" is what a real conflict looks like — a sync client
    ; or scanner reading the file while denying writes. Denying reads as well
    ; would make this section vacuous: the rollback copy could never be made, so
    ; there would be nothing to leak and nothing able to damage the target.
    original := FileRead(probe, "UTF-16")
    locked := FileOpen(probe, "r-wd")
    threw := false
    try ConfigWriteTextFileSafely(probe, "[B]`nreplaced=1`n", "UTF-16")
    catch
        threw := true
    locked.Close()
    Check(threw, "A safe write against a locked target reports failure")
    Check(FileExist(probe) != "", "A failed safe write does not delete the target")
    Check(FileRead(probe, "UTF-16") == original, "A failed safe write leaves the original content intact")

    ; Temp and rollback files would otherwise accumulate in the user's settings
    ; folder on every failed save. The exact name has to be excluded by hand:
    ; a Windows wildcard of "safe-write.ini.*" also matches "safe-write.ini",
    ; because a trailing "." matches an empty extension.
    strays := ""
    loop files, g_targetFolder . "safe-write.ini*" {
        if (A_LoopFileName != "safe-write.ini")
            strays .= (strays == "" ? "" : ", ") . A_LoopFileName
    }
    if (strays != "")
        Log("        left behind: " . strays)
    Check(strays == "", "A failed safe write leaves no temp or rollback files behind")

    ; ---------- Decoding files written before the quote fix ----------
    Log("")
    Log("--- Backward compatibility ---")
    ; Older builds stored a literal quote unescaped. Decoding must not change it,
    ; and a user-typed "%22" was stored as "%2522" then and still decodes to %22.
    Check(HotstringDecodeIniValue('say "hi" now') == 'say "hi" now', "Legacy: unescaped interior quote decodes unchanged")
    Check(HotstringDecodeIniValue("%2522") == "%22", "Legacy: escaped percent still decodes to a literal %22")
    Check(HotstringDecodeIniValue(HotstringEncodeIniValue("%22")) == "%22", "Round-trip: user-typed %22 stays literal")

    try DirDelete(g_targetFolder, true)
    Log("")
    Log(g_failures ? ("RESULT: " . g_failures . " FAILURE(S)") : "RESULT: all codecs round-trip")
    if (g_failures)
        FileAppend("FAIL  ConfigCodec: " . g_failures . " round-trip failure(s); see " . g_out . "`n", "*")
    else
        FileAppend("ok    ConfigCodec`n", "*")
    ExitApp(g_failures ? 1 : 0)
}

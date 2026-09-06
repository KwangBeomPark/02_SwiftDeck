#Requires AutoHotkey v2.0
; =================================================================================
; --- Utility Functions ---
; =================================================================================

GetFileName(path) {
    SplitPath path, &name
    return name
}

; Runs one startup step. A failure degrades that single feature instead of
; aborting OnStartup(), which would leave the app resident with no tray icon —
; and therefore no way for the user to quit it.
RunStartupStep(label, action, warnings) {
    try {
        action.Call()
        return true
    } catch Error as err {
        warnings.Push(label . ": " . err.Message)
        return false
    }
}

; AutoHotkey v2 has no built-in join.
StrJoin(items, separator := ", ") {
    result := ""
    for index, item in items
        result .= (index > 1 ? separator : "") . item
    return result
}

; Normalizes arbitrary user or filesystem text into a Win32 menu label.
; Win32 treats "&" as the keyboard-accelerator prefix, so an unescaped folder
; named "R&D" renders as "RD" with the D underlined. Line breaks would also break
; the label, and unbounded text produces an unusable menu.
SafeMenuLabel(text, fallback := "Item", maxLength := 60) {
    label := StrReplace(text, "`r`n", " ")
    label := StrReplace(label, "`r", " ")
    label := StrReplace(label, "`n", " ")
    label := StrReplace(label, "`t", " ")
    label := Trim(label)
    if (label == "")
        label := fallback
    if (StrLen(label) > maxLength) {
        clipped := SubStr(label, 1, maxLength)
        ; Never cut between the halves of a surrogate pair. Emoji occupy two
        ; UTF-16 units and a lone half renders as a replacement box.
        if (clipped != "") {
            lastUnit := Ord(SubStr(clipped, -1))
            if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF)
                clipped := SubStr(clipped, 1, maxLength - 1)
        }
        label := clipped . "..."
    }
    ; Escape last so clipping can never split an escaped "&&" pair.
    return StrReplace(label, "&", "&&")
}

; Win32 menus key items by their text: adding a label that is already present
; replaces that item instead of appending one, so two favorites sharing a
; nickname would silently collapse into a single entry. Callers keep a per-menu
; Map of labels already used and route every label through this first.
NewMenuLabelSet() {
    usedLabels := Map()
    usedLabels.CaseSense := false ; menu item lookup ignores case
    return usedLabels
}

UniqueMenuLabel(label, usedLabels) {
    candidate := label
    suffix := 1
    while usedLabels.Has(candidate) {
        suffix++
        candidate := label . " (" . suffix . ")"
    }
    usedLabels[candidate] := true
    return candidate
}

; Builds a "<program> "<path>"" command line. Run() hands the result to
; CreateProcess/ShellExecute without a shell, so "&", "|", "<" and ">" inside a
; path are ordinary characters and quoting is all that is required.
BuildQuotedCommand(program, path, separator := " ") {
    ; Deliberately no backslash doubling. CommandLineToArgvW would call for it,
    ; but explorer.exe parses its own command line and takes the quotes as-is:
    ; measured on Windows 11, explorer.exe "C:\" opens C:\ while the doubled form
    ; explorer.exe "C:\\" silently opens Documents instead. Settings folder paths
    ; always end in a backslash, so doubling broke them outright.
    return program . separator . '"' . Trim(path) . '"'
}

OpenFolder(folderPath, Args*) {
    if !folderPath {
        MsgBox "Folder path is not specified.", "Error", 262192
        return
    }

    if FileExist(folderPath) && !DirExist(folderPath) {
        ; A file, not a folder: reveal it. "/select," must sit flush against the quote.
        RunSafely(BuildQuotedCommand("explorer.exe /select,", folderPath, ""), "Open Folder")
        return
    }

    if !DirExist(folderPath) {
        MsgBox "The specified folder does not exist.`n`n" folderPath, "Error", 262192
        return
    }

    RunSafely(BuildQuotedCommand("explorer.exe", folderPath), "Open Folder")
}

; Opens a file in Notepad, but only after confirming it is really there — the
; editor would otherwise offer to create a new file under the missing name.
OpenFileInEditor(filePath, title := "Open File") {
    if (Trim(filePath) == "" || !FileExist(filePath)) {
        MsgBox("The file could not be found.`n`n" . filePath, title, 262192)
        return false
    }
    return RunSafely(BuildQuotedCommand("notepad.exe", filePath), title)
}

RunSafely(command, title := "Open Failed") {
    ; No character blocklist here on purpose. Run() goes straight to
    ; CreateProcess/ShellExecute without a shell, so "&", "|", "<" and ">" inside
    ; a quoted path cannot chain commands. Screening for them only broke ordinary
    ; folders such as "Sales & Marketing", which then refused to open at all.
    try {
        Run(command)
        return true
    } catch Error as err {
        MsgBox("❌ Could not open the requested item.`n`n" . command . "`n`nError: " . err.Message, title, 262160)
        return false
    }
}

AddTrailingBackslash(path) {
    if !RegExMatch(path, "[\\/]$")
        path .= "\"
    return path
}

GetLastFolderName(path) {
    trimmedPath := RTrim(path, "\/")
    partList := StrSplit(trimmedPath, "\")

    if (partList.Length) {
        return partList[partList.Length]
    } else {
        return path
    }
}

GetFoldersList(folderPath, attributes := "") {
    folderList := []
    loop files folderPath, attributes {
        if InStr(A_LoopFileAttrib, "H")
            continue
        folderList.Push(A_LoopFileFullPath)
    }
    return folderList
}

ParseKeyString(keyStr) {
    mods := { Ctrl: 0, Shift: 0, Win: 0, Alt: 0 }
    baseKey := keyStr
    loop {
        char := SubStr(baseKey, 1, 1)
        if (char == "^") {
            mods.Ctrl := 1
            baseKey := SubStr(baseKey, 2)
        } else if (char == "+") {
            mods.Shift := 1
            baseKey := SubStr(baseKey, 2)
        } else if (char == "#") {
            mods.Win := 1
            baseKey := SubStr(baseKey, 2)
        } else if (char == "!") {
            mods.Alt := 1
            baseKey := SubStr(baseKey, 2)
        } else {
            break
        }
    }
    return { Mods: mods, Key: baseKey, BaseKey: baseKey }
}

BuildKeyString(ctrl, shift, win, alt, baseKey) {
    prefix := ""
    if (ctrl)
        prefix .= "^"
    if (shift)
        prefix .= "+"
    if (win)
        prefix .= "#"
    if (alt)
        prefix .= "!"
    return prefix . baseKey
}

NormalizeHotkey(hotkeyText) {
    parsed := ParseKeyString(hotkeyText)
    return StrLower(BuildKeyString(
        parsed.Mods.Ctrl,
        parsed.Mods.Shift,
        parsed.Mods.Win,
        parsed.Mods.Alt,
        parsed.BaseKey
    ))
}

GetAddFolderHotkey(mainHotkey) {
    parsed := ParseKeyString(mainHotkey)
    mods := parsed.Mods

    ; Add the first unused modifier so the Explorer action never collides with
    ; the Favorites Menu. The default remains F1 -> Ctrl+F1.
    if (!mods.Ctrl)
        mods.Ctrl := 1
    else if (!mods.Shift)
        mods.Shift := 1
    else if (!mods.Alt)
        mods.Alt := 1
    else if (!mods.Win)
        mods.Win := 1
    else
        ; No unused modifier remains. Keep a predictable, usable fallback
        ; (Ctrl + the same base key); central validation still checks it
        ; against every other registered shortcut.
        return "^" . parsed.BaseKey

    return BuildKeyString(mods.Ctrl, mods.Shift, mods.Win, mods.Alt, parsed.BaseKey)
}

GetPromptMenuHotkey() {
    return "+#Space"
}

; Window classes that count as "a folder is on screen" for the Add Current Folder
; action. Kept as a pure helper so the hotkey criterion stays cheap and testable.
IsExplorerWindowClass(winClass) {
    return RegExMatch(winClass, "^(CabinetWClass|ExploreWClass|Progman|WorkerW)$") ? true : false
}

; The desktop is an Explorer surface but is never listed in Shell.Application.Windows,
; so its path has to be resolved without COM.
IsDesktopWindowClass(winClass) {
    return (winClass == "Progman" || winClass == "WorkerW")
}

; Every shortcut SwiftDeck registers for itself, as { Name, Hotkey } pairs.
; Shared by conflict validation and by the key-remap guard, so both always see
; the same list.
GetAppHotkeyAssignments(mainHotkey, promptModifier, promptUseNumpad, emojiHotkey, exitHotkey, promptMenuHotkey := "") {
    if (promptMenuHotkey == "")
        promptMenuHotkey := GetPromptMenuHotkey()
    assignments := [
        { Name: "Favorites Menu", Hotkey: mainHotkey },
        { Name: "Add Current Explorer Folder", Hotkey: GetAddFolderHotkey(mainHotkey) },
        { Name: "Prompt Popup Menu", Hotkey: promptMenuHotkey },
        { Name: "Emoji & Symbols", Hotkey: emojiHotkey },
        { Name: "Exit App", Hotkey: exitHotkey }
    ]

    if (promptModifier != "") {
        loop 10 {
            num := A_Index - 1
            baseKey := promptUseNumpad ? "Numpad" . num : num
            assignments.Push({ Name: "Quick Prompt " . num, Hotkey: promptModifier . baseKey })
        }
    }
    return assignments
}

; Returns the name of the app shortcut a candidate hotkey would collide with, or
; "" when it is free. AutoHotkey keys a criterion-less hotkey by its string, so
; registering a remap over one of these replaces the app's own callback — and
; deleting that remap later calls Hotkey(key, "Off") on the app's shortcut,
; silently killing it with no message.
FindAppHotkeyConflict(candidateHotkey, settings) {
    normalized := NormalizeHotkey(candidateHotkey)
    if (normalized == "")
        return ""

    assignments := GetAppHotkeyAssignments(
        settings.MainHotkey,
        settings.PromptModifier,
        settings.PromptUseNumpad,
        settings.EmojiHotkey,
        settings.ExitHotkey
    )
    for assignment in assignments {
        if (NormalizeHotkey(assignment.Hotkey) == normalized)
            return assignment.Name
    }
    return ""
}

ValidateHotkeyAssignments(mainHotkey, promptModifier, promptUseNumpad, emojiHotkey, exitHotkey, promptMenuHotkey := "") {
    assignments := GetAppHotkeyAssignments(
        mainHotkey, promptModifier, promptUseNumpad, emojiHotkey, exitHotkey, promptMenuHotkey)

    seen := Map()
    for assignment in assignments {
        normalized := NormalizeHotkey(assignment.Hotkey)
        if (normalized == "")
            continue
        if (seen.Has(normalized)) {
            return assignment.Name . " conflicts with " . seen[normalized]
                . " (" . FormatHotkeyDisplay(assignment.Hotkey) . ")."
        }
        seen[normalized] := assignment.Name
    }
    return ""
}

FormatHotkeyDisplay(hotkeyLabel) {
    formattedHK := hotkeyLabel
    ; Replace "+" (Shift) first so the "+" introduced by later replacements
    ; (e.g. "Ctrl+") is not mistaken for a Shift modifier.
    formattedHK := StrReplace(formattedHK, "+", "Shift+")
    formattedHK := StrReplace(formattedHK, "^", "Ctrl+")
    formattedHK := StrReplace(formattedHK, "#", "Win+")
    formattedHK := StrReplace(formattedHK, "!", "Alt+")
    return formattedHK
}

; A base key that is itself a modifier symbol cannot survive a round trip:
; BuildKeyString appends it, and ParseKeyString then reads it back as a modifier
; and leaves an empty key — so "Ctrl + the + key" reopens as "Ctrl+Shift+ nothing".
; GetKeyName accepts them (they resolve to "=", "6", "3", "1", "7"), so they have
; to be rejected on their own. "&" is AutoHotkey's custom-combination separator.
IsModifierSymbolKey(baseKey) {
    return (baseKey == "^" || baseKey == "+" || baseKey == "#" || baseKey == "!" || baseKey == "&")
}

; A hotkey shown inside a menu label still comes from the settings file, so it
; needs the same treatment as any other user text: "&" escaped, and clipped so a
; hand-edited value cannot push the label past what Menu.Add accepts. Exceeding
; it throws — and in the tray that happens after A_TrayMenu.Delete(), leaving no
; Exit or Settings item at all.
FormatHotkeyForMenu(hotkeyLabel) {
    return SafeMenuLabel(FormatHotkeyDisplay(hotkeyLabel), "?", 40)
}

ParseIniKeyValuePairs(lineStr) {
    if !lineStr
        return { Key: "", Val: "" }
    idx := InStr(lineStr, "=")
    if (idx > 0) {
        k := Trim(SubStr(lineStr, 1, idx - 1))
        v := Trim(SubStr(lineStr, idx + 1))
        return { Key: k, Val: v }
    }
    return { Key: "", Val: "" }
}

; User text that becomes an INI key must not be readable as INI syntax.
; "=" and line breaks split the entry, and Windows also treats a leading "["
; as a section header and a leading ";" as a comment — measured: a favorite
; named "[Draft] Reply" stored second of four silently loses the two entries
; after it on the next read, permanently once the section is rewritten.
IsPlainIniKeySafe(text) {
    if (InStr(text, "=") || InStr(text, "`r") || InStr(text, "`n"))
        return false
    firstChar := SubStr(Trim(text), 1, 1)
    return (firstChar != "[") && (firstChar != ";")
}

; The single place that explains the rule to the user, so every entry point says
; the same thing.
GetIniKeyRuleMessage() {
    return "The name cannot contain '=' or line breaks, and cannot start with '[' or ';'."
        . "`n`nThose are treated as settings-file syntax and would discard your other entries."
}

FixIniSpecialChars(k, v) {
    if (k == ">" && v == "=≥")
        return { Key: ">=", Val: "≥" }
    if (k == "<" && v == "=≤")
        return { Key: "<=", Val: "≤" }
    if (k == "!" && v == "=≠")
        return { Key: "!=", Val: "≠" }
    return { Key: k, Val: v }
}

; =================================================================================
; --- Translation Helpers ---
; =================================================================================

UriEncode(uri) {
    buf := Buffer(StrPut(uri, "UTF-8"))
    StrPut(uri, buf, "UTF-8")
    res := ""
    loop buf.Size - 1 {
        code := NumGet(buf, A_Index - 1, "UChar")
        if (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || InStr("-._~", Chr(code))
            res .= Chr(code)
        else
            res .= Format("%{:02X}", code)
    }
    return res
}

GoogleTranslate(text, targetLang := "ko") {
    if (Trim(text) == "")
        return ""
    
    url := "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" . targetLang . "&dt=t"
    body := "q=" . UriEncode(text)
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        ; Without these the popup can stay disabled indefinitely: the request is
        ; async and an argument-less WaitForResponse never gives up.
        req.SetTimeouts(5000, 5000, 5000, 15000)
        req.Open("POST", url, true)
        req.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded;charset=utf-8")
        req.Send(body)
        if !req.WaitForResponse(20)
            return ""
        res := req.ResponseText
        
        outText := ""
        
        ; Google JSON format for GTX starts with [[[
        ; "" means "no translation": returning the input text instead would be
        ; indistinguishable from a successful no-op translation.
        if (SubStr(res, 1, 3) != "[[[")
            return ""
            
        pos := 3
        len := StrLen(res)
        
        loop {
            if (SubStr(res, pos, 2) != '["')
                break
                
            textStart := pos + 2
            textEnd := _FindClosingQuote(res, textStart)
            if (!textEnd)
                break
                
            translatedPart := SubStr(res, textStart, textEnd - textStart)
            
            translatedPart := StrReplace(translatedPart, '\"', '"')
            translatedPart := StrReplace(translatedPart, '\\', '\')
            translatedPart := StrReplace(translatedPart, "\n", "`n")
            translatedPart := StrReplace(translatedPart, "\r", "`r")
            translatedPart := StrReplace(translatedPart, "\t", "`t")
            
            outText .= translatedPart
            
            ; State machine to safely skip the rest of this segment array
            bracketCount := 1
            scanPos := textEnd + 1
            
            while (scanPos <= len && bracketCount > 0) {
                ch := SubStr(res, scanPos, 1)
                
                if (ch == '"') {
                    scanPos := _FindClosingQuote(res, scanPos + 1)
                    if (!scanPos)
                        break 2
                    scanPos++
                    continue
                }
                
                if (ch == "[")
                    bracketCount++
                else if (ch == "]")
                    bracketCount--
                
                scanPos++
            }
            
            if (bracketCount > 0)
                break
                
            ; scanPos is at the character after the segment's closing bracket
            if (SubStr(res, scanPos, 2) == ",[") {
                pos := scanPos + 1
            } else {
                break
            }
        }
        
        return outText
    } catch {
        return ""
    }
}

_FindClosingQuote(str, startPos) {
    pos := startPos
    len := StrLen(str)
    while (pos <= len) {
        ch := SubStr(str, pos, 1)
        if (ch == '\') {
            pos += 2  ; skip escaped character
            continue
        }
        if (ch == Chr(34))
            return pos
        pos++
    }
    return 0
}

; =================================================================================
; --- Window / UI Helpers ---
; =================================================================================

ShowCenteredOnMouse(guiObj, options := "") {
    guiObj.Show("Hide " . options)
    guiObj.GetPos(,, &gW, &gH)
    
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY)
    
    monitorCount := MonitorGetCount()
    idx := MonitorGetPrimary()
    loop monitorCount {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (mX >= L && mX < R && mY >= T && mY < B) {
            idx := A_Index
            break
        }
    }
    
    ; Use WorkArea to avoid taskbar overlap
    MonitorGetWorkArea(idx, &WL, &WT, &WR, &WB)
    centeredPos := CalculateCenteredWindowPosition(gW, gH, WL, WT, WR, WB)
    
    ; WinMove uses physical screen coordinates regardless of DPIScale
    WinMove(centeredPos.X, centeredPos.Y, , , guiObj.Hwnd)
    guiObj.Show(options)
}

CalculateCenteredWindowPosition(guiWidth, guiHeight, workLeft, workTop, workRight, workBottom) {
    workWidth := Max(0, workRight - workLeft)
    workHeight := Max(0, workBottom - workTop)
    x := guiWidth >= workWidth ? workLeft : workLeft + (workWidth - guiWidth) // 2
    y := guiHeight >= workHeight ? workTop : workTop + (workHeight - guiHeight) // 2
    return { X: x, Y: y }
}

UpdateSaveButtonState(buttonCtrl, isDirty) {
    buttonCtrl.Text := isDirty
        ? "● Save && Apply (Unsaved)"
        : "💾 Save && Apply"
}

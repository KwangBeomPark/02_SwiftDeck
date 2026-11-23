#Requires AutoHotkey v2.0
; =============================================================================
; --- INI text, read the way Windows reads it ---
; =============================================================================
; The Windows profile functions behind IniRead return the caller's default when
; the file is locked by another program, missing for a moment, or a section is
; too large for them (measured: a 74,000-character section). A reader cannot
; tell that from an empty list, and saving that "empty" list deletes the real
; one. Reading the file's text once and parsing it here lets a read fail loudly
; instead, while the existing readers keep their exact results.
;
; Rules, measured against IniRead on Windows 11 (see ConfigStrictReadTests):
; - CRLF, LF and a lone CR all end a line.
; - A header is a trimmed line starting with "["; the name is the text up to
;   the first "]", trimmed, and anything after the "]" is ignored.
; - Blank lines, lines starting with ";" and lines before the first header are
;   not part of any section.
; - Only the first section of a name counts (names compare case-insensitively);
;   the list of names still shows every header, up to an empty name, which
;   ends the list Windows returns.
; - A section read returns each line with the key and the value trimmed around
;   the first "=", quotes kept; a line without "=" comes back trimmed.
; - A key read takes the first matching key (case-insensitive; spaces, but not
;   tabs, are trimmed from the requested section and key), trimmed, with one
;   pair of matching enclosing quotes removed.

IniParseText(text) {
    sections := Map()
    sections.CaseSense := "Off"
    names := []
    namesEnded := false
    current := ""
    ; CRLF, LF and a lone CR all end a line for Windows.
    text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    loop parse, text, "`n" {
        line := Trim(A_LoopField, " `t")
        if (line == "")
            continue
        if (SubStr(line, 1, 1) == "[") {
            close := InStr(line, "]")
            name := Trim(close ? SubStr(line, 2, close - 2) : SubStr(line, 2), " `t")
            if (name == "")
                namesEnded := true
            else if !namesEnded
                names.Push(name)
            if sections.Has(name) {
                current := ""
            } else {
                keys := Map()
                keys.CaseSense := "Off"
                current := { Lines: [], Keys: keys }
                sections[name] := current
            }
            continue
        }
        if (!IsObject(current) || SubStr(line, 1, 1) == ";")
            continue
        eq := InStr(line, "=")
        if !eq {
            current.Lines.Push(line)
            continue
        }
        key := Trim(SubStr(line, 1, eq - 1), " `t")
        value := Trim(SubStr(line, eq + 1), " `t")
        current.Lines.Push(key . "=" . value)
        if !current.Keys.Has(key)
            current.Keys[key] := value
    }
    return { Names: names, Sections: sections }
}

IniTextReadValue(parsed, section, key, defaultValue := "") {
    section := Trim(section, " ")
    key := Trim(key, " ")
    if !parsed.Sections.Has(section)
        return defaultValue
    keys := parsed.Sections[section].Keys
    if !keys.Has(key)
        return defaultValue
    value := keys[key]
    first := SubStr(value, 1, 1)
    if (StrLen(value) >= 2 && (first == '"' || first == "'") && SubStr(value, -1) == first)
        value := SubStr(value, 2, -1)
    return value
}

IniTextReadSection(parsed, section, defaultValue := "") {
    section := Trim(section, " ")
    if !parsed.Sections.Has(section)
        return defaultValue
    text := ""
    for line in parsed.Sections[section].Lines
        text .= (A_Index > 1 ? "`n" : "") . line
    return text
}

IniTextReadSectionNames(parsed) {
    text := ""
    for name in parsed.Names
        text .= (A_Index > 1 ? "`n" : "") . name
    return text
}

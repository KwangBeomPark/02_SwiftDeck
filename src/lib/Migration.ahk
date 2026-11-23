#Requires AutoHotkey v2.0
#Include Config.ahk
; =============================================================================
; --- Configuration Migration Utilities ---
; =============================================================================

MigratePromptModifier(modVal, useNumpadVal) {
    migrated := false

    if (modVal == "1") {
        modVal := "#"
        migrated := true
    } else if (modVal == "2") {
        modVal := "^"
        migrated := true
    } else if (modVal == "3") {
        modVal := "!"
        migrated := true
    } else if (modVal == "4") {
        modVal := "+#"
        migrated := true
    } else if (modVal == "5") {
        modVal := "+^"
        migrated := true
    } else if (modVal == "6") {
        modVal := "+!"
        migrated := true
    } else if (modVal == "7") {
        modVal := "^#"
        migrated := true
    } else if (modVal == "8") {
        modVal := "!#"
        migrated := true
    } else if (modVal == "9") {
        modVal := "^!"
        migrated := true
    } else if (modVal == "WinNumpad") {
        modVal := "#"
        useNumpadVal := 1
        migrated := true
    }

    if (migrated) {
        ConfigWriteValue("Settings", "Settings", "PromptModifier", modVal)
        ConfigWriteValue("Settings", "Settings", "PromptUseNumpad", useNumpadVal)
    }

    return { Mod: modVal, UseNumpad: useNumpadVal }
}

MigrateHotstringIni() {
    if !ConfigExists("Hotstrings")
        return

    ; Every decision below comes from one strict read of the file: a file that
    ; cannot be read raises ConfigReadError, which the startup step reports,
    ; instead of reading as empty for some of the reads and not others.
    state := ConfigReadStrict("Hotstrings", MigrateHotstringReadState)
    if state.IsCurrent
        return

    ; The migration rewrites the whole file, so it must never run on content it
    ; failed to understand. Measured: deleting the SchemaVersion line from a
    ; current file — a plausible hand edit, and the App Info window offers to
    ; open this file — makes the legacy reader match none of the v4 section
    ; names, return zero items, and the rewrite then deletes all 37 of them
    ; without raising anything.
    if (ConfigCountHotstringItems(state.Data) > 0) {
        ConfigWriteHotstringData(state.Data.Data, state.Data.GroupOrder)
        return
    }

    ; Nothing was read. If the file is really in the current format, only the
    ; marker is missing — put it back rather than rewriting the content.
    if (ConfigCountHotstringItems(state.V4) > 0) {
        ConfigWriteValue("Hotstrings", "Meta", "SchemaVersion", "4")
        return
    }

    ; Neither reader understood it, yet it holds something. Leave it alone and
    ; let the caller report it: an empty hotstring list is recoverable, a file
    ; overwritten with an empty default is not.
    if state.HasContent
        throw Error("The hotstring settings file is not in a recognised format, so it was left unchanged.")
}

MigrateHotstringReadState() {
    if (ConfigReadValue("Hotstrings", "Meta", "SchemaVersion", "1") == "4")
        return { IsCurrent: true }
    return {
        IsCurrent: false,
        Data: ConfigReadHotstringData(),
        V4: ConfigReadHotstringDataV4(),
        HasContent: ConfigHasContentSections("Hotstrings")
    }
}

; True when a file's bytes decode as valid UTF-8. A settings file left over from
; an ANSI-era build has no BOM, so assuming UTF-8 turns Korean text into mojibake
; the moment it is rewritten — and since the rewrite is what this migration does,
; that corruption is permanent. Pure ASCII is valid UTF-8, so it is unaffected.
FileLooksLikeUtf8(path) {
    static CP_UTF8 := 65001
    static MB_ERR_INVALID_CHARS := 0x8

    raw := FileRead(path, "RAW")
    if (raw.Size == 0)
        return true

    ; MB_ERR_INVALID_CHARS makes the conversion fail outright on malformed input
    ; instead of quietly substituting replacement characters.
    return DllCall("MultiByteToWideChar", "uint", CP_UTF8, "uint", MB_ERR_INVALID_CHARS,
        "ptr", raw.Ptr, "int", raw.Size, "ptr", 0, "int", 0, "int") > 0
}

MigrateIniEncoding() {
    for fileDef in ConfigGetManagedFiles() {
        path := fileDef.Path
        if !FileExist(path)
            continue

        try {
            fileObj := FileOpen(path, "r")
            enc := fileObj.Encoding
            fileObj.Close()

            if (enc != "UTF-16") {
                ; "CP0" is the system ANSI codepage, which is what a legacy
                ; BOM-less file on Korean Windows actually holds.
                sourceEncoding := FileLooksLikeUtf8(path) ? "UTF-8" : "CP0"
                content := FileRead(path, sourceEncoding)
                ConfigWriteTextFileSafely(path, content, "UTF-16")
            }
        } catch Error as err {
            ; A file left only under a backup name must be reported, so the
            ; startup warning says where the settings are.
            if err.HasOwnProp("KeptBackup")
                throw err
        }
    }
}

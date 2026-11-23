; Write only sibling temporary files; commit with an atomic Windows rename.
SettingsTempPath(path, tag := "pending") {
    loop 20 {
        candidate := path "." tag "." DllCall("GetCurrentProcessId") "." A_TickCount "." Random(100000, 999999)
        if !FileExist(candidate)
            return candidate
    }
    throw Error("Cannot reserve a temporary settings path.")
}

; createOnly is for content built without the target: a file that appeared
; meanwhile (a sync client restoring it) is then a conflict, not overwritten.
; requireTarget is for a save checked against the file it read: a target gone
; by the swap fails the replace instead of being created again.
SettingsCommitTemp(tempPath, targetPath, createOnly := false, requireTarget := false) {
    stream := FileOpen(tempPath, "rw")
    if !stream
        throw Error("Cannot reopen temporary settings for flushing.")
    try {
        if !DllCall("FlushFileBuffers", "ptr", stream.Handle)
            throw OSError()
    } finally {
        stream.Close()
    }
    if (!createOnly && (requireTarget || FileExist(targetPath))) {
        ; Keep the existing ACL; no direct-write fallback on failure. The old
        ; file is parked under a backup name until the swap is done, since a
        ; swap Windows cannot finish may otherwise leave no file at all. The
        ; tag is shorter than "pending" so the backup path is never the longer one.
        backupPath := SettingsTempPath(targetPath, "prev")
        if !DllCall("ReplaceFileW", "str", targetPath, "str", tempPath, "str", backupPath, "uint", 0, "ptr", 0, "ptr", 0)
            SettingsRecoverReplaced(targetPath, backupPath, OSError())
        ; A scanner may hold the fresh backup for a moment.
        loop 3 {
            if !FileExist(backupPath)
                break
            try FileDelete(backupPath)
            catch
                Sleep(50 * A_Index)
        }
    } else {
        ; A concurrently created destination wins rather than being overwritten.
        if !DllCall("MoveFileExW", "str", tempPath, "str", targetPath, "uint", 8)
            throw OSError()
    }
}

; After a failed swap. With ERROR_UNABLE_TO_MOVE_REPLACEMENT_2 (1177) the old
; file has left its path and survives only as the backup, even when a dropped
; network share cannot show it. It is moved back; if that fails, it is kept,
; and the error says where and carries KeptBackup so it is not retried over.
; Always throws.
SettingsRecoverReplaced(targetPath, backupPath, cause) {
    parked := (cause is OSError && cause.Number == 1177) || FileExist(backupPath)
    if !parked
        throw cause
    if !FileExist(targetPath) && DllCall("MoveFileExW", "str", backupPath, "str", targetPath, "uint", 8)
        throw cause
    kept := Error(cause.Message . "`n`nThe previous settings file was kept as:`n" . backupPath)
    kept.KeptBackup := backupPath
    throw kept
}

; verifyBase, when given, is called as verifyBase(path, existed) and throws to
; refuse the save when the file is no longer the one the caller read: on the
; copy, before anything is changed, and on the target itself right before the
; swap, which leaves only the swap for a change made elsewhere to slip in.
; describe, when given, is called as describe(copyPath) on the finished copy
; just before the swap, and what it returns is returned: the caller learns what
; it wrote without reading the shared file again, where a change landing after
; the swap would pass for its own.
SettingsWriteIniValues(path, changes, verifyBase := "", describe := "") {
    SplitPath(path, , &directory)
    if !DirExist(directory)
        DirCreate(directory)
    temp := SettingsTempPath(path)
    existed := FileExist(path) != ""
    result := ""
    try {
        if existed
            FileCopy(path, temp, false)
        else
            FileAppend("", temp, "UTF-16")
        if IsObject(verifyBase)
            verifyBase(temp, existed)
        for change in changes {
            if change.HasOwnProp("ClearSectionsExcept") {
                ; Listed from the private copy, which no other program holds: a
                ; failed read of the shared file would look like no sections.
                ; IniRead returns "" for a file without sections and throws only
                ; when it cannot read, which then refuses the save.
                existing := IniRead(temp)
                loop parse, existing, "`n", "`r" {
                    if (A_LoopField != "" && !SettingsListHas(change.ClearSectionsExcept, A_LoopField))
                        IniDelete(temp, A_LoopField)
                }
            } else if change.HasOwnProp("SectionText") {
                if change.SectionText != ""
                    IniWrite(change.SectionText, temp, change.Section)
                else
                    IniDelete(temp, change.Section)
            } else {
                IniWrite(String(change.Value), temp, change.Section, change.Key)
                if !(IniRead(temp, change.Section, change.Key, Chr(0x1F)) == String(change.Value))
                    throw Error("Temporary settings validation failed: " change.Key)
            }
        }
        if IsObject(describe)
            result := describe(temp)
        if IsObject(verifyBase)
            verifyBase(path, FileExist(path) != "")
        SettingsCommitTemp(temp, path, !existed, IsObject(verifyBase) && existed)
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
    return result
}

; Section names compare without case, as Windows INI files do.
SettingsListHas(list, value) {
    for item in list {
        if (item = value)
            return true
    }
    return false
}

SettingsWriteText(path, content, encoding := "UTF-16", createOnly := false) {
    SplitPath(path, , &directory)
    if !DirExist(directory)
        DirCreate(directory)
    temp := SettingsTempPath(path)
    try {
        FileAppend(content, temp, encoding)
        if !(FileRead(temp, encoding) == content)
            throw Error("Temporary settings content could not be verified.")
        SettingsCommitTemp(temp, path, createOnly)
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}

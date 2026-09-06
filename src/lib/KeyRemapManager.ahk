#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Theme.ahk
#Include Utils.ahk

; =================================================================================
; Module: KeyRemapManager
; Description: Manages UI and logic for system-wide custom key remapping.
; Author: KBPark
; =================================================================================
class KeyRemapManager {
    __New(parentGui := "") {
        this.parentGui := parentGui
        this.localData := ConfigReadKeyRemaps()
        if (parentGui)
            this.BuildUI(parentGui)
    }

    Show() {
        if (!this.parentGui) {
            this.rGui := Gui("+AlwaysOnTop -MaximizeBox", "Key Remap Manager")
            EnableDarkMode(this.rGui)
            this.BuildUI(this.rGui)
            ShowCenteredOnMouse(this.rGui, "AutoSize")
        }
    }

    BuildUI(guiObj) {
        startX := this.parentGui ? 35 : 25
        startY := this.parentGui ? 120 : 80
        listHeight := this.parentGui ? 290 : 345
        exampleOffset := this.parentGui ? 320 : 375
        autoSaveOffset := this.parentGui ? 370 : 425
        guiObj.SetFont("s10", "Segoe UI")
        this.mainHwnd := guiObj.Hwnd

        guiObj.Add("Text", "x" . startX . " y" . startY . " w400", "① Active Key Mappings:")

        guiObj.SetFont("cBlack")
        this.lbItems := guiObj.Add("ListBox", "x" . startX . " y" . (startY + 25) . " w300 h" . listHeight)

        guiObj.SetFont("s9 c888888 norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + exampleOffset) . " w310 BackgroundTrans", "e.g.) Caps Lock → Left Click")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        guiObj.SetFont("s9 cD03A3A norm", "Segoe UI")
        btnReset := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY - 5) . " w95 h25", "⚠️ Reset")
        btnReset.OnEvent("Click", (*) => this.RequestReset())
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        btnAdd := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 25) . " w95 h35", "➕ New")
        btnEdit := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 65) . " w95 h35", "✏️ Edit")
        btnDel := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 105) . " w95 h35", "❌ Delete")

        if (!this.parentGui) {
            btnClose := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 470) . " w95 h35", "Close")
            btnClose.OnEvent("Click", (*) => guiObj.Destroy())
        }

        guiObj.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + autoSaveOffset) . " w405 Center", "✓ Changes are saved and applied immediately.")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        this.RefreshList()

        this.lbItems.OnEvent("DoubleClick", (*) => this.EditSelectedItem())
        btnEdit.OnEvent("Click", (*) => this.EditSelectedItem())
        btnDel.OnEvent("Click", (*) => this.DeleteItem())
        btnAdd.OnEvent("Click", (*) => this.ShowEditPopup(false, 0))
    }


    TranslateKeyToFriendly(keyStr) {
        parsed := ParseKeyString(keyStr)
        mods := []
        if (parsed.Mods.Ctrl)
            mods.Push("Ctrl")
        if (parsed.Mods.Shift)
            mods.Push("Shift")
        if (parsed.Mods.Win)
            mods.Push("Win")
        if (parsed.Mods.Alt)
            mods.Push("Alt")

        friendlyBase := parsed.BaseKey
        keyMap := Map(
            "LButton", "Left Click",
            "RButton", "Right Click",
            "MButton", "Middle Click",
            "XButton1", "Mouse Back",
            "XButton2", "Mouse Forward",
            "WheelUp", "Wheel Up",
            "WheelDown", "Wheel Down",
            "Space", "Space",
            "Enter", "Enter",
            "Backspace", "Backspace",
            "Tab", "Tab",
            "Escape", "Esc",
            "CapsLock", "Caps Lock",
            "ScrollLock", "Scroll Lock",
            "NumLock", "Num Lock",
            "PrintScreen", "Print Screen",
            "Insert", "Insert",
            "Delete", "Delete",
            "Home", "Home",
            "End", "End",
            "PgUp", "Page Up",
            "PgDn", "Page Down",
            "AppsKey", "Menu Key",
            "Volume_Up", "Volume Up",
            "Volume_Down", "Volume Down",
            "Volume_Mute", "Mute",
            "Media_Play_Pause", "Play/Pause",
            "Media_Next", "Next Track",
            "Media_Prev", "Prev Track",
            "Media_Stop", "Stop Media",
            "NumpadEnter", "Numpad Enter",
            "NumpadAdd", "Numpad +",
            "NumpadSub", "Numpad -",
            "NumpadMult", "Numpad *",
            "NumpadDiv", "Numpad /",
            "NumpadDot", "Numpad ."
        )

        lowerBase := StrLower(parsed.BaseKey)
        for k, v in keyMap {
            if (StrLower(k) == lowerBase) {
                friendlyBase := v
                break
            }
        }

        if (StrLen(friendlyBase) == 1) {
            friendlyBase := StrUpper(friendlyBase)
        }

        if (mods.Length > 0) {
            prefix := ""
            for i, mod in mods {
                prefix .= (i > 1 ? " + " : "") . mod
            }
            return prefix . " + [" . friendlyBase . "]"
        }
        return "[" . friendlyBase . "]"
    }

    ; Re-reads this tab's settings from disk. The dashboard is created once and
    ; only hidden on close, and every save rewrites the whole section from
    ; memory — so without this, edits made to the file meanwhile (App Info's
    ; Open buttons invite exactly that) are overwritten by the stale snapshot.
    ReloadFromDisk() {
        this.localData := ConfigReadKeyRemaps()
    }

    RefreshList(targetIdx := 0) {
        listData := []
        for obj in this.localData {
            friendlySrc := this.TranslateKeyToFriendly(obj.Src)
            friendlyDst := this.TranslateKeyToFriendly(obj.Dst)
            listData.Push(friendlySrc . "  →  " . friendlyDst)
        }
        this.lbItems.Delete()
        if (listData.Length > 0)
            this.lbItems.Add(listData)
        if (targetIdx > 0 && targetIdx <= listData.Length) {
            this.lbItems.Choose(targetIdx)
        }
    }

    EditSelectedItem() {
        idx := this.lbItems.Value
        if (idx > 0 && idx <= this.localData.Length) {
            this.ShowEditPopup(true, idx)
        }
    }

    DeleteItem() {
        idx := this.lbItems.Value
        if (idx == 0)
            return

        friendlySrc := this.TranslateKeyToFriendly(this.localData[idx].Src)
        friendlyDst := this.TranslateKeyToFriendly(this.localData[idx].Dst)
        friendlyItem := friendlySrc . "  →  " . friendlyDst

        msgRes := MsgBox("❓ Are you sure you want to delete this key mapping?`n`n" . friendlyItem, "Confirm Delete", 262436)
        if (msgRes != "Yes")
            return

        this.localData.RemoveAt(idx)
        targetIdx := idx > this.localData.Length ? this.localData.Length : idx
        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback("✅ Mapping deleted and applied")
        }
    }

    ShowEditPopup(isEdit := false, editIdx := 0) {
        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", isEdit ? "Modify Key Mapping" : "Add Key Mapping")

        CleanUpAndClose() {
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        ; Key definitions mapping technical AHK keys to beautiful display labels
        keyDefs := [{ Key: "CapsLock", Disp: "Caps Lock" }, { Key: "ScrollLock", Disp: "Scroll Lock" }, { Key: "NumLock", Disp: "Num Lock" }, { Key: "PrintScreen", Disp: "Screen Capture" }, { Key: "Insert", Disp: "Insert" }, { Key: "Delete", Disp: "Delete" }, { Key: "AppsKey", Disp: "Context Menu" }, { Key: "Tab", Disp: "Tab" }, { Key: "Space", Disp: "Spacebar" }, { Key: "Enter", Disp: "Enter" }, { Key: "Backspace", Disp: "Backspace" }, { Key: "Escape", Disp: "Esc" }, { Key: "Home", Disp: "Home" }, { Key: "End", Disp: "End" }, { Key: "PgUp", Disp: "Page Up" }, { Key: "PgDn", Disp: "Page Down" }, { Key: "F1", Disp: "F1" }, { Key: "F2", Disp: "F2" }, { Key: "F3", Disp: "F3" }, { Key: "F4", Disp: "F4" }, { Key: "F5", Disp: "F5" }, { Key: "F6", Disp: "F6" }, { Key: "F7", Disp: "F7" }, { Key: "F8", Disp: "F8" }, { Key: "F9", Disp: "F9" }, { Key: "F10", Disp: "F10" }, { Key: "F11", Disp: "F11" }, { Key: "F12", Disp: "F12" }, { Key: "LButton", Disp: "🖱️ Mouse Left Click" }, { Key: "RButton", Disp: "🖱️ Mouse Right Click" }, { Key: "MButton", Disp: "🖱️ Mouse Wheel Click" }, { Key: "XButton1", Disp: "🖱️ Mouse Back Button" }, { Key: "XButton2", Disp: "🖱️ Mouse Forward Button" }, { Key: "WheelUp", Disp: "🖱️ Mouse Wheel Roll Up" }, { Key: "WheelDown", Disp: "🖱️ Mouse Wheel Roll Down" }, { Key: "Numpad0", Disp: "Keypad 0" }, { Key: "Numpad1", Disp: "Keypad 1" }, { Key: "Numpad2", Disp: "Keypad 2" }, { Key: "Numpad3", Disp: "Keypad 3" }, { Key: "Numpad4", Disp: "Keypad 4" }, { Key: "Numpad5", Disp: "Keypad 5" }, { Key: "Numpad6", Disp: "Keypad 6" }, { Key: "Numpad7", Disp: "Keypad 7" }, { Key: "Numpad8", Disp: "Keypad 8" }, { Key: "Numpad9", Disp: "Keypad 9" }, { Key: "NumpadEnter", Disp: "Keypad Enter" }, { Key: "NumpadAdd", Disp: "Keypad +" }, { Key: "NumpadSub", Disp: "Keypad -" }, { Key: "NumpadMult", Disp: "Keypad *" }, { Key: "NumpadDiv", Disp: "Keypad /" }, { Key: "NumpadDot", Disp: "Keypad ." }, { Key: "Media_Play_Pause", Disp: "Media Play/Pause" }, { Key: "Media_Next", Disp: "Media Next Track" }, { Key: "Media_Prev", Disp: "Media Prev Track" }, { Key: "Media_Stop", Disp: "Media Stop" }, { Key: "Volume_Up", Disp: "Volume Up" }, { Key: "Volume_Down", Disp: "Volume Down" }, { Key: "Volume_Mute", Disp: "Volume Mute" }, { Key: "a", Disp: "A" }, { Key: "b", Disp: "B" }, { Key: "c", Disp: "C" }, { Key: "d", Disp: "D" }, { Key: "e", Disp: "E" }, { Key: "f", Disp: "F" }, { Key: "g", Disp: "G" }, { Key: "h", Disp: "H" }, { Key: "i", Disp: "I" }, { Key: "j", Disp: "J" }, { Key: "k", Disp: "K" }, { Key: "l", Disp: "L" }, { Key: "m", Disp: "M" }, { Key: "n", Disp: "N" }, { Key: "o", Disp: "O" }, { Key: "p", Disp: "P" }, { Key: "q", Disp: "Q" }, { Key: "r", Disp: "R" }, { Key: "s", Disp: "S" }, { Key: "t", Disp: "T" }, { Key: "u", Disp: "U" }, { Key: "v", Disp: "V" }, { Key: "w", Disp: "W" }, { Key: "x", Disp: "X" }, { Key: "y", Disp: "Y" }, { Key: "z", Disp: "Z" }, { Key: "0", Disp: "0" }, { Key: "1", Disp: "1" }, { Key: "2", Disp: "2" }, { Key: "3", Disp: "3" }, { Key: "4", Disp: "4" }, { Key: "5", Disp: "5" }, { Key: "6", Disp: "6" }, { Key: "7", Disp: "7" }, { Key: "8", Disp: "8" }, { Key: "9", Disp: "9" }
                    ]

        comboList := []
        for item in keyDefs {
            comboList.Push(item.Disp)
        }

        GetDisplayString(baseKey) {
            lowerKey := StrLower(baseKey)
            for item in keyDefs {
                if (StrLower(item.Key) == lowerKey) {
                    return item.Disp
                }
            }
            return baseKey
        }

        GetKeyFromDisp(dispStr) {
            lowerDisp := StrLower(Trim(dispStr))
            for item in keyDefs {
                if (StrLower(item.Disp) == lowerDisp || StrLower(item.Key) == lowerDisp) {
                    return item.Key
                }
            }
            return dispStr ; Fallback to custom user typing
        }

        ; Parse edit values if applicable
        srcParsed := { Mods: { Ctrl: 0, Shift: 0, Win: 0, Alt: 0 }, BaseKey: "" }
        dstParsed := { Mods: { Ctrl: 0, Shift: 0, Win: 0, Alt: 0 }, BaseKey: "" }
        if (isEdit && editIdx > 0 && editIdx <= this.localData.Length) {
            srcParsed := ParseKeyString(this.localData[editIdx].Src)
            dstParsed := ParseKeyString(this.localData[editIdx].Dst)
        }

        ; --- From Section ---
        popup.Add("GroupBox", "x15 y15 w450 h90 cBlack", "② From (Press Key)")
        popup.Add("Text", "x30 y35 w420 c666666", "Select modifier keys and a base key:")
        chkSrcCtrl := popup.Add("CheckBox", "x30 y60 w50", "Ctrl")
        chkSrcShift := popup.Add("CheckBox", "x85 y60 w55", "Shift")
        chkSrcWin := popup.Add("CheckBox", "x145 y60 w50", "Win")
        chkSrcAlt := popup.Add("CheckBox", "x200 y60 w45", "Alt")
        cbSrc := popup.Add("ComboBox", "x255 y57 w195", comboList)

        ; --- To Section ---
        popup.Add("GroupBox", "x15 y120 w450 h90 cBlack", "③ To (Remapped Action)")
        popup.Add("Text", "x30 y140 w420 c666666", "This key combination will be triggered instead:")
        chkDstCtrl := popup.Add("CheckBox", "x30 y165 w50", "Ctrl")
        chkDstShift := popup.Add("CheckBox", "x85 y165 w55", "Shift")
        chkDstWin := popup.Add("CheckBox", "x145 y165 w50", "Win")
        chkDstAlt := popup.Add("CheckBox", "x200 y165 w45", "Alt")
        cbDst := popup.Add("ComboBox", "x255 y162 w195", comboList)

        ; Set values if editing
        if (isEdit) {
            chkSrcCtrl.Value := srcParsed.Mods.Ctrl
            chkSrcShift.Value := srcParsed.Mods.Shift
            chkSrcWin.Value := srcParsed.Mods.Win
            chkSrcAlt.Value := srcParsed.Mods.Alt
            cbSrc.Text := GetDisplayString(srcParsed.BaseKey)

            chkDstCtrl.Value := dstParsed.Mods.Ctrl
            chkDstShift.Value := dstParsed.Mods.Shift
            chkDstWin.Value := dstParsed.Mods.Win
            chkDstAlt.Value := dstParsed.Mods.Alt
            cbDst.Text := GetDisplayString(dstParsed.BaseKey)
        }

        ; Action buttons
        popup.SetFont("s10 cWhite bold", "Segoe UI")
        btnConfirm := popup.Add("Button", "x240 y230 w225 h35", isEdit ? "💾 Modify Mapping" : "➕ Add Mapping")
        popup.SetFont("s10 cBlack norm", "Segoe UI")
        btnConfirm.OnEvent("Click", (*) => OnConfirm())

        btnCancel := popup.Add("Button", "x15 y230 w215 h35", "Cancel")
        btnCancel.OnEvent("Click", (*) => CleanUpAndClose())

        OnConfirm() {
            srcDisp := Trim(cbSrc.Text)
            dstDisp := Trim(cbDst.Text)
            if (srcDisp == "" || dstDisp == "") {
                MsgBox("⚠️ Please select or type both Source and Destination keys.", "Warning", 262192)
                return
            }

            srcBase := GetKeyFromDisp(srcDisp)
            dstBase := GetKeyFromDisp(dstDisp)

            try validName := GetKeyName(srcBase)
            catch
                validName := ""
            if (validName == "") {
                MsgBox("⚠️ '" . srcBase . "' is not a valid key name.", "Invalid Key", 262160)
                return
            }

            try validDstName := GetKeyName(dstBase)
            catch
                validDstName := ""
            if (validDstName == "") {
                MsgBox("⚠️ '" . dstBase . "' is not a valid key name.", "Invalid Key", 262160)
                return
            }

            src := BuildKeyString(chkSrcCtrl.Value, chkSrcShift.Value, chkSrcWin.Value, chkSrcAlt.Value, srcBase)
            dst := BuildKeyString(chkDstCtrl.Value, chkDstShift.Value, chkDstWin.Value, chkDstAlt.Value, dstBase)

            blacklist := ["lbutton", "rbutton", "mbutton", "escape"]
            if (HasVal(blacklist, StrLower(src))) {
                MsgBox("⚠️ The standalone key '" . src . "' is critical and blocked to prevent system lockout.`n`nHowever, you CAN remap it by combining it with modifier keys (Ctrl, Shift, Win, Alt).", "Remap Blocked", 262160)
                return
            }

            ; Duplicate check
            for idx, item in this.localData {
                if (isEdit && idx == editIdx)
                    continue
                if (StrLower(item.Src) == StrLower(src)) {
                    MsgBox("⚠️ A mapping for '" . src . "' already exists.", "Duplicate Mapping", 262160)
                    return
                }
            }

            if (isEdit) {
                this.localData[editIdx] := { Src: src, Dst: dst }
            } else {
                this.localData.Push({ Src: src, Dst: dst })
            }

            if !this.SaveSettings(false)
                return
            this.RefreshList(isEdit ? editIdx : this.localData.Length)
            CleanUpAndClose()
            this.ShowAutoSaveFeedback(isEdit ? "✅ Mapping saved and applied" : "✅ Mapping added and applied")
        }

        ShowCenteredOnMouse(popup, "w480 h280")
    }

    IsDirty() {
        return false
    }

    RequestReset() {
        if (this.HasOwnProp("dashboardResetHandler"))
            this.dashboardResetHandler.Call("Key Remaps")
        else
            ResetToDefaults("Key Remaps")
    }

    SaveSettings(showFeedback := true) {
        try {
            ConfigWriteKeyRemaps(this.localData)
        } catch Error as err {
            this.localData := ConfigReadKeyRemaps()
            this.RefreshList()
            MsgBox("❌ The key mapping change could not be saved and was not applied.`n`nError: " . err.Message,
                "Save Failed", 262160)
            return false
        }

        try {
            LoadKeyRemaps()
        } catch Error as err {
            MsgBox("⚠️ The key mapping was saved, but the running app could not activate it.`n`n"
                . "Reload SwiftDeck to apply the saved change.`n`nError: " . err.Message,
                "Apply Failed", 262160)
            return true
        }

        if showFeedback
            this.ShowAutoSaveFeedback()
        return true
    }

    ShowAutoSaveFeedback(message := "✅ Saved and applied") {
        ToolTip(message)
        SetTimer(() => ToolTip(), -2000)
    }
}

HasVal(arr, val) {
    for index, value in arr {
        if (value == val)
            return true
    }
    return false
}

LoadKeyRemaps() {
    global g_registeredKeyRemaps

    ; Unregister existing key mappings
    for srcKey in g_registeredKeyRemaps {
        try Hotkey(srcKey, "Off")
        try Hotkey(srcKey . " Up", "Off")
    }
    g_registeredKeyRemaps.Clear()

    if !ConfigExists("KeyRemaps")
        return

    for item in ConfigReadKeyRemaps() {
        if (item.Src != "" && item.Dst != "") {
            try {
                if IsMouseButton(item.Dst) {
                    Hotkey(item.Src, RemapMouseDownHandler.Bind(item.Dst))
                    Hotkey(item.Src . " Up", RemapMouseUpHandler.Bind(item.Dst))
                } else {
                    Hotkey(item.Src, RemapGenericHandler.Bind(item.Dst))
                }
                g_registeredKeyRemaps[item.Src] := item.Dst
            }
        }
    }
}

IsMouseButton(dst) {
    lowerDst := StrLower(ParseKeyString(dst).BaseKey)
    return (lowerDst == "lbutton" || lowerDst == "rbutton" || lowerDst == "mbutton" || lowerDst == "xbutton1" || lowerDst == "xbutton2")
}

RemapGenericHandler(dst, ThisHotkey) {
    if (dst != "")
        Send(FormatKeyStringForSend(dst))
}

RemapMouseDownHandler(dst, ThisHotkey) {
    if (dst != "")
        Send(FormatKeyStringForSend(dst, "Down"))
}

RemapMouseUpHandler(dst, ThisHotkey) {
    if (dst != "")
        Send(FormatKeyStringForSend(dst, "Up"))
}

FormatKeyStringForSend(keyStr, eventType := "") {
    parsed := ParseKeyString(keyStr)
    modStr := BuildKeyString(parsed.Mods.Ctrl, parsed.Mods.Shift, parsed.Mods.Win, parsed.Mods.Alt, "")
    baseKey := parsed.BaseKey

    if (eventType != "")
        suffix := " " . eventType
    else
        suffix := ""

    if (baseKey == "")
        return modStr
    if (StrLen(baseKey) == 1 && suffix == "")
        return modStr . baseKey
    return modStr . "{" . baseKey . suffix . "}"
}

CleanupKeyRemaps(ExitReason, ExitCode) {
    global g_registeredKeyRemaps
    for srcKey in g_registeredKeyRemaps {
        try Hotkey(srcKey, "Off")
        try Hotkey(srcKey . " Up", "Off")
    }
}

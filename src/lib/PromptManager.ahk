#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Theme.ahk
#Include Utils.ahk
#Include Migration.ahk
#Include Clipboard.ahk

; =================================================================================
; Module: PromptManager
; Description: Manages the Quick Prompts UI, shortcut execution, and data storage.
; Author: KBPark
; =================================================================================
class PromptManager {
    static selectedIndex := 0
    static dataGroup := []

    ; ==========================================
    ; --- 1. Execution Engine (Static) ---
    ; ==========================================
    static ProcessQuickPrompt(groupNum) {
        PromptManager.selectedIndex := 0
        PromptManager.dataGroup := ConfigReadPromptItems(groupNum)
        tapKey := GetPromptTapKey(A_ThisHotkey)

        if !ConfigExists("Prompts")
            return

        if (PromptManager.dataGroup.Length = 0) {
            ; The rest of the UI is English; this one string was bilingual.
            ToolTip("⚠️ Quick Prompt slot " . groupNum . " is empty`nAdd prompts in App Settings → Prompts")
            SetTimer(() => ToolTip(), -1000)
            return
        }

        PromptManager.dataGroup.Push({
            fontSize: 11,
            fontColor: "black",
            label: "Nothing",
            msg: ""
        })

        hkDisplay := FormatHotkeyDisplay(A_ThisHotkey)
        total := PromptManager.dataGroup.Length

        while PromptHotkeyModifierPressed(A_ThisHotkey) {
            if GetKeyState(tapKey, "P") {
                PromptManager.selectedIndex := (PromptManager.selectedIndex < PromptManager.dataGroup.Length) ? PromptManager.selectedIndex + 1 :
                    1
                sel := PromptManager.selectedIndex
                ; Show the hotkey and position (e.g. "Win+Numpad1 (2/5)") above the title.
                ToolTip(hkDisplay . " (" . sel . "/" . total . ")`n" . PromptManager.dataGroup[sel].label)
                Sleep(200)
            } else {
                Sleep(10)
            }
        }

        Sleep(100)

        if (PromptManager.selectedIndex > 0) {
            SetTimer(() => PromptManager.ExecutePrompt(), -1)
        }
        return
    }

    static ExecutePrompt() {
        if (PromptManager.selectedIndex > 0 && PromptManager.selectedIndex <= PromptManager.dataGroup.Length && PromptManager.dataGroup[
            PromptManager.selectedIndex].msg != "") {
            msg := PromptManager.dataGroup[PromptManager.selectedIndex].msg
            if (HasSpecialKeys(msg)) {
                ExecutePromptSequence(msg)
            } else {
                ; Return without clearing the tooltip on failure: PastePromptText
                ; has just shown the "clipboard is busy" warning, and the
                ; ToolTip() below would wipe it in the same tick.
                if !PastePromptText(msg,
                    PromptManager.dataGroup[PromptManager.selectedIndex].fontColor,
                    PromptManager.dataGroup[PromptManager.selectedIndex].fontSize)
                    return
            }
        }
        ToolTip()
        return
    }

    ; ==========================================
    ; --- 2. GUI Manager (Instance) ---
    ; ==========================================
    __New(parentGui := "") {
        this.parentGui := parentGui
        this.localData := ConfigReadPromptData()
        if (parentGui)
            this.BuildUI(parentGui)
    }

    Show() {
        if (!this.parentGui) {
            this.hGui := Gui("+AlwaysOnTop", "Quick Prompts Manager")
            EnableDarkMode(this.hGui)
            this.BuildUI(this.hGui)
            ShowCenteredOnMouse(this.hGui, "w460 h555")
        }
    }

    BuildUI(guiObj) {
        startX := this.parentGui ? 30 : 30
        startY := this.parentGui ? 120 : 20
        listHeight := this.parentGui ? 165 : 210
        previewLabelOffset := this.parentGui ? 230 : 275
        previewEditOffset := this.parentGui ? 250 : 295
        autoSaveOffset := this.parentGui ? 370 : 415
        this.mainHwnd := guiObj.Hwnd
        if (!this.parentGui)
            guiObj.OnEvent("Close", (*) => guiObj.Destroy())

        settings := ConfigReadAppSettings()
        migrated := MigratePromptModifier(settings.PromptModifier, settings.PromptUseNumpad)
        friendlyMod := FormatHotkeyDisplay(migrated.Mod)
        keySuffix := migrated.UseNumpad ? "Numpad" : "Number"
        slotText := "① Select Slot (" . friendlyMod . keySuffix . "):"

        slotChoices := []
        loop 10 {
            slotNum := Mod(A_Index, 10)
            slotChoices.Push(keySuffix . " " . slotNum)
        }

        guiObj.Add("Text", "x" . startX . " y" . startY . " w300", slotText)

        guiObj.SetFont("cBlack")
        this.ddlNumpad := guiObj.Add("DropDownList", "x" . (startX + 220) . " y" . (startY - 5) . " w180 Choose1", slotChoices)
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.Add("Text", "x" . startX . " y" . (startY + 35) . " w200", "② Prompts in this Slot:")

        guiObj.SetFont("cBlack")
        this.lbItems := guiObj.Add("ListBox", "x" . startX . " y" . (startY + 55) . " w295 h" . listHeight)
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.Add("Text", "x" . startX . " y" . (startY + previewLabelOffset) . " w200", "③ Content Preview:")

        guiObj.SetFont("c444444")
        this.edtPreview := guiObj.Add("Edit", "x" . startX . " y" . (startY + previewEditOffset) . " w400 h105 ReadOnly Multi BackgroundD4D4D4", "")
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.SetFont("s9 cD03A3A norm", "Segoe UI")
        btnReset := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 25) . " w95 h25", "⚠️ Reset")
        btnReset.OnEvent("Click", (*) => this.RequestReset())
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        btnNew := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 55) . " w95 h35", "➕ New")
        btnEdit := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 95) . " w95 h35", "✏️ Edit")
        btnDel := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 135) . " w95 h35", "❌ Delete")
        guiObj.SetFont("s9 cWhite norm", "Segoe UI")
        btnUp := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 175) . " w95 h35", "▲ Up")
        btnDown := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 215) . " w95 h35", "▼ Down")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        if (!this.parentGui) {
            btnClose := guiObj.Add("Button", "x" . (startX + 305) . " y" . (startY + 455) . " w95 h35", "Close")
            btnClose.OnEvent("Click", (*) => guiObj.Destroy())
        }

        this.ddlNumpad.OnEvent("Change", (*) => this.RefreshList(0))
        this.lbItems.OnEvent("Change", (*) => this.UpdatePreview())
        this.lbItems.OnEvent("DoubleClick", (*) => this.EditSelectedItem())
        btnNew.OnEvent("Click", (*) => this.ShowEditPopup(false, 0))
        btnEdit.OnEvent("Click", (*) => this.EditSelectedItem())
        btnDel.OnEvent("Click", (*) => this.DeleteItem())
        btnUp.OnEvent("Click", (*) => this.MoveItem(-1))
        btnDown.OnEvent("Click", (*) => this.MoveItem(1))

        guiObj.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + autoSaveOffset) . " w400 Center", "✓ Changes are saved and applied immediately.")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        this.RefreshList()
    }

    ShowEditPopup(isEdit := false, editIdx := 0) {
        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", isEdit ? "Edit Prompt" : "Add Prompt")

        CleanUpAndClose() {
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))

        tVal := ""
        mVal := ""
        if (isEdit && editIdx > 0 && editIdx <= this.localData[currNum].Length) {
            item := this.localData[currNum][editIdx]
            tVal := item.Title
            mVal := item.Msg
        }

        popup.Add("Text", "x15 y15 w400 c666666", "① Prompt Title:")
        edtTitle := popup.Add("Edit", "x15 y35 w400 h25", tVal)

        popup.Add("Text", "x15 y70 w130 c666666", "② Prompt Content:")

        popup.SetFont("s9 cBlack norm", "Segoe UI")
        ddlLang := popup.Add("DropDownList", "x145 y65 w80 Choose1", ["Korean", "English", "Polish", "German", "French", "Spanish"])

        popup.SetFont("s9 cWhite Bold", "Segoe UI")
        btnTranslate := popup.Add("Button", "x230 y65 w80 h24", "🌐 Translate")
        btnInsertKey := popup.Add("Button", "x315 y65 w100 h24", "Insert Key ▼")
        popup.SetFont("s10 cBlack norm", "Segoe UI")

        edtMsg := popup.Add("Edit", "x15 y95 w400 h120 Multi", mVal)

        InsertKeyTag := (ItemName, ItemPos, MyMenu) => InsertKeyToEdit(ItemName)
        InsertKeyToEdit(ItemName) {
            if (RegExMatch(ItemName, "\{[^}]+\}", &tagMatch)) {
                tag := tagMatch[0]
                edtMsg.Value := edtMsg.Value . tag
                ControlFocus(edtMsg.Hwnd)
                Send("^{End}")
            }
        }

        keyMenu := Menu()
        keyMenu.Add("{Enter}", InsertKeyTag)
        keyMenu.Add("{Tab}", InsertKeyTag)
        keyMenu.Add("{Esc}", InsertKeyTag)
        keyMenu.Add("{Backspace}", InsertKeyTag)
        keyMenu.Add("{Space}", InsertKeyTag)
        keyMenu.Add("{Delete}", InsertKeyTag)
        keyMenu.Add()
        mNav := Menu()
        mNav.Add("{Up}", InsertKeyTag)
        mNav.Add("{Down}", InsertKeyTag)
        mNav.Add("{Left}", InsertKeyTag)
        mNav.Add("{Right}", InsertKeyTag)
        mNav.Add("{Home}", InsertKeyTag)
        mNav.Add("{End}", InsertKeyTag)
        keyMenu.Add("Navigation", mNav)
        mShort := Menu()
        mShort.Add("{Ctrl+a} Select All", InsertKeyTag)
        mShort.Add("{Ctrl+c} Copy", InsertKeyTag)
        mShort.Add("{Ctrl+v} Paste", InsertKeyTag)
        mShort.Add("{Ctrl+x} Cut", InsertKeyTag)
        mShort.Add("{Ctrl+z} Undo", InsertKeyTag)
        mShort.Add("{Ctrl+l} Address Bar", InsertKeyTag)
        mShort.Add("{Ctrl+s} Save", InsertKeyTag)
        mShort.Add("{Ctrl+End} Go to End", InsertKeyTag)
        keyMenu.Add("Shortcuts", mShort)
        keyMenu.Add()
        mDelay := Menu()
        mDelay.Add("{Wait:300} 0.3s", InsertKeyTag)
        mDelay.Add("{Wait:500} 0.5s", InsertKeyTag)
        mDelay.Add("{Wait:1000} 1s", InsertKeyTag)
        mDelay.Add("{Wait:2000} 2s", InsertKeyTag)
        mDelay.Add("{Wait:3000} 3s", InsertKeyTag)
        keyMenu.Add("Delay", mDelay)

        btnInsertKey.OnEvent("Click", (*) => keyMenu.Show())

        btnTranslate.OnEvent("Click", (*) => OnTranslate())

        OnTranslate() {
            srcText := Trim(edtMsg.Value)
            if (srcText == "")
                return

            langMap := ["ko", "en", "pl", "de", "fr", "es"]
            targetLang := langMap[ddlLang.Value]

            ToolTip("⏳ Translating...")
            WinSetEnabled(0, popup.Hwnd)
            
            ; GoogleTranslate reports failure as "" rather than throwing, so the
            ; empty branch is the only failure path — a catch here would be dead
            ; code. The window is re-enabled below whatever the outcome.
            translatedText := GoogleTranslate(srcText, targetLang)
            if (translatedText != "")
                edtMsg.Value := translatedText
            else
                MsgBox("Translation failed.`n`nThe service could not be reached, or it returned"
                    . " nothing usable. Your text was left unchanged.", "Translation Failed", 262160)
            
            WinSetEnabled(1, popup.Hwnd)
            WinActivate(popup.Hwnd)
            ToolTip()
        }

        popup.SetFont("s10 cWhite bold", "Segoe UI")
        btnConfirm := popup.Add("Button", "x225 y230 w190 h35", isEdit ? "💾 Modify Prompt" : "➕ Add Prompt")
        popup.SetFont("s10 cBlack norm", "Segoe UI")
        btnConfirm.OnEvent("Click", (*) => OnConfirm())

        btnCancel := popup.Add("Button", "x15 y230 w190 h35", "Cancel")
        btnCancel.OnEvent("Click", (*) => CleanUpAndClose())

        OnConfirm() {
            t := Trim(edtTitle.Value)
            m := Trim(edtMsg.Value)
            if (t == "") {
                MsgBox("⚠️ Please enter a title.", "Warning", 262192)
                return
            }
            if (!IsPlainIniKeySafe(t)) {
                MsgBox("⚠️ " . GetIniKeyRuleMessage(), "Invalid Prompt Title", 262192)
                return
            }

            ; Check the resulting slot size before committing it to memory, so an
            ; over-long prompt is refused instead of being written as a section
            ; Windows cannot read back (which the next save turns into deletion).
            candidate := []
            for existing in this.localData[currNum]
                candidate.Push(existing)
            if (isEdit)
                candidate[editIdx] := { Title: t, Msg: m }
            else
                candidate.Push({ Title: t, Msg: m })

            limitWarning := ConfigCheckPromptSlotLimit(candidate)
            if (limitWarning != "") {
                MsgBox("⚠️ " . limitWarning, "Prompt Slot Too Large", 262192)
                return
            }

            if (isEdit) {
                this.localData[currNum][editIdx].Title := t
                this.localData[currNum][editIdx].Msg := m
            } else {
                this.localData[currNum].Push({ Title: t, Msg: m })
            }

            if !this.SaveSettings(false)
                return
            this.RefreshList(isEdit ? editIdx : this.localData[currNum].Length)
            CleanUpAndClose()
            this.ShowAutoSaveFeedback(isEdit ? "✅ Prompt saved and applied" : "✅ Prompt added and applied")
        }

        ShowCenteredOnMouse(popup, "w430 h280")
    }

    EditSelectedItem() {
        idx := this.lbItems.Value
        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))
        if (idx > 0 && idx <= this.localData[currNum].Length) {
            this.ShowEditPopup(true, idx)
        }
    }

    ; Re-reads this tab's settings from disk. The dashboard is created once and
    ; only hidden on close, and every save rewrites the whole section from
    ; memory — so without this, edits made to the file meanwhile (App Info's
    ; Open buttons invite exactly that) are overwritten by the stale snapshot.
    ReloadFromDisk() {
        this.localData := ConfigReadPromptData()
    }

    RefreshList(targetIdx := 0) {
        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))

        this.lbItems.Delete()
        listData := []
        for idx, item in this.localData[currNum] {
            listData.Push(item.Title)
        }
        if (listData.Length > 0)
            this.lbItems.Add(listData)

        if (targetIdx > 0 && targetIdx <= listData.Length) {
            this.lbItems.Choose(targetIdx)
        }
        this.UpdatePreview()
    }

    UpdatePreview() {
        idx := this.lbItems.Value
        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))
        if (idx > 0 && idx <= this.localData[currNum].Length) {
            this.edtPreview.Value := this.localData[currNum][idx].Msg
        } else {
            this.edtPreview.Value := ""
        }
    }

    MoveItem(dir) {
        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))
        idx := this.lbItems.Value
        if (idx == 0)
            return

        targetIdx := idx + dir
        if (targetIdx < 1 || targetIdx > this.localData[currNum].Length)
            return

        temp := this.localData[currNum][idx]
        this.localData[currNum][idx] := this.localData[currNum][targetIdx]
        this.localData[currNum][targetIdx] := temp

        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback()
        }
    }

    DeleteItem() {
        currNum := Integer(SubStr(this.ddlNumpad.Text, 8))
        selIdx := this.lbItems.Value

        if (selIdx == 0)
            return

        itemTitle := this.localData[currNum][selIdx].Title
        msgRes := MsgBox("❓ Are you sure you want to delete this prompt?`n`n[" . itemTitle . "]", "Confirm Delete", 262436)
        if (msgRes != "Yes")
            return

        this.localData[currNum].RemoveAt(selIdx)

        targetIdx := selIdx > this.localData[currNum].Length ? this.localData[currNum].Length : selIdx
        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback("✅ Prompt deleted and applied")
        }
    }

    IsDirty() {
        return false
    }

    RequestReset() {
        if (this.HasOwnProp("dashboardResetHandler"))
            this.dashboardResetHandler.Call("Prompts")
        else
            ResetToDefaults("Prompts")
    }

    SaveSettings(showFeedback := true) {
        try {
            ConfigWritePromptData(this.localData)
            if showFeedback
                this.ShowAutoSaveFeedback()
            return true
        } catch Error as err {
            this.localData := ConfigReadPromptData()
            this.RefreshList()
            MsgBox("❌ The prompt change could not be saved and was not applied.`n`nError: " . err.Message,
                "Save Failed", 262160)
            return false
        }
    }

    ShowAutoSaveFeedback(message := "✅ Saved and applied") {
        ToolTip(message)
        SetTimer(() => ToolTip(), -2000)
    }
}

GetPromptTapKey(hotkeyText) {
    baseKey := hotkeyText
    while (baseKey != "") {
        firstChar := SubStr(baseKey, 1, 1)
        if InStr("^+#!", firstChar)
            baseKey := SubStr(baseKey, 2)
        else
            break
    }
    return baseKey
}

PromptHotkeyModifierPressed(hotkeyText) {
    pressed := false
    if InStr(hotkeyText, "^")
        pressed := pressed || GetKeyState("LCtrl", "P") || GetKeyState("RCtrl", "P")
    if InStr(hotkeyText, "+")
        pressed := pressed || GetKeyState("LShift", "P") || GetKeyState("RShift", "P")
    if InStr(hotkeyText, "#")
        pressed := pressed || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    if InStr(hotkeyText, "!")
        pressed := pressed || GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")
    return pressed
}

; =================================================================================
; --- Prompt Sequence Execution Engine ---
; =================================================================================

HasSpecialKeys(msg) {
    return RegExMatch(msg, "\{[^}]+\}")
}

ExecutePromptSequence(msg) {
    static DEFAULT_KEY_DELAY := 50
    static PASTE_DELAY := 100
    pos := 1
    msgLen := StrLen(msg)

    while (pos <= msgLen) {
        if (RegExMatch(msg, "\{[^}]+\}", &m, pos) && m.Pos == pos) {
            tagContent := SubStr(m[0], 2, StrLen(m[0]) - 2)

            if (RegExMatch(tagContent, "i)^Wait:(\d+)$", &wm)) {
                Sleep(Integer(wm[1]))
            } else if (RegExMatch(tagContent, "i)^(Ctrl|Alt|Shift|Win)\+")) {
                Send(_ConvertComboKey(tagContent))
                Sleep(DEFAULT_KEY_DELAY)
            } else {
                Send("{" . tagContent . "}")
                Sleep(DEFAULT_KEY_DELAY)
            }
            pos := m.Pos + m.Len
        } else {
            nextTag := RegExMatch(msg, "\{[^}]+\}", &nm, pos)
            if (nextTag > 0) {
                plainText := SubStr(msg, pos, nextTag - pos)
                pos := nextTag
            } else {
                plainText := SubStr(msg, pos)
                pos := msgLen + 1
            }
            if (plainText != "") {
                A_Clipboard := plainText
                ClipWait(1)
                Send("^v")
                Sleep(PASTE_DELAY)
            }
        }
    }
}

_ConvertComboKey(tagContent) {
    parts := StrSplit(tagContent, "+")
    modStr := ""
    keyPart := ""

    for i, part in parts {
        p := Trim(part)
        if (i < parts.Length) {
            switch StrLower(p) {
                case "ctrl":  modStr .= "^"
                case "alt":   modStr .= "!"
                case "shift": modStr .= "+"
                case "win":   modStr .= "#"
                default:      keyPart .= p . "+"
            }
        } else {
            keyPart .= p
        }
    }

    if (StrLen(keyPart) > 1)
        keyPart := "{" . keyPart . "}"

    return modStr . keyPart
}

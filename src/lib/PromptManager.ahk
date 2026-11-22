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
        if PromptSequenceBusy()
            return
        PromptManager.selectedIndex := 0
        PromptManager.dataGroup := ConfigReadPromptItems(groupNum)
        tapKey := GetPromptTapKey(A_ThisHotkey)

        if !ConfigExists("Prompts")
            return

        slotName := ConfigReadPromptSlotNames()[groupNum]
        if (PromptManager.dataGroup.Length = 0) {
            ; The rest of the UI is English; this one string was bilingual.
            ToolTip("⚠️ Quick Prompt slot " . groupNum . (slotName != "" ? " (" . slotName . ")" : "")
                . " is empty`nAdd prompts in App Settings → Prompts")
            SetTimer(() => ToolTip(), -1000)
            return
        }

        PromptManager.dataGroup.Push({
            fontSize: 11,
            fontColor: "black",
            label: "Nothing",
            msg: ""
        })

        hkDisplay := FormatHotkeyDisplay(A_ThisHotkey) . (slotName != "" ? " · " . slotName : "")
        total := PromptManager.dataGroup.Length

        while PromptHotkeyModifierPressed(A_ThisHotkey) {
            if GetKeyState("Escape", "P") {
                PromptManager.selectedIndex := 0
                ShowFeedbackToolTip("🚫 Prompt cancelled", 1000)
                return
            }
            if GetKeyState(tapKey, "P") {
                PromptManager.selectedIndex := (PromptManager.selectedIndex < PromptManager.dataGroup.Length) ? PromptManager.selectedIndex + 1 :
                    1
                sel := PromptManager.selectedIndex
                ; Show the hotkey, slot name and position (e.g. "Win+Numpad1 · Outlook (2/5)") above the title.
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
        if PromptSequenceBusy()
            return
        if (PromptManager.selectedIndex > 0 && PromptManager.selectedIndex <= PromptManager.dataGroup.Length && PromptManager.dataGroup[
            PromptManager.selectedIndex].msg != "") {
            msg := PromptManager.dataGroup[PromptManager.selectedIndex].msg
            if (HasSpecialKeys(msg)) {
                ExecutePromptSequence(msg)
            } else {
                expanded := ExpandPromptDynamicTokens(msg, GetUserClipboardText())
                if (expanded == "") {
                    ShowFeedbackToolTip("ℹ️ Nothing to paste (clipboard has no text)", 1500)
                    return
                }
                ; Return without clearing the tooltip on failure: PastePromptText
                ; has just shown the "clipboard is busy" warning, and the
                ; ToolTip() below would wipe it in the same tick.
                if !PastePromptText(expanded,
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
        this.isEditingPopup := false
        this.localData := ConfigReadPromptData()
        this.slotNames := ConfigReadPromptSlotNames()
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
        ; Dashboard tabs share x35 and a button column at x+310, so switching
        ; tabs does not shift the layout sideways.
        startX := this.parentGui ? 35 : 30
        startY := this.parentGui ? 110 : 20
        listHeight := this.parentGui ? 165 : 210
        previewLabelOffset := this.parentGui ? 230 : 275
        previewEditOffset := this.parentGui ? 250 : 295
        previewHeight := this.parentGui ? 95 : 105
        autoSaveOffset := this.parentGui ? 355 : 415
        this.mainHwnd := guiObj.Hwnd
        if (!this.parentGui)
            guiObj.OnEvent("Close", (*) => guiObj.Destroy())

        settings := ConfigGetFallbackAppSettings()
        try settings := ConfigReadAppSettings()
        migrated := MigratePromptModifier(settings.PromptModifier, settings.PromptUseNumpad)
        friendlyMod := FormatHotkeyDisplay(migrated.Mod)
        keySuffix := migrated.UseNumpad ? "Numpad" : "Number"
        this.slotKeySuffix := keySuffix
        slotText := "① Select Slot (" . friendlyMod . keySuffix . "):"

        this.txtSlotHeader := guiObj.Add("Text", "x" . startX . " y" . startY . " w215", slotText)

        guiObj.SetFont("cBlack")
        this.ddlNumpad := guiObj.Add("DropDownList", "x" . (startX + 220) . " y" . (startY - 5) . " w185 Choose1", this.BuildSlotChoices())
        ; Let the open list run wider than the box, so a long slot name is
        ; shown in full there even when the closed box cuts it off.
        SendMessage(0x0160, Round(280 * A_ScreenDPI / 96), 0, this.ddlNumpad)  ; CB_SETDROPPEDWIDTH
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.Add("Text", "x" . startX . " y" . (startY + 35) . " w200", "② Prompts in this Slot:")

        guiObj.SetFont("s9 c" . THEME_TEXT . " norm", "Segoe UI")
        btnName := guiObj.Add("Button", "x" . (startX + 205) . " y" . (startY + 25) . " w95 h25", "🏷️ Name Slot")
        btnName.OnEvent("Click", (*) => this.RenameSlot(guiObj))
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        guiObj.SetFont("cBlack")
        this.lbItems := guiObj.Add("ListBox", "x" . startX . " y" . (startY + 55) . " w300 h" . listHeight)
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.Add("Text", "x" . startX . " y" . (startY + previewLabelOffset) . " w200", "③ Content Preview:")

        guiObj.SetFont("c444444")
        this.edtPreview := guiObj.Add("Edit", "x" . startX . " y" . (startY + previewEditOffset) . " w405 h" . previewHeight . " ReadOnly Multi BackgroundD4D4D4", "")
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.SetFont("s9 cD03A3A norm", "Segoe UI")
        btnReset := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 25) . " w95 h25", "⚠️ Reset")
        btnReset.OnEvent("Click", (*) => this.RequestReset())
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        btnNew := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 55) . " w95 h35", "➕ New")
        btnEdit := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 95) . " w95 h35", "✏️ Edit")
        btnDel := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 135) . " w95 h35", "❌ Delete")
        guiObj.SetFont("s9 cWhite norm", "Segoe UI")
        btnUp := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 175) . " w95 h35", "▲ Up")
        btnDown := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 215) . " w95 h35", "▼ Down")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        if (!this.parentGui) {
            btnClose := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 455) . " w95 h35", "Close")
            btnClose.OnEvent("Click", (*) => guiObj.Destroy())
        }

        this.btnAdd := btnNew
        this.selectionButtons := [btnEdit, btnDel, btnUp, btnDown]
        this.ddlNumpad.OnEvent("Change", (*) => this.RefreshList(0))
        this.lbItems.OnEvent("Change", (*) => this.UpdatePreview())
        this.lbItems.OnEvent("DoubleClick", (*) => this.EditSelectedItem())
        btnNew.OnEvent("Click", (*) => this.ShowEditPopup(false, 0))
        btnEdit.OnEvent("Click", (*) => this.EditSelectedItem())
        btnDel.OnEvent("Click", (*) => this.DeleteItem())
        btnUp.OnEvent("Click", (*) => this.MoveItem(-1))
        btnDown.OnEvent("Click", (*) => this.MoveItem(1))

        guiObj.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + autoSaveOffset) . " w405 Center", "✓ Changes are saved and applied immediately.")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        this.RefreshList()
    }

    ShowEditPopup(isEdit := false, editIdx := 0) {
        this.isEditingPopup := true
        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", isEdit ? "Edit Prompt" : "Add Prompt")

        CleanUpAndClose() {
            this.isEditingPopup := false
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        currNum := this.CurrentSlotNum()

        tVal := ""
        mVal := ""
        origTitle := ""
        origMsg := ""
        if (isEdit && editIdx > 0 && editIdx <= this.localData[currNum].Length) {
            item := this.localData[currNum][editIdx]
            tVal := item.Title
            mVal := item.Msg
            origTitle := tVal
            origMsg := mVal
        }

        popup.Add("Text", "x15 y15 w245 c666666", "① Prompt Title:")
        edtTitle := popup.Add("Edit", "x15 y35 w245 h25", tVal)

        popup.Add("Text", "x270 y15 w145 c666666", "Slot:")
        ddlTargetSlot := popup.Add("DropDownList", "x270 y35 w145 Choose" . this.ddlNumpad.Value, this.BuildSlotChoices())
        SendMessage(0x0160, Round(240 * A_ScreenDPI / 96), 0, ddlTargetSlot)  ; CB_SETDROPPEDWIDTH

        popup.Add("Text", "x15 y70 w130 c666666", "② Prompt Content:")

        popup.SetFont("s9 cBlack norm", "Segoe UI")
        ddlLang := popup.Add("DropDownList", "x145 y65 w80 Choose1", ["Korean", "English", "Polish", "German", "French", "Spanish"])

        popup.SetFont("s9 cWhite Bold", "Segoe UI")
        btnTranslate := popup.Add("Button", "x230 y65 w80 h24", "🌐 Translate")
        btnInsertKey := popup.Add("Button", "x315 y65 w100 h24", "Insert Key ▼")
        popup.SetFont("s10 cBlack norm", "Segoe UI")

        edtMsg := popup.Add("Edit", "x15 y95 w400 h120 Multi", mVal)
        ; Keep the caret at the end whenever the text is set from code, so
        ; Insert Key still appends when the content box was never clicked.
        ; Setting .Value moves the caret back to the start.
        MoveMsgCaretToEnd() {
            msgLen := SendMessage(0x000E, 0, 0, edtMsg)                ; WM_GETTEXTLENGTH
            SendMessage(0x00B1, msgLen, msgLen, edtMsg)                ; EM_SETSEL
        }
        MoveMsgCaretToEnd()

        InsertKeyTag := (ItemName, ItemPos, MyMenu) => InsertKeyToEdit(ItemName)
        InsertKeyToEdit(ItemName) {
            if (RegExMatch(ItemName, "\{[^}]+\}", &tagMatch)) {
                tag := tagMatch[0]
                ; Insert at the caret. The selection is hidden while the menu
                ; is open, and tabbing into the box selects all of it, so any
                ; selection is collapsed to its end rather than replaced.
                selEnd := Buffer(4, 0)
                SendMessage(0x00B0, 0, selEnd.Ptr, edtMsg)                 ; EM_GETSEL
                caret := NumGet(selEnd, 0, "UInt")
                SendMessage(0x00B1, caret, caret, edtMsg)                  ; EM_SETSEL
                SendMessage(0x00C2, true, StrPtr(tag), edtMsg)             ; EM_REPLACESEL, undoable
                ControlFocus(edtMsg.Hwnd)
                SendMessage(0x00B7, 0, 0, edtMsg)                          ; EM_SCROLLCARET
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
        keyMenu.Add()
        mDynamic := Menu()
        mDynamic.Add("{Clipboard} Copied Text", InsertKeyTag)
        mDynamic.Add("{Date} Today (YYYY-MM-DD)", InsertKeyTag)
        mDynamic.Add("{Time} Current Time (HH:MM)", InsertKeyTag)
        keyMenu.Add("Dynamic Text", mDynamic)

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
            if (translatedText != "") {
                edtMsg.Value := translatedText
                MoveMsgCaretToEnd()
            } else
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

            targetDropdownIdx := ddlTargetSlot.Value
            targetNum := Mod(targetDropdownIdx, 10)

            ; Apply this one change to the slots as they are on disk now. The
            ; copy in memory is the one the window opened with, and saving it
            ; would overwrite all ten slots, losing anything changed in the
            ; file meanwhile (App Info's Open buttons, a synced copy).
            try latest := ConfigReadPromptData()
            catch Error as err {
                MsgBox("❌ The prompt file could not be read, so nothing was saved.`n`nError: " . err.Message,
                    "Save Failed", 262160)
                return
            }
            if !PromptApplyEdit(latest, currNum, targetNum, isEdit, editIdx, origTitle, origMsg, t, m) {
                this.localData := latest
                this.RefreshList()
                MsgBox("⚠️ This prompt was changed outside this window while you were editing. Close and reopen it before saving.",
                    "Prompt List Changed", 262192)
                return
            }

            ; Check the resulting slot size before saving, so an over-long
            ; prompt is refused instead of being written as a section Windows
            ; cannot read back (which the next save turns into deletion).
            limitWarning := ConfigCheckPromptSlotLimit(latest[targetNum])
            if (limitWarning != "") {
                MsgBox("⚠️ " . limitWarning, "Prompt Slot Too Large", 262192)
                return
            }

            movedSlot := (targetNum != currNum)
            this.localData := latest
            if !this.SaveSettings(false)
                return
            if (movedSlot) {
                this.ddlNumpad.Choose(targetDropdownIdx)
                this.RefreshList(this.localData[targetNum].Length)
            } else {
                this.RefreshList(isEdit ? editIdx : this.localData[currNum].Length)
            }
            CleanUpAndClose()
            if (isEdit && movedSlot)
                this.ShowAutoSaveFeedback("✅ Prompt moved to " . this.slotKeySuffix . " " . targetNum)
            else
                this.ShowAutoSaveFeedback(isEdit ? "✅ Prompt saved and applied" : "✅ Prompt added and applied")
        }

        ShowCenteredOnMouse(popup, "w430 h280")
    }

    EditSelectedItem() {
        idx := this.lbItems.Value
        currNum := this.CurrentSlotNum()
        if (idx > 0 && idx <= this.localData[currNum].Length) {
            this.ShowEditPopup(true, idx)
        }
    }

    UpdateSlotHeader() {
        settings := ConfigGetFallbackAppSettings()
        try settings := ConfigReadAppSettings()
        migrated := MigratePromptModifier(settings.PromptModifier, settings.PromptUseNumpad)
        friendlyMod := FormatHotkeyDisplay(migrated.Mod)
        this.slotKeySuffix := migrated.UseNumpad ? "Numpad" : "Number"
        if this.HasOwnProp("txtSlotHeader")
            this.txtSlotHeader.Value := "① Select Slot (" . friendlyMod . this.slotKeySuffix . "):"
    }

    ; Re-reads this tab's settings from disk. The dashboard is created once and
    ; only hidden on close, and every save rewrites the whole section from
    ; memory — so without this, edits made to the file meanwhile (App Info's
    ; Open buttons invite exactly that) are overwritten by the stale snapshot.
    ReloadFromDisk() {
        if this.isEditingPopup
            return
        this.localData := ConfigReadPromptData()
        this.slotNames := ConfigReadPromptSlotNames()
        this.UpdateSlotHeader()
        if this.HasOwnProp("ddlNumpad")
            this.UpdateSlotChoices()
    }

    ; Slots 1-9 then 0, the order of the number row. A named slot shows its
    ; name after the key, e.g. "Numpad 1 · Outlook".
    BuildSlotChoices() {
        choices := []
        loop 10 {
            slotNum := Mod(A_Index, 10)
            label := this.slotKeySuffix . " " . slotNum
            if (this.slotNames[slotNum] != "")
                label .= " · " . this.slotNames[slotNum]
            choices.Push(label)
        }
        return choices
    }

    ; Rebuilds the dropdown text without moving the selection; Choose raises
    ; no Change event, so the list below stays as it is.
    UpdateSlotChoices() {
        selected := this.ddlNumpad.Value
        this.ddlNumpad.Delete()
        this.ddlNumpad.Add(this.BuildSlotChoices())
        this.ddlNumpad.Choose(selected ? selected : 1)
    }

    ; The dropdown position maps straight to the slot number (see
    ; BuildSlotChoices). Its text cannot be parsed for it: it carries the name.
    CurrentSlotNum() {
        return Mod(this.ddlNumpad.Value, 10)
    }

    RenameSlot(guiObj) {
        slotNum := this.CurrentSlotNum()
        oldName := this.slotNames[slotNum]
        maxLength := ConfigGetMaxPromptSlotNameLength()

        guiObj.Opt("+OwnDialogs")
        ib := InputBox("Name for slot " . slotNum . " (e.g. Outlook, Edge), up to " . maxLength . " characters."
            . "`nLeave it empty to remove the name.", "Name Slot", "w380 h140", oldName)
        if (ib.Result != "OK")
            return
        newName := ConfigNormalizePromptSlotName(ib.Value)
        if (newName == oldName)
            return
        if (StrLen(newName) > maxLength) {
            MsgBox("⚠️ A slot name can be up to " . maxLength . " characters.", "Name Too Long", 262192)
            return
        }

        try {
            ConfigWritePromptSlotName(slotNum, newName)
        } catch Error as err {
            MsgBox("❌ The slot name could not be saved.`n`nError: " . err.Message, "Save Failed", 262160)
            return
        }
        this.slotNames := ConfigReadPromptSlotNames()
        this.UpdateSlotChoices()
        this.ShowAutoSaveFeedback(newName == "" ? "✅ Slot name removed" : "✅ Slot name saved")
    }

    RefreshList(targetIdx := 0) {
        currNum := this.CurrentSlotNum()

        listData := []
        for idx, item in this.localData[currNum] {
            listData.Push(item.Title)
        }
        SetListBoxItems(this.lbItems, listData, "This slot is empty. Click ➕ New.")

        if (targetIdx > 0 && targetIdx <= listData.Length) {
            this.lbItems.Choose(targetIdx)
        }
        this.UpdatePreview()
    }

    UpdatePreview() {
        idx := this.lbItems.Value
        currNum := this.CurrentSlotNum()
        if (idx > 0 && idx <= this.localData[currNum].Length) {
            this.edtPreview.Value := this.localData[currNum][idx].Msg
        } else {
            this.edtPreview.Value := ""
        }
        UpdateSelectionButtons(this.lbItems, this.selectionButtons, this.btnAdd)
    }

    MoveItem(dir) {
        currNum := this.CurrentSlotNum()
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
        currNum := this.CurrentSlotNum()
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
            ; Keep the copy in memory equal to what the file reads back. A save
            ; does not round-trip text exactly (CRLF, outer whitespace), and the
            ; edit popup compares the file against this copy before saving.
            try this.localData := ConfigReadPromptData()
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
        ShowFeedbackToolTip(message)
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
    return RegExMatch(StripPromptDynamicTokens(msg), "\{[^}]+\}") > 0
}

; True while a prompt sequence runs. Its {Wait} and key delays let a second
; prompt start in the middle: that prompt's text landed between the first
; one's fragments, the first one's remaining keys ({Enter}) then acted on the
; mix, and the clipboard kept the second prompt instead of the user's copy.
; Every prompt entry point is refused meanwhile, rather than queued: a queued
; prompt would paste later into whatever window has the focus by then.
global g_promptSequenceRunning := false

; Returns true, and says why nothing happens, while a prompt sequence runs.
PromptSequenceBusy() {
    global g_promptSequenceRunning
    if !g_promptSequenceRunning
        return false
    ShowFeedbackToolTip("⏳ A prompt is still running — try again when it finishes", 1500)
    return true
}

ExecutePromptSequence(msg) {
    global g_promptSequenceRunning
    if PromptSequenceBusy()
        return
    g_promptSequenceRunning := true
    try RunPromptSequence(msg)
    finally g_promptSequenceRunning := false
}

RunPromptSequence(msg) {
    static DEFAULT_KEY_DELAY := 50
    static PASTE_DELAY := 100
    static ACTION_TAG_PATTERN := "i)\{(?!Clipboard\}|Date\}|Time\})[^}]+\}"

    snapshot := SnapshotUserClipboard()
    liveClipText := GetUserClipboardText()
    lastPasted := ""
    ; Clipboard sequence number right after this sequence's last write.
    lastWriteSeq := 0
    ; The sequence number when this sequence last looked at the clipboard.
    seenSeq := GetClipboardSequenceNumber()
    pendingCopyCheck := false
    seqBeforeCopy := 0
    pos := 1
    msgLen := StrLen(msg)

    RefreshClipboardAfterCopyTag() {
        if (!pendingCopyCheck)
            return
        loop 10 {
            if (GetClipboardSequenceNumber() != seqBeforeCopy)
                break
            Sleep(25)
        }
        if (GetClipboardSequenceNumber() != seqBeforeCopy) {
            liveClipText := GetCurrentClipboardText()
            freshSnapshot := CaptureClipboardSnapshot()
            if (freshSnapshot.HasSaved)
                snapshot := freshSnapshot
        }
        pendingCopyCheck := false
    }

    ; A copy made while the sequence runs, typically by the user during a
    ; {Wait}, is what must be kept: the next fragment would overwrite it and
    ; the restore afterwards would bring back the older snapshot. Any change
    ; counts, the same rule the restore timer applies: a copy of the same text
    ; in another format cannot be told apart from our own fragment by its text.
    KeepNewerClipboard() {
        nowSeq := GetClipboardSequenceNumber()
        if (seenSeq == 0 || nowSeq == seenSeq)
            return
        seenSeq := nowSeq
        liveClipText := GetCurrentClipboardText()
        freshSnapshot := CaptureClipboardSnapshot()
        if (freshSnapshot.HasSaved)
            snapshot := freshSnapshot
    }

    while (pos <= msgLen) {
        if (RegExMatch(msg, ACTION_TAG_PATTERN, &m, pos) && m.Pos == pos) {
            tagContent := SubStr(m[0], 2, StrLen(m[0]) - 2)

            if (RegExMatch(tagContent, "i)^Wait:(\d+)$", &wm)) {
                Sleep(Integer(wm[1]))
                if (pendingCopyCheck && GetClipboardSequenceNumber() != seqBeforeCopy) {
                    liveClipText := GetCurrentClipboardText()
                    freshSnapshot := CaptureClipboardSnapshot()
                    if (freshSnapshot.HasSaved)
                        snapshot := freshSnapshot
                    pendingCopyCheck := false
                }
            } else if (RegExMatch(tagContent, "i)^(Ctrl|Alt|Shift|Win)\+")) {
                isCopyTag := RegExMatch(tagContent, "i)^Ctrl\+(c|x)$") > 0
                if (isCopyTag)
                    seqBeforeCopy := GetClipboardSequenceNumber()
                Send(_ConvertComboKey(tagContent))
                Sleep(DEFAULT_KEY_DELAY)
                if (isCopyTag)
                    pendingCopyCheck := true
            } else {
                Send("{" . tagContent . "}")
                Sleep(DEFAULT_KEY_DELAY)
            }
            pos := m.Pos + m.Len
        } else {
            nextTag := RegExMatch(msg, ACTION_TAG_PATTERN, &nm, pos)
            if (nextTag > 0) {
                plainText := SubStr(msg, pos, nextTag - pos)
                pos := nextTag
            } else {
                plainText := SubStr(msg, pos)
                pos := msgLen + 1
            }
            if (plainText != "") {
                if (pendingCopyCheck)
                    RefreshClipboardAfterCopyTag()
                KeepNewerClipboard()
                expandedPlain := ExpandPromptDynamicTokens(plainText, liveClipText)
                if (expandedPlain != "") {
                    PausePendingClipboardRestore()
                    ; Same guarded write the plain paste path uses. A raw
                    ; "A_Clipboard :=" throws while a clipboard manager, RDP session
                    ; or Office has the clipboard open, and here that would surface
                    ; halfway through a key sequence, with part of it already sent.
                    if !TrySetPromptClipboard(expandedPlain) {
                        if (lastPasted != "")
                            ScheduleClipboardRestore(snapshot, lastPasted, 3000, lastWriteSeq)
                        else
                            ReschedulePendingClipboardRestore(3000)
                        ReportClipboardBusy()
                        return
                    }
                    lastWriteSeq := GetClipboardSequenceNumber()
                    seenSeq := lastWriteSeq
                    lastPasted := expandedPlain
                    ClipWait(1)
                    Send("^v")
                    Sleep(PASTE_DELAY)
                }
            }
        }
    }

    if (lastPasted != "")
        ScheduleClipboardRestore(snapshot, lastPasted, 3000, lastWriteSeq)
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

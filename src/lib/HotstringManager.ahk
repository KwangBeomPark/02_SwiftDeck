#Requires AutoHotkey v2.0
#Include Config.ahk
#Include HotstringRuntime.ahk
#Include Theme.ahk
#Include Utils.ahk
; Runtime globals such as g_registeredHotstrings are initialized in SwiftDeck.ahk
; before this module is included.

; =================================================================================
; Module: HotstringManager
; Description: Provides a GUI for managing dynamic hotstrings (auto-text expansions).
; Author: KBPark
; =================================================================================
class HotstringManager {
    __New(parentGui := "") {
        this.parentGui := parentGui
        hotstringData := ConfigReadHotstringData()
        this.localData := hotstringData.Data
        this.groupOrder := hotstringData.GroupOrder
        if (parentGui)
            this.BuildUI(parentGui)
    }

    Show() {
        if (!this.parentGui) {
            this.hsGui := Gui("+AlwaysOnTop", "HotStrings Manager")
            EnableDarkMode(this.hsGui)
            this.BuildUI(this.hsGui)
            ShowCenteredOnMouse(this.hsGui, "w430 h520")
        }
    }

    BuildUI(guiObj) {
        startX := this.parentGui ? 30 : 30
        startY := this.parentGui ? 120 : 20
        listHeight := this.parentGui ? 290 : 345
        moveUpOffset := this.parentGui ? 245 : 300
        moveDownOffset := this.parentGui ? 285 : 340
        autoSaveOffset := this.parentGui ? 380 : 435
        this.mainHwnd := guiObj.Hwnd
        if (!this.parentGui)
            guiObj.OnEvent("Close", (*) => guiObj.Destroy())

        ; Group Name row — clean layout with single Manage button
        guiObj.Add("Text", "x" . startX . " y" . startY . " w100", "① Select Group:")

        guiObj.SetFont("cBlack")
        ; DropDownList, not ComboBox: a name typed into an editable box never
        ; reaches GroupOrder, so items saved under it were silently discarded on
        ; write while the UI reported success. Groups are created via "Groups".
        this.cbGroup := guiObj.Add("DropDownList", "x" . (startX + 105) . " y" . (startY - 5) . " w195", [])
        guiObj.SetFont("c" . THEME_TEXT)

        btnManageGrp := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY - 5) . " w95 h25", "⚙️ Groups")

        this.txtDesc := guiObj.Add("Text", "x" . startX . " y" . (startY + 30) . " w400 c" . THEME_MUTED,
            "(Type abbreviation + ending character, e.g. Space/Enter/Tab)")

        guiObj.Add("Text", "x" . startX . " y" . (startY + 55) . " w200", "② Abbreviation List:")

        guiObj.SetFont("cBlack")
        this.lbItems := guiObj.Add("ListBox", "x" . startX . " y" . (startY + 75) . " w300 h" . listHeight)
        guiObj.SetFont("c" . THEME_TEXT)

        guiObj.SetFont("s9 cD03A3A norm", "Segoe UI")
        btnReset := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 45) . " w95 h25", "⚠️ Reset")
        btnReset.OnEvent("Click", (*) => this.RequestReset())
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        btnAdd := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 75) . " w95 h35", "➕ New")
        btnEdit := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 115) . " w95 h35", "✏️ Edit")
        btnDel := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 155) . " w95 h35", "❌ Delete")
        guiObj.SetFont("s9 cWhite norm", "Segoe UI")
        btnUp := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + moveUpOffset) . " w95 h35", "▲ Up")
        btnDown := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + moveDownOffset) . " w95 h35", "▼ Down")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        if (!this.parentGui) {
            btnClose := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 475) . " w95 h35", "Close")
            btnClose.OnEvent("Click", (*) => guiObj.Destroy())
        }

        this.cbGroup.OnEvent("Change", (*) => this.OnGroupChange())
        this.lbItems.OnEvent("DoubleClick", (*) => this.EditSelectedItem())

        btnManageGrp.OnEvent("Click", (*) => this.ShowGroupManagerPopup())
        btnAdd.OnEvent("Click", (*) => this.ShowEditPopup(false, 0))
        btnEdit.OnEvent("Click", (*) => this.EditSelectedItem())
        btnDel.OnEvent("Click", (*) => this.DeleteItem())
        btnUp.OnEvent("Click", (*) => this.MoveItem(-1))
        btnDown.OnEvent("Click", (*) => this.MoveItem(1))

        guiObj.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + autoSaveOffset) . " w405 Center", "✓ Changes are saved and applied immediately.")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        this.UpdateGroupsDdl()
        this.RefreshList()
    }

    ; =========================================================================
    ; Group Manager Popup — Add, Rename, Delete, Reorder groups in one place
    ; =========================================================================
    ShowGroupManagerPopup() {
        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", "Manage Groups")

        CleanUpAndClose() {
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        popup.Add("Text", "x15 y10 w300 c666666", "Add, rename, reorder, or delete hotstring groups.")
        popup.SetFont("s8 c999999", "Segoe UI")
        popup.Add("Text", "x15 y30 w300", "(Prefix with * when adding for menu-only group)")
        popup.SetFont("s10 cBlack", "Segoe UI")

        ; Group ListBox
        lbGroups := popup.Add("ListBox", "x15 y55 w260 h230")

        ; Action buttons (right side)
        btnGAdd := popup.Add("Button", "x290 y55 w120 h32", "➕ New")
        btnGRename := popup.Add("Button", "x290 y92 w120 h32", "✏️ Rename")
        btnGDelete := popup.Add("Button", "x290 y129 w120 h32", "❌ Delete")
        popup.SetFont("s9 cWhite norm", "Segoe UI")
        btnGUp := popup.Add("Button", "x290 y210 w58 h32", "▲ Up")
        btnGDown := popup.Add("Button", "x352 y210 w58 h32", "▼ Down")
        popup.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        ; Close button
        btnGClose := popup.Add("Button", "x290 y253 w120 h32", "Close")

        RefreshGroupList(selectName := "") {
            lbGroups.Delete()
            groupNames := []
            for _, groupSection in this.groupOrder {
                groupName := this.GetGroupName(groupSection)
                if (groupName != "") {
                    prefix := (SubStr(groupSection, 1, 11) == "Group_Menu_") ? "📋 " : "⌨️ "
                    itemCount := this.localData.Has(groupSection) ? this.localData[groupSection].Length : 0
                    groupNames.Push(prefix . groupName . "  (" . itemCount . ")")
                }
            }
            if (groupNames.Length > 0)
                lbGroups.Add(groupNames)

            if (selectName != "") {
                for i, groupSection in this.groupOrder {
                    if (this.GetGroupName(groupSection) == selectName) {
                        lbGroups.Choose(i)
                        break
                    }
                }
            } else if (groupNames.Length > 0) {
                lbGroups.Choose(1)
            }
        }

        GetSelectedIdx() {
            return lbGroups.Value
        }

        btnGAdd.OnEvent("Click", (*) => OnAdd())
        OnAdd() {
            popup.Opt("+OwnDialogs")
            ib := InputBox("Enter a name for the new group:`n(Prefix with '*' for menu-only group)", "New Group", "w350 h140")

            if (ib.Result != "OK" || Trim(ib.Value) == "")
                return
            groupInput := Trim(ib.Value)
            isMenuOnly := (SubStr(groupInput, 1, 1) == "*")
            groupName := isMenuOnly ? Trim(SubStr(groupInput, 2)) : groupInput
            groupName := Trim(groupName)
            if (groupName == "") {
                MsgBox("⚠️ Group name cannot be empty.", "Warning", 262192)
                return
            }
            if (this.localData.Has("Group_Space_" . groupName) || this.localData.Has("Group_Menu_" . groupName)) {
                MsgBox("⚠️ Group '" . groupName . "' already exists.", "Duplicate Group", 262160)
                return
            }
            groupSection := (isMenuOnly ? "Group_Menu_" : "Group_Space_") . groupName
            this.localData[groupSection] := []
            this.groupOrder.Push(groupSection)
            this.UpdateGroupsDdl(groupName)
            this.RefreshList(0)
            RefreshGroupList(groupName)
            if !this.SaveSettings(false) {
                RefreshGroupList()
                return
            }
            this.ShowAutoSaveFeedback("✅ Group '" . groupName . "' saved")
        }

        btnGRename.OnEvent("Click", (*) => OnRename())
        OnRename() {
            selectedIndex := GetSelectedIdx()
            if (selectedIndex == 0 || selectedIndex > this.groupOrder.Length)
                return
            oldSection := this.groupOrder[selectedIndex]
            oldName := this.GetGroupName(oldSection)
            if (oldName == "Default") {
                MsgBox("⚠️ The Default group cannot be renamed.", "Warning", 262192)
                return
            }

            popup.Opt("+OwnDialogs")
            ib := InputBox("Rename group '" . oldName . "' to:", "Rename Group", "w350 h120", oldName)

            if (ib.Result != "OK" || Trim(ib.Value) == "" || Trim(ib.Value) == oldName)
                return
            newName := Trim(ib.Value)
            if (this.localData.Has("Group_Space_" . newName) || this.localData.Has("Group_Menu_" . newName)) {
                MsgBox("⚠️ Group '" . newName . "' already exists.", "Duplicate Group", 262160)
                return
            }
            isMenuGroup := (SubStr(oldSection, 1, 11) == "Group_Menu_")
            newSection := (isMenuGroup ? "Group_Menu_" : "Group_Space_") . newName

            if (this.localData.Has(oldSection)) {
                this.localData[newSection] := this.localData[oldSection]
                this.localData.Delete(oldSection)
            } else {
                this.localData[newSection] := []
            }
            this.groupOrder[selectedIndex] := newSection

            this.UpdateGroupsDdl(newName)
            this.RefreshList(0)
            RefreshGroupList(newName)
            if !this.SaveSettings(false) {
                RefreshGroupList()
                return
            }
            this.ShowAutoSaveFeedback("✅ Group renamed and applied")
        }

        btnGDelete.OnEvent("Click", (*) => OnDelete())
        OnDelete() {
            selectedIndex := GetSelectedIdx()
            if (selectedIndex == 0 || selectedIndex > this.groupOrder.Length)
                return
            groupSection := this.groupOrder[selectedIndex]
            groupName := this.GetGroupName(groupSection)
            if (groupName == "Default") {
                MsgBox("⚠️ The Default group cannot be deleted.", "Warning", 262192)
                return
            }
            itemCount := this.localData.Has(groupSection) ? this.localData[groupSection].Length : 0
            msgRes := MsgBox("❓ Are you sure you want to delete group '" . groupName . "'?`n(" . itemCount . " hotstrings will be removed)", "Delete Group", 262436)
            if (msgRes != "Yes")
                return
            if (this.localData.Has(groupSection))
                this.localData.Delete(groupSection)
            this.groupOrder.RemoveAt(selectedIndex)
            this.UpdateGroupsDdl()
            this.RefreshList(0)
            RefreshGroupList()
            if !this.SaveSettings(false) {
                RefreshGroupList()
                return
            }
            this.ShowAutoSaveFeedback("✅ Group '" . groupName . "' deleted")
        }

        btnGUp.OnEvent("Click", (*) => OnMove(-1))
        btnGDown.OnEvent("Click", (*) => OnMove(1))
        OnMove(dir) {
            selectedIndex := GetSelectedIdx()
            if (selectedIndex == 0)
                return
            targetIdx := selectedIndex + dir
            if (targetIdx < 1 || targetIdx > this.groupOrder.Length)
                return
            groupName := this.GetGroupName(this.groupOrder[selectedIndex])
            temp := this.groupOrder[selectedIndex]
            this.groupOrder[selectedIndex] := this.groupOrder[targetIdx]
            this.groupOrder[targetIdx] := temp
            if !this.SaveSettings(false) {
                RefreshGroupList()
                return
            }
            this.UpdateGroupsDdl(groupName)
            RefreshGroupList(groupName)
            this.ShowAutoSaveFeedback()
        }

        btnGClose.OnEvent("Click", (*) => CleanUpAndClose())

        RefreshGroupList()
        ShowCenteredOnMouse(popup, "w425 h300")
    }

    GetGroupName(groupSection) {
        if (SubStr(groupSection, 1, 12) == "Group_Space_")
            return SubStr(groupSection, 13)
        if (SubStr(groupSection, 1, 11) == "Group_Menu_")
            return SubStr(groupSection, 12)
        return ""
    }

    GetRawGroupName(displayName) {
        return displayName
    }

    UpdateGroupsDdl(selectGroup := "") {
        groups := []
        for _, groupSection in this.groupOrder {
            if (this.localData.Has(groupSection)) {
                groupName := this.GetGroupName(groupSection)
                if (groupName != "")
                    groups.Push(groupName)
            }
        }

        this.cbGroup.Delete()
        if (groups.Length > 0)
            this.cbGroup.Add(groups)

        if (selectGroup != "") {
            this.cbGroup.Text := selectGroup
        } else if (groups.Length > 0) {
            this.cbGroup.Choose(1)
        }
    }

    OnGroupChange() {
        ; The dropdown only offers groups that already exist, so there is
        ; nothing to create here any more.
        this.RefreshList(0)
    }

    ; True when the dropdown resolves to a group that really exists. Saving into
    ; anything else would be discarded by ConfigWriteHotstringData, which only
    ; writes sections listed in GroupOrder.
    HasSelectableGroup() {
        return this.localData.Has(this.GetCurrentSection())
    }

    GetCurrentSection() {
        displayName := Trim(this.cbGroup.Text)
        if (displayName == "")
            displayName := "Default"
        rawName := this.GetRawGroupName(displayName)

        if (this.localData.Has("Group_Menu_" . rawName))
            return "Group_Menu_" . rawName
        return "Group_Space_" . rawName
    }

    IsDuplicateKey(keyToCheck, currentSec, currentIdx := 0) {
        for groupSection, items in this.localData {
            for idx, item in items {
                if (groupSection == currentSec && idx == currentIdx)
                    continue
                if (StrLower(item.Key) == StrLower(keyToCheck)) {
                    return this.GetGroupName(groupSection)
                }
            }
        }
        return ""
    }

    ; Re-reads this tab's settings from disk. The dashboard is created once and
    ; only hidden on close, and every save rewrites the whole section from
    ; memory — so without this, edits made to the file meanwhile (App Info's
    ; Open buttons invite exactly that) are overwritten by the stale snapshot.
    ReloadFromDisk() {
        hotstringData := ConfigReadHotstringData()
        this.localData := hotstringData.Data
        this.groupOrder := hotstringData.GroupOrder
    }

    RefreshList(targetIdx := 0) {
        groupSection := this.GetCurrentSection()

        this.lbItems.Delete()
        listData := []

        if (this.localData.Has(groupSection)) {
            for idx, item in this.localData[groupSection] {
                displayVal := StrReplace(item.Val, "`n", " ↵ ")
                if (StrLen(displayVal) > 25)
                    displayVal := SubStr(displayVal, 1, 25) . "…"
                listData.Push("[ " . item.Key . " ]  ▶  " . displayVal)
            }
        }

        if (listData.Length > 0)
            this.lbItems.Add(listData)

        if (targetIdx > 0 && targetIdx <= listData.Length) {
            this.lbItems.Choose(targetIdx)
        }
    }

    EditSelectedItem() {
        idx := this.lbItems.Value
        if (idx > 0) {
            this.ShowEditPopup(true, idx)
        }
    }

    MoveItem(dir) {
        groupSection := this.GetCurrentSection()
        idx := this.lbItems.Value
        if (idx == 0)
            return

        targetIdx := idx + dir
        if (targetIdx < 1 || targetIdx > this.localData[groupSection].Length)
            return

        temp := this.localData[groupSection][idx]
        this.localData[groupSection][idx] := this.localData[groupSection][targetIdx]
        this.localData[groupSection][targetIdx] := temp

        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback()
        }
    }

    ShowEditPopup(isEdit := false, editIdx := 0) {
        groupSection := this.GetCurrentSection()
        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", isEdit ? "Edit Hotstring" : "Add Hotstring")

        CleanUpAndClose() {
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        existingKey := ""
        existingVal := ""
        if (isEdit && this.localData.Has(groupSection) && editIdx > 0 && editIdx <= this.localData[groupSection].Length) {
            existingKey := this.localData[groupSection][editIdx].Key
            existingVal := this.localData[groupSection][editIdx].Val
        }

        popup.Add("GroupBox", "x15 y10 w400 h90 cBlack", "③ Abbreviation (Trigger)")
        popup.Add("Text", "x30 y30 w370 c666666", "Type this text to trigger the expansion:")
        edtKey := popup.Add("Edit", "x30 y55 w370 h30", existingKey)

        popup.Add("GroupBox", "x15 y115 w400 h120 cBlack", "④ Replacement (Output)")
        popup.Add("Text", "x30 y135 w370 c666666", "The abbreviation will be replaced with this text:")
        edtVal := popup.Add("Edit", "x30 y158 w370 h60", existingVal)

        ; Action buttons
        popup.SetFont("s10 cWhite bold", "Segoe UI")
        btnConfirm := popup.Add("Button", "x215 y250 w200 h35", isEdit ? "💾 Save Changes" : "➕ Add Hotstring")
        popup.SetFont("s10 cBlack norm", "Segoe UI")
        btnConfirm.OnEvent("Click", (*) => OnConfirm())

        btnCancel := popup.Add("Button", "x15 y250 w190 h35", "Cancel")
        btnCancel.OnEvent("Click", (*) => CleanUpAndClose())

        OnConfirm() {
            triggerText := Trim(edtKey.Value)
            replacementText := Trim(edtVal.Value)
            if (triggerText == "" || replacementText == "") {
                MsgBox("⚠️ Please enter both an abbreviation and its replacement text.", "Warning", 262192)
                return
            }

            ; AutoHotkey refuses to register an abbreviation longer than this
            ; (measured: 40 passes, 41 raises "max abbreviation length is 40").
            ; Without the check the item saves, fails to register, and the
            ; warning tooltip is immediately painted over by the success toast.
            if (StrLen(triggerText) > 40) {
                ; StrLen counts UTF-16 units, which is also what AutoHotkey's own
                ; limit counts, so an emoji costs two — say "units", not
                ; "characters", rather than appearing to miscount.
                MsgBox("⚠️ This abbreviation is too long: " . StrLen(triggerText)
                    . " of the 40 units AutoHotkey allows."
                    . "`n`nA longer one can be saved but would never trigger. Please shorten it."
                    . "`n`nNote that emoji and some symbols count as two units each.",
                    "Abbreviation Too Long", 262192)
                return
            }

            ; Refuse rather than report success for a write that would be dropped.
            if (!this.localData.Has(groupSection)) {
                MsgBox("⚠️ Select a group first.`n`nUse the ⚙️ Groups button to create one, then add the abbreviation to it.",
                    "No Group Selected", 262192)
                return
            }

            duplicateGroup := this.IsDuplicateKey(triggerText, groupSection, isEdit ? editIdx : 0)
            if (duplicateGroup != "") {
                MsgBox("⚠️ The abbreviation '" . triggerText . "' is already registered in group: " . duplicateGroup . ".`nDuplicates are not allowed.", "Duplicate", 262160)
                return
            }

            if (!this.localData.Has(groupSection))
                this.localData[groupSection] := []

            if (isEdit) {
                this.localData[groupSection][editIdx].Key := triggerText
                this.localData[groupSection][editIdx].Val := replacementText
            } else {
                this.localData[groupSection].Push({ Key: triggerText, Val: replacementText })
            }

            if !this.SaveSettings(false)
                return
            this.RefreshList(isEdit ? editIdx : this.localData[groupSection].Length)
            CleanUpAndClose()
            this.ShowAutoSaveFeedback(isEdit ? "✅ Hotstring saved and applied" : "✅ Hotstring added and applied")
        }

        ShowCenteredOnMouse(popup, "w430 h300")
    }

    DeleteItem() {
        groupSection := this.GetCurrentSection()
        selectedIndex := this.lbItems.Value
        if (selectedIndex == 0)
            return

        item := this.localData[groupSection][selectedIndex]
        friendlyItem := "[ " . item.Key . " ]  ▶  " . StrReplace(item.Val, "`n", " ↵ ")
        msgRes := MsgBox("❓ Are you sure you want to delete this hotstring?`n`n" . friendlyItem, "Confirm Delete", 262436)
        if (msgRes != "Yes")
            return

        this.localData[groupSection].RemoveAt(selectedIndex)

        targetIdx := selectedIndex > this.localData[groupSection].Length ? this.localData[groupSection].Length : selectedIndex
        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback("✅ Hotstring deleted and applied")
        }
    }

    IsDirty() {
        return false
    }

    RequestReset() {
        if (this.HasOwnProp("dashboardResetHandler"))
            this.dashboardResetHandler.Call("Hotstrings")
        else
            ResetToDefaults("Hotstrings")
    }

    SaveSettings(showFeedback := true) {
        try {
            ConfigWriteHotstringData(this.localData, this.groupOrder)
        } catch Error as err {
            hotstringData := ConfigReadHotstringData()
            this.localData := hotstringData.Data
            this.groupOrder := hotstringData.GroupOrder
            this.UpdateGroupsDdl()
            this.RefreshList()
            MsgBox("❌ The hotstring change could not be saved and was not applied.`n`nError: " . err.Message,
                "Save Failed", 262160)
            return false
        }

        try {
            LoadHotstrings()
            BuildEmojiMenu()
        } catch Error as err {
            MsgBox("⚠️ The hotstring change was saved, but the running app could not activate it.`n`n"
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

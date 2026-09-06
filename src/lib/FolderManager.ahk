#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Theme.ahk
#Include Utils.ahk

; =================================================================================
; Module: FolderManager
; Description: Handles the UI and logic for managing Favorite Folders.
; Author: KBPark
; =================================================================================
class FolderManager {
    static ReadFolderItems() {
        return ConfigReadFolderItems()
    }

    static WriteFolderItems(items) {
        ConfigWriteFolderItems(items)
    }

    __New(parentGui := "") {
        this.orderedItems := FolderManager.ReadFolderItems()
        this.parentGui := parentGui
        if (parentGui)
            this.BuildUI(parentGui)
    }

    Show() {
        if (!this.parentGui) {
            this.rGui := Gui("+AlwaysOnTop -MaximizeBox", "Folder Manager")
            EnableDarkMode(this.rGui)
            this.BuildUI(this.rGui)
            ShowCenteredOnMouse(this.rGui, "AutoSize")
        }
    }

    BuildUI(guiObj) {
        this.mainHwnd := guiObj.Hwnd
        startX := this.parentGui ? 35 : 25
        startY := this.parentGui ? 120 : 80
        listHeight := this.parentGui ? 300 : 345
        moveUpOffset := this.parentGui ? 245 : 290
        moveDownOffset := this.parentGui ? 285 : 330
        autoSaveOffset := this.parentGui ? 345 : 390
        hintOffset := this.parentGui ? 375 : 435
        guiObj.SetFont("s10", "Segoe UI")

        guiObj.Add("Text", "x" . startX . " y" . startY . " w400", "Saved Folders:")

        ; Set ListBox text color to black (for readability on white background)
        guiObj.SetFont("cBlack")
        this.lbItems := guiObj.Add("ListBox", "x" . startX . " y" . (startY + 25) . " w300 h" . listHeight)
        guiObj.SetFont("c" . THEME_TEXT)

        btnAddDir := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 25) . " w95 h35", "➕ New")
        btnEdit := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 65) . " w95 h35", "✏️ Edit")
        btnSep := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 105) . " w95 h35", "➖ Separator")
        btnDel := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 145) . " w95 h35", "❌ Delete")

        guiObj.SetFont("s9 cWhite norm", "Segoe UI")
        btnUp := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + moveUpOffset) . " w95 h35", "▲ Up")
        btnDown := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + moveDownOffset) . " w95 h35", "▼ Down")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        guiObj.SetFont("s9 cD03A3A norm", "Segoe UI")
        btnReset := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY - 5) . " w95 h25", "⚠️ Reset")
        btnReset.OnEvent("Click", (*) => this.RequestReset())

        guiObj.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        guiObj.Add("Text", "x" . startX . " y" . (startY + autoSaveOffset) . " w405 Center", "✓ Changes are saved and applied immediately.")
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        guiObj.Add("Text", "x" . startX . " y" . (startY + hintOffset) . " w405 c" . THEME_MUTED . " Center", "💡 Press the Folder Menu Hotkey (default: F1) anywhere to open this menu.")

        if (!this.parentGui) {
            btnClose := guiObj.Add("Button", "x" . (startX + 310) . " y" . (startY + 465) . " w95 h35", "Close")
            btnClose.OnEvent("Click", (*) => guiObj.Destroy())
        }

        this.RefreshList()

        this.lbItems.OnEvent("DoubleClick", (*) => this.EditFolder())
        btnAddDir.OnEvent("Click", (*) => this.AddFolder())
        btnEdit.OnEvent("Click", (*) => this.EditFolder())
        btnSep.OnEvent("Click", (*) => this.AddSeparator())
        btnDel.OnEvent("Click", (*) => this.DeleteItem())
        btnUp.OnEvent("Click", (*) => this.MoveItem(-1))
        btnDown.OnEvent("Click", (*) => this.MoveItem(1))
    }

    ; Re-reads this tab's settings from disk. The dashboard is created once and
    ; only hidden on close, and every save rewrites the whole section from
    ; memory — so without this, edits made to the file meanwhile (App Info's
    ; Open buttons invite exactly that) are overwritten by the stale snapshot.
    ReloadFromDisk() {
        this.orderedItems := FolderManager.ReadFolderItems()
    }

    RefreshList(targetIdx := 0) {
        listData := []
        sepCnt := 0
        for obj in this.orderedItems {
            if (obj.Name == "-") {
                sepCnt++
                listData.Push("── Separator #" . sepCnt . " ──")
            } else {
                listData.Push(obj.Name)
            }
        }
        this.lbItems.Delete()
        if (listData.Length > 0)
            this.lbItems.Add(listData)
        if (targetIdx > 0 && targetIdx <= listData.Length)
            this.lbItems.Choose(targetIdx)
    }

    MoveItem(dir) {
        idx := this.lbItems.Value
        if (idx == 0)
            return

        targetIdx := idx + dir
        if (targetIdx < 1 || targetIdx > this.orderedItems.Length)
            return

        temp := this.orderedItems[idx]
        this.orderedItems[idx] := this.orderedItems[targetIdx]
        this.orderedItems[targetIdx] := temp

        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback()
        }
    }

    DeleteItem() {
        idx := this.lbItems.Value
        if (idx == 0)
            return

        item := this.orderedItems[idx]
        friendlyItem := (item.Name == "-") ? "Separator" : "[" . item.Name . "]`nPath: " . item.Path
        msgRes := MsgBox("❓ Are you sure you want to delete this favorite folder?`n`n" . friendlyItem, "Confirm Delete", 262436)
        if (msgRes != "Yes")
            return

        this.orderedItems.RemoveAt(idx)
        targetIdx := idx > this.orderedItems.Length ? this.orderedItems.Length : idx
        if this.SaveSettings(false) {
            this.RefreshList(targetIdx)
            this.ShowAutoSaveFeedback("✅ Deleted and applied")
        }
    }

    AddSeparator() {
        this.orderedItems.Push({ Name: "-", Path: "-" })
        if this.SaveSettings(false) {
            this.RefreshList(this.orderedItems.Length)
            this.ShowAutoSaveFeedback("✅ Separator added")
        }
    }

    AddFolderItem(folderName, folderPath) {
        folderName := Trim(folderName)
        if (!IsPlainIniKeySafe(folderName)) {
            MsgBox("⚠️ " . GetIniKeyRuleMessage(), "Invalid Folder Name", 262192)
            return false
        }
        this.orderedItems.Push({ Name: folderName, Path: folderPath })
        if !this.SaveSettings(false)
            return false
        this.RefreshList(this.orderedItems.Length)
        this.ShowAutoSaveFeedback("✅ Folder added")
        return true
    }

    EditFolder() {
        idx := this.lbItems.Value
        if (idx == 0)
            return

        item := this.orderedItems[idx]
        if (item.Name == "-") {
            MsgBox("⚠️ Separator cannot be edited.", "Info", 262208)
            return
        }

        WinSetEnabled(0, this.mainHwnd)
        popup := Gui("+AlwaysOnTop +Owner" . this.mainHwnd . " -MinimizeBox -MaximizeBox", "Edit Folder")

        CleanUpAndClose() {
            WinSetEnabled(1, this.mainHwnd)
            WinActivate(this.mainHwnd)
            popup.Destroy()
        }
        popup.OnEvent("Close", (*) => CleanUpAndClose())
        popup.BackColor := "FFFFFF"
        popup.SetFont("s10 cBlack", "Segoe UI")

        popup.Add("GroupBox", "x15 y10 w400 h80 cBlack", "Folder Name (Nickname)")
        edtName := popup.Add("Edit", "x30 y35 w370 h30", item.Name)

        popup.Add("GroupBox", "x15 y100 w400 h80 cBlack", "Folder Path")
        edtPath := popup.Add("Edit", "x30 y125 w300 h30", item.Path)
        btnBrowse := popup.Add("Button", "x340 y124 w60 h32", "Browse")

        btnBrowse.OnEvent("Click", (*) => OnBrowse())
        OnBrowse() {
            popup.Opt("-AlwaysOnTop")
            selectedDir := DirSelect("*" . edtPath.Value, 3, "Select a folder")
            popup.Opt("+AlwaysOnTop")
            if (selectedDir != "")
                edtPath.Value := selectedDir
        }

        popup.SetFont("s10 cWhite bold", "Segoe UI")
        btnConfirm := popup.Add("Button", "x215 y200 w200 h35", "💾 Save Changes")
        popup.SetFont("s10 cBlack norm", "Segoe UI")
        btnConfirm.OnEvent("Click", (*) => OnConfirm())

        btnCancel := popup.Add("Button", "x15 y200 w190 h35", "Cancel")
        btnCancel.OnEvent("Click", (*) => CleanUpAndClose())

        OnConfirm() {
            n := Trim(edtName.Value)
            p := Trim(edtPath.Value)
            if (n == "" || p == "") {
                MsgBox("⚠️ Please enter both folder name and path.", "Warning", 262192)
                return
            }
            if (!IsPlainIniKeySafe(n)) {
                MsgBox("⚠️ " . GetIniKeyRuleMessage(), "Invalid Folder Name", 262192)
                return
            }

            this.orderedItems[idx].Name := n
            this.orderedItems[idx].Path := p

            if !this.SaveSettings(false)
                return
            this.RefreshList(idx)
            CleanUpAndClose()
            this.ShowAutoSaveFeedback("✅ Folder saved and applied")
        }

        ShowCenteredOnMouse(popup, "w430 h250")
    }

    AddFolder() {
        ; Temporarily disable AlwaysOnTop of parentGui / main window & set dialog ownership
        if (this.parentGui) {
            this.parentGui.Opt("-AlwaysOnTop +OwnDialogs")
            WinSetAlwaysOnTop(0, this.mainHwnd)
        } else if (this.rGui) {
            this.rGui.Opt("-AlwaysOnTop +OwnDialogs")
            WinSetAlwaysOnTop(0, this.rGui.Hwnd)
        }

        ; 3 = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
        selectedDir := DirSelect("*" . A_MyDocuments, 3, "Select a folder to add to Favorites")

        if (selectedDir == "") {
            ; Restore AlwaysOnTop before returning
            if (this.parentGui) {
                this.parentGui.Opt("+AlwaysOnTop")
                WinSetAlwaysOnTop(1, this.mainHwnd)
            } else if (this.rGui) {
                this.rGui.Opt("+AlwaysOnTop")
                WinSetAlwaysOnTop(1, this.rGui.Hwnd)
            }
            return
        }

        defaultName := GetFileName(selectedDir)
        if (defaultName == "")
            defaultName := selectedDir

        ib := InputBox("Enter a nickname for this folder:`nPath: " . selectedDir,
            "Add Folder", "w350 h150", defaultName)

        ; Restore AlwaysOnTop
        if (this.parentGui) {
            this.parentGui.Opt("+AlwaysOnTop")
            WinSetAlwaysOnTop(1, this.mainHwnd)
        } else if (this.rGui) {
            this.rGui.Opt("+AlwaysOnTop")
            WinSetAlwaysOnTop(1, this.rGui.Hwnd)
        }

        if (ib.Result != "OK" || Trim(ib.Value) == "")
            return

        this.AddFolderItem(ib.Value, selectedDir)
    }

    IsDirty() {
        return false
    }

    RequestReset() {
        if (this.HasOwnProp("dashboardResetHandler"))
            this.dashboardResetHandler.Call("Favorites")
        else
            ResetToDefaults("Favorites")
    }

    SaveSettings(showFeedback := true) {
        try {
            FolderManager.WriteFolderItems(this.orderedItems)
            if showFeedback
                this.ShowAutoSaveFeedback()
            return true
        } catch Error as err {
            this.orderedItems := FolderManager.ReadFolderItems()
            this.RefreshList()
            MsgBox("❌ The folder change could not be saved and was not applied.`n`nError: " . err.Message,
                "Save Failed", 262160)
            return false
        }
    }

    ShowAutoSaveFeedback(message := "✅ Saved and applied") {
        ToolTip(message)
        SetTimer(() => ToolTip(), -2000)
    }
}

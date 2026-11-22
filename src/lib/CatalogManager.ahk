#Requires AutoHotkey v2.0
#Include Catalog.ahk
#Include Theme.ahk
#Include Utils.ahk
#Include HotstringRuntime.ahk

; =================================================================================
; Module: CatalogManager
; Description: The Catalog window, opened from the settings header. It lists the
;              catalogs in UserSetting\Catalog\, shows everything the chosen one
;              holds, adds checked items to the user's settings or switches to
;              the whole catalog, and imports or exports .swiftdeck files.
; Author: KBPark
; =================================================================================
class CatalogManager {
    static instance := ""

    ; onChange runs after the user's own settings changed, so the settings
    ; window can re-read its tabs.
    static Show(ownerHwnd := 0, onChange := "") {
        if CatalogManager.instance
            CatalogManager.instance.Close()
        CatalogManager.instance := CatalogManager(ownerHwnd, onChange)
    }

    __New(ownerHwnd, onChange) {
        this.ownerHwnd := ownerHwnd
        this.onChange := onChange
        this.catalogs := []
        this.current := ""
        this.rows := []
        try {
            this.BuildUI()
            this.RefreshCatalogs()
            ShowCenteredOnMouse(this.gui, "w640 h515")
        } catch Error as err {
            ; BuildUI disables the settings window first; it must not stay
            ; disabled behind a window that never opened.
            this.Close()
            throw err
        }
    }

    BuildUI() {
        options := "+AlwaysOnTop -MinimizeBox -MaximizeBox" . GetFittingGuiOptions(640, 515)
        if (this.ownerHwnd && WinExist("ahk_id " . this.ownerHwnd)) {
            WinSetEnabled(0, this.ownerHwnd)
            options .= " +Owner" . this.ownerHwnd
        }
        g := Gui(options, "SwiftDeck Catalog")
        this.gui := g
        ; Message boxes and file pickers belong to this window, not behind it.
        g.Opt("+OwnDialogs")
        ApplyTheme(g, "📚 Catalog", "Prompts and hotstrings shared as .swiftdeck files.")
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())

        g.Add("Text", "x20 y75 w70", "Catalog:")
        g.SetFont("cBlack")
        this.ddlCatalog := g.Add("DropDownList", "x90 y71 w320")
        g.SetFont("c" . THEME_TEXT)
        this.ddlCatalog.OnEvent("Change", (*) => this.LoadSelected())
        btnImport := g.Add("Button", "x420 y70 w95 h28", "📥 Import")
        btnImport.OnEvent("Click", (*) => this.ImportCatalog())
        btnExport := g.Add("Button", "x520 y70 w100 h28", "📤 Export mine")
        btnExport.OnEvent("Click", (*) => this.ShowExportDialog())

        g.SetFont("s9 c" . THEME_MUTED, "Segoe UI")
        this.txtInfo := g.Add("Text", "x20 y104 w600 h18 BackgroundTrans")
        g.SetFont("s10 cBlack", "Segoe UI")
        this.lv := g.Add("ListView", "x20 y126 w600 h270 Checked Grid", ["Item", "Content"])
        this.lv.ModifyCol(1, 240)
        this.lv.ModifyCol(2, 335)
        g.SetFont("s10 c" . THEME_TEXT, "Segoe UI")

        g.Add("Text", "x20 y410 w110", "Prompts go to:")
        targets := ["Their own slot"]
        loop 10
            targets.Push("Numpad " . Mod(A_Index, 10))
        g.SetFont("cBlack")
        this.ddlTarget := g.Add("DropDownList", "x130 y406 w150", targets)
        this.ddlTarget.Choose(1)
        g.SetFont("c" . THEME_TEXT)
        this.btnCheckAll := g.Add("Button", "x420 y404 w95 h28", "☑ Check all")
        this.btnCheckAll.OnEvent("Click", (*) => this.lv.Modify(0, "Check"))
        this.btnClear := g.Add("Button", "x520 y404 w100 h28", "☐ Clear")
        this.btnClear.OnEvent("Click", (*) => this.lv.Modify(0, "-Check"))

        this.btnAdd := g.Add("Button", "x20 y445 w190 h35", "➕ Add checked to mine")
        this.btnAdd.OnEvent("Click", (*) => this.AddChecked())
        this.btnSwitch := g.Add("Button", "x220 y445 w200 h35", "🔄 Switch to this catalog")
        this.btnSwitch.OnEvent("Click", (*) => this.SwitchToCatalog())
        g.SetFont("s10 cD03A3A", "Segoe UI")
        this.btnDelete := g.Add("Button", "x430 y445 w95 h35", "🗑 Delete")
        this.btnDelete.OnEvent("Click", (*) => this.DeleteCatalog())
        g.SetFont("s10 c" . THEME_TEXT, "Segoe UI")
        btnClose := g.Add("Button", "x530 y445 w90 h35", "Close")
        btnClose.OnEvent("Click", (*) => this.Close())

        g.SetFont("s9 c" . THEME_MUTED, "Segoe UI")
        g.Add("Text", "x20 y488 w600 BackgroundTrans",
            "Add keeps your own hotstring triggers. Switch first saves your current prompts and hotstrings as a catalog.")
        g.SetFont("s10 c" . THEME_TEXT, "Segoe UI")
    }

    Close() {
        if (this.ownerHwnd && WinExist("ahk_id " . this.ownerHwnd)) {
            WinSetEnabled(1, this.ownerHwnd)
            WinActivate(this.ownerHwnd)
        }
        if this.HasOwnProp("gui")
            try this.gui.Destroy()
        if (CatalogManager.instance == this)
            CatalogManager.instance := ""
    }

    RefreshCatalogs(selectPath := "") {
        this.catalogs := CatalogList()
        this.ddlCatalog.Delete()
        labels := []
        chosen := 1
        for idx, entry in this.catalogs {
            stamp := CatalogFormatDate(entry.Created)
            labels.Push(entry.Name . (stamp != "" ? "  ·  " . stamp : ""))
            if (selectPath != "" && entry.Path = selectPath)
                chosen := idx
        }
        if (labels.Length) {
            this.ddlCatalog.Add(labels)
            this.ddlCatalog.Choose(chosen)
        }
        this.LoadSelected()
    }

    SelectedEntry() {
        idx := this.ddlCatalog.Value
        return (idx >= 1 && idx <= this.catalogs.Length) ? this.catalogs[idx] : ""
    }

    LoadSelected() {
        this.current := ""
        this.rows := []
        this.lv.Opt("-Redraw")
        this.lv.Delete()
        entry := this.SelectedEntry()
        if (entry == "") {
            this.txtInfo.Text := "No catalogs yet. 📥 Import a .swiftdeck file someone sent you, or 📤 Export yours to share."
        } else {
            try {
                this.current := CatalogRead(entry.Path)
                this.FillList()
            } catch Error as err {
                this.current := ""
                this.txtInfo.Text := "⚠️ This catalog cannot be read: " . err.Message
            }
        }
        this.lv.Opt("+Redraw")
        hasItems := this.current != "" && this.rows.Length > 0
        for ctrl in [this.btnAdd, this.btnCheckAll, this.btnClear]
            ctrl.Enabled := hasItems
        this.btnSwitch.Enabled := this.current != ""
        this.btnDelete.Enabled := entry != ""
    }

    FillList() {
        catalog := this.current
        promptCount := 0
        loop 10 {
            num := Mod(A_Index, 10)
            slotName := catalog.SlotNames[num]
            where := "Num" . num . (slotName != "" ? " · " . slotName : "")
            for idx, item in catalog.Prompts[num] {
                content := CatalogPreviewText(item.Msg)
                ; {Enter}, {Ctrl+c} and the like are typed as keys when it runs.
                if HasSpecialKeys(item.Msg)
                    content := "⚠ sends keys · " . content
                this.lv.Add(, "⌨️ " . where . " › " . item.Title, content)
                this.rows.Push({ Kind: "Prompt", Slot: num, Index: idx })
                promptCount++
            }
        }
        hotstringCount := 0
        for section in catalog.Hotstrings.GroupOrder {
            if !catalog.Hotstrings.Data.Has(section)
                continue
            group := HotstringGetRuntimeGroupName(section)
                . (HotstringGetRuntimeGroupType(section) == "Menu" ? " (menu)" : "")
            for idx, item in catalog.Hotstrings.Data[section] {
                content := CatalogPreviewText(item.Val) . (HotstringIsInWord(item) ? "   (in-word)" : "")
                this.lv.Add(, "✏️ " . group . " › " . item.Key, content)
                this.rows.Push({ Kind: "Hotstring", Section: section, Index: idx })
                hotstringCount++
            }
        }
        stamp := CatalogFormatDate(catalog.Info.Created)
        SplitPath(catalog.Info.Path, &fileName)
        this.txtInfo.Text := promptCount . " prompts · " . hotstringCount . " hotstrings"
            . (stamp != "" ? " · saved " . stamp : "") . " · " . fileName
    }

    CheckedPicks() {
        picks := []
        row := 0
        while (row := this.lv.GetNext(row, "Checked"))
            picks.Push(this.rows[row])
        return picks
    }

    ; The hotstrings and menus run from the files, and the settings tabs show
    ; them. Returns the triggers that could not be activated.
    AfterOwnSettingsChanged() {
        failed := []
        try failed := LoadHotstrings(false)
        try BuildEmojiMenu()
        if (this.onChange != "")
            try this.onChange.Call()
        return failed
    }

    AddChecked() {
        picks := this.CheckedPicks()
        if (picks.Length == 0) {
            MsgBox("Check the items to add first.", "Add to Mine", 262208)
            return
        }
        promptSlot := (this.ddlTarget.Value <= 1) ? -1 : Mod(this.ddlTarget.Value - 1, 10)
        try {
            ; Kept to put the prompts back if the hotstrings cannot be saved;
            ; the plan works on copies and leaves this as read.
            myPrompts := ConfigReadPromptData()
            plan := CatalogPlanAdd(myPrompts, ConfigReadHotstringData(), this.current, picks, promptSlot)
        } catch Error as err {
            MsgBox("❌ The checked items could not be prepared.`n`nError: " . err.Message, "Add to Mine", 262160)
            return
        }
        if (plan.AddedPrompts + plan.AddedHotstrings == 0) {
            MsgBox("Nothing was added: you already have every checked hotstring trigger.`n`n"
                . FormatShortList(plan.Skipped), "Add to Mine", 262208)
            return
        }

        ; Prompts and hotstrings are two files. If the second cannot be saved,
        ; the first is put back, so the add happens whole or not at all.
        if (plan.AddedPrompts > 0) {
            try {
                ConfigWritePromptData(plan.Prompts)
            } catch Error as err {
                MsgBox("❌ Nothing was added: the prompts could not be saved.`n`nError: " . err.Message, "Add to Mine", 262160)
                return
            }
        }
        if (plan.AddedHotstrings > 0) {
            try {
                ConfigWriteHotstringData(plan.Hotstrings.Data, plan.Hotstrings.GroupOrder)
            } catch Error as err {
                undone := true
                if (plan.AddedPrompts > 0) {
                    try ConfigWritePromptData(myPrompts)
                    catch
                        undone := false
                }
                this.AfterOwnSettingsChanged()
                MsgBox((undone
                    ? "❌ Nothing was added: the hotstrings could not be saved."
                    : "⚠️ The prompts were added, but the hotstrings could not be saved.")
                    . "`n`nError: " . err.Message, "Add to Mine", 262160)
                return
            }
        }

        ; Added items stay in the list; unchecking them avoids adding twice.
        this.lv.Modify(0, "-Check")
        failed := this.AfterOwnSettingsChanged()
        message := "✅ Added " . plan.AddedPrompts . " prompt(s) and " . plan.AddedHotstrings . " hotstring(s)"
        if (plan.Skipped.Length > 0)
            message .= "`nKept your own: " . FormatShortList(plan.Skipped)
        if (failed.Length > 0)
            message := "⚠️ Added, but " . failed.Length . " hotstring(s) could not be activated: " . FormatShortList(failed)
        ShowFeedbackToolTip(message, 4000)
    }

    SwitchToCatalog() {
        if (this.current == "")
            return
        catalog := this.current
        name := catalog.Info.Name
        message := "🔄 Switch to the catalog '" . name . "'?`n`n"
            . "Your prompts, slot names and hotstrings are replaced by the catalog's. "
            . "Folders, key remapping and General settings stay as they are.`n`n"
            . "Your current prompts and hotstrings are saved first as a catalog, so you can switch back."
        if (MsgBox(message, "Switch Catalog", 262452) != "Yes")
            return

        try {
            previousPrompts := ConfigReadPromptData()
            previousNames := ConfigReadPromptSlotNames()
            backupName := CatalogSaveCurrent("My settings " . FormatTime(A_Now, "yyyy-MM-dd HH.mm.ss")).Name
        } catch Error as err {
            MsgBox("❌ Nothing was switched: your current settings could not be saved first.`n`nError: " . err.Message,
                "Switch Catalog", 262160)
            return
        }
        try {
            ConfigWritePromptData(catalog.Prompts, catalog.SlotNames)
        } catch Error as err {
            this.RefreshCatalogs(catalog.Info.Path)
            MsgBox("❌ Nothing was switched: the prompts could not be saved.`n`nError: " . err.Message,
                "Switch Catalog", 262160)
            return
        }
        try {
            ConfigWriteHotstringData(catalog.Hotstrings.Data, catalog.Hotstrings.GroupOrder)
        } catch Error as err {
            ; Put the prompts back, so the switch happens whole or not at all.
            undone := true
            try ConfigWritePromptData(previousPrompts, previousNames)
            catch
                undone := false
            this.AfterOwnSettingsChanged()
            this.RefreshCatalogs(catalog.Info.Path)
            MsgBox((undone
                ? "❌ Nothing was switched: the hotstrings could not be saved."
                : "⚠️ The prompts were switched, but the hotstrings could not be saved.`n`n"
                    . "Your previous settings are in the catalog '" . backupName . "'.")
                . "`n`nError: " . err.Message, "Switch Catalog", 262160)
            return
        }

        failed := this.AfterOwnSettingsChanged()
        this.RefreshCatalogs(catalog.Info.Path)
        ShowFeedbackToolTip(failed.Length > 0
            ? "⚠️ Switched, but " . failed.Length . " hotstring(s) could not be activated: " . FormatShortList(failed)
            : "✅ Switched to '" . name . "'. Your previous settings are saved as '" . backupName . "'.", 5000)
    }

    DeleteCatalog() {
        entry := this.SelectedEntry()
        if (entry == "")
            return
        if (MsgBox("🗑 Move the catalog '" . entry.Name . "' to the Recycle Bin?", "Delete Catalog", 262452) != "Yes")
            return
        try {
            FileRecycle(entry.Path)
        } catch Error as err {
            MsgBox("❌ The catalog could not be deleted.`n`nError: " . err.Message, "Delete Catalog", 262160)
            return
        }
        this.RefreshCatalogs()
        ShowFeedbackToolTip("🗑 Moved to the Recycle Bin: " . entry.Name)
    }

    ImportCatalog() {
        source := FileSelect(3, , "Import a SwiftDeck catalog", "SwiftDeck catalog (*." . CatalogGetExtension() . ")")
        if (source == "")
            return
        target := CatalogImportTarget(source)
        if (FileExist(target) && StrLower(target) != StrLower(source)) {
            SplitPath(target, &fileName)
            if (MsgBox("Your list already has a catalog file named '" . fileName . "'.`n`nReplace it with this one?",
                "Import Catalog", 262452) != "Yes")
                return
        }
        try {
            CatalogImport(source, target)
        } catch Error as err {
            MsgBox("❌ This file could not be imported.`n`nError: " . err.Message, "Import Catalog", 262160)
            return
        }
        this.RefreshCatalogs(target)
        ShowFeedbackToolTip("📥 Imported into your catalog list")
    }

    ShowExportDialog() {
        try {
            prompts := ConfigReadPromptData()
            names := ConfigReadPromptSlotNames()
            hotstrings := ConfigReadHotstringData()
        } catch Error as err {
            MsgBox("❌ Your settings could not be read.`n`nError: " . err.Message, "Export My Catalog", 262160)
            return
        }

        ownerHwnd := this.gui.Hwnd
        dlg := ""
        CloseDialog() {
            if WinExist("ahk_id " . ownerHwnd) {
                WinSetEnabled(1, ownerHwnd)
                WinActivate(ownerHwnd)
            }
            if (dlg != "")
                try dlg.Destroy()
        }
        WinSetEnabled(0, ownerHwnd)
        try {
            dlg := Gui("+AlwaysOnTop +Owner" . ownerHwnd . " -MinimizeBox -MaximizeBox", "Export My Catalog")
            this.FillExportDialog(dlg, prompts, names, hotstrings, CloseDialog)
            ShowCenteredOnMouse(dlg, "w420 h395")
        } catch Error as err {
            ; The catalog window was disabled first; never leave it so.
            CloseDialog()
            throw err
        }
    }

    FillExportDialog(dlg, prompts, names, hotstrings, CloseDialog) {
        dlg.Opt("+OwnDialogs")
        ApplyTheme(dlg)
        dlg.OnEvent("Close", (*) => CloseDialog())
        dlg.OnEvent("Escape", (*) => CloseDialog())

        dlg.Add("Text", "x20 y20 w70", "Name:")
        dlg.SetFont("cBlack")
        edtName := dlg.Add("Edit", "x90 y16 w310", "My SwiftDeck catalog")
        lv := dlg.Add("ListView", "x20 y52 w380 h230 Checked", ["Share", "Items"])
        dlg.SetFont("c" . THEME_TEXT)
        rows := []
        loop 10 {
            num := Mod(A_Index, 10)
            if (prompts[num].Length == 0)
                continue
            lv.Add("Check", "⌨️ Num" . num . (names[num] != "" ? " · " . names[num] : ""), prompts[num].Length . " prompt(s)")
            rows.Push({ Slot: num })
        }
        for section in hotstrings.GroupOrder {
            if !hotstrings.Data.Has(section) || hotstrings.Data[section].Length == 0
                continue
            lv.Add("Check", "✏️ " . HotstringGetRuntimeGroupName(section), hotstrings.Data[section].Length . " hotstring(s)")
            rows.Push({ Section: section })
        }
        lv.ModifyCol(1, 255)
        lv.ModifyCol(2, 100)

        dlg.SetFont("s9 c" . THEME_MUTED, "Segoe UI")
        dlg.Add("Text", "x20 y290 w380",
            "Folder paths, key remapping and General settings are never included. "
            . "Read your prompts before sharing: they may hold names or company details.")
        dlg.SetFont("s10 c" . THEME_TEXT, "Segoe UI")
        btnCancel := dlg.Add("Button", "x20 y340 w180 h35", "Cancel")
        btnCancel.OnEvent("Click", (*) => CloseDialog())
        btnSave := dlg.Add("Button", "x210 y340 w190 h35", "📤 Save as file...")
        btnSave.OnEvent("Click", (*) => SaveExport())

        SaveExport() {
            name := Trim(edtName.Value)
            if (name == "") {
                MsgBox("Enter a name for the catalog.", "Export My Catalog", 262208)
                return
            }
            slots := Map()
            sections := Map()
            row := 0
            while (row := lv.GetNext(row, "Checked")) {
                pick := rows[row]
                if pick.HasOwnProp("Slot")
                    slots[pick.Slot] := true
                else
                    sections[pick.Section] := true
            }
            if (slots.Count + sections.Count == 0) {
                MsgBox("Check at least one slot or group to share.", "Export My Catalog", 262208)
                return
            }
            path := FileSelect("S16", A_MyDocuments . "\" . CatalogSafeFileName(name) . "." . CatalogGetExtension(),
                "Export catalog", "SwiftDeck catalog (*." . CatalogGetExtension() . ")")
            if (path == "")
                return
            if !RegExMatch(path, "i)\." . CatalogGetExtension() . "$") {
                path .= "." . CatalogGetExtension()
                ; The save dialog asked about the name without the extension.
                if (FileExist(path) && MsgBox("'" . path . "' already exists.`n`nReplace it?",
                    "Export My Catalog", 262452) != "Yes")
                    return
            }
            selected := CatalogSelectForExport(prompts, names, hotstrings, slots, sections)
            try {
                CatalogWrite(path, name, selected.Prompts, selected.SlotNames, selected.Hotstrings)
            } catch Error as err {
                MsgBox("❌ The catalog could not be saved.`n`nError: " . err.Message, "Export My Catalog", 262160)
                return
            }
            CloseDialog()
            ShowFeedbackToolTip("📤 Saved: " . path, 4000)
        }
    }
}

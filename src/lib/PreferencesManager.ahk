#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Theme.ahk
#Include Utils.ahk
#Include Migration.ahk

; =================================================================================
; Module: PreferencesManager
; Description: Manages application-wide settings and custom hotkey bindings.
; Author: KBPark
; =================================================================================
class PreferencesManager {
    ; Base keys offered by every hotkey ComboBox on this tab.
    static GetHotkeyBaseKeys() {
        return [
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
            "Space", "Enter", "Tab", "Escape", "CapsLock", "ScrollLock", "NumLock", "PrintScreen", "Insert", "Delete",
            "LButton", "RButton", "MButton", "XButton1", "XButton2",
            "WheelUp", "WheelDown",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
        ]
    }

    __New(parentGui := "") {
        this.parentGui := parentGui
        this.dirtyState := false
        if (parentGui)
            this.BuildUI(parentGui)
    }

    Show() {
        if (!this.parentGui) {
            this.pGui := Gui("+AlwaysOnTop", "🔧 Preferences")
            ApplyTheme(this.pGui, "Preferences", "Configure basic app settings and hotkeys.")
            this.BuildUI(this.pGui)
            ShowCenteredOnMouse(this.pGui, "AutoSize")
        }
    }

    BuildUI(guiObj) {
        ; Standalone window starts lower (header takes space)
        startX := this.parentGui ? 35 : 25
        startY := this.parentGui ? 120 : 80

        guiObj.SetFont("s10 c" . THEME_TEXT, "Segoe UI")

        ; Build against the shipped defaults if the settings file is unreadable,
        ; so the dashboard still opens instead of failing into the error dialog.
        settings := ConfigGetFallbackAppSettings()
        try settings := ConfigReadAppSettings()
        mainHotkey := settings.MainHotkey
        promptMod := settings.PromptModifier
        promptUseNumpad := settings.PromptUseNumpad

        migrated := MigratePromptModifier(promptMod, promptUseNumpad)
        promptMod := migrated.Mod
        promptUseNumpad := migrated.UseNumpad

        mainParsed := ParseKeyString(mainHotkey)
        promptParsed := ParseKeyString(promptMod)

        ; --- Main Hotkey GroupBox ---
        guiObj.Add("GroupBox", "x" . startX . " y" . startY . " w410 h85 c" . THEME_ACCENT, "📁 Favorites Menu Hotkey")
        guiObj.Add("Text", "x" . (startX + 15) . " y" . (startY + 20) . " w380", "Modifiers && Base Key:")

        this.chkMainCtrl := guiObj.Add("CheckBox", "x" . (startX + 15) . " y" . (startY + 48) . " w50", "Ctrl")
        this.chkMainShift := guiObj.Add("CheckBox", "x" . (startX + 70) . " y" . (startY + 48) . " w55", "Shift")
        this.chkMainWin := guiObj.Add("CheckBox", "x" . (startX + 130) . " y" . (startY + 48) . " w50", "Win")
        this.chkMainAlt := guiObj.Add("CheckBox", "x" . (startX + 185) . " y" . (startY + 48) . " w45", "Alt")

        this.chkMainCtrl.Value := mainParsed.Mods.Ctrl
        this.chkMainShift.Value := mainParsed.Mods.Shift
        this.chkMainWin.Value := mainParsed.Mods.Win
        this.chkMainAlt.Value := mainParsed.Mods.Alt

        guiObj.SetFont("cBlack")
        this.cbMainKey := guiObj.Add("ComboBox", "x" . (startX + 240) . " y" . (startY + 45) . " w155",
            PreferencesManager.GetHotkeyBaseKeys())
        guiObj.SetFont("c" . THEME_TEXT)
        this.cbMainKey.Text := mainParsed.Key

        guiObj.SetFont("s8 c" . THEME_ACCENT, "Segoe UI")
        this.txtMainPreview := guiObj.Add("Text", "x" . (startX + 15) . " y" . (startY + 70) . " w380 h13", "")
        guiObj.SetFont("s10 c" . THEME_TEXT, "Segoe UI")

        for ctrl in [this.chkMainCtrl, this.chkMainShift, this.chkMainWin, this.chkMainAlt]
            ctrl.OnEvent("Click", ObjBindMethod(this, "OnMainHotkeyChange"))
        this.cbMainKey.OnEvent("Change", ObjBindMethod(this, "OnMainHotkeyChange"))
        this.UpdateMainHotkeyPreview()

        ; --- Quick Prompts GroupBox ---
        guiObj.Add("GroupBox", "x" . startX . " y" . (startY + 100) . " w410 h85 c" . THEME_ACCENT, "⌨️ Quick Prompts Hotkey")
        guiObj.Add("Text", "x" . (startX + 15) . " y" . (startY + 120) . " w380", "Modifiers && Number Key Type:")

        this.chkPromptCtrl := guiObj.Add("CheckBox", "x" . (startX + 15) . " y" . (startY + 148) . " w50", "Ctrl")
        this.chkPromptShift := guiObj.Add("CheckBox", "x" . (startX + 70) . " y" . (startY + 148) . " w55", "Shift")
        this.chkPromptWin := guiObj.Add("CheckBox", "x" . (startX + 130) . " y" . (startY + 148) . " w50", "Win")
        this.chkPromptAlt := guiObj.Add("CheckBox", "x" . (startX + 185) . " y" . (startY + 148) . " w45", "Alt")

        this.chkPromptCtrl.Value := promptParsed.Mods.Ctrl
        this.chkPromptShift.Value := promptParsed.Mods.Shift
        this.chkPromptWin.Value := promptParsed.Mods.Win
        this.chkPromptAlt.Value := promptParsed.Mods.Alt

        numpadChoose := (promptUseNumpad == 1) ? 1 : 2
        guiObj.SetFont("cBlack")
        this.ddlPromptNumpad := guiObj.Add("DropDownList", "x" . (startX + 240) . " y" . (startY + 145) . " w155 Choose" . numpadChoose, ["Numpad 0~9", "Standard 0~9"])
        guiObj.SetFont("c" . THEME_TEXT)

        ; --- Live hotkey preview (updates as modifiers / number type change) ---
        guiObj.SetFont("s8 c" . THEME_ACCENT, "Segoe UI")
        this.txtPromptPreview := guiObj.Add("Text", "x" . (startX + 15) . " y" . (startY + 170) . " w380 h13", "")
        guiObj.SetFont("s10 c" . THEME_TEXT, "Segoe UI")

        for ctrl in [this.chkPromptCtrl, this.chkPromptShift, this.chkPromptWin, this.chkPromptAlt]
            ctrl.OnEvent("Click", ObjBindMethod(this, "OnPromptHotkeyChange"))
        this.ddlPromptNumpad.OnEvent("Change", ObjBindMethod(this, "OnPromptHotkeyChange"))
        this.UpdatePromptPreview()

        ; --- Emoji & Exit hotkeys ---
        ; Both were already stored in the settings file but had no editor, so the
        ; only way to change them was hand-editing the INI.
        emojiParsed := ParseKeyString(settings.EmojiHotkey)
        exitParsed := ParseKeyString(settings.ExitHotkey)

        guiObj.Add("GroupBox", "x" . startX . " y" . (startY + 200) . " w410 h88 c" . THEME_ACCENT, "😀 Emoji && Exit Hotkeys")

        this.emojiControls := this.AddHotkeyRow(guiObj, startX, startY + 222, "Emoji:", emojiParsed)
        this.exitControls := this.AddHotkeyRow(guiObj, startX, startY + 252, "Exit:", exitParsed)

        ; --- Save Preferences ---
        guiObj.SetFont("s10 cWhite bold", "Segoe UI")
        this.btnSave := guiObj.Add("Button", "x" . startX . " y" . (startY + 300) . " w410 h38", "💾 Save && Apply")
        this.btnSave.OnEvent("Click", ObjBindMethod(this, "OnSavePreferences"))
        guiObj.SetFont("c" . THEME_TEXT . " norm", "Segoe UI")

        ; --- Data, Startup & Recovery ---
        guiObj.Add("GroupBox", "x" . startX . " y" . (startY + 350) . " w410 h125", "Data, Startup && Recovery")

        this.chkStartup := guiObj.Add("CheckBox", "x" . (startX + 15) . " y" . (startY + 370) . " w380 h22", "🚀 Run SwiftDeck when Windows starts")
        this.chkStartup.Value := ConfigIsStartupEnabled()
        this.chkStartup.OnEvent("Click", ObjBindMethod(this, "OnStartupToggle"))

        btnOpenSettings := guiObj.Add("Button", "x" . (startX + 15) . " y" . (startY + 400) . " w120 h30", "📂 Open Folder")
        btnOpenSettings.OnEvent("Click", (*) => OpenFolder(ConfigGetSettingsFolder()))

        btnBackup := guiObj.Add("Button", "x" . (startX + 140) . " y" . (startY + 400) . " w110 h30", "📥 Backup Saved")
        btnBackup.OnEvent("Click", (*) => BackupConfigs(true))

        btnRestore := guiObj.Add("Button", "x" . (startX + 255) . " y" . (startY + 400) . " w105 h30", "🔄 Restore")
        btnRestore.OnEvent("Click", ObjBindMethod(this, "OnRestoreSettings"))

        guiObj.SetFont("s9 cD03A3A bold", "Segoe UI")
        btnResetAll := guiObj.Add("Button", "x" . (startX + 15) . " y" . (startY + 435) . " w345 h30", "⚠️ FACTORY RESET ALL SETTINGS")
        btnResetAll.OnEvent("Click", ObjBindMethod(this, "OnFactoryReset"))
        guiObj.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")
    }

    ; One compact "<label> [Ctrl][Shift][Win][Alt] [base key]" row. Returns the
    ; controls so the save path can read the combination back.
    AddHotkeyRow(guiObj, startX, rowY, labelText, parsed) {
        guiObj.SetFont("s9 c" . THEME_TEXT, "Segoe UI")
        guiObj.Add("Text", "x" . (startX + 15) . " y" . (rowY + 3) . " w48", labelText)

        chkCtrl := guiObj.Add("CheckBox", "x" . (startX + 66) . " y" . rowY . " w48", "Ctrl")
        chkShift := guiObj.Add("CheckBox", "x" . (startX + 117) . " y" . rowY . " w54", "Shift")
        chkWin := guiObj.Add("CheckBox", "x" . (startX + 174) . " y" . rowY . " w48", "Win")
        chkAlt := guiObj.Add("CheckBox", "x" . (startX + 225) . " y" . rowY . " w45", "Alt")

        chkCtrl.Value := parsed.Mods.Ctrl
        chkShift.Value := parsed.Mods.Shift
        chkWin.Value := parsed.Mods.Win
        chkAlt.Value := parsed.Mods.Alt

        guiObj.SetFont("cBlack")
        cbKey := guiObj.Add("ComboBox", "x" . (startX + 275) . " y" . (rowY - 2) . " w120",
            PreferencesManager.GetHotkeyBaseKeys())
        guiObj.SetFont("s10 c" . THEME_TEXT, "Segoe UI")
        cbKey.Text := parsed.Key

        row := { Ctrl: chkCtrl, Shift: chkShift, Win: chkWin, Alt: chkAlt, Key: cbKey }
        for ctrl in [chkCtrl, chkShift, chkWin, chkAlt]
            ctrl.OnEvent("Click", ObjBindMethod(this, "MarkDirty"))
        cbKey.OnEvent("Change", ObjBindMethod(this, "MarkDirty"))
        return row
    }

    ; Reads one hotkey row back into an AutoHotkey hotkey string.
    ReadHotkeyRow(row) {
        baseKey := Trim(row.Key.Text)
        return {
            Hotkey: BuildKeyString(row.Ctrl.Value, row.Shift.Value, row.Win.Value, row.Alt.Value, baseKey),
            BaseKey: baseKey,
            HasModifier: (row.Ctrl.Value || row.Shift.Value || row.Win.Value || row.Alt.Value)
        }
    }

    OnStartupToggle(*) {
        requestedState := this.chkStartup.Value == 1
        if !ConfigSetStartupEnabled(requestedState)
            this.chkStartup.Value := ConfigIsStartupEnabled()
    }

    HasPendingDashboardChanges() {
        return this.parentGui
            && DashboardManager.instance
            && DashboardManager.instance.HasUnsavedChanges()
    }

    OnRestoreSettings(*) {
        if (this.HasPendingDashboardChanges()) {
            msg := "⚠️ You have unsaved dashboard changes.`n`n"
                . "Restoring a backup will discard them if you confirm the restore in the next step.`n"
                . "Choose No to return and save first.`n`nContinue to Restore?"
            if (MsgBox(msg, "Unsaved Changes", 262452) != "Yes")
                return
        }
        RestoreConfigs()
    }

    OnFactoryReset(*) {
        if (this.parentGui && DashboardManager.instance)
            DashboardManager.instance.RequestResetToDefaults("All")
        else
            ResetToDefaults("All")
    }

    ; Refreshes the "Preview: Win+Num1 … Win+Num9" hint from the current selections.
    OnMainHotkeyChange(*) {
        this.UpdateMainHotkeyPreview()
        this.MarkDirty()
    }

    OnPromptHotkeyChange(*) {
        this.UpdatePromptPreview()
        this.MarkDirty()
    }

    UpdateMainHotkeyPreview(*) {
        baseKey := Trim(this.cbMainKey.Text)
        if (baseKey == "")
            baseKey := "F1"
        mainHotkey := BuildKeyString(this.chkMainCtrl.Value, this.chkMainShift.Value, this.chkMainWin.Value, this.chkMainAlt.Value, baseKey)
        addFolderHotkey := GetAddFolderHotkey(mainHotkey)
        this.txtMainPreview.Value := "Related shortcut: Add current folder = " . FormatHotkeyDisplay(addFolderHotkey)
    }

    UpdatePromptPreview(*) {
        modStr := BuildKeyString(this.chkPromptCtrl.Value, this.chkPromptShift.Value, this.chkPromptWin.Value, this.chkPromptAlt.Value, "")
        if (modStr == "") {
            this.txtPromptPreview.Value := "⚠️ Select at least one modifier"
            return
        }
        prefix := FormatHotkeyDisplay(modStr)
        numLabel := (this.ddlPromptNumpad.Value == 1) ? "Num" : ""
        this.txtPromptPreview.Value := "Preview:  " . prefix . numLabel . "1  …  " . prefix . numLabel . "9"
    }

    IsDirty() {
        return this.dirtyState
    }

    MarkDirty(*) {
        this.dirtyState := true
        UpdateSaveButtonState(this.btnSave, true)
    }

    MarkClean() {
        this.dirtyState := false
        UpdateSaveButtonState(this.btnSave, false)
    }

    OnSavePreferences(*) {
        this.TrySavePreferences()
    }

    TrySavePreferences(showFeedback := true, reloadAfterSave := true) {
        mainBase := Trim(this.cbMainKey.Text)
        if (mainBase == "")
            mainBase := "F1"

        try {
            validName := GetKeyName(mainBase)
        } catch {
            validName := ""
        }
        if (validName == "") {
            MsgBox("⚠️ '" . mainBase . "' is not a valid key name.`n`nNo settings were saved.", "Invalid Key", 262160)
            return false
        }

        newHotkey := BuildKeyString(this.chkMainCtrl.Value, this.chkMainShift.Value, this.chkMainWin.Value, this.chkMainAlt.Value, mainBase)
        newModVal := BuildKeyString(this.chkPromptCtrl.Value, this.chkPromptShift.Value, this.chkPromptWin.Value, this.chkPromptAlt.Value, "")
        newUseNumpad := (this.ddlPromptNumpad.Value == 1) ? 1 : 0

        if (newModVal == "") {
            MsgBox("⚠️ Please select at least one Quick Prompts modifier key.`n`nExample: Win + Numpad 1`n`nNo settings were saved.", "Invalid Hotkey", 262160)
            return false
        }

        emojiRow := this.ReadHotkeyRow(this.emojiControls)
        exitRow := this.ReadHotkeyRow(this.exitControls)

        ; Both of these fire globally, so a bare key would make ordinary typing
        ; open the symbol menu or quit the app. Require a modifier and a real key.
        for spec in [{ Label: "Emoji & Symbols", Row: emojiRow }, { Label: "Exit App", Row: exitRow }] {
            if (spec.Row.BaseKey == "") {
                MsgBox("⚠️ Choose a base key for the " . spec.Label . " shortcut.`n`nNo settings were saved.",
                    "Invalid Hotkey", 262160)
                return false
            }
            try {
                rowKeyName := GetKeyName(spec.Row.BaseKey)
            } catch {
                rowKeyName := ""
            }
            if (rowKeyName == "") {
                MsgBox("⚠️ '" . spec.Row.BaseKey . "' is not a valid key name for the " . spec.Label
                    . " shortcut.`n`nNo settings were saved.", "Invalid Key", 262160)
                return false
            }
            if (!spec.Row.HasModifier) {
                MsgBox("⚠️ The " . spec.Label . " shortcut needs at least one modifier key.`n`n"
                    . "Without one, pressing '" . spec.Row.BaseKey . "' while typing would trigger it.`n`n"
                    . "No settings were saved.", "Invalid Hotkey", 262160)
                return false
            }
        }

        conflict := ValidateHotkeyAssignments(
            newHotkey,
            newModVal,
            newUseNumpad,
            emojiRow.Hotkey,
            exitRow.Hotkey
        )
        if (conflict != "") {
            MsgBox("⚠️ Hotkey conflict detected:`n`n" . conflict . "`n`nPlease choose a different combination.`n`nNo settings were saved.", "Hotkey Conflict", 262160)
            return false
        }

        ConfigWriteAppSettings(newHotkey, newModVal, newUseNumpad, emojiRow.Hotkey, exitRow.Hotkey)
        this.MarkClean()

        if (!this.parentGui)
            this.pGui.Destroy()
        if (showFeedback)
            MsgBox("✅ Settings saved successfully! The app will now reload.", "Success", 262208)
        if (reloadAfterSave)
            Reload()
        return true
    }
}

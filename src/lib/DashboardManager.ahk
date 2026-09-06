#Requires AutoHotkey v2.0
#Include Theme.ahk
#Include FolderManager.ahk
#Include PromptManager.ahk
#Include HotstringManager.ahk
#Include KeyRemapManager.ahk
#Include PreferencesManager.ahk
#Include AppInfo.ahk
#Include Manual.ahk
; Runtime global g_appVersion is initialized in SwiftDeck.ahk before this module is included.

; =================================================================================
; Module: DashboardManager
; Description: The main unified settings window hosting all feature configuration tabs.
; Author: KBPark
; =================================================================================
class DashboardManager {
    static instance := ""

    static Show(tabIndex := 1) {
        if (!DashboardManager.instance) {
            DashboardManager.instance := DashboardManager()
        }
        DashboardManager.instance.ShowGui(tabIndex)
    }

    __New() {
        this.hGui := Gui("+AlwaysOnTop +OwnDialogs", "SwiftDeck App Settings")
        ApplyTheme(this.hGui, "SwiftDeck", "")
        this.hGui.OnEvent("Close", ObjBindMethod(this, "HandleClose"))

        this.hGui.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        this.txtHeaderStatus := this.hGui.Add("Text", "x20 y40 w280 h20 BackgroundTrans",
            "v" . g_appVersion . " | FinOps Automation && HotKey Suite")

        ; Add top-right global actions. Update stays hidden until a newer release is detected.
        this.hGui.SetFont("s9 cCCCCCC norm", "Segoe UI")
        btnGlobalManual := this.hGui.Add("Button", "x310 y20 w80 h28", "📘 Manual")
        btnGlobalManual.OnEvent("Click", (*) => OpenAppManual("", this.hGui.Hwnd))

        this.btnGlobalInfo := this.hGui.Add("Button", "x395 y20 w85 h28", "ℹ️ App Info")
        this.btnGlobalInfo.OnEvent("Click", (*) => ShowAppInformation(this.hGui.Hwnd))

        this.btnGlobalUpdate := this.hGui.Add("Button", "x310 y50 w170 h22 Hidden", "⬆ Update")
        this.btnGlobalUpdate.OnEvent("Click", ObjBindMethod(this, "HandleUpdateAction"))
        this.hGui.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        ; Create Tab Control
        ; Height is driven by the General tab, the tallest panel: it now carries a
        ; fourth hotkey group. The other tabs simply gain trailing whitespace.
        this.mainTab := this.hGui.Add("Tab3", "x20 y80 w460 h535", ["📁 Folders", "⌨️ Prompts", "✏️ Hotstrings", "🔀 Key Remap", "⚙️ General"])

        this.mainTab.UseTab(1)
        this.folderMgr := FolderManager(this.hGui)
        this.folderMgr.dashboardResetHandler := ObjBindMethod(this, "RequestResetToDefaults")

        this.mainTab.UseTab(2)
        this.promptMgr := PromptManager(this.hGui)
        this.promptMgr.dashboardResetHandler := ObjBindMethod(this, "RequestResetToDefaults")

        this.mainTab.UseTab(3)
        this.hotstringMgr := HotstringManager(this.hGui)
        this.hotstringMgr.dashboardResetHandler := ObjBindMethod(this, "RequestResetToDefaults")

        this.mainTab.UseTab(4)
        this.keyRemapMgr := KeyRemapManager(this.hGui)
        this.keyRemapMgr.dashboardResetHandler := ObjBindMethod(this, "RequestResetToDefaults")

        this.mainTab.UseTab(5)
        this.prefMgr := PreferencesManager(this.hGui)

        this.mainTab.UseTab()
        this.mainTab.OnEvent("Change", (*) => this.OnTabChange())
        UpdateManager.RegisterUiRefreshCallback(ObjBindMethod(this, "RefreshUpdateIndicator"))
        UpdateManager.RegisterPreUpdateCallback(ObjBindMethod(this, "ConfirmUnsavedChanges", "update"))
        this.RefreshUpdateIndicator()
    }

    OnTabChange() {
        tabIndex := this.mainTab.Value
        if (tabIndex == 1) {
            this.folderMgr.RefreshList()
        } else if (tabIndex == 2) {
            this.promptMgr.RefreshList()
        } else if (tabIndex == 3) {
            this.hotstringMgr.RefreshList()
        } else if (tabIndex == 4) {
            this.keyRemapMgr.RefreshList()
        }
    }

    ShowGui(tabIndex) {
        this.ReloadTabsFromDisk()
        this.mainTab.Choose(tabIndex)
        this.OnTabChange()
        this.RefreshUpdateIndicator()
        ShowCenteredOnMouse(this.hGui)
    }

    ; The dashboard is built once and only hidden on close, so its lists would
    ; otherwise stay on the snapshot taken the first time it opened. Every save
    ; rewrites the whole section from that snapshot, which would discard anything
    ; changed in the settings files meanwhile. These four tabs save immediately,
    ; so there is no unsaved in-memory state to lose by re-reading. General is
    ; excluded: it holds pending edits behind its own Save & Apply button.
    ReloadTabsFromDisk() {
        for manager in [this.folderMgr, this.promptMgr, this.hotstringMgr, this.keyRemapMgr] {
            try manager.ReloadFromDisk()
        }
    }

    RefreshUpdateIndicator() {
        if !this.HasOwnProp("btnGlobalUpdate") || !this.HasOwnProp("txtHeaderStatus")
            return
        state := UpdateManager.GetState()
        if (state.Status == "available") {
            this.txtHeaderStatus.Text := "⬆ New version v" . state.LatestVersion . " available"
            this.txtHeaderStatus.SetFont("s9 cFFCC66 bold", "Segoe UI")
            this.btnGlobalUpdate.Text := "⬆ Update to v" . state.LatestVersion
            this.btnGlobalUpdate.Visible := true
        } else {
            this.txtHeaderStatus.Text := "v" . g_appVersion . " | FinOps Automation && HotKey Suite"
            this.txtHeaderStatus.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
            this.btnGlobalUpdate.Visible := false
        }
    }

    HandleUpdateAction(*) {
        SetTimer((*) => UpdateManager.BeginUpdate(), -50)
    }

    HasUnsavedChanges() {
        return this.prefMgr.IsDirty()
    }

    SaveAllChanges(reloadForGeneral := true, showFeedback := true) {
        generalWasDirty := this.prefMgr.IsDirty()
        try {
            if (generalWasDirty && !this.prefMgr.TrySavePreferences(false, false))
                return false
        } catch Error as err {
            MsgBox("❌ Could not save all settings.`n`nError: " . err.Message, "Save Failed", 262160)
            return false
        }

        if (generalWasDirty && reloadForGeneral) {
            MsgBox("✅ All changes were saved. The app will now reload to apply the new hotkeys.", "Saved", 262208)
            Reload()
            return true
        }

        if (showFeedback) {
            ToolTip("✅ All changes saved")
            SetTimer(() => ToolTip(), -2000)
        }
        return true
    }

    DiscardChanges() {
        UpdateManager.RegisterUiRefreshCallback()
        UpdateManager.RegisterPreUpdateCallback()
        this.hGui.Destroy()
        DashboardManager.instance := ""
    }

    RequestResetToDefaults(target) {
        if this.HasUnsavedChanges() {
            targetLabel := target == "All" ? "all settings" : target
            msg := "⚠️ You have unsaved dashboard changes.`n`n"
                . "Resetting " . targetLabel . " will discard them if you confirm the reset in the next step.`n"
                . "Choose No to return and save first.`n`nContinue to Reset?"
            if (MsgBox(msg, "Unsaved Changes", 262452) != "Yes")
                return false
        }
        ResetToDefaults(target)
        return true
    }

    ConfirmUnsavedChanges(actionName := "close") {
        if !this.HasUnsavedChanges()
            return true

        msg := "You have unsaved changes.`n`n"
            . "Yes  = Save All`n"
            . "No   = Discard changes`n"
            . "Cancel = Keep editing"
        result := MsgBox(msg, "Unsaved Changes", 262195)

        if (result == "Yes")
            return this.SaveAllChanges(actionName == "close", actionName != "exit")
        if (result == "No") {
            this.DiscardChanges()
            return true
        }
        return false
    }

    HandleClose(*) {
        if !this.HasUnsavedChanges() {
            this.hGui.Hide()
            return true
        }

        if !this.ConfirmUnsavedChanges("close")
            return true
        if (DashboardManager.instance)
            this.hGui.Hide()
        return true
    }
}

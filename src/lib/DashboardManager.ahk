#Requires AutoHotkey v2.0
#Include Theme.ahk
#Include FolderManager.ahk
#Include PromptManager.ahk
#Include HotstringManager.ahk
#Include KeyRemapManager.ahk
#Include PreferencesManager.ahk
#Include AppInfo.ahk
#Include Manual.ahk
#Include CatalogManager.ahk
; Runtime global g_appVersion is initialized in SwiftDeck.ahk before this module is included.

; =================================================================================
; Module: DashboardManager
; Description: The main unified settings window hosting all feature configuration tabs.
; Author: KBPark
; =================================================================================
class DashboardManager {
    static instance := ""
    static listKeysHooked := false

    static Show(tabIndex := 1) {
        if (!DashboardManager.instance) {
            DashboardManager.instance := DashboardManager()
        }
        DashboardManager.instance.ShowGui(tabIndex)
    }

    __New() {
        ; Measured design size of this window. It used to be 514x665, which at
        ; 150% on a 1080p panel scaled to 998px of a 1008px work area: the
        ; window filled the screen and, having no resize border, could not be
        ; made smaller. Every tab now shares one compact height instead.
        ; Above the size the screen can hold, the part that falls off the
        ; bottom — Factory Reset, backup and restore — could not be scrolled
        ; or dragged back into view, so that case still opts out of scaling.
        this.hGui := Gui("+AlwaysOnTop +OwnDialogs" . GetFittingGuiOptions(514, 550),
            "SwiftDeck App Settings")
        ApplyTheme(this.hGui, "SwiftDeck", "")
        this.hGui.OnEvent("Close", ObjBindMethod(this, "HandleClose"))
        ; Esc goes through the same unsaved-changes check as the close button.
        this.hGui.OnEvent("Escape", ObjBindMethod(this, "HandleClose"))

        this.hGui.SetFont("s9 c" . THEME_MUTED . " norm", "Segoe UI")
        this.txtHeaderStatus := this.hGui.Add("Text", "x20 y40 w280 h18 BackgroundTrans",
            "v" . g_appVersion . " | FinOps Automation && HotKey Suite")

        ; Add top-right global actions. Update stays hidden until a newer release is detected.
        this.hGui.SetFont("s9 cCCCCCC norm", "Segoe UI")
        ; A window of its own: a sixth tab would wrap the tab strip to two rows.
        btnGlobalCatalog := this.hGui.Add("Button", "x225 y14 w80 h28", "📚 Catalog")
        btnGlobalCatalog.OnEvent("Click", (*) => CatalogManager.Show(this.hGui.Hwnd, ObjBindMethod(this, "OnCatalogChanged")))
        btnGlobalManual := this.hGui.Add("Button", "x310 y14 w80 h28", "📘 Manual")
        btnGlobalManual.OnEvent("Click", (*) => OpenAppManual("", this.hGui.Hwnd))

        this.btnGlobalInfo := this.hGui.Add("Button", "x395 y14 w85 h28", "ℹ️ App Info")
        this.btnGlobalInfo.OnEvent("Click", (*) => ShowAppInformation(this.hGui.Hwnd))

        this.btnGlobalUpdate := this.hGui.Add("Button", "x310 y45 w170 h22 Hidden", "⬆ Update")
        this.btnGlobalUpdate.OnEvent("Click", ObjBindMethod(this, "HandleUpdateAction"))
        this.hGui.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")

        ; Create Tab Control
        ; Every tab lays out from y110 and ends by y490, so the panels share one
        ; height and none of them leaves a band of empty space at the bottom.
        this.mainTab := this.hGui.Add("Tab3", "x20 y70 w460 h430", ["📁 Folders", "⌨️ Prompts", "✏️ Hotstrings", "🔀 Key Remap", "⚙️ General"])

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
        if !DashboardManager.listKeysHooked {
            OnMessage(0x0100, ObjBindMethod(DashboardManager, "OnListKeyDown"))  ; WM_KEYDOWN
            DashboardManager.listKeysHooked := true
        }
        UpdateManager.RegisterUiRefreshCallback(ObjBindMethod(this, "RefreshUpdateIndicator"))
        UpdateManager.RegisterPreUpdateCallback(ObjBindMethod(this, "ConfirmUnsavedChanges", "update"))
        this.RefreshUpdateIndicator()
    }

    ; Del deletes and Enter edits the selected item while one of the four tab
    ; lists has the focus. Registered once per process, it resolves against the
    ; dashboard that exists now (it is rebuilt after Discard) and leaves every
    ; other control, including the lists' popups, untouched.
    static OnListKeyDown(wParam, lParam, msg, hwnd) {
        dash := DashboardManager.instance
        if !dash
            return
        if (lParam & 0x40000000)  ; auto-repeat: one action per key press
            return
        if (wParam != 0x2E && wParam != 0x0D)  ; VK_DELETE, VK_RETURN
            return
        ; This runs for every key typed into the app, so it must never throw.
        try {
            for mgr in [dash.folderMgr, dash.promptMgr, dash.hotstringMgr, dash.keyRemapMgr] {
                if (hwnd != mgr.lbItems.Hwnd)
                    continue
                if (wParam == 0x2E)
                    action := ObjBindMethod(mgr, "DeleteItem")
                else
                    action := ObjBindMethod(mgr, mgr.HasMethod("EditFolder") ? "EditFolder" : "EditSelectedItem")
                ; Run once this message is handled, not inside it: the action
                ; opens a confirmation box or an edit popup.
                SetTimer(action, -1)
                return 0
            }
        }
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
        for manager in [this.folderMgr, this.promptMgr, this.hotstringMgr, this.keyRemapMgr, this.prefMgr] {
            try manager.ReloadFromDisk()
        }
    }

    ; A catalog added to or replaced the prompts and hotstrings on disk. The
    ; Hotstrings tab's ReloadFromDisk also rebuilds its group list, keeping the
    ; group that was open when it still exists.
    OnCatalogChanged() {
        this.ReloadTabsFromDisk()
        this.OnTabChange()
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

        if (showFeedback)
            ShowFeedbackToolTip("✅ All changes saved")
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

        ; Exit and Reload end the process right after, so they skip both the
        ; save-then-reload step and the tooltip nobody would see.
        if (result == "Yes")
            return this.SaveAllChanges(actionName == "close", actionName != "exit" && actionName != "reload")
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

RegisterDashboardOpenCallback((tabIndex := 1) => DashboardManager.Show(tabIndex))

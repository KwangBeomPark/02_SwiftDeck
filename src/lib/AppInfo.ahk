#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Theme.ahk
#Include FolderManager.ahk
#Include Utils.ahk
#Include UpdateManager.ahk
; Runtime global g_appVersion is initialized in SwiftDeck.ahk before this module is included.

; =================================================================================
; Module: AppInfo
; Description: Displays application details, diagnostics, paths, and support links.
; Author: KBPark
; =================================================================================
; A download that returned an error page (captive portal, proxy notice) is saved
; with the right extension but is not a valid image, and Add("Picture") then
; throws "Can't create control" — taking the whole App Information window with
; it, on every open, until the file is deleted by hand. Drop the bad file so the
; next open re-downloads it, and let the caller fall back.
TryAddPicture(guiObj, options, imagePath) {
    if !FileExist(imagePath)
        return ""
    try {
        return guiObj.Add("Picture", options, imagePath)
    } catch {
        try FileDelete(imagePath)
        return ""
    }
}

ShowAppInformation(parentHwnd := 0) {

    bmcBtnPath := GetAppAssetPath("bmc_button.png")
    if !FileExist(bmcBtnPath) {
        try {
            SplitPath(bmcBtnPath, , &bmcDir)
            if (bmcDir != "" && !DirExist(bmcDir))
                DirCreate(bmcDir)
            Download("https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png", bmcBtnPath)
        }
    }

    githubBtnPath := GetAppAssetPath("github_icon.png")
    if !FileExist(githubBtnPath) {
        try {
            SplitPath(githubBtnPath, , &githubDir)
            if (githubDir != "" && !DirExist(githubDir))
                DirCreate(githubDir)
            Download("https://www.google.com/s2/favicons?domain=github.com&sz=64", githubBtnPath)
        }
    }
    favoriteConfigPath := GetConfigPath("Folders")
    promptConfigPath := GetConfigPath("Prompts")
    hotstringConfigPath := GetConfigPath("Hotstrings")

    guiOptions := "+AlwaysOnTop -MinimizeBox -MaximizeBox"
    if (parentHwnd && WinExist("ahk_id " . parentHwnd)) {
        WinSetEnabled(0, parentHwnd)
        guiOptions .= " +Owner" . parentHwnd
    } else {
        parentHwnd := 0
    }

    infoGui := Gui(guiOptions, "ℹ️ App Information & Support")
    ApplyTheme(infoGui, "", "") ; No header text from Theme

    ; Developer Info Title
    infoGui.SetFont("s10 bold c" . THEME_TEXT, "Segoe UI")
    infoGui.Add("Text", "x20 y15 w350 h25 BackgroundTrans", "👤 Developer: Kwang Beom Park")

    ; Developer Description
    infoGui.SetFont("s9 norm c" . THEME_MUTED, "Segoe UI")
    infoGui.Add("Text", "x20 y40 w350 h60 BackgroundTrans", "A business operations practitioner passionate about office automation and daily productivity.`n👉 Click the GitHub icon on the right to view other office apps!")

    picGithub := TryAddPicture(infoGui, "x380 y15 w64 h64 BackgroundTrans", githubBtnPath)
    if (picGithub)
        picGithub.OnEvent("Click", (*) => RunSafely("https://github.com/KwangBeomPark", "Open GitHub"))
    infoGui.SetFont("s10 norm c" . THEME_TEXT, "Segoe UI")

    CleanUpAndClose() {
        if (parentHwnd && WinExist("ahk_id " . parentHwnd)) {
            WinSetEnabled(1, parentHwnd)
            WinActivate("ahk_id " . parentHwnd)
        }
        infoGui.Destroy()
    }
    infoGui.OnEvent("Close", (*) => CleanUpAndClose())

    ; Gather statistics
    folderCount := FolderManager.ReadFolderItems().Length
    hsSpaceCount := 0
    hsMenuCount := 0
    if ConfigExists("Hotstrings") {
        hsCounts := ConfigCountHotstrings()
        hsSpaceCount := hsCounts.Space
        hsMenuCount := hsCounts.Menu
    }
    hsTotal := hsSpaceCount + hsMenuCount

    promptCount := 0
    if ConfigExists("Prompts") {
        loop 10 {
            promptCount += ConfigCountPairs("Prompts", "Numpad" . (A_Index - 1))
        }
    }

    remapCount := 0
    if ConfigExists("KeyRemaps")
        remapCount := ConfigCountPairs("KeyRemaps", "Remaps")

    ; 1. Application Overview
    infoGui.Add("GroupBox", "x20 y110 w440 h140 c" . THEME_ACCENT, "📊 Application Overview")
    infoGui.Add("Text", "x35 y135 w190", "Installed version: " . g_appVersion)
    txtUpdateStatus := infoGui.Add("Text", "x225 y135 w220", UpdateManager.GetStatusText())
    infoGui.Add("Text", "x35 y160 w190", "📁 Favorites: " . folderCount . " registered")
    infoGui.Add("Text", "x35 y185 w190", "⌨️ Prompts: " . promptCount . " total")
    infoGui.Add("Text", "x245 y160 w190", "✏️ Hotstrings: " . hsTotal . " total")
    infoGui.SetFont("s9 c" . THEME_MUTED)
    infoGui.Add("Text", "x255 y180 w180", "(Auto: " . hsSpaceCount . " / Menu: " . hsMenuCount . ")")
    infoGui.SetFont("s10 c" . THEME_TEXT)
    infoGui.Add("Text", "x245 y185 w190", "🔀 Key Remaps: " . remapCount . " total")

    btnCheckUpdates := infoGui.Add("Button", "x35 y212 w175 h28", "🔍 Check for Updates")
    btnUpdateNow := infoGui.Add("Button", "x220 y212 w225 h28", "⬆ Update && Restart")

    RefreshUpdateControls() {
        state := UpdateManager.GetState()
        txtUpdateStatus.Value := UpdateManager.GetStatusText()
        btnUpdateNow.Enabled := A_IsCompiled && state.Status == "available"
    }

    CheckUpdates(*) {
        txtUpdateStatus.Value := "Checking GitHub…"
        UpdateManager.CheckForUpdates(false)
        RefreshUpdateControls()
    }

    StartUpdate(*) {
        CleanUpAndClose()
        SetTimer((*) => UpdateManager.BeginUpdate(), -50)
    }

    btnCheckUpdates.OnEvent("Click", CheckUpdates)
    btnUpdateNow.OnEvent("Click", StartUpdate)
    RefreshUpdateControls()

    ; 2. File Paths
    infoGui.Add("GroupBox", "x20 y260 w440 h155 c" . THEME_ACCENT, "📂 Configuration File Paths")

    infoGui.SetFont("s9 c" . THEME_MUTED)
    infoGui.Add("Text", "x35 y285 w410", "Favorites Config:")
    infoGui.SetFont("s9 c" . THEME_TEXT)
    infoGui.Add("Edit", "x35 y303 w345 h22 ReadOnly Background2D2D30 -Border", favoriteConfigPath)
    btnOpenFavFile := infoGui.Add("Button", "x390 y301 w55 h24", "Open")
    btnOpenFavFile.OnEvent("Click", (*) => OpenFileInEditor(favoriteConfigPath, "Open Config File"))

    infoGui.SetFont("s9 c" . THEME_MUTED)
    infoGui.Add("Text", "x35 y328 w410", "Quick Prompts Config:")
    infoGui.SetFont("s9 c" . THEME_TEXT)
    infoGui.Add("Edit", "x35 y346 w345 h22 ReadOnly Background2D2D30 -Border", promptConfigPath)
    btnOpenPrFile := infoGui.Add("Button", "x390 y344 w55 h24", "Open")
    btnOpenPrFile.OnEvent("Click", (*) => OpenFileInEditor(promptConfigPath, "Open Config File"))

    infoGui.SetFont("s9 c" . THEME_MUTED)
    infoGui.Add("Text", "x35 y371 w410", "Hotstrings Config:")
    infoGui.SetFont("s9 c" . THEME_TEXT)
    infoGui.Add("Edit", "x35 y389 w345 h22 ReadOnly Background2D2D30 -Border", hotstringConfigPath)
    btnOpenHsFile := infoGui.Add("Button", "x390 y387 w55 h24", "Open")
    btnOpenHsFile.OnEvent("Click", (*) => OpenFileInEditor(hotstringConfigPath, "Open Config File"))
    infoGui.SetFont("s10 c" . THEME_TEXT)

    ; 3. Support Developer
    infoGui.Add("GroupBox", "x20 y425 w440 h115 c" . THEME_ACCENT, "☕ Support the Developer")
    infoGui.Add("Text", "x35 y447 w410", "If this tool helps your daily workflow, consider buying a coffee!")

    picCoffee := TryAddPicture(infoGui, "x130 y470 w217 h60 BackgroundTrans", bmcBtnPath)
    if (picCoffee) {
        picCoffee.OnEvent("Click", (*) => RunSafely("https://www.buymeacoffee.com/KBPark_Bob", "Open Support Page"))
    } else {
        infoGui.SetFont("s11 cBlack bold", "Segoe UI")
        btnCoffee := infoGui.Add("Button", "x130 y475 w220 h45", "☕ Buy Me a Coffee")
        btnCoffee.OnEvent("Click", (*) => RunSafely("https://www.buymeacoffee.com/KBPark_Bob", "Open Support Page"))
        infoGui.SetFont("s10 c" . THEME_TEXT . " norm", "Segoe UI")
    }

    btnClose := infoGui.Add("Button", "x180 y555 w120 h35 Default", "Close")
    btnClose.OnEvent("Click", (*) => CleanUpAndClose())

    ShowCenteredOnMouse(infoGui, "w480 h605")
}

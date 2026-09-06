#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Utils.ahk
#Include FolderManager.ahk
#Include DashboardManager.ahk
; g_FolderMenuCache is owned by this module.

; =================================================================================
; Module: FolderMenu
; Description: Core logic for displaying and managing the popup Favorites menu.
; Author: KBPark
; =================================================================================
; =================================================================================
; --- Folder Menu System ---
; =================================================================================

; Global cache store (for top-level and 1st-level folder menus)
global g_FolderMenuCache := Map()

ShowFavoritesMenu() {
    if !ConfigExists("Folders") {
        MsgBox("⚠️ Cannot find the setting file.", "Error", 262160)
        return
    }

    folderItems := FolderManager.ReadFolderItems()

    ; --- Loading indicator while scanning folders (hidden instantly on cache hit) ---
    loadGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    loadGui.SetFont("s12", "Segoe UI")
    loadGui.Add("Text", "w280 Center", "📂 Loading folders...")
    ShowCenteredOnMouse(loadGui, "NoActivate")

    mainContextMenu := Menu()
    usedRootLabels := NewMenuLabelSet()
    for idx, obj in folderItems {
        rootFolderPath := obj.Path
        rootFolderName := obj.Name
        if rootFolderPath == "A_Startup"
            rootFolderPath := A_Startup

        if rootFolderName == "-" {
            mainContextMenu.Add()
            continue
        }
        rootMenuLabel := UniqueMenuLabel(SafeMenuLabel(rootFolderName, "Folder"), usedRootLabels)
        mainContextMenu.Add(rootMenuLabel, BuildFolderSubmenu(rootFolderPath, rootFolderName))
    }

    loadGui.Destroy()  ; Scan complete → remove loading indicator

    mainContextMenu.Add()

    ; Add current folder and settings entry
    mainHotkeyStr := ConfigReadAppSettings().MainHotkey
    
    addFolderHotkey := GetAddFolderHotkey(mainHotkeyStr)
    ; Route the trailing actions through the same label set so a favorite that
    ; happens to carry one of these names cannot hijack the Disable() below.
    addFolderMenuText := UniqueMenuLabel(
        "⭐ Add Current Folder  [" . FormatHotkeyDisplay(addFolderHotkey) . "]", usedRootLabels)

    mainContextMenu.Add(addFolderMenuText, (*) => AddCurrentExplorerFolder())
    ; Use the cheap window-class probe, not the COM lookup: this runs on every
    ; Favorites menu open and must match what the Ctrl+F1 criterion allows.
    if !IsExplorerContextActive() {
        mainContextMenu.Disable(addFolderMenuText)
    }
    mainContextMenu.Add(UniqueMenuLabel("⚙️ App Settings", usedRootLabels), (*) => DashboardManager.Show(1))

    mainContextMenu.Show()
    return
}

AddCurrentExplorerFolder() {
    if !IsExplorerContextActive() {
        MsgBox("⚠️ No Explorer window found. Please open Explorer and try again.", "Info", 262208)
        return
    }

    explorerPath := GetActiveExplorerPath()
    if (explorerPath == "") {
        ; Views like This PC and Control Panel have no folder path. A modal dialog
        ; here would interrupt a shortcut the user may have meant for Explorer, so
        ; report it transiently the way the rest of the app reports minor results.
        ToolTip("⚠️ This window has no folder path to add")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    ; Only adopt the dashboard as dialog owner while it is actually on screen.
    ; Closing App Settings only hides it, and a dialog owned by a hidden window
    ; can open behind Explorer with no way to reach it.
    if (DashboardManager.instance && WinExist("ahk_id " . DashboardManager.instance.hGui.Hwnd))
        DashboardManager.instance.hGui.Opt("+OwnDialogs")
    ib := InputBox("Enter a nickname for this folder:`nPath: " . explorerPath, "Add Folder", "w350 h150", GetFileName(explorerPath))
    if (ib.Result != "OK" || Trim(ib.Value) == "")
        return

    DashboardManager.Show(1)
    DashboardManager.instance.folderMgr.AddFolderItem(ib.Value, explorerPath)
}

; Returns the foreground window handle and class when an Explorer surface owns it.
; Deliberately free of COM: the Ctrl+F1 hotkey criterion calls this while the
; keyboard hook is blocked waiting for an answer.
GetActiveExplorerContext() {
    hwnd := WinExist("A")
    if (!hwnd)
        return { Hwnd: 0, Class: "" }

    try {
        winClass := WinGetClass(hwnd)
    } catch {
        return { Hwnd: 0, Class: "" }
    }

    if !IsExplorerWindowClass(winClass)
        return { Hwnd: 0, Class: "" }
    return { Hwnd: hwnd, Class: winClass }
}

; Hotkey criterion for "Add Current Folder". Must stay cheap and must never throw.
IsExplorerContextActive() {
    return GetActiveExplorerContext().Hwnd != 0
}

GetActiveExplorerPath() {
    context := GetActiveExplorerContext()
    if (!context.Hwnd)
        return ""

    if IsDesktopWindowClass(context.Class)
        return A_Desktop

    ; Shell.Application is an out-of-process COM call into explorer.exe. It can be
    ; rejected while the shell is busy (RPC_E_CALL_REJECTED), disconnect mid-loop
    ; when a window closes, and returns an empty list when SwiftDeck is elevated
    ; but Explorer is not. Every access has to degrade to "no path" instead of
    ; surfacing an unhandled error dialog on a hotkey press.
    try {
        for window in ComObject("Shell.Application").Windows {
            try {
                if (window.HWND != context.Hwnd)
                    continue
                path := window.Document.Folder.Self.Path
            } catch {
                continue
            }
            ; Shell namespaces such as This PC report a CLSID instead of a path.
            if (path != "" && DirExist(path))
                return path
        }
    } catch {
        return ""
    }
    return ""
}

GetFolderTreeHash(rootPath) {
    hashStr := ""
    try {
        hashStr := FileGetTime(rootPath, "M")
    } catch {
        return "ERROR"
    }
    
    loop files AddTrailingBackslash(rootPath) . "*", "D" {
        if InStr(A_LoopFileAttrib, "H")
            continue
        try hashStr .= "|" . A_LoopFileTimeModified
    }
    return hashStr
}

BuildFolderSubmenu(rootPath, rootLabel) {
    global g_FolderMenuCache
    maxLv1 := 30  ; Max Level-1 subfolders to display
    maxLv2 := 20  ; Max Level-2 subfolders to display

    ; Show warning menu item if folder doesn't exist or drive is disconnected
    if !FileExist(rootPath) || !InStr(FileExist(rootPath), "D") {
        MenuLv0 := Menu()
        MenuLv0.Add(SafeMenuLabel("No Folder Exist: " . rootPath, "No Folder Exist", 80), ShowFolderWarningMsg.Bind())
        return MenuLv0
    }

    ; [Cache Logic Start]
    ; Extract modification time hash (very fast — reads only 1 level even on network drives)
    currentHash := GetFolderTreeHash(rootPath)
    
    ; Cache check
    if (g_FolderMenuCache.Has(rootPath)) {
        cacheObj := g_FolderMenuCache[rootPath]
        if (cacheObj.Hash == currentHash) {
            return cacheObj.Menu
        }
    }
    ; [Cache Logic End]

    menuLv1 := Menu()
    usedLv1Labels := NewMenuLabelSet()
    menuLv1.Add(UniqueMenuLabel("Open " . SafeMenuLabel(rootLabel, "Folder"), usedLv1Labels), OpenFolder.Bind(rootPath))
    menuLv1.Add()

    cntLv1 := 0
    for childPath in GetFoldersList(AddTrailingBackslash(rootPath) . "*", "D") {
        cntLv1++
        if (cntLv1 > maxLv1) {
            menuLv1.Add(UniqueMenuLabel("... (" . (cntLv1 - 1) . "+ more folders)", usedLv1Labels), OpenFolder.Bind(rootPath))
            break
        }
        childLabel := GetLastFolderName(childPath)
        if !childLabel
            continue

        menuLv2 := Menu()
        usedLv2Labels := NewMenuLabelSet()
        menuLv2.Add(UniqueMenuLabel("Open " . SafeMenuLabel(childLabel, "Folder"), usedLv2Labels), OpenFolder.Bind(childPath))
        menuLv2.Add()

        cntLv2 := 0
        for grandchildPath in GetFoldersList(AddTrailingBackslash(childPath) . "*", "D") {
            cntLv2++
            if (cntLv2 > maxLv2) {
                menuLv2.Add(UniqueMenuLabel("... (" . (cntLv2 - 1) . "+ more folders)", usedLv2Labels), OpenFolder.Bind(childPath))
                break
            }
            grandchildLabel := GetLastFolderName(grandchildPath)
            if !grandchildLabel
                continue
            menuLv2.Add(UniqueMenuLabel(SafeMenuLabel(grandchildLabel, "Folder"), usedLv2Labels), OpenFolder.Bind(grandchildPath))
        }

        if (cntLv2 == 0) {
            menuLv1.Add(UniqueMenuLabel(SafeMenuLabel(childLabel, "Folder"), usedLv1Labels), OpenFolder.Bind(childPath))
        } else {
            menuLv1.Add(UniqueMenuLabel(SafeMenuLabel(childLabel, "Folder"), usedLv1Labels), menuLv2)
        }
    }

    ; Update Cache
    g_FolderMenuCache[rootPath] := { Hash: currentHash, Menu: menuLv1 }

    return menuLv1
}

ShowFolderWarningMsg() {
    MsgBox("The specified folder could not be found. The network drive may be disconnected or inaccessible.", "Folder Not Found!", 262144)
}

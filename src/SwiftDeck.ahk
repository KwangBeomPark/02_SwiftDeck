#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName SwiftDeck
;@Ahk2Exe-SetVersion 1.4.2.0
;@Ahk2Exe-SetDescription SwiftDeck - FinOps Automation & HotKey Suite
;@Ahk2Exe-SetMainIcon ..\assets\SwiftDeck.ico

; =============================================================================
; SECTION: Global Configuration
; =============================================================================

; [Global] Display version shown in the app UI
global g_appVersion := "1.4.2"

; [Global] All active settings live beside the executable; Roaming originals stay untouched.
global g_targetFolder := A_ScriptDir . "\UserSetting\"

; [Global] Config file names
global g_fileName_Folder := "App02_01FavFolderSetting_v2_DoNotDelete.ini"
global g_fileName_Hotkey := "App02_02HotkeySetting_v2_DoNotDelete.ini"
global g_fileName_Hotstring := "App02_03HotstringSetting_DoNotDelete.ini"
global g_fileName_KeyRemap := "App02_04KeyRemap_DoNotDelete.ini"

; [Global] Full config file paths
global g_filePath_Folder := g_targetFolder . g_fileName_Folder
global g_filePath_Hotkey := g_targetFolder . g_fileName_Hotkey
global g_filePath_Hotstring := g_targetFolder . g_fileName_Hotstring
global g_filePath_KeyRemap := g_targetFolder . g_fileName_KeyRemap

; [Global] Runtime state
global g_registeredHotstrings := []
global g_registeredKeyRemaps := Map()

GetAppAssetPath(fileName) {
    candidates := [
        A_ScriptDir . "\assets\" . fileName,
        A_ScriptDir . "\..\assets\" . fileName,
        A_ScriptDir . "\" . fileName
    ]

    for candidate in candidates {
        if FileExist(candidate)
            return candidate
    }
    return A_ScriptDir . "\assets\" . fileName
}

; =============================================================================
; SECTION: Tray Icon
; =============================================================================
appIconPath := GetAppAssetPath("SwiftDeck.ico")
if FileExist(appIconPath) {
    TraySetIcon(appIconPath)
}

; =============================================================================
; SECTION: Script Configuration (Includes & Global Variables)
; =============================================================================

#Include SettingsManager.ahk
#Include lib\Theme.ahk
#Include lib\Utils.ahk
#Include lib\Clipboard.ahk
#Include lib\Config.ahk
#Include lib\Migration.ahk
#Include lib\FolderMenu.ahk
#Include lib\FolderManager.ahk
#Include lib\PreferencesManager.ahk
#Include lib\PromptManager.ahk
#Include lib\PromptMenu.ahk
#Include lib\HotstringManager.ahk
#Include lib\KeyRemapManager.ahk
#Include lib\EmojiPicker.ahk
#Include lib\UpdateManager.ahk
#Include lib\DashboardManager.ahk
#Include lib\AppInfo.ahk
#Include lib\Manual.ahk

; =============================================================================
; SECTION: Error Safety Net
; =============================================================================
; Without this, any unhandled error shows AutoHotkey's raw dialog — including
; source file paths — to whoever is running the packaged executable.
OnError(HandleUnexpectedError)

HandleUnexpectedError(err, mode) {
    message := "Unknown error"
    try message := err.Message
    catch
        message := String(err)

    logged := false
    try {
        detail := FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  [" . mode . "] " . Type(err) . ": " . message
        try detail .= "`n    at " . err.File . ":" . err.Line
        try if (err.Extra != "")
            detail .= "`n    extra: " . err.Extra
        FileAppend(detail . "`n`n", ConfigGetErrorLogPath(), "UTF-8")
        logged := true
    }

    ; On "ExitApp" the process is closing whatever this returns, so do not
    ; promise the user that SwiftDeck is still running.
    outcome := (mode == "ExitApp")
        ? "SwiftDeck ran into an unexpected problem and has to close."
        : "SwiftDeck ran into an unexpected problem and skipped that action.`n`nSwiftDeck is still running."
    ; Only promise a log file if the write actually succeeded.
    trailer := logged
        ? "`n`nDetails were saved to:`n" . ConfigGetErrorLogPath()
        : ""
    MsgBox(outcome . "`n`n" . message . trailer, "SwiftDeck", 262160)
    return 1 ; handled — end this thread instead of showing the default dialog
}

; =============================================================================
; SECTION: Application Startup
; =============================================================================
if UpdateManager.HandleStartupArguments()
    ExitApp()
OnStartup() ; Invoked immediately on script start
UpdateManager.CompletePendingStartup()

OnStartup() {
    warnings := []

    ; Standard PL Suite configuration migration and shortcut cleanup
    ; Never initialize defaults over a failed legacy copy.
    try {
        ConfigMigrateLegacySettings([A_AppData . "\SwiftDeck\", A_AppData . "\AHK_FolderHotKey\"])
        ConfigMigrateLegacyAppSettings()
        EnsureSettingsMigration()
    } catch Error as err {
        MsgBox("Settings migration could not be completed. Your existing files were preserved.`nClose SwiftDeck, check that UserSetting is writable, and retry.`n`n" err.Message, "SwiftDeck settings", 262160)
        ExitApp()
    }
    CleanLegacyShortcuts()

    isFirstRun := false
    try isFirstRun := ConfigIsFirstRun()

    RunStartupStep("Settings files", InitializeAllConfigs, warnings)

    ; Back up before migrating, not after. The migrations rewrite whole files,
    ; so running the backup afterwards means a migration that gets it wrong is
    ; immediately copied over the one recovery point the user had.
    RunStartupStep("Settings backup", BackupConfigs, warnings)

    ; Run config migrations
    RunStartupStep("Encoding migration", MigrateIniEncoding, warnings)
    RunStartupStep("Hotstring migration", MigrateHotstringIni, warnings)

    ; Normalize old hotkey settings such as "WinNumpad". Falling back to the
    ; shipped defaults keeps the hotkeys and tray menu usable even if the
    ; settings file is corrupt or locked.
    settings := ConfigGetFallbackAppSettings()
    try {
        settings := ConfigReadAppSettings()
        migratedPrompt := MigratePromptModifier(settings.PromptModifier, settings.PromptUseNumpad)
        settings.PromptModifier := migratedPrompt.Mod
        settings.PromptUseNumpad := migratedPrompt.UseNumpad
    } catch Error as err {
        warnings.Push("Hotkey settings (defaults applied): " . err.Message)
    }

    ; Load runtime input automation features
    RunStartupStep("Hotstrings", LoadHotstrings, warnings)
    RunStartupStep("Emoji & Symbols menu", BuildEmojiMenu, warnings)
    RunStartupStep("Key remapping", LoadKeyRemaps, warnings)
    OnExit(CleanupKeyRemaps)

    ; Register dynamic hotkey (main menu). The settings editor refuses a bare
    ; mouse button or typing key, but the file can also be hand-edited or shared
    ; between machines, and registering "LButton" here would swallow every click
    ; in Windows — including the ones needed to fix it. Fall back rather than
    ; leave the user with no way back.
    ; Wrapped because nothing between here and SetupTrayMenu() may throw: a
    ; failure at this point would leave the app running with no tray icon and no
    ; way to close it, which is the exact state this startup path exists to
    ; prevent.
    try {
        if (settings.MainHotkey != "") {
            parsedMain := ParseKeyString(settings.MainHotkey)
            mainMods := parsedMain.Mods
            if (!mainMods.Ctrl && !mainMods.Shift && !mainMods.Win && !mainMods.Alt
                && HotkeyBaseKeyNeedsModifier(parsedMain.BaseKey)) {
                warnings.Push("Favorites hotkey (default F1 applied): '" . settings.MainHotkey
                    . "' would take over that key everywhere in Windows.")
                settings.MainHotkey := "F1"
            }
        }
    } catch Error as err {
        warnings.Push("Favorites hotkey check: " . err.Message)
    }
    try {
        Hotkey(settings.MainHotkey, (*) => ShowFavoritesMenu())
    } catch {
        settings.MainHotkey := "F1"
        Hotkey("F1", (*) => ShowFavoritesMenu())
    }

    ; Register dynamic prompt hotkeys
    if (settings.PromptModifier != "") {
        loop 10 {
            num := A_Index - 1
            baseKey := settings.PromptUseNumpad ? "Numpad" . num : num
            hk := settings.PromptModifier . baseKey
            try Hotkey(hk, BindPrompt(num))
        }
    }

    ; Register Emoji Picker, Prompt Menu, and Exit hotkeys
    try Hotkey(settings.EmojiHotkey, ShowEmojiMenu)
    try Hotkey(GetPromptMenuHotkey(), (*) => ShowPromptMenu())  ; Shift+Win+Space → Prompt Popup Menu
    try Hotkey(settings.ExitHotkey, RequestExitApp)

    ; Register dynamic "Add Current Explorer Folder" hotkey (Ctrl + mainHotkey).
    ; The criterion is evaluated while the keyboard hook waits, so it only reads
    ; the active window class. Resolving the actual path needs an out-of-process
    ; COM call into explorer.exe, which happens in the hotkey action instead.
    addFolderHotkey := GetAddFolderHotkey(settings.MainHotkey)
    HotIf((*) => IsExplorerContextActive())
    try {
        Hotkey(addFolderHotkey, (*) => AddCurrentExplorerFolder())
    } catch {
        Hotkey("^F1", (*) => AddCurrentExplorerFolder())
    }
    HotIf() ; Reset context to default (global)

    ; Setup custom tray menu
    SetupTrayMenu(settings)

    ; Load cached release state immediately and schedule a delayed GitHub check
    ; at most once every 24 hours. The request itself uses bounded timeouts.
    UpdateManager.Initialize(g_appVersion)

    ; Show a concise hotkey cheat sheet on first run (manual stays available in the tray)
    if (isFirstRun) {
        SetTimer(() => ShowHotkeyCheatSheet(), -1000) ; Show cheat sheet after 1 second
    }

    ; Show startup notification (TrayTip). If a step failed above, say which one
    ; rather than starting up looking healthy with features quietly missing.
    formattedHK := FormatHotkeyDisplay(settings.MainHotkey)
    if (warnings.Length) {
        ; A TrayTip is capped in length and is suppressed entirely under Focus
        ; Assist, so record the detail somewhere the user can still read later.
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  [startup] "
            . StrJoin(warnings, "`n             ") . "`n`n", ConfigGetErrorLogPath(), "UTF-8")
        TrayTip("These parts did not load:`n- " . StrJoin(warnings, "`n- ")
            . "`n`nEverything else is running. See SwiftDeck-error.log for details.",
            "⚠️ SwiftDeck started with warnings",
            "Icon!")
        SetTimer(() => TrayTip(), -8000)
    } else {
        TrayTip("App is running in the background.`nPress [" . formattedHK . "] anytime to open the menu!",
            "✅ SwiftDeck Ready",
            "Iconi")
        SetTimer(() => TrayTip(), -4000) ; Hide notification after 4 seconds
    }
}

BindPrompt(num) {
    return (*) => PromptManager.ProcessQuickPrompt(num)
}

RequestExitApp(*) {
    if (DashboardManager.instance && !DashboardManager.instance.ConfirmUnsavedChanges("exit"))
        return
    ExitApp()
}

SetupTrayMenu(settings) {
    global g_emojiMenu
    A_TrayMenu.Delete() ; Remove default AHK tray items (Open, Pause, Exit, etc.)

    ; Format hotkey hints so every actionable item advertises its shortcut
    ; Menu-safe: these come from the settings file, so they are escaped and
    ; clipped. The static parts of each label keep their own "&&".
    mainHK := FormatHotkeyForMenu(settings.MainHotkey)
    emojiHK := FormatHotkeyForMenu(settings.EmojiHotkey)
    promptMenuHK := FormatHotkeyForMenu(GetPromptMenuHotkey())
    exitHK := FormatHotkeyForMenu(settings.ExitHotkey)

    foldersLabel := "📂 Open Folders Menu (" . mainHK . ")"
    A_TrayMenu.Add(foldersLabel, (*) => ShowFavoritesMenu())
    A_TrayMenu.Add("⌨️ Quick Prompts Menu (" . promptMenuHK . ")", (*) => ShowPromptMenu())
    A_TrayMenu.Add("😀 Emoji && Symbols (" . emojiHK . ")", ShowEmojiMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("⚙️ App Settings", (*) => DashboardManager.Show(1))
    A_TrayMenu.Add("📁 Open Settings Folder", (*) => OpenFolder(ConfigGetSettingsFolder()))
    A_TrayMenu.Add("📘 Open App Manual", (*) => OpenAppManual())
    A_TrayMenu.Add("⌨️ Hotkey Cheat Sheet", (*) => ShowHotkeyCheatSheet())
    A_TrayMenu.Add("ℹ️ App Information", (*) => ShowAppInformation())
    A_TrayMenu.Add("🔍 Check for Updates", (*) => UpdateManager.CheckForUpdates(true))
    A_TrayMenu.Add()
    A_TrayMenu.Add("🔄 Reload App", (*) => Reload())
    A_TrayMenu.Add("❌ Exit App (" . exitHK . ")", RequestExitApp)

    ; Double-click tray icon to open favorites menu
    A_TrayMenu.Default := foldersLabel
}

; Shows a compact, always-on-top summary of the currently active hotkeys.
ShowHotkeyCheatSheet() {
    settings := ConfigReadAppSettings()

    mainHK := FormatHotkeyDisplay(settings.MainHotkey)
    addHK := FormatHotkeyDisplay(GetAddFolderHotkey(settings.MainHotkey))
    emojiHK := FormatHotkeyDisplay(settings.EmojiHotkey)
    promptMenuHK := FormatHotkeyDisplay(GetPromptMenuHotkey())
    exitHK := FormatHotkeyDisplay(settings.ExitHotkey)

    if (settings.PromptModifier != "") {
        promptPrefix := FormatHotkeyDisplay(settings.PromptModifier) . (settings.PromptUseNumpad ? "Num" : "")
        quickLine := promptPrefix . "0 ~ " . promptPrefix . "9"
    } else {
        quickLine := "(disabled)"
    }

    msg := "📂 Favorites Menu`t: " . mainHK . "`n"
        . "➕ Add Current Folder`t: " . addHK . "`n"
        . "⌨️ Quick Prompts`t: " . quickLine . "`n"
        . "📝 Prompt Popup Menu`t: " . promptMenuHK . "`n"
        . "😀 Emoji & Symbols`t: " . emojiHK . "`n"
        . "❌ Exit App`t: " . exitHK

    ; Quick Prompts default to the numeric keypad, which most laptops under 15"
    ; do not have. Nothing fails visibly in that case — the shortcut simply does
    ; not exist — so say where to change it rather than leave the user pressing
    ; a key that can never work.
    if (settings.PromptModifier != "" && settings.PromptUseNumpad) {
        msg .= "`n`nNo numeric keypad on your keyboard?`n"
            . "Quick Prompts will not respond. Switch them to the top-row number keys in`n"
            . "App Settings → ⚙️ General → Quick Prompts Hotkey → " . '"Standard 0~9"'
            . "`n(right-click the tray icon → ⚙️ App Settings)"
    }

    MsgBox(msg, "⌨️ SwiftDeck — Hotkey Cheat Sheet", 262144) ; 0x40000 = always on top
}

#Requires AutoHotkey v2.0
#Include ..\src\lib\Utils.ahk

AssertEqual(actual, expected, label) {
    if (actual != expected)
        throw Error(label . ": expected '" . expected . "', got '" . actual . "'")
}

AssertEqual(GetAddFolderHotkey("F1"), "^F1", "Default add-folder hotkey")
AssertEqual(GetAddFolderHotkey("^F1"), "^+F1", "Ctrl main hotkey")
AssertEqual(GetAddFolderHotkey("^+!#F1"), "^F1", "All-modifier fallback")
AssertEqual(ValidateHotkeyAssignments("F1", "#", 1, "^#Space", "^#Escape"), "", "Default hotkey set")

conflict := ValidateHotkeyAssignments("+#Space", "#", 1, "^#Space", "^#Escape")
if !InStr(conflict, "Prompt Popup Menu conflicts with Favorites Menu")
    throw Error("Expected Favorites/Prompt Popup conflict, got: " . conflict)

AssertEqual(IsExplorerWindowClass("CabinetWClass"), true, "Explorer folder window")
AssertEqual(IsExplorerWindowClass("ExploreWClass"), true, "Legacy Explorer window")
AssertEqual(IsExplorerWindowClass("Progman"), true, "Desktop window")
AssertEqual(IsExplorerWindowClass("WorkerW"), true, "Desktop worker window")
AssertEqual(IsExplorerWindowClass("Chrome_WidgetWin_1"), false, "Non-Explorer window")
AssertEqual(IsExplorerWindowClass(""), false, "Missing window class")
AssertEqual(IsExplorerWindowClass("XCabinetWClassY"), false, "Reject partial class match")
AssertEqual(IsDesktopWindowClass("Progman"), true, "Desktop resolves without COM")
AssertEqual(IsDesktopWindowClass("CabinetWClass"), false, "Folder window needs the shell lookup")

; --- Menu label safety ---
; Win32 reads a single "&" as the accelerator prefix, so it must be doubled.
AssertEqual(SafeMenuLabel("R&D"), "R&&D", "Escape a single ampersand")
AssertEqual(SafeMenuLabel("Sales & Marketing"), "Sales && Marketing", "Escape ampersand in a folder name")
AssertEqual(SafeMenuLabel("A&B&C"), "A&&B&&C", "Escape every ampersand")
AssertEqual(SafeMenuLabel("plain"), "plain", "Leave ampersand-free text untouched")
AssertEqual(SafeMenuLabel("A`r`nB"), "A B", "Collapse CRLF")
AssertEqual(SafeMenuLabel("A`nB`tC"), "A B C", "Collapse newline and tab")
AssertEqual(SafeMenuLabel("  padded  "), "padded", "Trim surrounding space")
AssertEqual(SafeMenuLabel(""), "Item", "Fall back on empty text")
AssertEqual(SafeMenuLabel("   ", "Folder"), "Folder", "Fall back on whitespace-only text")

longLabel := SafeMenuLabel(StrReplace(Format("{:65}", ""), " ", "a"))
AssertEqual(StrLen(longLabel), 63, "Clip long text to 60 characters plus ellipsis")
AssertEqual(SubStr(longLabel, -4), "a...", "Long text keeps the ellipsis suffix")
AssertEqual(SafeMenuLabel("abcdef", "Item", 3), "abc...", "Honor a custom clip length")
; An emoji is two UTF-16 units; clipping must not leave half of one behind.
AssertEqual(SafeMenuLabel("ab" . Chr(0x1F4C2) . "cd", "Item", 3), "ab...", "Never clip inside a surrogate pair")
AssertEqual(SafeMenuLabel("ab" . Chr(0x1F4C2) . "cd", "Item", 4), "ab" . Chr(0x1F4C2) . "...", "Keep a whole surrogate pair")

; Escaping runs after clipping so a "&&" pair can never be split in half.
clipped := SafeMenuLabel("ab&" . StrReplace(Format("{:65}", ""), " ", "c"), "Item", 4)
AssertEqual(clipped, "ab&&c...", "Clip first, then escape")

; --- Menu label uniqueness ---
; Adding an existing label replaces that item instead of appending a new one,
; so duplicates have to be disambiguated before they reach Menu.Add.
labels := NewMenuLabelSet()
AssertEqual(UniqueMenuLabel("Reports", labels), "Reports", "First use keeps the label")
AssertEqual(UniqueMenuLabel("Reports", labels), "Reports (2)", "Second use is suffixed")
AssertEqual(UniqueMenuLabel("Reports", labels), "Reports (3)", "Third use increments the suffix")
AssertEqual(UniqueMenuLabel("REPORTS", labels), "REPORTS (4)", "Menu lookup ignores case")
AssertEqual(UniqueMenuLabel("Other", labels), "Other", "Unrelated labels are unaffected")

; A label that already looks like a generated suffix must not collide either.
collision := NewMenuLabelSet()
AssertEqual(UniqueMenuLabel("Docs (2)", collision), "Docs (2)", "Pre-existing suffix is kept")
AssertEqual(UniqueMenuLabel("Docs", collision), "Docs", "Base label still available")
AssertEqual(UniqueMenuLabel("Docs", collision), "Docs (3)", "Skip past an occupied suffix")

; --- Command building ---
; Run() does not go through a shell, so "&" in a path is data, not syntax.
AssertEqual(BuildQuotedCommand("explorer.exe", "C:\R&D"), 'explorer.exe "C:\R&D"', "Quote a path containing &")
AssertEqual(BuildQuotedCommand("explorer.exe", "C:\Sales & Marketing"),
    'explorer.exe "C:\Sales & Marketing"', "Quote a path with & and spaces")
AssertEqual(BuildQuotedCommand("notepad.exe", "  C:\a b\c.ini  "), 'notepad.exe "C:\a b\c.ini"', "Trim before quoting")
; Trailing backslashes pass through untouched. Doubling them (as CommandLineToArgvW
; would want) makes explorer.exe open Documents instead of the requested folder.
AssertEqual(BuildQuotedCommand("explorer.exe", "C:\Logs\"), 'explorer.exe "C:\Logs\"', "Keep a trailing backslash as-is")
AssertEqual(BuildQuotedCommand("explorer.exe", "C:\"), 'explorer.exe "C:\"', "Keep a drive root as-is")
; The settings folder always ends in a backslash, so this is the everyday case.
AssertEqual(BuildQuotedCommand("explorer.exe", "C:\Users\me\AppData\Roaming\SwiftDeck\"),
    'explorer.exe "C:\Users\me\AppData\Roaming\SwiftDeck\"', "Settings folder path is unchanged")
; "/select," must sit flush against the quote, so the separator is suppressed.
AssertEqual(BuildQuotedCommand("explorer.exe /select,", "C:\a\b.txt", ""),
    'explorer.exe /select,"C:\a\b.txt"', "Reveal-file command takes no separator")

; --- Key remap vs the app's own shortcuts ---
; AutoHotkey keys a criterion-less hotkey by its string, so a remap on one of
; these replaces the app's callback, and removing the remap later turns the
; app's own shortcut off.
defaultSettings := { MainHotkey: "F1", PromptModifier: "#", PromptUseNumpad: 1,
    EmojiHotkey: "^#Space", ExitHotkey: "^#Escape" }

AssertEqual(FindAppHotkeyConflict("F1", defaultSettings), "Favorites Menu", "F1 is reserved by the favorites menu")
AssertEqual(FindAppHotkeyConflict("^F1", defaultSettings), "Add Current Explorer Folder",
    "Ctrl+F1 is reserved by the add-folder shortcut")
AssertEqual(FindAppHotkeyConflict("^#Space", defaultSettings), "Emoji & Symbols", "Emoji hotkey is reserved")
AssertEqual(FindAppHotkeyConflict("^#Escape", defaultSettings), "Exit App", "Exit hotkey is reserved")
AssertEqual(FindAppHotkeyConflict("+#Space", defaultSettings), "Prompt Popup Menu", "Prompt menu hotkey is reserved")
AssertEqual(FindAppHotkeyConflict("#Numpad3", defaultSettings), "Quick Prompt 3", "Quick prompt slots are reserved")

; A bare key is a different hotkey from the same key with modifiers.
AssertEqual(FindAppHotkeyConflict("Space", defaultSettings), "", "Bare Space does not collide with Ctrl+Win+Space")
AssertEqual(FindAppHotkeyConflict("CapsLock", defaultSettings), "", "An unused key is free to remap")
AssertEqual(FindAppHotkeyConflict("F2", defaultSettings), "", "F2 is free with the default main hotkey")
AssertEqual(FindAppHotkeyConflict("", defaultSettings), "", "An empty candidate never conflicts")

; The reserved set follows the user's own hotkey choices.
movedSettings := { MainHotkey: "F9", PromptModifier: "^", PromptUseNumpad: 0,
    EmojiHotkey: "^#Space", ExitHotkey: "^#Escape" }
AssertEqual(FindAppHotkeyConflict("F9", movedSettings), "Favorites Menu", "Reserved set follows a moved main hotkey")
AssertEqual(FindAppHotkeyConflict("F1", movedSettings), "", "The old main hotkey is released")
AssertEqual(FindAppHotkeyConflict("^5", movedSettings), "Quick Prompt 5", "Standard-number prompt slots are reserved")

; Prompt slots disappear from the reserved set when prompt hotkeys are off.
noPromptSettings := { MainHotkey: "F1", PromptModifier: "", PromptUseNumpad: 1,
    EmojiHotkey: "^#Space", ExitHotkey: "^#Escape" }
AssertEqual(FindAppHotkeyConflict("#Numpad3", noPromptSettings), "", "No prompt slots reserved when disabled")

; --- INI key safety ---
; User text becomes an INI key. Windows reads a leading "[" as a section header
; and a leading ";" as a comment, so such a name silently discards the entries
; stored after it (measured: 3 of 4 favorites lost).
AssertEqual(IsPlainIniKeySafe("Normal Title"), true, "Ordinary name is allowed")
AssertEqual(IsPlainIniKeySafe("Q4 Report (final)"), true, "Punctuation is allowed")
AssertEqual(IsPlainIniKeySafe("a=b"), false, "Reject '='")
AssertEqual(IsPlainIniKeySafe("two`nlines"), false, "Reject a newline")
AssertEqual(IsPlainIniKeySafe("two`rlines"), false, "Reject a carriage return")
AssertEqual(IsPlainIniKeySafe("[Draft] Reply"), false, "Reject a leading bracket")
AssertEqual(IsPlainIniKeySafe("  [Draft]"), false, "Reject a leading bracket after spaces")
AssertEqual(IsPlainIniKeySafe(";Note"), false, "Reject a leading semicolon")
; Built by concatenation: AutoHotkey strips " ;" as a comment even inside a
; quoted string, so "  ;Note" cannot be written as a single literal.
AssertEqual(IsPlainIniKeySafe("  " . ";Note"), false, "Reject a leading semicolon after spaces")
AssertEqual(IsPlainIniKeySafe("Draft [2]"), true, "A bracket later in the name is fine")
AssertEqual(IsPlainIniKeySafe("Use; carefully"), true, "A semicolon later in the name is fine")

; --- Startup step isolation ---
; A failing step must be recorded and skipped, never abort the whole startup.
stepWarnings := []
AssertEqual(RunStartupStep("Good step", () => 1, stepWarnings), true, "Successful step reports true")
AssertEqual(stepWarnings.Length, 0, "Successful step records no warning")
AssertEqual(RunStartupStep("Broken step", () => Integer("not a number"), stepWarnings), false,
    "Failing step reports false instead of throwing")
AssertEqual(stepWarnings.Length, 1, "Failing step records exactly one warning")
if !InStr(stepWarnings[1], "Broken step")
    throw Error("Warning should name the step, got: " . stepWarnings[1])
AssertEqual(RunStartupStep("Later step", () => 1, stepWarnings), true, "Startup continues after a failure")
AssertEqual(stepWarnings.Length, 1, "A later success adds no warning")

; --- String joining ---
AssertEqual(StrJoin([]), "", "Join an empty list")
AssertEqual(StrJoin(["only"]), "only", "Join a single item")
AssertEqual(StrJoin(["a", "b", "c"]), "a, b, c", "Join with the default separator")
AssertEqual(StrJoin(["a", "b"], " | "), "a | b", "Join with a custom separator")

centered := CalculateCenteredWindowPosition(500, 400, 0, 0, 1920, 1040)
AssertEqual(centered.X, 710, "Primary monitor center X")
AssertEqual(centered.Y, 320, "Primary monitor center Y")

secondary := CalculateCenteredWindowPosition(500, 400, -1920, 0, 0, 1040)
AssertEqual(secondary.X, -1210, "Negative-coordinate monitor center X")
AssertEqual(secondary.Y, 320, "Negative-coordinate monitor center Y")

oversized := CalculateCenteredWindowPosition(2200, 1200, -1920, -200, 0, 840)
AssertEqual(oversized.X, -1920, "Oversized window clamps to work-area left")
AssertEqual(oversized.Y, -200, "Oversized window clamps to work-area top")

ExitApp(0)

#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
#Include ..\src\lib\Utils.ahk

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

; --- Modifier symbols are not base keys ---
; BuildKeyString appends the base key and ParseKeyString reads a trailing
; modifier symbol back as a modifier, so these cannot round-trip.
AssertEqual(IsModifierSymbolKey("^"), true, "Caret is a modifier symbol")
AssertEqual(IsModifierSymbolKey("+"), true, "Plus is a modifier symbol")
AssertEqual(IsModifierSymbolKey("#"), true, "Hash is a modifier symbol")
AssertEqual(IsModifierSymbolKey("!"), true, "Bang is a modifier symbol")
AssertEqual(IsModifierSymbolKey("&"), true, "Ampersand is the custom-combo separator")
AssertEqual(IsModifierSymbolKey("F1"), false, "A function key is a valid base key")
AssertEqual(IsModifierSymbolKey("a"), false, "A letter is a valid base key")

; Demonstrates the mutation the check prevents.
AssertEqual(ParseKeyString(BuildKeyString(1, 0, 0, 0, "+")).BaseKey, "",
    "Ctrl + the plus key loses its base key on a round trip")
AssertEqual(ParseKeyString(BuildKeyString(1, 0, 0, 0, "F1")).BaseKey, "F1",
    "A real base key round-trips unchanged")

; --- Menu-safe hotkey display ---
AssertEqual(FormatHotkeyForMenu("^F1"), "Ctrl+F1", "Ordinary hotkey formats unchanged")
longHotkey := FormatHotkeyForMenu(StrReplace(Format("{:80}", ""), " ", "z"))
if (StrLen(longHotkey) > 45)
    throw Error("A hand-edited hotkey must be clipped for menu use, got " . StrLen(longHotkey))

; --- Key remap vs the app's own shortcuts ---
; AutoHotkey keys a criterion-less hotkey by its string, so a remap on one of
; these replaces the app's callback, and removing the remap later turns the
; app's own shortcut off.
defaultSettings := { MainHotkey: "F1", PromptModifier: "#", PromptUseNumpad: 1,
    EmojiHotkey: "^#Space", ExitHotkey: "^#Escape" }

AssertEqual(FindAppHotkeyConflict("F1", defaultSettings), "Favorites Menu", "F1 is reserved by the favorites menu")
; Ctrl+F1 is registered under HotIf, so a plain remap coexists with it and
; deleting that remap cannot switch it off — it is not reserved.
AssertEqual(FindAppHotkeyConflict("^F1", defaultSettings), "",
    "The Explorer-only add-folder shortcut does not block a remap")
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

; --- Alias spellings must not slip past the guard ---
; AutoHotkey registers "Esc" and "Escape" as separate hotkeys bound to the same
; physical key, and the later registration simply wins — so comparing the raw
; text would let a remap silently take over an app shortcut.
AssertEqual(NormalizeBaseKey("Esc"), NormalizeBaseKey("Escape"), "Esc and Escape canonicalize alike")
AssertEqual(NormalizeBaseKey("vk1B"), NormalizeBaseKey("Escape"), "A vk code matches its named key")
AssertEqual(NormalizeBaseKey("Ins"), NormalizeBaseKey("Insert"), "Ins and Insert canonicalize alike")
AssertEqual(NormalizeBaseKey("Del"), NormalizeBaseKey("Delete"), "Del and Delete canonicalize alike")
AssertEqual(NormalizeBaseKey("ESCAPE"), NormalizeBaseKey("escape"), "Canonicalization ignores case")
AssertEqual(NormalizeBaseKey(""), "", "An empty base key stays empty")
if (NormalizeBaseKey("F1") == NormalizeBaseKey("F2"))
    throw Error("Different keys must not canonicalize alike")
; Enter and NumpadEnter share a virtual key and are told apart by scan code, so
; identifying by virtual key alone would wrongly merge them.
if (NormalizeBaseKey("Enter") == NormalizeBaseKey("NumpadEnter"))
    throw Error("Enter and NumpadEnter are different keys and must not merge")
; Unrecognized text still compares equal to itself rather than collapsing to "".
AssertEqual(NormalizeBaseKey("Return"), NormalizeBaseKey("return"), "Unknown key names fall back consistently")
if (NormalizeBaseKey("Return") == NormalizeBaseKey("Enter"))
    throw Error("'Return' is not a valid key name in v2 and must not pass as Enter")

AssertEqual(NormalizeHotkey("^#Esc"), NormalizeHotkey("^#Escape"), "Whole hotkeys compare through aliases")
aliasSettings := { MainHotkey: "F1", PromptModifier: "#", PromptUseNumpad: 1,
    EmojiHotkey: "^#Space", ExitHotkey: "^#Esc" }
AssertEqual(FindAppHotkeyConflict("^#Escape", aliasSettings), "Exit App",
    "A differently spelled exit hotkey is still detected")
AssertEqual(ValidateHotkeyAssignments("Escape", "#", 1, "^#Space", "^#Esc"), "",
    "Unrelated keys still validate cleanly")

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

; --- High-DPI fit ---
; Measured design sizes: the settings window is 514x665 and the manual 700x720
; in 96-DPI units. Display scaling multiplies those; the work area does not
; follow, so on a small panel at high scaling the bottom becomes unreachable.
AssertEqual(WouldExceedWorkArea(514, 665, 96, 1920, 1032), false, "Settings fits a 1080p screen at 100%")
AssertEqual(WouldExceedWorkArea(514, 665, 120, 1920, 1020), false, "Settings fits a 1080p screen at 125%")
AssertEqual(WouldExceedWorkArea(514, 665, 144, 1920, 1008), false, "Settings fits a 1080p screen at 150%")
AssertEqual(WouldExceedWorkArea(514, 665, 168, 1920, 996), true, "Settings overflows a 1080p screen at 175%")
AssertEqual(WouldExceedWorkArea(514, 665, 192, 1920, 984), true, "Settings overflows a 1080p screen at 200%")
; 200% is normally paired with a 4K panel, where everything doubles together.
AssertEqual(WouldExceedWorkArea(514, 665, 192, 3840, 2064), false, "Settings fits 4K at 200%")
AssertEqual(WouldExceedWorkArea(700, 720, 192, 3840, 2064), false, "Manual fits 4K at 200%")
; The manual is taller, so it runs out of room one step earlier.
AssertEqual(WouldExceedWorkArea(700, 720, 144, 1920, 1008), true, "Manual overflows a 1080p screen at 150%")
AssertEqual(WouldExceedWorkArea(700, 720, 120, 1920, 1020), false, "Manual fits a 1080p screen at 125%")
; Width matters too, on narrow screens.
AssertEqual(WouldExceedWorkArea(700, 720, 96, 640, 1032), true, "A window wider than the work area also counts")

centered := CalculateCenteredWindowPosition(500, 400, 0, 0, 1920, 1040)
AssertEqual(centered.X, 710, "Primary monitor center X")
AssertEqual(centered.Y, 320, "Primary monitor center Y")

secondary := CalculateCenteredWindowPosition(500, 400, -1920, 0, 0, 1040)
AssertEqual(secondary.X, -1210, "Negative-coordinate monitor center X")
AssertEqual(secondary.Y, 320, "Negative-coordinate monitor center Y")

oversized := CalculateCenteredWindowPosition(2200, 1200, -1920, -200, 0, 840)
AssertEqual(oversized.X, -1920, "Oversized window clamps to work-area left")
AssertEqual(oversized.Y, -200, "Oversized window clamps to work-area top")

; A hotkey bound with no modifier at all can take the key away from the rest of
; Windows. Bare LButton swallows every left click, including the clicks needed to
; open the settings window and undo it, so this rule is what stands between a
; two-click mistake in the General tab and a machine that needs Task Manager.
AssertTrue(HotkeyBaseKeyNeedsModifier("LButton"), "A bare left click is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("RButton"), "A bare right click is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("WheelDown"), "A bare wheel event is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("Space"), "A bare Space is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("Enter"), "A bare Enter is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("Tab"), "A bare Tab is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("a"), "A bare letter is refused")
AssertTrue(HotkeyBaseKeyNeedsModifier("7"), "A bare digit is refused")

; F1 is the shipped default, so the rule must not be a blanket "needs a
; modifier" — that would refuse the app's own out-of-the-box hotkey.
AssertTrue(!HotkeyBaseKeyNeedsModifier("F1"), "F1 stays usable on its own")
AssertTrue(!HotkeyBaseKeyNeedsModifier("F12"), "Function keys stay usable on their own")
AssertTrue(!HotkeyBaseKeyNeedsModifier("Escape"), "Escape stays usable on its own")
AssertTrue(!HotkeyBaseKeyNeedsModifier("Insert"), "Insert stays usable on its own")
AssertTrue(!HotkeyBaseKeyNeedsModifier(""), "An empty key is left to the other checks")

TestsPassed("Utils")

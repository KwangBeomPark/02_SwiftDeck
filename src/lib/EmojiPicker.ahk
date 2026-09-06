#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Utils.ahk
; =================================================================================
; --- Emoji & Symbol Popup Menu (Emoji Picker) ---
; =================================================================================

global g_emojiMenu := Menu()
; False until a build actually populated the menu, so a failed build retries.
global g_emojiMenuHasContent := false

; Built-in symbol set. The tray advertises "Emoji & Symbols", so the menu ships
; with a usable set of its own instead of depending on the user having created
; Hotstrings first. Each entry is { Char, Name }; picking one types the Char.
EmojiGetBuiltInGroups() {
    return [
        { Title: "→  Arrows", Items: [
            { Char: "→", Name: "Right" }, { Char: "←", Name: "Left" },
            { Char: "↑", Name: "Up" }, { Char: "↓", Name: "Down" },
            { Char: "↔", Name: "Left-right" }, { Char: "⇒", Name: "Double right" },
            { Char: "⇐", Name: "Double left" }, { Char: "⇔", Name: "Double left-right" },
            { Char: "▶", Name: "Play / next" }, { Char: "◀", Name: "Previous" },
            { Char: "▲", Name: "Increase" }, { Char: "▼", Name: "Decrease" }] },

        { Title: "₩  Currency & Units", Items: [
            { Char: "₩", Name: "Won" }, { Char: "$", Name: "Dollar" },
            { Char: "€", Name: "Euro" }, { Char: "¥", Name: "Yen" },
            { Char: "£", Name: "Pound" }, { Char: "%", Name: "Percent" },
            { Char: "‰", Name: "Per mille" }, { Char: "℃", Name: "Celsius" },
            { Char: "℉", Name: "Fahrenheit" }, { Char: "㎡", Name: "Square metre" },
            { Char: "㎏", Name: "Kilogram" }, { Char: "㎞", Name: "Kilometre" }] },

        { Title: "±  Math", Items: [
            { Char: "±", Name: "Plus-minus" }, { Char: "×", Name: "Multiply" },
            { Char: "÷", Name: "Divide" }, { Char: "≒", Name: "Approximately" },
            { Char: "≠", Name: "Not equal" }, { Char: "≤", Name: "Less or equal" },
            { Char: "≥", Name: "Greater or equal" }, { Char: "∑", Name: "Sum" },
            { Char: "√", Name: "Square root" }, { Char: "∞", Name: "Infinity" },
            { Char: "∴", Name: "Therefore" }, { Char: "°", Name: "Degree" }] },

        { Title: "※  Marks & Bullets", Items: [
            { Char: "※", Name: "Reference mark" }, { Char: "★", Name: "Star filled" },
            { Char: "☆", Name: "Star outline" }, { Char: "●", Name: "Circle filled" },
            { Char: "○", Name: "Circle outline" }, { Char: "◎", Name: "Double circle" },
            { Char: "■", Name: "Square filled" }, { Char: "□", Name: "Square outline" },
            { Char: "◆", Name: "Diamond filled" }, { Char: "◇", Name: "Diamond outline" },
            { Char: "·", Name: "Middle dot" }, { Char: "…", Name: "Ellipsis" }] },

        { Title: "✓  Checks", Items: [
            { Char: "✓", Name: "Check" }, { Char: "✔", Name: "Check heavy" },
            { Char: "✗", Name: "Cross" }, { Char: "✘", Name: "Cross heavy" },
            { Char: "☑", Name: "Checked box" }, { Char: "☐", Name: "Empty box" },
            { Char: "☒", Name: "Crossed box" }] },

        { Title: "「  Brackets", Items: [
            { Char: "「」", Name: "Corner brackets" }, { Char: "『』", Name: "White corner brackets" },
            { Char: "〈〉", Name: "Angle brackets" }, { Char: "《》", Name: "Double angle brackets" },
            { Char: "【】", Name: "Black lenticular" }, { Char: "〔〕", Name: "Tortoise shell" },
            { Char: "―", Name: "Em dash" }, { Char: "~", Name: "Tilde" }] },

        { Title: "😀  Emoji", Items: [
            { Char: "😀", Name: "Grinning" }, { Char: "👍", Name: "Thumbs up" },
            { Char: "🙏", Name: "Thanks" }, { Char: "✅", Name: "Done" },
            { Char: "❌", Name: "Not done" }, { Char: "🔥", Name: "Hot" },
            { Char: "⭐", Name: "Star" }, { Char: "📌", Name: "Pinned" },
            { Char: "📎", Name: "Attachment" }, { Char: "📅", Name: "Date" },
            { Char: "💡", Name: "Idea" }, { Char: "🚀", Name: "Launch" }] }
    ]
}

EmojiMenuItemCount() {
    global g_emojiMenu
    try {
        return DllCall("GetMenuItemCount", "ptr", g_emojiMenu.Handle, "int")
    } catch {
        return 0
    }
}

; Showing an empty Menu is a silent no-op — the hotkey simply appears dead. If a
; failed build left the menu empty, rebuild and otherwise show a hint so the
; shortcut always reports something.
ShowEmojiMenu(*) {
    global g_emojiMenu, g_emojiMenuHasContent
    if !g_emojiMenuHasContent
        try BuildEmojiMenu()

    if !g_emojiMenuHasContent {
        ; The hint is a placeholder, not content: leave the flag false so the next
        ; press retries the build instead of keeping this message forever.
        hint := "(Symbols could not be loaded)"
        try {
            g_emojiMenu.Delete()
            g_emojiMenu.Add(hint, (*) => 0)
            g_emojiMenu.Disable(hint)
        }
    }
    g_emojiMenu.Show()
}

BuildEmojiMenu() {
    global g_emojiMenu, g_emojiMenuHasContent
    g_emojiMenu.Delete()
    g_emojiMenuHasContent := false

    SendMenuText(text, ItemName, ItemPos, MyMenu) {
        SendText(text)
    }

    usedTopLabels := NewMenuLabelSet()

    ; --- Built-in symbols ---
    for group in EmojiGetBuiltInGroups() {
        subMenu := Menu()
        usedItemLabels := NewMenuLabelSet()
        for item in group.Items {
            itemLabel := UniqueMenuLabel(
                SafeMenuLabel(item.Char . "   " . item.Name, "Symbol"), usedItemLabels)
            try subMenu.Add(itemLabel, SendMenuText.Bind(item.Char))
        }
        try g_emojiMenu.Add(UniqueMenuLabel(SafeMenuLabel(group.Title, "Symbols"), usedTopLabels), subMenu)
    }

    ; --- User Hotstring & Menu Groups ---
    userGroupCount := 0
    if ConfigExists("Hotstrings") {
        hotstringData := ConfigReadHotstringData()
        for secName in hotstringData.GroupOrder {
            if !hotstringData.Data.Has(secName)
                continue

            displayName := SafeMenuLabel(HotstringGetRuntimeGroupName(secName), "Unnamed Group")
            mUserGroup := Menu()
            usedItemLabels := NewMenuLabelSet()
            hasItems := false
            for item in hotstringData.Data[secName] {
                if (item.Key != "" && item.Val != "") {
                    itemLabel := UniqueMenuLabel(
                        SafeMenuLabel(item.Val, "Text") . "  [" . SafeMenuLabel(item.Key, "Trigger", 20) . "]",
                        usedItemLabels)
                    try {
                        mUserGroup.Add(itemLabel, SendMenuText.Bind(item.Val))
                        hasItems := true
                    }
                }
            }

            if (hasItems) {
                if (userGroupCount == 0)
                    try g_emojiMenu.Add() ; separator between built-ins and user groups
                userGroupCount++
                ; Plain numbering: keycap sequences (U+FE0F U+20E3) render as
                ; tofu in Win32 menus on some systems.
                try g_emojiMenu.Add(
                    UniqueMenuLabel(userGroupCount . ". " . displayName, usedTopLabels), mUserGroup)
            }
        }
    }

    g_emojiMenuHasContent := EmojiMenuItemCount() > 0
}

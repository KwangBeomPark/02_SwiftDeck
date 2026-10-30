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
; Groups names the hotstring groups that belong to a category (matched without
; case), so the category shows their triggers instead of a second copy of the
; same symbols. Bullets_Indicators is the name earlier default files use.
EmojiGetBuiltInGroups() {
    return [
        { Title: "→  Arrows", Groups: ["Arrows"], Items: [
            { Char: "→", Name: "Right" }, { Char: "←", Name: "Left" },
            { Char: "↑", Name: "Up" }, { Char: "↓", Name: "Down" },
            { Char: "↔", Name: "Left-right" }, { Char: "⇒", Name: "Double right" },
            { Char: "⇐", Name: "Double left" }, { Char: "⇔", Name: "Double left-right" },
            { Char: "▶", Name: "Play / next" }, { Char: "◀", Name: "Previous" },
            { Char: "▲", Name: "Increase" }, { Char: "▼", Name: "Decrease" }] },

        { Title: "±  Math", Groups: ["Math"], Items: [
            { Char: "±", Name: "Plus-minus" }, { Char: "×", Name: "Multiply" },
            { Char: "÷", Name: "Divide" }, { Char: "≒", Name: "Approximately" },
            { Char: "≠", Name: "Not equal" }, { Char: "≤", Name: "Less or equal" },
            { Char: "≥", Name: "Greater or equal" }, { Char: "∑", Name: "Sum" },
            { Char: "√", Name: "Square root" }, { Char: "∞", Name: "Infinity" },
            { Char: "∴", Name: "Therefore" }, { Char: "°", Name: "Degree" }] },

        { Title: "※  Marks & Checks", Groups: ["Marks_Checks", "Bullets_Indicators"], Items: [
            { Char: "※", Name: "Reference mark" }, { Char: "★", Name: "Star filled" },
            { Char: "☆", Name: "Star outline" }, { Char: "●", Name: "Circle filled" },
            { Char: "○", Name: "Circle outline" }, { Char: "◎", Name: "Double circle" },
            { Char: "■", Name: "Square filled" }, { Char: "□", Name: "Square outline" },
            { Char: "◆", Name: "Diamond filled" }, { Char: "◇", Name: "Diamond outline" },
            { Char: "·", Name: "Middle dot" }, { Char: "…", Name: "Ellipsis" },
            { Char: "✓", Name: "Check" }, { Char: "✔", Name: "Check heavy" },
            { Char: "✗", Name: "Cross" }, { Char: "✘", Name: "Cross heavy" },
            { Char: "☑", Name: "Checked box" }, { Char: "☐", Name: "Empty box" },
            { Char: "☒", Name: "Crossed box" }] },

        { Title: "①  Numbers", Groups: ["Numbers"], Items: [
            { Char: "①", Name: "One" }, { Char: "②", Name: "Two" },
            { Char: "③", Name: "Three" }, { Char: "④", Name: "Four" },
            { Char: "⑤", Name: "Five" }, { Char: "⑥", Name: "Six" },
            { Char: "⑦", Name: "Seven" }, { Char: "⑧", Name: "Eight" },
            { Char: "⑨", Name: "Nine" }, { Char: "⑩", Name: "Ten" }] },

        { Title: "₩  Currency & Units", Groups: ["Currency"], Items: [
            { Char: "₩", Name: "Won" }, { Char: "$", Name: "Dollar" },
            { Char: "€", Name: "Euro" }, { Char: "¥", Name: "Yen" },
            { Char: "£", Name: "Pound" }, { Char: "%", Name: "Percent" },
            { Char: "‰", Name: "Per mille" }, { Char: "℃", Name: "Celsius" },
            { Char: "℉", Name: "Fahrenheit" }, { Char: "㎡", Name: "Square metre" },
            { Char: "㎏", Name: "Kilogram" }, { Char: "㎞", Name: "Kilometre" }] },

        { Title: "「  Brackets", Groups: [], Items: [
            { Char: "「」", Name: "Corner brackets" }, { Char: "『』", Name: "White corner brackets" },
            { Char: "〈〉", Name: "Angle brackets" }, { Char: "《》", Name: "Double angle brackets" },
            { Char: "【】", Name: "Black lenticular" }, { Char: "〔〕", Name: "Tortoise shell" },
            { Char: "―", Name: "Em dash" }, { Char: "~", Name: "Tilde" }] },

        { Title: "😀  Emoji", Groups: [], Items: [
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

    ; Fills a submenu; returns whether anything was added.
    AddEntries(subMenu, entries) {
        usedItemLabels := NewMenuLabelSet()
        added := false
        for entry in entries {
            try {
                subMenu.Add(UniqueMenuLabel(EmojiEntryLabel(entry), usedItemLabels), SendMenuText.Bind(entry.Text))
                added := true
            }
        }
        return added
    }

    ; A hotstring file that cannot be read leaves the built-in symbols usable;
    ; LoadHotstrings reports the read failure itself.
    hotstringData := { Data: Map(), GroupOrder: [] }
    if ConfigExists("Hotstrings")
        try hotstringData := ConfigReadHotstringData()
    plan := EmojiBuildMenuPlan(EmojiGetBuiltInGroups(), hotstringData)

    usedTopLabels := NewMenuLabelSet()
    for category in plan.Categories {
        subMenu := Menu()
        if AddEntries(subMenu, category.Entries)
            try g_emojiMenu.Add(UniqueMenuLabel(SafeMenuLabel(category.Title, "Symbols"), usedTopLabels), subMenu)
    }

    ; --- User Hotstring & Menu Groups that no category above took in ---
    userGroupCount := 0
    for group in plan.UserGroups {
        subMenu := Menu()
        if !AddEntries(subMenu, group.Entries)
            continue
        if (userGroupCount == 0)
            try g_emojiMenu.Add() ; separator between built-ins and user groups
        userGroupCount++
        ; Plain numbering: keycap sequences (U+FE0F U+20E3) render as
        ; tofu in Win32 menus on some systems.
        try g_emojiMenu.Add(UniqueMenuLabel(userGroupCount . ". "
            . SafeMenuLabel(group.Name, "Unnamed Group"), usedTopLabels), subMenu)
    }

    g_emojiMenuHasContent := EmojiMenuItemCount() > 0
}

; Decides what the menu shows without touching it, so it can be tested. Each
; category takes in the hotstring groups it names: their items come first, with
; the trigger, then the built-in symbols that no hotstring in any group already
; types. A symbol therefore appears once, and where it has a trigger it is
; listed with it. Groups no category names (For_Email, the user's own) follow.
EmojiBuildMenuPlan(categories, hotstringData) {
    typedByHotstring := Map()
    for secName in hotstringData.GroupOrder {
        if !hotstringData.Data.Has(secName)
            continue
        for item in hotstringData.Data[secName] {
            if (item.Key != "" && item.Val != "")
                typedByHotstring[item.Val] := true
        }
    }

    plan := { Categories: [], UserGroups: [] }
    takenGroups := Map()
    for category in categories {
        names := Map()
        for item in category.Items
            names[item.Char] := item.Name

        entries := []
        for secName in hotstringData.GroupOrder {
            if takenGroups.Has(secName) || !hotstringData.Data.Has(secName)
                continue
            if !EmojiCategoryTakesGroup(category, HotstringGetRuntimeGroupName(secName))
                continue
            takenGroups[secName] := true
            for item in hotstringData.Data[secName] {
                if (item.Key != "" && item.Val != "")
                    entries.Push({ Text: item.Val, Name: names.Has(item.Val) ? names[item.Val] : "", Trigger: item.Key })
            }
        }
        for item in category.Items {
            if !typedByHotstring.Has(item.Char)
                entries.Push({ Text: item.Char, Name: item.Name, Trigger: "" })
        }
        if (entries.Length > 0)
            plan.Categories.Push({ Title: category.Title, Entries: entries })
    }

    for secName in hotstringData.GroupOrder {
        if takenGroups.Has(secName) || !hotstringData.Data.Has(secName)
            continue
        entries := []
        for item in hotstringData.Data[secName] {
            if (item.Key != "" && item.Val != "")
                entries.Push({ Text: item.Val, Name: "", Trigger: item.Key })
        }
        if (entries.Length > 0)
            plan.UserGroups.Push({ Name: HotstringGetRuntimeGroupName(secName), Entries: entries })
    }
    return plan
}

EmojiCategoryTakesGroup(category, groupName) {
    for name in category.Groups {
        if (StrLower(name) == StrLower(Trim(groupName)))
            return true
    }
    return false
}

; "→   Right  [>>]" for a symbol with a trigger, "⇒   Double right" without one.
EmojiEntryLabel(entry) {
    label := SafeMenuLabel(entry.Text, "Text")
    if (entry.Name != "")
        label .= "   " . entry.Name
    if (entry.Trigger != "")
        label .= "  [" . SafeMenuLabel(entry.Trigger, "Trigger", 20) . "]"
    return label
}

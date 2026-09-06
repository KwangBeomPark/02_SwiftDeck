#Requires AutoHotkey v2.0
#Include Config.ahk
#Include Utils.ahk

; =================================================================================
; Module: PromptMenu
; Description: Shows registered Quick Prompts as a popup menu at mouse cursor.
;              Activated via Shift+Win+Space. Reuses EmojiPicker menu pattern.
; Author: KBPark
; =================================================================================

global g_promptMenu := Menu()

BuildPromptMenu() {
    global g_promptMenu
    g_promptMenu.Delete()

    if !ConfigExists("Prompts")
        return

    ; Read the user's configured prompt hotkey so each group shows its actual
    ; shortcut (e.g. "Win+Num1") instead of a generic "Slot 1".
    settings := ConfigReadAppSettings()
    modDisplay := FormatHotkeyDisplay(settings.PromptModifier)

    ; Build the group label from the real hotkey. Falls back to "Slot N" when
    ; the prompt modifier is empty (hotkeys disabled), since no shortcut applies.
    PromptGroupLabel(num) {
        if (settings.PromptModifier == "")
            return "⌨️ Slot " . num
        keyPart := (settings.PromptUseNumpad ? "Num" : "") . num
        return "⌨️ " . modDisplay . keyPart
    }

    promptData := ConfigReadPromptData()

    ; First pass: is any slot populated at all?
    hasAnyItems := false
    loop 10 {
        n := A_Index - 1
        if (promptData.Has(n) && promptData[n].Length > 0) {
            hasAnyItems := true
            break
        }
    }

    ; Nothing configured anywhere — show a single hint and stop.
    if (!hasAnyItems) {
        emptyHint := "(No prompts registered)"
        g_promptMenu.Add(emptyHint, (*) => 0)
        g_promptMenu.Disable(emptyHint)
        return
    }

    ; Second pass: one entry per slot. Populated slots get a submenu; empty slots
    ; are shown disabled so the full hotkey map stays discoverable at a glance.
    usedGroupLabels := NewMenuLabelSet()
    loop 10 {
        num := A_Index - 1
        groupLabel := UniqueMenuLabel(PromptGroupLabel(num), usedGroupLabels)

        if (promptData.Has(num) && promptData[num].Length > 0) {
            subMenu := Menu()
            usedItemLabels := NewMenuLabelSet()
            for idx, item in promptData[num] {
                ; Prefix the tap-order number so the menu matches the tap-to-cycle sequence.
                itemLabel := UniqueMenuLabel(idx . ". " . SafeMenuLabel(item.Title, "Prompt"), usedItemLabels)
                boundNum := num
                boundIdx := idx
                subMenu.Add(itemLabel, ((n, i, *) => _ExecutePromptFromMenu(n, i)).Bind(boundNum, boundIdx))
            }
            g_promptMenu.Add(groupLabel, subMenu)
        } else if (settings.PromptModifier != "") {
            emptyLabel := UniqueMenuLabel(groupLabel . "  —  (empty)", usedGroupLabels)
            g_promptMenu.Add(emptyLabel, (*) => 0)
            g_promptMenu.Disable(emptyLabel)
        }
    }
}

ShowPromptMenu(*) {
    BuildPromptMenu()
    g_promptMenu.Show()
}

_ExecutePromptFromMenu(groupNum, itemIdx, *) {
    promptData := ConfigReadPromptData()
    if !promptData.Has(groupNum)
        return
    if (itemIdx < 1 || itemIdx > promptData[groupNum].Length)
        return

    item := promptData[groupNum][itemIdx]
    msg := item.Msg

    if (msg == "")
        return

    if (HasSpecialKeys(msg)) {
        ExecutePromptSequence(msg)
    } else {
        if !TrySetPromptClipboard(msg) {
            ReportClipboardBusy()
            return
        }
        Send("^v")
    }
}

#Requires AutoHotkey v2.0
#Include Config.ahk

; Runtime globals such as g_registeredHotstrings are initialized in SwiftDeck.ahk.

; Returns the triggers that could not be registered. Startup shows them here;
; the settings tab passes false and reports them itself, so that its own
; "saved and applied" message cannot paint over the warning.
LoadHotstrings(showFailures := true) {
    global g_registeredHotstrings

    ; Read first, strictly: a file that cannot be read — held by another
    ; program, or missing for a moment while it is replaced — raises
    ; ConfigReadError here, while the hotstrings already running are still
    ; registered, instead of reading as empty and switching them all off.
    hotstringData := ConfigReadStrict("Hotstrings", ConfigReadHotstringData)

    for hotstringSpec in g_registeredHotstrings {
        try Hotstring(hotstringSpec, , "Off")
    }
    g_registeredHotstrings := []

    failedItems := []

    ; No * option: AutoHotkey checks the trigger only after an ending character.
    for entry in HotstringBuildRuntimePlan(hotstringData) {
        try {
            Hotstring(entry.Spec, entry.Replacement)
            Hotstring(entry.Spec, , "On")
            g_registeredHotstrings.Push(entry.Spec)
        } catch {
            failedItems.Push(entry.Trigger)
        }
    }

    if (showFailures && failedItems.Length > 0)
        ShowFeedbackToolTip("⚠️ Failed hotstrings (" . failedItems.Length . "): " . FormatShortList(failedItems), 5000)
    return failedItems
}

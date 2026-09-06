#Requires AutoHotkey v2.0
; =============================================================================
; --- Clipboard Utilities (HTML & Plain Text) ---
; =============================================================================

; Putting text on the clipboard can fail outright: another process — a clipboard
; manager, an RDP session, Office — can hold it open. Try the styled format,
; fall back to plain text, and report failure to the caller instead of letting a
; busy clipboard surface as an unexpected-error dialog on a hotkey press.
TrySetPromptClipboard(text, color := "black", sizePt := 11) {
    try {
        SetStyledClipboard(text, color, sizePt)
        return true
    }
    try {
        A_Clipboard := text
        return true
    }
    return false
}

; Shared feedback for the paste paths, so a busy clipboard reads the same way
; wherever it happens.
ReportClipboardBusy() {
    ToolTip("⚠️ The clipboard is busy — please try again")
    SetTimer(() => ToolTip(), -2500)
}

; A restore that is still pending, so two prompts in quick succession do not
; snapshot the first prompt's own text as if it were the user's clipboard.
global g_pendingClipboardRestore := ""

; Pasting a prompt used to leave the prompt text on the clipboard, destroying
; whatever the user had copied — an ordinary loss when the work is copying a
; cell and then firing a prompt. So the clipboard is snapshotted and put back.
; This covers plain prompts only; prompts containing {Key} sequences go through
; ExecutePromptSequence, which still pastes each fragment without restoring.
;
; The delay is deliberately generous. Nothing tells us when the target has
; actually read the clipboard, and the two ways to be wrong are not equal:
; restoring too early makes the target paste the user's PREVIOUS clipboard —
; silently inserting unrelated, possibly confidential text into an email —
; while restoring too late only leaves the prompt on the clipboard a while
; longer. Measured: a consumer that processes Ctrl+V at ~900ms already loses
; with a 700ms delay, and RDP or Citrix clipboard redirection routinely exceeds
; a second. Waiting costs nothing, because the guard below refuses to overwrite
; anything the user copied in the meantime.
PastePromptText(text, color := "black", sizePt := 11) {
    global g_pendingClipboardRestore

    saved := ""
    hasSaved := false
    if (g_pendingClipboardRestore != "") {
        ; A restore is already queued; its snapshot is the user's real clipboard.
        saved := g_pendingClipboardRestore
        hasSaved := true
    } else {
        try {
            saved := ClipboardAll()
            hasSaved := true
        }
    }

    if !TrySetPromptClipboard(text, color, sizePt) {
        ReportClipboardBusy()
        return false
    }

    Send("^v")

    if (hasSaved) {
        g_pendingClipboardRestore := saved
        SetTimer(() => RestoreClipboardAfterPaste(saved, text), -3000)
    }
    return true
}

RestoreClipboardAfterPaste(saved, pastedText) {
    global g_pendingClipboardRestore

    current := ""
    try current := A_Clipboard
    catch {
        g_pendingClipboardRestore := ""
        return
    }

    ; Anything other than exactly what we pasted means the user (or another app)
    ; has since put something newer there, which must win. "!==" because "!=" is
    ; case-insensitive in AutoHotkey v2.
    if (current !== pastedText) {
        g_pendingClipboardRestore := ""
        return
    }

    try A_Clipboard := saved
    g_pendingClipboardRestore := ""
}

SetStyledClipboard(text, color, sizePt) {
    htmlText := HtmlEncodeWithBr(text)  ; HTML-safe encoding + newlines → <br>
    frag :=
        '<div style="font-family:Segoe UI, Arial, sans-serif; white-space:pre-wrap;">'
        . '<span style="color:' color '; font-size:' sizePt 'pt;">'
        . htmlText
        . '</span>'
        . '</div>'
    SetClipboardHtml(frag, text)
}

HtmlEncodeWithBr(s) {
    s := StrReplace(s, "&", "&amp;")
    s := StrReplace(s, "<", "&lt;")
    s := StrReplace(s, ">", "&gt;")
    s := StrReplace(s, '"', "&quot;")
    s := StrReplace(s, "'", "&#39;")
    ; Convert newlines to <br>
    s := StrReplace(s, "`r`n", "<br>")
    s := StrReplace(s, "`n", "<br>")
    s := StrReplace(s, "`r", "<br>")
    return s
}

; Set clipboard in CF_HTML format
;  - Registers both HTML and UNICODETEXT simultaneously
SetClipboardHtml(htmlFragment, plainText, sourceURL := "") {
    docStart := '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>'
    docEnd := '</body></html>'
    mStart := '<!--StartFragment-->'
    mEnd := '<!--EndFragment-->'
    htmlDoc := docStart . mStart . htmlFragment . mEnd . docEnd

    ; Header template (offsets filled later)
    hdr :=
    (
        "Version:0.9`r`n"
        "StartHTML:##########`r`n"
        "EndHTML:##########`r`n"
        "StartFragment:##########`r`n"
        "EndFragment:##########`r`n"
    )
    if (sourceURL != "")
        hdr .= "SourceURL:" . sourceURL . "`r`n"

    ; Helper: calculate UTF-8 byte length
    StrToUtf8Buffer(s) {
        buf := Buffer(StrPut(s, "UTF-8"))
        StrPut(s, buf, "UTF-8")
        return buf
    }

    hdrBuf := StrToUtf8Buffer(hdr), hdrBytes := hdrBuf.Size - 1
    docBuf := StrToUtf8Buffer(htmlDoc), docBytes := docBuf.Size - 1

    ; Fragment position (character index → UTF-8 byte offset)
    idxStart := InStr(htmlDoc, mStart)
    idxEnd := InStr(htmlDoc, mEnd)
    preStart := SubStr(htmlDoc, 1, idxStart - 1)
    preEnd := SubStr(htmlDoc, 1, idxEnd - 1)
    preStartBytes := StrToUtf8Buffer(preStart).Size - 1
    preEndBytes := StrToUtf8Buffer(preEnd).Size - 1
    mStartBytes := StrToUtf8Buffer(mStart).Size - 1

    StartHTML := hdrBytes
    EndHTML := hdrBytes + docBytes
    StartFragment := StartHTML + preStartBytes + mStartBytes
    EndFragment := StartHTML + preEndBytes

    fill10(x) => Format("{:010}", x)
    hdrFinal := RegExReplace(hdr, "StartHTML:\K##########", fill10(StartHTML))
    hdrFinal := RegExReplace(hdrFinal, "EndHTML:\K##########", fill10(EndHTML))
    hdrFinal := RegExReplace(hdrFinal, "StartFragment:\K##########", fill10(StartFragment))
    hdrFinal := RegExReplace(hdrFinal, "EndFragment:\K##########", fill10(EndFragment))

    fullFinal := hdrFinal . htmlDoc

    ; Final UTF-8 binary
    bin := StrToUtf8Buffer(fullFinal), dataSize := bin.Size - 1

    ; PlainText (compatibility) - UTF-16
    plain := plainText  ; Keep original text as-is
    ; UTF-16 requires charCount * 2 bytes
    reqW := StrPut(plain, "UTF-16") * 2
    plainBuf := Buffer(reqW), StrPut(plain, plainBuf, "UTF-16")

    ; Set clipboard data
    hHTML := DllCall("RegisterClipboardFormat", "str", "HTML Format", "uint")
    CF_UNICODETEXT := 13
    ; Clipboard managers routinely hold the clipboard for a moment after a copy,
    ; so 150ms of retries was easy to lose a race against.
    opened := false
    loop 12 {
        if DllCall("OpenClipboard", "ptr", 0, "int") {
            opened := true
            break
        }
        Sleep(40)
    }
    if !opened
        throw Error("OpenClipboard failed")

    hMem := 0, hTxt := 0
    try {
        DllCall("EmptyClipboard")

        GMEM_MOVEABLE := 0x0002, GMEM_ZEROINIT := 0x0040, GHND := GMEM_MOVEABLE | GMEM_ZEROINIT

        ; --- HTML data ---
        hMem := DllCall("GlobalAlloc", "uint", GHND, "uptr", dataSize + 1, "ptr")
        pMem := DllCall("GlobalLock", "ptr", hMem, "ptr")
        DllCall("RtlMoveMemory", "ptr", pMem, "ptr", bin.Ptr, "uptr", dataSize + 1)
        DllCall("GlobalUnlock", "ptr", hMem)
        if !DllCall("SetClipboardData", "uint", hHTML, "ptr", hMem, "ptr") {
            DllCall("GlobalFree", "ptr", hMem)
            hMem := 0
            throw Error("SetClipboardData(HTML) failed")
        }
        hMem := 0  ; Ownership transferred to clipboard

        ; --- UNICODETEXT ---
        hTxt := DllCall("GlobalAlloc", "uint", GHND, "uptr", plainBuf.Size, "ptr")
        pTxt := DllCall("GlobalLock", "ptr", hTxt, "ptr")
        DllCall("RtlMoveMemory", "ptr", pTxt, "ptr", plainBuf.Ptr, "uptr", plainBuf.Size)
        DllCall("GlobalUnlock", "ptr", hTxt)
        if !DllCall("SetClipboardData", "uint", CF_UNICODETEXT, "ptr", hTxt, "ptr") {
            DllCall("GlobalFree", "ptr", hTxt)
            hTxt := 0
            throw Error("SetClipboardData(TEXT) failed")
        }
        hTxt := 0  ; Ownership transferred to clipboard
    } catch Error as err {
        ; Free any memory that was NOT successfully transferred to the clipboard
        if (hMem != 0)
            DllCall("GlobalFree", "ptr", hMem)
        if (hTxt != 0)
            DllCall("GlobalFree", "ptr", hTxt)
        throw err
    } finally {
        DllCall("CloseClipboard")
    }
}

#Requires AutoHotkey v2.0
#Warn All, Off
; Shared harness for the *Tests.ahk scripts.
;
; The point of the OnError handler is that an uncaught assertion would otherwise
; open a modal dialog and simply hang: the process never exits, so a test runner
; can only report "timed out" and the actual failure message stays on a dialog
; nobody is watching. Here the message goes to stdout and the process exits
; non-zero, which is what scripts/build.ps1 gates on.

OnError(ReportTestFailure)

ReportTestFailure(err, mode) {
    message := "Unknown error"
    try message := err.Message
    catch
        message := String(err)

    location := ""
    try location := "`n  at " . err.File . ":" . err.Line

    ; "*" is stdout.
    FileAppend("FAIL  " . message . location . "`n", "*")
    ExitApp(1)
}

AssertEqual(actual, expected, label) {
    if (actual != expected)
        throw Error(label . ": expected '" . expected . "', got '" . actual . "'")
}

; For conditions that are not a simple equality.
AssertTrue(condition, label) {
    if (!condition)
        throw Error(label)
}

; Call at the end of a test script instead of ExitApp(0), so the run reports
; what it covered rather than exiting silently.
TestsPassed(suiteName) {
    FileAppend("ok    " . suiteName . "`n", "*")
    ExitApp(0)
}

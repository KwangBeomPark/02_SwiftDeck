; Keep fixtures on request without recursively deleting audit evidence.
TestFinishDirectory(path) {
    for argument in A_Args {
        if argument = "--keep-fixtures" {
            DirMove(path, RTrim(path, "\") ".retained." DllCall("GetCurrentProcessId") "." A_TickCount "." Random(100000, 999999), false)
            return
        }
    }
    DirDelete(path, true)
}

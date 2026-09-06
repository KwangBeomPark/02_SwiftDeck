#Requires AutoHotkey v2.0
#Include Utils.ahk

; =================================================================================
; Module: UpdateManager
; Description: Checks GitHub Releases and exposes update state to the app UI.
; =================================================================================
class UpdateManager {
    static RepositoryOwner := "KwangBeomPark"
    static RepositoryName := "02_SwiftDeck"
    static BinaryAssetName := "SwiftDeck.exe"
    static ManifestAssetName := "SwiftDeck.update.ini"
    static State := {
        Status: "not_checked",
        LatestVersion: "",
        ReleaseUrl: "",
        ErrorMessage: ""
    }
    static CurrentVersion := ""
    static UiRefreshCallback := ""
    static PreUpdateCallback := ""
    static PendingCompletion := ""

    static Initialize(currentVersion) {
        this.CurrentVersion := this.NormalizeReleaseTag(currentVersion)
        this.LoadCachedState()
        this.NotifyUi()
        if this.ShouldCheckNow()
            SetTimer((*) => this.CheckForUpdates(false), -5000)
    }

    static GetState() {
        return this.State
    }

    static RegisterUiRefreshCallback(callback := "") {
        this.UiRefreshCallback := callback
    }

    static RegisterPreUpdateCallback(callback := "") {
        this.PreUpdateCallback := callback
    }

    static GetLatestReleaseApiUrl() {
        return "https://api.github.com/repos/" . this.RepositoryOwner . "/" . this.RepositoryName . "/releases/latest"
    }

    static GetReleaseUrl(version) {
        return "https://github.com/" . this.RepositoryOwner . "/" . this.RepositoryName . "/releases/tag/v" . version
    }

    static GetAssetDownloadUrl(version, assetName) {
        version := this.NormalizeReleaseTag(version)
        if !RegExMatch(assetName, "^[A-Za-z0-9._-]+$")
            throw Error("Unsafe release asset name: " . assetName)
        return "https://github.com/" . this.RepositoryOwner . "/" . this.RepositoryName
            . "/releases/download/v" . version . "/" . assetName
    }

    ; Releases publish a version-stamped copy of the same binary next to the
    ; fixed-name asset, so a download from the Releases page is identifiable.
    static GetVersionedAssetName(version) {
        return "SwiftDeck.v" . this.NormalizeReleaseTag(version) . ".exe"
    }

    static NormalizeReleaseTag(tagName) {
        tagName := Trim(tagName)
        if !RegExMatch(tagName, "^v?([0-9]+\.[0-9]+\.[0-9]+)$", &match)
            throw Error("Unsupported release tag: " . tagName)
        return match[1]
    }

    static ClassifyVersion(latestVersion, currentVersion) {
        latestVersion := this.NormalizeReleaseTag(latestVersion)
        currentVersion := this.NormalizeReleaseTag(currentVersion)
        comparison := VerCompare(latestVersion, currentVersion)
        if (comparison > 0)
            return "available"
        if (comparison < 0)
            return "local_newer"
        return "up_to_date"
    }

    static ParseLatestReleaseJson(jsonText) {
        if !RegExMatch(jsonText, '"tag_name"\s*:\s*"(v?[0-9]+\.[0-9]+\.[0-9]+)"', &tagMatch)
            throw Error("GitHub response did not contain a supported release tag.")
        version := this.NormalizeReleaseTag(tagMatch[1])
        return {
            Version: version,
            ReleaseUrl: this.GetReleaseUrl(version)
        }
    }

    static ParseUpdateManifest(manifestText) {
        if !RegExMatch(manifestText, "im)^Version[ \t]*=[ \t]*([0-9]+\.[0-9]+\.[0-9]+)[ \t]*$", &versionMatch)
            throw Error("Update manifest is missing Version.")
        if !RegExMatch(manifestText, "im)^Asset[ \t]*=[ \t]*([A-Za-z0-9._-]+)[ \t]*$", &assetMatch)
            throw Error("Update manifest is missing Asset.")
        if !RegExMatch(manifestText, "im)^Sha256[ \t]*=[ \t]*([A-Fa-f0-9]{64})[ \t]*$", &hashMatch)
            throw Error("Update manifest is missing a valid SHA-256 digest.")
        if !RegExMatch(manifestText, "im)^Size[ \t]*=[ \t]*([0-9]+)[ \t]*$", &sizeMatch)
            throw Error("Update manifest is missing Size.")

        version := this.NormalizeReleaseTag(versionMatch[1])
        canonicalAssetName := assetMatch[1]
        if (canonicalAssetName != this.BinaryAssetName)
            throw Error("Unexpected update asset: " . canonicalAssetName)
        size := Integer(sizeMatch[1])
        if (size < 100000 || size > 50000000)
            throw Error("Update asset size is outside the allowed range.")

        ; AssetVersioned is optional so manifests published before v1.3.2 stay
        ; readable. When present it must name exactly the expected versioned
        ; binary; anything else means the manifest is not trustworthy.
        assetName := canonicalAssetName
        if RegExMatch(manifestText, "im)^AssetVersioned[ \t]*=[ \t]*([A-Za-z0-9._-]+)[ \t]*$", &versionedMatch) {
            if (versionedMatch[1] != this.GetVersionedAssetName(version))
                throw Error("Unexpected versioned update asset: " . versionedMatch[1])
            assetName := versionedMatch[1]
        }

        return {
            Version: version,
            AssetName: assetName,
            CanonicalAssetName: canonicalAssetName,
            Sha256: StrUpper(hashMatch[1]),
            Size: size
        }
    }

    static CheckForUpdates(showFeedback := false) {
        currentVersion := this.RequireCurrentVersion()
        previousState := this.State

        this.State := {
            Status: "checking",
            LatestVersion: this.State.LatestVersion,
            ReleaseUrl: this.State.ReleaseUrl,
            ErrorMessage: ""
        }
        this.NotifyUi()

        try {
            jsonText := this.HttpGetText(this.GetLatestReleaseApiUrl(), "application/vnd.github+json")
            release := this.ParseLatestReleaseJson(jsonText)
            status := this.ClassifyVersion(release.Version, currentVersion)
            this.State := {
                Status: status,
                LatestVersion: release.Version,
                ReleaseUrl: release.ReleaseUrl,
                ErrorMessage: ""
            }
            this.SaveSuccessfulCheck()
            if (status == "available")
                this.NotifyAvailableVersionOnce(release.Version)
        } catch Error as err {
            if (previousState.LatestVersion != "") {
                this.State := {
                    Status: previousState.Status,
                    LatestVersion: previousState.LatestVersion,
                    ReleaseUrl: previousState.ReleaseUrl,
                    ErrorMessage: err.Message
                }
            } else {
                this.State := {
                    Status: "error",
                    LatestVersion: "",
                    ReleaseUrl: "",
                    ErrorMessage: err.Message
                }
            }
        }

        this.NotifyUi()
        if showFeedback
            this.ShowCheckResult()
        return this.State
    }

    static GetStatusText() {
        state := this.State
        switch state.Status {
            case "checking":
                return "Checking GitHub…"
            case "available":
                return "Latest: v" . state.LatestVersion . " — update available"
            case "up_to_date":
                return "Latest: v" . state.LatestVersion . " — up to date"
            case "local_newer":
                return "Latest: v" . state.LatestVersion . " — development build"
            case "error":
                return "Update check failed"
            default:
                return "Latest: not checked"
        }
    }

    static ShowCheckResult() {
        currentVersion := this.RequireCurrentVersion()
        state := this.State
        if (state.ErrorMessage != "") {
            MsgBox("Could not refresh GitHub Releases.`n`n" . state.ErrorMessage, "Update Check Failed", 262160)
            return
        }
        switch state.Status {
            case "available":
                msg := "SwiftDeck v" . state.LatestVersion . " is available.`n`nInstalled: v" . currentVersion
                MsgBox(msg, "Update Available", 262208)
            case "up_to_date":
                MsgBox("SwiftDeck v" . currentVersion . " is the latest release.", "Up to Date", 262208)
            case "local_newer":
                msg := "Installed: v" . currentVersion . "`nGitHub latest: v" . state.LatestVersion
                    . "`n`nThis development build is newer than the latest public release."
                MsgBox(msg, "Development Build", 262208)
            case "error":
                MsgBox("Could not check GitHub Releases.`n`n" . state.ErrorMessage, "Update Check Failed", 262160)
        }
    }

    static HttpGetText(url, acceptHeader := "text/plain") {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 15000)
        req.Open("GET", url, false)
        req.SetRequestHeader("Accept", acceptHeader)
        req.SetRequestHeader("User-Agent", "SwiftDeck-UpdateChecker")
        req.Send()
        if (req.Status != 200)
            throw Error("GitHub returned HTTP " . req.Status . ".")
        return req.ResponseText
    }

    static DownloadFile(url, destinationPath) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 10000, 60000)
        req.Open("GET", url, false)
        req.SetRequestHeader("Accept", "application/octet-stream")
        req.SetRequestHeader("User-Agent", "SwiftDeck-Updater")
        req.Send()
        if (req.Status != 200)
            throw Error("Download returned HTTP " . req.Status . ".")

        stream := ComObject("ADODB.Stream")
        try {
            stream.Type := 1
            stream.Open()
            stream.Write(req.ResponseBody)
            stream.SaveToFile(destinationPath, 2)
        } finally {
            try stream.Close()
        }
    }

    ; Prefers the version-stamped asset and falls back to the fixed-name copy so a
    ; release that only carries the canonical binary still installs. Size and
    ; SHA-256 are verified by the caller either way.
    static DownloadUpdateAsset(version, manifest, destinationPath) {
        try {
            this.DownloadFile(this.GetAssetDownloadUrl(version, manifest.AssetName), destinationPath)
            return
        } catch Error as err {
            if (manifest.AssetName == manifest.CanonicalAssetName)
                throw err
        }
        if FileExist(destinationPath)
            try FileDelete(destinationPath)
        this.DownloadFile(this.GetAssetDownloadUrl(version, manifest.CanonicalAssetName), destinationPath)
    }

    static ComputeFileSha256(filePath) {
        if !FileExist(filePath)
            throw Error("Cannot hash a missing file: " . filePath)

        hAlgorithm := 0
        hHash := 0
        status := DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlgorithm, "wstr", "SHA256", "ptr", 0, "uint", 0, "uint")
        if (status != 0)
            throw Error("BCryptOpenAlgorithmProvider failed: " . status)

        try {
            objectLengthBuffer := Buffer(4, 0)
            digestLengthBuffer := Buffer(4, 0)
            resultLength := 0
            status := DllCall("bcrypt\BCryptGetProperty", "ptr", hAlgorithm, "wstr", "ObjectLength",
                "ptr", objectLengthBuffer.Ptr, "uint", objectLengthBuffer.Size, "uint*", &resultLength, "uint", 0, "uint")
            if (status != 0)
                throw Error("Could not read SHA-256 object length: " . status)
            status := DllCall("bcrypt\BCryptGetProperty", "ptr", hAlgorithm, "wstr", "HashDigestLength",
                "ptr", digestLengthBuffer.Ptr, "uint", digestLengthBuffer.Size, "uint*", &resultLength, "uint", 0, "uint")
            if (status != 0)
                throw Error("Could not read SHA-256 digest length: " . status)

            hashObject := Buffer(NumGet(objectLengthBuffer, 0, "UInt"), 0)
            digest := Buffer(NumGet(digestLengthBuffer, 0, "UInt"), 0)
            status := DllCall("bcrypt\BCryptCreateHash", "ptr", hAlgorithm, "ptr*", &hHash,
                "ptr", hashObject.Ptr, "uint", hashObject.Size, "ptr", 0, "uint", 0, "uint", 0, "uint")
            if (status != 0)
                throw Error("BCryptCreateHash failed: " . status)

            file := FileOpen(filePath, "r")
            if !file
                throw Error("Could not open update file for hashing.")
            try {
                chunk := Buffer(65536, 0)
                while (bytesRead := file.RawRead(chunk, chunk.Size)) {
                    status := DllCall("bcrypt\BCryptHashData", "ptr", hHash, "ptr", chunk.Ptr,
                        "uint", bytesRead, "uint", 0, "uint")
                    if (status != 0)
                        throw Error("BCryptHashData failed: " . status)
                }
            } finally {
                file.Close()
            }

            status := DllCall("bcrypt\BCryptFinishHash", "ptr", hHash, "ptr", digest.Ptr,
                "uint", digest.Size, "uint", 0, "uint")
            if (status != 0)
                throw Error("BCryptFinishHash failed: " . status)

            hashText := ""
            loop digest.Size
                hashText .= Format("{:02X}", NumGet(digest, A_Index - 1, "UChar"))
            return hashText
        } finally {
            if hHash
                DllCall("bcrypt\BCryptDestroyHash", "ptr", hHash)
            if hAlgorithm
                DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlgorithm, "uint", 0)
        }
    }

    static BeginUpdate() {
        state := this.State
        if (state.Status != "available") {
            state := this.CheckForUpdates(true)
            if (state.Status != "available" || state.ErrorMessage != "")
                return false
        }
        if !A_IsCompiled {
            MsgBox("Automatic installation is available only in the compiled SwiftDeck.exe.`n`nSource mode can still check GitHub Releases.",
                "Source Mode", 262208)
            return false
        }

        preUpdateCallback := this.PreUpdateCallback
        if (IsObject(preUpdateCallback) && !preUpdateCallback.Call())
            return false

        targetPath := A_ScriptFullPath
        SplitPath(targetPath, , &targetDir)
        if !this.IsFolderWritable(targetDir) {
            MsgBox("SwiftDeck cannot update files in its current folder.`n`n" . targetDir
                . "`n`nMove SwiftDeck to a writable folder or download the release manually.",
                "Update Folder Is Read-Only", 262160)
            return false
        }

        progress := this.ShowProgressWindow()
        pendingPath := ""
        helperPath := ""
        try {
            progress.Status.Value := "Reading the signed release manifest…"
            progress.Bar.Value := 15
            manifestUrl := this.GetAssetDownloadUrl(state.LatestVersion, this.ManifestAssetName)
            manifest := this.ParseUpdateManifest(this.HttpGetText(manifestUrl, "text/plain"))
            if (manifest.Version != state.LatestVersion)
                throw Error("Release tag and update manifest version do not match.")

            token := FormatTime(, "yyyyMMddHHmmss") . "-" . A_TickCount
            pendingPath := targetPath . ".update-" . token . ".tmp"
            backupPath := targetPath . ".previous-" . token . ".bak"
            helperPath := targetPath . ".updater-" . token . ".exe"
            markerPath := targetPath . ".update-" . token . ".ok"

            progress.Status.Value := "Downloading SwiftDeck v" . state.LatestVersion . "…"
            progress.Bar.Value := 35
            this.DownloadUpdateAsset(state.LatestVersion, manifest, pendingPath)
            if (FileGetSize(pendingPath) != manifest.Size)
                throw Error("Downloaded file size does not match the release manifest.")

            progress.Status.Value := "Verifying SHA-256 integrity…"
            progress.Bar.Value := 70
            actualHash := this.ComputeFileSha256(pendingPath)
            if (actualHash != manifest.Sha256)
                throw Error("Downloaded file SHA-256 does not match the release manifest.")

            FileCopy(targetPath, helperPath, true)
            progress.Status.Value := "Update verified. Restarting SwiftDeck…"
            progress.Bar.Value := 100

            command := this.QuoteArgument(helperPath)
                . " --apply-update " . ProcessExist()
                . " " . this.QuoteArgument(targetPath)
                . " " . this.QuoteArgument(pendingPath)
                . " " . this.QuoteArgument(backupPath)
                . " " . this.QuoteArgument(token)
                . " " . this.QuoteArgument(markerPath)
            Run(command)
            Sleep(400)
            ExitApp()
        } catch Error as err {
            try progress.Gui.Destroy()
            if (pendingPath != "" && FileExist(pendingPath))
                try FileDelete(pendingPath)
            if (helperPath != "" && FileExist(helperPath))
                try FileDelete(helperPath)
            MsgBox("SwiftDeck was not changed.`n`n" . err.Message, "Update Failed", 262160)
            return false
        }
    }

    static ShowProgressWindow() {
        progressGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "SwiftDeck Update")
        progressGui.SetFont("s10", "Segoe UI")
        statusText := progressGui.Add("Text", "x20 y20 w360 h24", "Preparing update…")
        progressBar := progressGui.Add("Progress", "x20 y55 w360 h20 Range0-100", 5)
        progressGui.Add("Text", "x20 y85 w360 h35", "Your saved settings stay in %AppData%\SwiftDeck and will not be replaced.")
        ShowCenteredOnMouse(progressGui, "w400 h135")
        return { Gui: progressGui, Status: statusText, Bar: progressBar }
    }

    static IsFolderWritable(folderPath) {
        probePath := folderPath . "\.SwiftDeck-write-test-" . A_TickCount . ".tmp"
        try {
            FileAppend("ok", probePath, "UTF-8-RAW")
            FileDelete(probePath)
            return true
        } catch {
            if FileExist(probePath)
                try FileDelete(probePath)
            return false
        }
    }

    static QuoteArgument(value) {
        return '"' . StrReplace(value, '"', '\"') . '"'
    }

    static HandleStartupArguments() {
        if (A_Args.Length == 0)
            return false
        mode := A_Args[1]
        if (mode == "--apply-update") {
            this.RunApplyUpdateWorker(A_Args)
            return true
        }
        if (mode == "--update-complete") {
            this.CaptureUpdateCompletion(A_Args)
            return false
        }
        return false
    }

    static RunApplyUpdateWorker(args) {
        if (args.Length != 7)
            ExitApp(2)

        originalPidText := args[2]
        targetPath := args[3]
        pendingPath := args[4]
        backupPath := args[5]
        token := args[6]
        markerPath := args[7]
        newPid := 0

        try {
            this.ValidateWorkerArguments(originalPidText, targetPath, pendingPath, backupPath, token, markerPath)
            originalPid := Integer(originalPidText)
            ProcessWaitClose(originalPid, 20)
            if ProcessExist(originalPid)
                throw Error("The previous SwiftDeck process did not exit.")

            this.MoveFileWithRetry(targetPath, backupPath)
            this.MoveFileWithRetry(pendingPath, targetPath)

            command := this.QuoteArgument(targetPath)
                . " --update-complete " . this.QuoteArgument(token)
                . " " . this.QuoteArgument(markerPath)
                . " " . this.QuoteArgument(A_ScriptFullPath)
                . " " . this.QuoteArgument(backupPath)
            Run(command, , , &newPid)

            loop 120 {
                if FileExist(markerPath)
                    break
                if (newPid && !ProcessExist(newPid))
                    break
                Sleep(250)
            }

            if !FileExist(markerPath)
                throw Error("The updated app did not confirm a successful startup.")

            if FileExist(backupPath)
                try this.DeleteFileWithRetry(backupPath)
            try FileDelete(markerPath)
            ExitApp(0)
        } catch Error as err {
            this.RollBackUpdate(targetPath, pendingPath, backupPath, newPid)
            if FileExist(targetPath)
                try Run(this.QuoteArgument(targetPath))
            MsgBox("The update could not be completed, so SwiftDeck restored the previous version.`n`n" . err.Message,
                "Update Rolled Back", 262160)
            ExitApp(1)
        }
    }

    static ValidateWorkerArguments(originalPidText, targetPath, pendingPath, backupPath, token, markerPath) {
        if !A_IsCompiled
            throw Error("Update worker must be compiled.")
        if !RegExMatch(originalPidText, "^[0-9]+$")
            throw Error("Invalid update process ID.")
        if !RegExMatch(token, "^[0-9]{14}-[0-9]+$")
            throw Error("Invalid update token.")
        if (pendingPath != targetPath . ".update-" . token . ".tmp")
            throw Error("Invalid pending update path.")
        if (backupPath != targetPath . ".previous-" . token . ".bak")
            throw Error("Invalid backup path.")
        if (markerPath != targetPath . ".update-" . token . ".ok")
            throw Error("Invalid update marker path.")
        expectedHelper := targetPath . ".updater-" . token . ".exe"
        if (StrLower(A_ScriptFullPath) != StrLower(expectedHelper))
            throw Error("Update worker is not running from the expected location.")
        if !RegExMatch(targetPath, "i)^[A-Z]:\\") || InStr(targetPath, "..")
            throw Error("Invalid target executable path.")
        if !FileExist(targetPath) || !FileExist(pendingPath)
            throw Error("Required update files are missing.")
    }

    static CaptureUpdateCompletion(args) {
        if (args.Length != 5)
            return false
        token := args[2]
        markerPath := args[3]
        helperPath := args[4]
        backupPath := args[5]
        if !RegExMatch(token, "^[0-9]{14}-[0-9]+$")
            return false
        if (markerPath != A_ScriptFullPath . ".update-" . token . ".ok")
            return false
        if (StrLower(helperPath) != StrLower(A_ScriptFullPath . ".updater-" . token . ".exe"))
            return false
        if (backupPath != A_ScriptFullPath . ".previous-" . token . ".bak")
            return false
        this.PendingCompletion := {
            MarkerPath: markerPath,
            HelperPath: helperPath
        }
        return true
    }

    static CompletePendingStartup() {
        if !IsObject(this.PendingCompletion)
            return
        completion := this.PendingCompletion
        try FileAppend("ok", completion.MarkerPath, "UTF-8-RAW")
        SetTimer((*) => this.CleanupFinishedHelper(completion.HelperPath), -5000)
        TrayTip("SwiftDeck restarted successfully.", "✅ Update complete", "Iconi")
        SetTimer((*) => TrayTip(), -5000)
    }

    static CleanupFinishedHelper(helperPath) {
        if FileExist(helperPath)
            try this.DeleteFileWithRetry(helperPath)
    }

    static MoveFileWithRetry(sourcePath, destinationPath) {
        lastError := ""
        loop 40 {
            try {
                FileMove(sourcePath, destinationPath)
                return true
            } catch Error as err {
                lastError := err.Message
                Sleep(250)
            }
        }
        throw Error("Could not replace the application file: " . lastError)
    }

    static DeleteFileWithRetry(filePath) {
        lastError := ""
        loop 20 {
            try {
                FileDelete(filePath)
                return true
            } catch Error as err {
                lastError := err.Message
                Sleep(250)
            }
        }
        throw Error("Could not delete update file: " . lastError)
    }

    static RollBackUpdate(targetPath, pendingPath, backupPath, newPid := 0) {
        if (newPid && ProcessExist(newPid))
            try ProcessClose(newPid)
        ; Never remove the target unless a verified previous executable was
        ; successfully moved to the backup path first.
        if FileExist(backupPath) {
            if FileExist(targetPath)
                try this.DeleteFileWithRetry(targetPath)
            try this.MoveFileWithRetry(backupPath, targetPath)
        }
        if FileExist(pendingPath)
            try FileDelete(pendingPath)
    }

    static GetStateFilePath() {
        return A_AppData . "\SwiftDeck\UpdateState.ini"
    }

    static ShouldCheckNow() {
        statePath := this.GetStateFilePath()
        if !FileExist(statePath)
            return true
        try lastCheck := IniRead(statePath, "Update", "LastCheck", "")
        catch
            return true
        if !RegExMatch(lastCheck, "^[0-9]{14}$")
            return true
        try {
            hoursSinceCheck := DateDiff(A_Now, lastCheck, "Hours")
            return hoursSinceCheck < 0 || hoursSinceCheck >= 24
        }
        catch
            return true
    }

    static LoadCachedState() {
        statePath := this.GetStateFilePath()
        if !FileExist(statePath)
            return false
        try latestVersion := IniRead(statePath, "Update", "LatestVersion", "")
        catch
            return false
        if (latestVersion == "")
            return false

        try status := this.ClassifyVersion(latestVersion, this.RequireCurrentVersion())
        catch
            return false
        this.State := {
            Status: status,
            LatestVersion: latestVersion,
            ReleaseUrl: this.GetReleaseUrl(latestVersion),
            ErrorMessage: ""
        }
        return true
    }

    static SaveSuccessfulCheck() {
        statePath := this.GetStateFilePath()
        SplitPath(statePath, , &stateDir)
        try {
            if !DirExist(stateDir)
                DirCreate(stateDir)
            IniWrite(A_Now, statePath, "Update", "LastCheck")
            IniWrite(this.State.LatestVersion, statePath, "Update", "LatestVersion")
        }
    }

    static NotifyAvailableVersionOnce(version) {
        statePath := this.GetStateFilePath()
        try lastNotified := IniRead(statePath, "Update", "LastNotifiedVersion", "")
        catch
            lastNotified := ""
        if (lastNotified == version)
            return

        TrayTip("Open App Settings and select Update to install it.", "⬆ SwiftDeck v" . version . " is available", "Iconi")
        SetTimer((*) => TrayTip(), -5000)
        try IniWrite(version, statePath, "Update", "LastNotifiedVersion")
    }

    static NotifyUi() {
        callback := this.UiRefreshCallback
        if IsObject(callback)
            try callback.Call()
    }

    static RequireCurrentVersion() {
        if (this.CurrentVersion == "")
            throw Error("UpdateManager.Initialize(currentVersion) must be called first.")
        return this.CurrentVersion
    }
}

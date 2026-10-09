#Requires AutoHotkey v2.0
#Include _TestHarness.ahk
#Include ..\src\lib\UpdateManager.ahk

AssertThrows(callback, label) {
    didThrow := false
    try callback.Call()
    catch
        didThrow := true
    if !didThrow
        throw Error(label . ": expected an exception")
}

AssertEqual(UpdateManager.NormalizeReleaseTag("v1.3.0"), "1.3.0", "Normalize v-prefixed tag")
AssertEqual(UpdateManager.NormalizeReleaseTag("1.3.1"), "1.3.1", "Normalize plain tag")
AssertThrows(() => UpdateManager.NormalizeReleaseTag("v1.3"), "Reject incomplete tag")
AssertThrows(() => UpdateManager.NormalizeReleaseTag("release-1.3.0"), "Reject unexpected tag prefix")

AssertEqual(UpdateManager.ClassifyVersion("1.3.1", "1.3.0"), "available", "Newer release")
AssertEqual(UpdateManager.ClassifyVersion("1.3.0", "1.3.0"), "up_to_date", "Same release")
AssertEqual(UpdateManager.ClassifyVersion("1.2.0", "1.3.0"), "local_newer", "Prevent downgrade")

release := UpdateManager.ParseLatestReleaseJson('{"tag_name":"v1.3.1","name":"SwiftDeck v1.3.1"}')
AssertEqual(release.Version, "1.3.1", "Parse latest release tag")
AssertEqual(release.ReleaseUrl, "https://github.com/KwangBeomPark/02_SwiftDeck/releases/tag/v1.3.1", "Build release URL")
AssertThrows(() => UpdateManager.ParseLatestReleaseJson('{"tag_name":"nightly"}'), "Reject unsupported GitHub tag")

manifestText := "[Release]`nVersion=1.3.1`nAsset=SwiftDeck.exe`nSha256="
    . "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
    . "`nSize=1434112`n"
manifest := UpdateManager.ParseUpdateManifest(manifestText)
AssertEqual(manifest.Version, "1.3.1", "Parse manifest version")
AssertEqual(manifest.AssetName, "SwiftDeck.exe", "Parse canonical asset")
AssertEqual(manifest.CanonicalAssetName, "SwiftDeck.exe", "Keep canonical asset name")
AssertEqual(manifest.Size, 1434112, "Parse manifest size")
AssertThrows(() => UpdateManager.ParseUpdateManifest(StrReplace(manifestText, "SwiftDeck.exe", "Other.exe")), "Reject unexpected asset")

AssertEqual(UpdateManager.GetVersionedAssetName("v1.3.2"), "SwiftDeck.v1.3.2.exe", "Build versioned asset name")

versionedManifestText := "[Release]`nVersion=1.3.2`nAsset=SwiftDeck.exe`nAssetVersioned=SwiftDeck.v1.3.2.exe`nSha256="
    . "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
    . "`nSize=1457664`n"
versionedManifest := UpdateManager.ParseUpdateManifest(versionedManifestText)
AssertEqual(versionedManifest.AssetName, "SwiftDeck.v1.3.2.exe", "Prefer versioned asset")
AssertEqual(versionedManifest.CanonicalAssetName, "SwiftDeck.exe", "Retain canonical fallback asset")
AssertThrows(() => UpdateManager.ParseUpdateManifest(
    StrReplace(versionedManifestText, "AssetVersioned=SwiftDeck.v1.3.2.exe", "AssetVersioned=SwiftDeck.v9.9.9.exe")),
    "Reject versioned asset that disagrees with the manifest version")
AssertThrows(() => UpdateManager.ParseUpdateManifest(
    StrReplace(versionedManifestText, "AssetVersioned=SwiftDeck.v1.3.2.exe", "AssetVersioned=Other.exe")),
    "Reject unexpected versioned asset")

AssertEqual(UpdateManager.GetAssetDownloadUrl("1.3.1", "SwiftDeck.exe"),
    "https://github.com/KwangBeomPark/02_SwiftDeck/releases/download/v1.3.1/SwiftDeck.exe",
    "Build canonical asset URL")
AssertEqual(UpdateManager.GetAssetDownloadUrl("1.3.2", UpdateManager.GetVersionedAssetName("1.3.2")),
    "https://github.com/KwangBeomPark/02_SwiftDeck/releases/download/v1.3.2/SwiftDeck.v1.3.2.exe",
    "Build versioned asset URL")
AssertThrows(() => UpdateManager.GetAssetDownloadUrl("1.3.1", "../SwiftDeck.exe"), "Reject unsafe asset name")

hashTestPath := A_Temp . "\SwiftDeck-UpdateManagerTests-" . A_TickCount . ".tmp"
try {
    FileAppend("abc", hashTestPath, "UTF-8-RAW")
    AssertEqual(UpdateManager.ComputeFileSha256(hashTestPath),
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        "Compute SHA-256 with Windows CNG")
} finally {
    if FileExist(hashTestPath)
        FileDelete(hashTestPath)
}

rollbackDir := A_Temp . "\SwiftDeck-RollbackTests-" . A_TickCount
DirCreate(rollbackDir)
try {
    targetPath := rollbackDir . "\SwiftDeck Test.exe"
    pendingPath := targetPath . ".update-test.tmp"
    missingBackupPath := targetPath . ".previous-missing.bak"
    FileAppend("original", targetPath, "UTF-8-RAW")
    FileAppend("pending", pendingPath, "UTF-8-RAW")
    UpdateManager.RollBackUpdate(targetPath, pendingPath, missingBackupPath)
    AssertEqual(FileRead(targetPath, "UTF-8"), "original", "Never delete target without backup")
    AssertEqual(FileExist(pendingPath), "", "Remove unused pending file")

    backupPath := targetPath . ".previous-valid.bak"
    FileDelete(targetPath)
    FileAppend("new-binary", targetPath, "UTF-8-RAW")
    FileAppend("previous-binary", backupPath, "UTF-8-RAW")
    UpdateManager.RollBackUpdate(targetPath, pendingPath, backupPath)
    AssertEqual(FileRead(targetPath, "UTF-8"), "previous-binary", "Restore verified backup")
    AssertEqual(FileExist(backupPath), "", "Consume restored backup")
} finally {
    if DirExist(rollbackDir)
        TestFinishDirectory(rollbackDir)
}

; Exercise the same signed artifact shape produced by ReleaseSafety.ps1.
releaseHash := "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
manifestFixture := '{"application":"SwiftDeck","version":"9.8.7","signed":true,"artifacts":['
    . '{"name":"App02_SwiftDeck_Setup_v9.8.7.exe","bytes":123456,"sha256":"' releaseHash '",'
    . '"signature":{"status":"Valid","signerThumbprint":"fixture","timestampThumbprint":"fixture"}}]}'
parsed := UpdateManager.ParseBuildManifestJson(manifestFixture, "9.8.7")
AssertEqual(parsed.AssetName, "App02_SwiftDeck_Setup_v9.8.7.exe", "Read nested signature without losing installer fields")
AssertEqual(parsed.Sha256, releaseHash, "Read installer hash from its own artifact")
AssertTrue(parsed.IsInstaller, "Installer metadata returns installer update mode")
historicalJson := StrReplace(manifestFixture, "SwiftDeck_Setup", "SwiftDeck-Setup")
AssertEqual(UpdateManager.ParseBuildManifestJson(historicalJson, "9.8.7").AssetName,
    "App02_SwiftDeck-Setup_v9.8.7.exe", "Read historical App02 installer names")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"application":"SwiftDeck"', '"application":"AnotherApp"'), "9.8.7"), "Reject another product")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(manifestFixture, "9.8.8"), "Reject wrong manifest version")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":"123456"'), "9.8.7"), "Reject string size")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":123456.0'), "9.8.7"), "Reject floating size")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":true'), "9.8.7"), "Reject boolean size")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":99999'), "9.8.7"), "Reject undersized installer")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":100000001'), "9.8.7"), "Reject oversized installer")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, releaseHash, "invalid"), "9.8.7"), "Reject invalid hash")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"name":"App02', '"name":"../App02'), "9.8.7"), "Reject path traversal asset")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":123456,"bytes":123456'), "9.8.7"), "Reject duplicate metadata keys")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(manifestFixture . "extra", "9.8.7"), "Reject trailing JSON data")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(SubStr(manifestFixture, 1, -1), "9.8.7"), "Reject truncated JSON")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":0123456'), "9.8.7"), "Reject leading zero number")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"bytes":123456', '"bytes":+123456'), "9.8.7"), "Reject plus number")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"version":"9.8.7"', '"version":"9.8.7","version":"9.8.7"'), "9.8.7"), "Reject repeated version")
duplicateJson := '{"application":"SwiftDeck","version":"9.8.7","artifacts":['
    . '{"name":"App02_SwiftDeck_Setup_v9.8.7.exe","bytes":123456,"sha256":"' releaseHash '"},'
    . '{"name":"App02_SwiftDeck_Setup_v9.8.7.exe","bytes":123456,"sha256":"' releaseHash '"}]}'
AssertThrows(() => UpdateManager.ParseBuildManifestJson(duplicateJson, "9.8.7"), "Reject duplicate installer artifacts")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(duplicateJson, '"name":"App02_SwiftDeck_Setup', '"name":"App02_SwiftDeck-Setup', , 1), "9.8.7"), "Reject ambiguous historical/new installers")
foreignHashJson := '{"application":"SwiftDeck","version":"9.8.7","artifacts":['
    . '{"name":"App02_SwiftDeck_Setup_v9.8.7.exe","bytes":123456},'
    . '{"name":"other.exe","bytes":123456,"sha256":"' releaseHash '"}]}'
AssertThrows(() => UpdateManager.ParseBuildManifestJson(foreignHashJson, "9.8.7"), "Never borrow another artifact hash")
AssertThrows(() => UpdateManager.ParseBuildManifestJson(StrReplace(manifestFixture, '"artifacts":[', '"artifacts":{'), "9.8.7"), "Reject non-array artifacts")
AssertEqual(ReleaseJson.Parse('{"x":1,"X":2}').Count, 2, "JSON keys are case sensitive")
AssertEqual(ReleaseJson.Parse('{"note":"braces { } and quote \" remain data"}')["note"],
    'braces { } and quote " remain data', "Strings cannot split artifact objects")
AssertEqual(ReleaseJson.Parse('{"name":"\u0041\uD83D\uDE00"}')["name"], "A" . Chr(0x1F600), "Decode Unicode pair")
AssertThrows(() => ReleaseJson.Parse('{"name":"\uD800"}'), "Reject orphan surrogate")
AssertThrows(() => ReleaseJson.Parse('{"name":"\N"}'), "Reject nonstandard escape")
AssertThrows(() => ReleaseJson.Parse('{"name":"\u0000"}'), "Reject unsupported NUL")
deepJson := "0"
loop 34
    deepJson := "[" . deepJson . "]"
AssertThrows(() => ReleaseJson.Parse(deepJson), "Reject excess nesting")
hugeJson := ""
loop 1049
    hugeJson .= Format("{:01000}", 0)
AssertThrows(() => ReleaseJson.Parse(hugeJson), "Bound manifest length")

TestsPassed("UpdateManager (signed manifest + JSON safety regressions)")

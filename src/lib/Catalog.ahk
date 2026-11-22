#Requires AutoHotkey v2.0
#Include Config.ahk

; =================================================================================
; Module: Catalog
; Description: Catalogs of prompts and hotstrings someone exported, kept as
;              .swiftdeck files in UserSetting\Catalog\ to browse, add items
;              from, or switch to. A catalog is one INI file holding the same
;              sections as the live prompt and hotstring files ([Meta] carries
;              both PromptEncoding and SchemaVersion), so the same readers and
;              writers serve both. Folders, key remapping and General settings
;              are never part of one.
; Author: KBPark
; =================================================================================

CatalogGetFormatVersion() {
    return 1
}

CatalogGetExtension() {
    return "swiftdeck"
}

CatalogGetFolder() {
    global g_targetFolder
    return g_targetFolder . "Catalog\"
}

; The most a catalog may hold. Reading runs under Critical, so a damaged
; count must not keep the whole app busy reading entries that do not exist.
CatalogGetMaxGroups() {
    return 999
}

CatalogGetMaxHotstrings() {
    return 5000
}

; A file name Windows accepts, from a display name.
CatalogSafeFileName(name) {
    name := RegExReplace(name, '[\\/:*?"<>|\x00-\x1F]', "_")
    name := Trim(name, " .")
    if (StrLen(name) > 60) {
        name := SubStr(name, 1, 60)
        ; Do not keep half of a character that needs two UTF-16 units.
        lastCode := Ord(SubStr(name, -1))
        if (lastCode >= 0xD800 && lastCode <= 0xDBFF)
            name := SubStr(name, 1, -1)
        name := RTrim(name, " .")
    }
    if RegExMatch(name, "i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$")
        name .= "_"
    return (name != "") ? name : "Catalog"
}

; yyyyMMddHHmmss -> yyyy-MM-dd HH:mm, or "" when the stamp is not one.
CatalogFormatDate(stamp) {
    if !RegExMatch(stamp, "^\d{14}$")
        return ""
    try return FormatTime(stamp, "yyyy-MM-dd HH:mm")
    catch
        return ""
}

; One line of a prompt or replacement, for a list column.
CatalogPreviewText(text, maxLength := 70) {
    text := RegExReplace(text, "\R", " ↵ ")
    return (StrLen(text) > maxLength) ? SubStr(text, 1, maxLength) . "…" : text
}

; { Path, Name, Created } for a catalog this version can read, otherwise "".
; Format 1 always records the current prompt encoding and hotstring schema;
; without them the readers would fall back to the legacy rules, which read
; such a file's hotstrings as none and turn "\n" in its prompts into newlines.
CatalogReadInfo(path) {
    try {
        format := IniRead(path, "Catalog", "Format", "")
        promptEncoding := IniRead(path, "Meta", "PromptEncoding", "")
        schemaVersion := IniRead(path, "Meta", "SchemaVersion", "")
    } catch {
        return ""
    }
    if !RegExMatch(format, "^\d{1,3}$") || Integer(format) < 1 || Integer(format) > CatalogGetFormatVersion()
        return ""
    if (promptEncoding != String(ConfigGetPromptEncodingVersion()) || schemaVersion != "4")
        return ""
    SplitPath(path, , , , &baseName)
    name := ""
    created := ""
    try name := HotstringDecodeIniValue(IniRead(path, "Catalog", "Name", ""))
    try created := IniRead(path, "Catalog", "Created", "")
    return { Path: path, Name: (Trim(name) != "") ? Trim(name) : baseName, Created: created }
}

; The catalogs in the folder, newest first.
CatalogList(folder := "") {
    if (folder == "")
        folder := CatalogGetFolder()
    entries := []
    if !DirExist(folder)
        return entries
    loop files folder . "*." . CatalogGetExtension(), "F" {
        info := CatalogReadInfo(A_LoopFileFullPath)
        if (info == "")
            continue
        ; Insertion sort: there are a handful of catalogs, not thousands.
        pos := entries.Length + 1
        for idx, entry in entries {
            if (StrCompare(info.Created, entry.Created) > 0
                || (info.Created == entry.Created && StrCompare(info.Name, entry.Name) < 0)) {
                pos := idx
                break
            }
        }
        entries.InsertAt(pos, info)
    }
    return entries
}

; Reads a catalog with the same readers as the live settings:
; { Info, Prompts, SlotNames, Hotstrings }. The readers are pointed at the file
; only while this runs, under Critical, so a hotkey that fires meanwhile cannot
; read the catalog in place of the user's own settings.
CatalogRead(path) {
    global g_configPathOverride
    info := CatalogReadInfo(path)
    if (info == "")
        throw Error("This file is not a SwiftDeck catalog, or it needs a newer SwiftDeck:`n" . path)
    CatalogCheckSize(path)
    wasCritical := A_IsCritical
    Critical("On")
    g_configPathOverride := Map("Prompts", path, "Hotstrings", path)
    try {
        catalog := {
            Info: info,
            Prompts: ConfigReadPromptData(),
            SlotNames: ConfigReadPromptSlotNames(),
            Hotstrings: ConfigReadHotstringData()
        }
    } finally {
        g_configPathOverride := ""
        Critical(wasCritical ? wasCritical : "Off")
    }
    CatalogCheckStorable(catalog)
    return catalog
}

; Refuses counts no real catalog has, before anything loops over them.
CatalogCheckSize(path) {
    groupCount := IniRead(path, "Groups", "Count", "0")
    if !RegExMatch(groupCount, "^\d{1,4}$") || Integer(groupCount) > CatalogGetMaxGroups()
        throw Error("This catalog lists more hotstring groups than SwiftDeck reads (" . CatalogGetMaxGroups() . ").")
    total := 0
    loop Integer(groupCount) {
        groupNo := Format("{:03}", A_Index)
        groupId := IniRead(path, "Groups", "Group" . groupNo . "Id", "Group" . groupNo)
        itemCount := IniRead(path, groupId, "ItemCount", "0")
        if !RegExMatch(itemCount, "^\d{1,5}$")
            throw Error("This catalog has an unreadable hotstring count in " . groupId . ".")
        total += Integer(itemCount)
        if (total > CatalogGetMaxHotstrings())
            throw Error("This catalog holds more hotstrings than SwiftDeck reads (" . CatalogGetMaxHotstrings() . ").")
    }
}

; What is applied from a catalog goes through the same savers as an edit, so
; anything those would refuse is refused here, before the user picks from it.
CatalogCheckStorable(catalog) {
    loop 10 {
        for item in catalog.Prompts[A_Index - 1] {
            if !IsPlainIniKeySafe(item.Title)
                throw Error("This catalog has a prompt title SwiftDeck cannot store: " . item.Title)
        }
    }
    ConfigBuildPromptChanges(catalog.Prompts)
    ConfigBuildHotstringChanges(catalog.Hotstrings.Data, catalog.Hotstrings.GroupOrder)
}

; Writes a catalog in one atomic write, replacing any file at path whole.
; The data is checked by the same rules as a save of the live settings.
CatalogWrite(path, name, promptData, slotNames, hotstringData) {
    changes := [{ ClearSectionsExcept: [] }]
    changes.Push({ Section: "Catalog", Key: "Format", Value: String(CatalogGetFormatVersion()) })
    changes.Push({ Section: "Catalog", Key: "Name", Value: HotstringEncodeIniValue(Trim(name)) })
    changes.Push({ Section: "Catalog", Key: "Created", Value: A_Now })
    for change in ConfigBuildPromptChanges(promptData)
        changes.Push(change)
    changes.Push({ Section: "SlotNames", SectionText: ConfigBuildSlotNamesText(slotNames) })
    for change in ConfigBuildHotstringChanges(hotstringData.Data, hotstringData.GroupOrder)
        changes.Push(change)
    SettingsWriteIniValues(path, changes)
}

; Saves the user's current prompts and hotstrings as a catalog in the folder,
; which is what makes a switch reversible. It never replaces a catalog: a name
; already taken gets " (2)", " (3)" and so on. Returns { Path, Name }.
CatalogSaveCurrent(name) {
    folder := CatalogGetFolder()
    ConfigEnsureDir(folder)
    finalName := name
    loop {
        path := folder . CatalogSafeFileName(finalName) . "." . CatalogGetExtension()
        if !FileExist(path)
            break
        finalName := name . " (" . (A_Index + 1) . ")"
    }
    CatalogWrite(path, finalName, ConfigReadPromptData(), ConfigReadPromptSlotNames(), ConfigReadHotstringData())
    return { Path: path, Name: finalName }
}

; Where an imported file is kept: its own name, with the catalog extension.
CatalogImportTarget(sourcePath) {
    SplitPath(sourcePath, , , , &baseName)
    return CatalogGetFolder() . CatalogSafeFileName(baseName) . "." . CatalogGetExtension()
}

; Copies a received catalog into the folder after reading it whole, so a
; damaged or foreign file is refused before it is kept. The caller decides
; whether an existing catalog of the same name may be replaced.
CatalogImport(sourcePath, targetPath) {
    CatalogRead(sourcePath)
    if (StrLower(sourcePath) == StrLower(targetPath))
        return targetPath
    ConfigEnsureDir(CatalogGetFolder())
    ConfigCopyFileSafely(sourcePath, targetPath)
    return targetPath
}

; The part of the user's settings to export: only the slots and groups picked.
; slots: Map of slot number -> true; sections: Map of group section -> true.
CatalogSelectForExport(promptData, slotNames, hotstringData, slots, sections) {
    prompts := Map()
    names := Map()
    loop 10 {
        num := A_Index - 1
        picked := slots.Has(num) && slots[num]
        prompts[num] := picked ? promptData[num].Clone() : []
        names[num] := picked ? slotNames[num] : ""
    }
    data := Map()
    order := []
    for section in hotstringData.GroupOrder {
        if (sections.Has(section) && sections[section] && hotstringData.Data.Has(section)) {
            data[section] := hotstringData.Data[section].Clone()
            order.Push(section)
        }
    }
    return { Prompts: prompts, SlotNames: names, Hotstrings: { Data: data, GroupOrder: order } }
}

; Adds catalog items to a copy of the user's settings. Nothing is written and
; the inputs are not changed. picks: { Kind: "Prompt", Slot, Index } or
; { Kind: "Hotstring", Section, Index }. promptSlot: -1 keeps each prompt's
; catalog slot, 0-9 puts them all in that slot. A hotstring whose trigger the
; user already has, in any group, is skipped: the user's own stays. A group
; goes into the user's group of the same name, typed or menu-only alike, since
; the Hotstrings tab cannot tell two groups of one name apart.
CatalogPlanAdd(myPrompts, myHotstrings, catalog, picks, promptSlot := -1) {
    prompts := Map()
    loop 10
        prompts[A_Index - 1] := myPrompts[A_Index - 1].Clone()
    data := Map()
    for section, items in myHotstrings.Data
        data[section] := items.Clone()
    order := myHotstrings.GroupOrder.Clone()

    owned := Map()
    owned.CaseSense := false  ; hotstring triggers ignore case
    groupByName := Map()
    groupByName.CaseSense := false
    for section in order {
        if data.Has(section) {
            groupByName[HotstringGetRuntimeGroupName(section)] := section
            for item in data[section]
                owned[Trim(item.Key)] := true
        }
    }

    plan := { Prompts: prompts, Hotstrings: { Data: data, GroupOrder: order },
        AddedPrompts: 0, AddedHotstrings: 0, Skipped: [] }
    for pick in picks {
        if (pick.Kind == "Prompt") {
            source := catalog.Prompts[pick.Slot][pick.Index]
            slot := (promptSlot >= 0 && promptSlot <= 9) ? promptSlot : pick.Slot
            prompts[slot].Push({ Title: source.Title, Msg: source.Msg })
            plan.AddedPrompts++
        } else {
            source := catalog.Hotstrings.Data[pick.Section][pick.Index]
            trigger := Trim(source.Key)
            if owned.Has(trigger) {
                plan.Skipped.Push(trigger)
                continue
            }
            groupName := HotstringGetRuntimeGroupName(pick.Section)
            section := groupByName.Has(groupName) ? groupByName[groupName] : pick.Section
            if !data.Has(section) {
                data[section] := []
                order.Push(section)
                groupByName[groupName] := section
            }
            data[section].Push({ Key: source.Key, Val: source.Val, Mode: HotstringGetMode(source) })
            owned[trigger] := true
            plan.AddedHotstrings++
        }
    }
    return plan
}

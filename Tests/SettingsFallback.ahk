; SettingsFallback.ahk - Isolated platform defaults, persistence and file identity checks.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => SettingsFallback.OnError(err, mode))
OnExit((*) => SettingsFallback.CleanUp())
SetTimer(() => SettingsFallback.Fail("Timed out after 20 seconds."), -20000)
SettingsFallback.Run()

; A failed settings write must fail the test without opening its error dialog.
MsgBox(args*) {
    throw Error("Unexpected settings error dialog: " (args.Length ? args[1] : ""))
}

class SettingsFallback {
    static Folder := "", Started := A_TickCount

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static EqualJson(actual, expected, message) => SettingsFallback.Assert(JSON.Stringify(actual) == JSON.Stringify(expected), message)
    static Mark(message) => FileAppend("PASS SETTINGS_FALLBACK " message "`n", "*")

    static Run() {
        SettingsFallback.Folder := Platform.Join(A_Temp, "ALTRun-SettingsFallback-" Platform.NewUuid())
        for folder in ["Data", "Files"]
            DirCreate(Platform.Join(SettingsFallback.Folder, folder))
        AppSettings.Portable := false
        AppSettings.UserDir := SettingsFallback.Folder
        AppSettings.DataDir := Platform.Join(SettingsFallback.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.LegacyFile := Platform.Join(SettingsFallback.Folder, "Legacy.json")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        FileIndex.File := Platform.Join(AppSettings.DataDir, "FileIndex.json")
        Logger.Enabled := false
        I18n.LangDir := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "Lang")
        I18n.Init("en")
        SettingsFallback.StockDefaults()
        SettingsFallback.CustomDefaults()
        SettingsFallback.FileIdentities()
        SettingsFallback.KnowledgeIdentities()
        SettingsFallback.Mark("complete " (A_TickCount - SettingsFallback.Started) "ms")
        ExitApp(0)
    }

    static StockDefaults() {
        stored := AppSettings.Defaults()
        stored["Features"]["Applications"]["Folders"] := ["A_DesktopCommon", "A_Desktop", "A_ProgramsCommon", "A_Programs"]
        stored["Features"]["Applications"]["FileTypes"] := ["*.appref-ms", "*.url", "*.exe", "*.lnk"]
        stored["Features"]["Terminal"]["Shell"] := "cmd"
        stored["General"]["FileManager"] := "explorer"
        stored["CustomCommands"] := AppSettings._WindowsCommands()
        JSON.WriteFile(AppSettings.File, stored)
        AppSettings.Load()
        if Platform.IsWindows {
            SettingsFallback.EqualJson(AppSettings.Data, stored, "Windows stock settings changed during load.")
            SettingsFallback.Assert(AppSettings._runtimeFallbacks.Length = 0, "Windows installed runtime fallbacks.")
        } else {
            expected := AppSettings.Defaults()
            SettingsFallback.EqualJson(AppSettings.Feature("Applications")["Folders"], expected["Features"]["Applications"]["Folders"], "Application roots did not use current-platform defaults.")
            SettingsFallback.EqualJson(AppSettings.Feature("Applications")["FileTypes"], expected["Features"]["Applications"]["FileTypes"], "Application file types did not use current-platform defaults.")
            SettingsFallback.Assert(AppSettings.Feature("Terminal")["Shell"] == expected["Features"]["Terminal"]["Shell"], "The stock Windows shell was not adapted.")
            SettingsFallback.Assert(AppSettings.General["FileManager"] == "", "The stock Windows file manager was not adapted.")
            SettingsFallback.EqualJson(AppSettings.CustomCommands, expected["CustomCommands"], "Stock commands did not use current-platform defaults.")
            SettingsFallback.Assert(AppSettings._runtimeFallbacks.Length = 5, "The expected stock values were not tracked.")
        }
        effective := AppSettings._CopyValue(AppSettings.Data)
        runtime := JSON.Stringify(AppSettings.Data)
        SettingsFallback.Assert(AppSettings.Save(), "Saving the stock settings failed.")
        SettingsFallback.EqualJson(JSON.Parse(FileRead(AppSettings.File, "UTF-8")), stored, "Saving overwrote the stored Windows choices.")
        SettingsFallback.Assert(JSON.Stringify(AppSettings.Data) == runtime, "Saving changed the effective runtime settings.")
        AppSettings.General["HistorySize"] := 17
        stored["General"]["HistorySize"] := 17
        SettingsFallback.Assert(AppSettings.Save(), "Saving an unrelated edit failed.")
        SettingsFallback.EqualJson(JSON.Parse(FileRead(AppSettings.File, "UTF-8")), stored, "An unrelated edit persisted runtime substitutions.")
        SettingsFallback.Mark("stock runtime defaults preserve stored choices")

        AppSettings.Feature("Terminal")["Shell"] := "custom-shell"
        AppSettings.General["FileManager"] := "custom-manager"
        AppSettings.Feature("Applications")["Folders"] := [Platform.Join(SettingsFallback.Folder, "CustomApps")]
        AppSettings.Feature("Applications")["FileTypes"] := ["*.custom"]
        AppSettings.CustomCommands[1]["Title"] := "User edited command"
        edited := JSON.Stringify(AppSettings.Data)
        SettingsFallback.Assert(AppSettings.Save(), "Saving changed effective defaults failed.")
        SettingsFallback.Assert(JSON.Stringify(JSON.Parse(FileRead(AppSettings.File, "UTF-8"))) == edited, "An edited effective choice was replaced by its stored original.")
        SettingsFallback.Assert(AppSettings._runtimeFallbacks.Length = 0, "Successfully saved edits retained obsolete stock values.")
        AppSettings.Feature("Terminal")["Shell"] := effective["Features"]["Terminal"]["Shell"]
        AppSettings.General["FileManager"] := effective["General"]["FileManager"]
        AppSettings.Feature("Applications")["Folders"] := effective["Features"]["Applications"]["Folders"]
        AppSettings.Feature("Applications")["FileTypes"] := effective["Features"]["Applications"]["FileTypes"]
        AppSettings.Data["CustomCommands"] := effective["CustomCommands"]
        edited := JSON.Stringify(AppSettings.Data)
        SettingsFallback.Assert(AppSettings.Save(), "Saving a subsequent return to platform defaults failed.")
        SettingsFallback.Assert(JSON.Stringify(JSON.Parse(FileRead(AppSettings.File, "UTF-8"))) == edited, "A subsequent edit restored obsolete Windows settings.")
        AppSettings.Load()
        SettingsFallback.Assert(JSON.Stringify(AppSettings.Data) == edited, "Edited effective choices did not survive reload.")
        SettingsFallback.Mark("edits to effective choices persist")
    }

    static CustomDefaults() {
        custom := AppSettings.Defaults()
        custom["Features"]["Applications"]["Folders"] := [Platform.Join(SettingsFallback.Folder, "CustomApps"), "A_Desktop"]
        custom["Features"]["Applications"]["FileTypes"] := ["*.custom", "*.exe"]
        custom["Features"]["Terminal"]["Shell"] := "custom-shell"
        custom["General"]["FileManager"] := "custom-manager"
        custom["CustomCommands"] := [AppSettings._WindowsCommands()[1]]
        JSON.WriteFile(AppSettings.File, custom)
        AppSettings.Load()
        SettingsFallback.EqualJson(AppSettings.Data, custom, "A customized Windows choice was adapted.")
        SettingsFallback.Assert(AppSettings._runtimeFallbacks.Length = 0, "Custom choices were tracked as stock defaults.")
        SettingsFallback.Assert(AppSettings.Save(), "Saving custom settings failed.")
        SettingsFallback.EqualJson(JSON.Parse(FileRead(AppSettings.File, "UTF-8")), custom, "Custom settings did not persist unchanged.")
        SettingsFallback.Mark("custom choices remain intact")
    }

    static FileIdentities() {
        folder := Platform.Join(SettingsFallback.Folder, "Files")
        upper := Platform.Join(folder, "Foo.txt"), lower := Platform.Join(folder, "foo.txt")
        FileAppend("Uppercase filename.`n", upper, "UTF-8")
        if Platform.IsLinux
            FileAppend("Lowercase filename.`n", lower, "UTF-8")
        options := AppSettings.Feature("FileSearch")
        options["ScopeFolders"] := [folder]
        options["ScopeDepth"] := 1
        options["ScopeExclude"] := ""
        options["MaxEntries"] := 10
        FileIndex.Rebuild()
        started := A_TickCount
        while FileIndex.Scanning {
            FileIndex._ScanSome()
            SettingsFallback.Assert(A_TickCount - started < 3000, "The isolated file scan did not finish.")
        }
        paths := Map()
        paths.CaseSense := "On"
        for item in FileIndex.Search("foo", 10)
            paths[Platform.Identity(item.Path)] := true
        SettingsFallback.Assert(paths.Has(Platform.Identity(upper)), "The index lost the uppercase filename.")
        if Platform.IsLinux
            SettingsFallback.Assert(paths.Count = 2 && paths.Has(lower), "The Linux index merged distinct Foo/foo files.")
        else
            SettingsFallback.Assert(paths.Count = 1, "The isolated scan returned unexpected files.")
        FileIndex.Paths := []
        SettingsFallback.Assert(FileIndex._LoadCache(), "The current-platform index cache did not load.")
        SettingsFallback.Assert(FileIndex.Paths.Length = paths.Count, "The cached paths did not retain their identities.")
        cached := JSON.Parse(FileRead(FileIndex.File, "UTF-8"))
        cached["Platform"] := Platform.IsWindows ? "Linux" : "Windows"
        JSON.WriteFile(FileIndex.File, cached)
        SettingsFallback.Assert(!FileIndex._LoadCache(), "A different platform's file index was accepted.")
        cached.Delete("Platform")
        JSON.WriteFile(FileIndex.File, cached)
        SettingsFallback.Assert(FileIndex._LoadCache() = Platform.IsWindows, "Legacy index cache platform handling was incorrect.")
        SettingsFallback.Mark("file identities and platform cache isolation")
    }

    static KnowledgeIdentities() {
        Knowledge.Load()
        upper := "FileSearch:" Platform.Join(SettingsFallback.Folder, "Foo.txt")
        lower := "FileSearch:" Platform.Join(SettingsFallback.Folder, "foo.txt")
        Loop 3
            Knowledge.Record("foo", upper)
        Knowledge.Record("foo", lower)
        if (Knowledge._saveTimer != "")
            SetTimer(Knowledge._saveTimer, 0)
        SettingsFallback.Assert(Knowledge.Picks.Count = (Platform.IsWindows ? 1 : 2), "Knowledge UID case handling was incorrect.")
        if Platform.IsWindows {
            SettingsFallback.Assert(Knowledge.Picks[StrLower(upper)]["Count"] = 4, "Windows did not combine case variants.")
            SettingsFallback.Assert(Knowledge.Boost("foo", upper) = Knowledge.Boost("foo", lower), "Windows case variants have different ranking.")
        } else {
            SettingsFallback.Assert(Knowledge.Picks[upper]["Count"] = 3 && Knowledge.Picks[lower]["Count"] = 1, "Distinct Unix picks were combined.")
            SettingsFallback.Assert(Knowledge.QueryPicks["foo"].Count = 2, "Query history merged distinct Unix UIDs.")
            SettingsFallback.Assert(Knowledge.Boost("foo", upper) > Knowledge.Boost("foo", lower), "Unix ranking did not retain independent pick counts.")
        }
        snapshot := JSON.Stringify(Knowledge.Picks)
        queries := JSON.Stringify(Knowledge.QueryPicks)
        Knowledge.Save()
        SettingsFallback.Assert(FileExist(Knowledge.File), "Knowledge was not saved.")
        Knowledge.Load()
        SettingsFallback.Assert(JSON.Stringify(Knowledge.Picks) == snapshot && JSON.Stringify(Knowledge.QueryPicks) == queries, "Knowledge identities changed during reload.")
        SettingsFallback.Mark("knowledge UID case and persistence")
    }

    static CleanUp() {
        try {
            if (FileIndex._timer != "")
                SetTimer(FileIndex._timer, 0)
            if (Knowledge._saveTimer != "")
                SetTimer(Knowledge._saveTimer, 0)
            prefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-SettingsFallback-"))
            folder := Platform.FullPath(SettingsFallback.Folder)
            if (SettingsFallback.Folder != "" && InStr(Platform.Identity(folder), Platform.Identity(prefix)) = 1 && DirExist(folder))
                DirDelete(folder, true)
        }
    }

    static OnError(err, mode) {
        SettingsFallback.Fail(err.Message "`n" err.Stack)
        return true
    }

    static Fail(message) {
        FileAppend("FAIL SETTINGS_FALLBACK " message "`n", "**")
        ExitApp(1)
    }
}

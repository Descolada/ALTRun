; Isolated portable Preferences parity: draft import/export, hidden lists, usage and shortcut storage.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PreferencesParity.Fail(err.Message "`n" err.Stack))
OnExit((*) => PreferencesParity.CleanUp())
SetTimer(() => PreferencesParity.Fail("Timed out after 30 seconds."), -30000)
PreferencesParity.Run()

MsgBox(args*) {
    throw Error("Unexpected Preferences fixture dialog.")
}

class PreferencesParity {
    static Folder := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        root := Platform.FullPath("..", A_ScriptDir)
        PreferencesParity.Folder := Platform.Join(A_Temp, "ALTRun-PreferencesParity-" Platform.NewUuid())
        DirCreate(PreferencesParity.Folder)
        AppSettings.Portable := false
        AppSettings.UserDir := PreferencesParity.Folder
        AppSettings.DataDir := Platform.Join(PreferencesParity.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.Data["Snippets"] := []
        AppSettings.Snippets.Push(Map("Name", "Original", "Keyword", "orig", "Text", "saved text", "AutoExpand", 1))
        AppSettings.Feature("Applications")["Hidden"] := ["/Applications/Hidden.app"]
        AppSettings.Feature("System")["Hidden"] := ["Sleep"]
        ScriptProvider.Folder := Platform.Join(PreferencesParity.Folder, "Scripts")
        Usage.File := Platform.Join(AppSettings.DataDir, "Usage.json")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        I18n.Init("en")
        Logger.Enabled := false
        ThemeManager.BuiltinDir := Platform.Join(root, "Resources", "Themes")
        ThemeManager.UserDir := PreferencesParity.Folder
        ThemeManager.Load("Dark", "Compact")
        Usage.Days := Map(FormatTime(, "yyyy-MM-dd"), Map("Show", 9, "Applications", 3, "Snippets", 1))
        Usage.Since := FormatTime(, "yyyy-MM-dd")
        AppSettings.Save()
        saved := FileRead(AppSettings.File, "UTF-8")

        PreferencesWindow.Show("Prefs.Page.Snippets")
        PreferencesParity.Assert(PreferencesWindow.Pages.Length = PreferencesWindow.PageKeys.Length && PreferencesWindow.Pages.Length = (Platform.IsLinux ? 17 : 20), "Preferences pages are missing.")
        bindings := Map()
        for bind in PreferencesWindow.Binds {
            PreferencesParity.Assert(!bindings.Has(bind.Path), "Duplicate settings binding: " bind.Path)
            bindings[bind.Path] := bind
        }
        for path in ["General.SelectionHotkey", "General.DoubleTap", "General.CheckForUpdates", "Appearance.StatusBar"
            , "Features.Applications.Hidden", "Features.System.Hidden", "Features.FileSearch.ScopeExclude"
            , "Features.FileSearch.TypeFilters", "Features.FileSearch.MaxEntries", "Features.FileSearch.RefreshMinutes"
            , "Features.FileSearch.InDefaultResults", "Features.FileSearch.MinQueryLength"]
            PreferencesParity.Assert(bindings.Has(path), "Missing editable preference: " path)
        if !Platform.IsLinux
            for path in ["Extensions.QuickSwitch.Hotkey", "Extensions.AutoDate.DateFormat"]
                PreferencesParity.Assert(bindings.Has(path), "Missing native extension preference: " path)
        FileAppend("PASS PREFERENCES_PARITY complete pages and distinct settings bindings`n", "*")

        result := PreferencesWindow.ImportSnippetText('Name,Keyword,Text,Auto expand`nOriginal,orig,"updated, text",1`nNew,new,"line one`nline two",0')
        PreferencesParity.Assert(result.Added = 1 && result.Updated = 1, "CSV draft import did not merge keywords.")
        PreferencesParity.Assert(AppSettings.Snippets.Length = 1 && AppSettings.Snippets[1]["Text"] == "saved text", "Import modified applied settings.")
        exported := DelimitedText.Parse(PreferencesWindow.ExportSnippetText())
        PreferencesParity.Assert(exported.Length = 3 && exported[2][3] == "updated, text" && exported[3][3] == "line one`nline two", "Draft CSV export lost quoting or multiline content.")
        result := PreferencesWindow.ImportSnippetText("Name`tKeyword`tText`nTSV`ttsv`tfrom spreadsheet")
        PreferencesParity.Assert(result.Added = 1 && PreferencesWindow.Working["Snippets"].Length = 3, "Spreadsheet TSV import failed.")
        PreferencesParity.Assert(FileRead(AppSettings.File, "UTF-8") == saved, "Draft import wrote persisted settings.")
        FileAppend("PASS PREFERENCES_PARITY CSV/TSV import and export preserve saved settings and multiline draft text`n", "*")

        rows := PreferencesWindow.UsageRows()
        PreferencesParity.Assert(rows[1].Id = "Applications" && rows[1].Counts[1] = 3 && rows[1].Share == "75.0%", "Usage ranking or share includes launcher shows.")
        PreferencesParity.Assert(rows[rows.Length].Id = "Show" && rows[rows.Length].Counts[1] = 9 && rows[rows.Length].Share == "-", "Usage lost separate show count.")
        for key in ["Prefs.Page.Usage", "Prefs.Page.FileIndex", "Prefs.Page.Keyboard", "Prefs.Page.QuickSwitch", "Prefs.Page.Advanced"]
            PreferencesWindow._SelectRow(PreferencesWindow._PageIndex(key))
        PreferencesParity.Assert(PreferencesWindow.DataFoldersOverlap(PreferencesParity.Folder, Platform.Join(PreferencesParity.Folder, "child")), "Nested data folders were allowed.")
        PreferencesParity.Assert(!PreferencesWindow.DataFoldersOverlap(PreferencesParity.Folder, PreferencesParity.Folder "-sibling"), "A sibling folder was considered nested.")
        FileAppend("PASS PREFERENCES_PARITY usage statistics and portable data-folder boundaries`n", "*")

        if Platform.IsMac {
            g := Gui("-MinimizeBox", "ALTRun shortcut fixture")
            for shortcut in ["!Space", "^!F18", "#1", "^+Left", "~MButton", "CapsLock & j"] {
                control := HotkeyBox.Add(g, "xm w220", shortcut)
                PreferencesParity.Assert(HotkeyBox.Value(control) == shortcut, "Recorder changed persisted syntax: " shortcut)
            }
            control := HotkeyBox.Add(g, "xm w220", "!Space")
            g.AddButton("xm w120", "Done")
            HotkeyBox.Start(control)
            PreferencesParity.Assert(A_IsSuspended, "Recorder did not suspend active shortcuts.")
            HotkeyBox.CancelActive()
            PreferencesParity.Assert(!A_IsSuspended, "Recorder left shortcuts suspended.")
            Suspend(true)
            HotkeyBox.Start(control)
            HotkeyBox.CancelActive()
            PreferencesParity.Assert(A_IsSuspended, "Recorder changed an existing suspension.")
            Suspend(false)
            capabilities := RequestCapabilities()
            if (capabilities.InputControl = "Granted") {
                g.Show()
                control.Focus()
                Sleep(120)
                PreferencesParity.Assert(g.ToClr().HasFocus && A_IsSuspended, "The owned recorder did not acquire focus and suspend shortcuts.")
                SendEvent("^!{F18}")
                Sleep(200)
                PreferencesParity.Assert(HotkeyBox.Value(control) == "^!F18", "Native shortcut recording lost modifiers or the function-key name.")
                PreferencesParity.Assert(!A_IsSuspended, "Completed recording left shortcuts suspended.")
                control.Focus()
                Sleep(80)
                PreferencesParity.Assert(g.ToClr().HasFocus && A_IsSuspended, "The owned shortcut recorder lost focus.")
                SendEvent("{Backspace}")
                Sleep(150)
                PreferencesParity.Assert(HotkeyBox.Value(control) == "", "Backspace did not clear the native shortcut.")
                control.Focus()
                Sleep(80)
                PreferencesParity.Assert(g.ToClr().HasFocus && A_IsSuspended, "The owned shortcut recorder lost focus.")
                SendEvent("#a")
                Sleep(150)
                PreferencesParity.Assert(HotkeyBox.Value(control) == "#a", "Command+A was consumed as text editing instead of recorded.")
                control.Focus()
                Sleep(80)
                PreferencesParity.Assert(g.ToClr().HasFocus && A_IsSuspended, "The owned shortcut recorder lost focus.")
                SendEvent("{Esc}")
                Sleep(150)
                PreferencesParity.Assert(HotkeyBox.Value(control) == "#a" && !A_IsSuspended, "Escape did not retain the original shortcut and stop recording.")
            }
            g.Destroy()
            report := PreferencesWindow.PermissionReport()
            PreferencesParity.Assert(InStr(report, "InputMonitoring:") && InStr(report, "WindowControl:"), "Status-only permission diagnostics are missing capabilities.")
            FileAppend("PASS PREFERENCES_PARITY native recorder preserves storage and suspension; permission status query`n", "*")
        }
        PreferencesWindow.Close()
        PreferencesParity.Assert(AppSettings.Snippets.Length = 1 && FileRead(AppSettings.File, "UTF-8") == saved, "Closing Preferences committed the draft.")
        ExitApp(0)
    }

    static CleanUp() {
        HotkeyBox.CancelActive()
        try PreferencesWindow.Close()
        if (PreferencesParity.Folder != "" && InStr(PreferencesParity.Folder, "ALTRun-PreferencesParity-"))
            try DirDelete(PreferencesParity.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL PREFERENCES_PARITY " message "`n", "**")
        ExitApp(1)
        return true
    }
}

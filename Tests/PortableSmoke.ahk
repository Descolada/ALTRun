; PortableSmoke.ahk - Bounded launcher integration checks with isolated test data.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

#CSharp
using System;
using System.Reflection;
using System.Text;
using System.Text.Json;

public static string ALTRunSmokeSelectionReport(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapper)
{
    var control = Wrapper.Native;
    var type = control.GetType();
    var frameworkText = (string)type.GetProperty("SelectedText").GetValue(control);
    var nativeText = frameworkText;
    var native = type.GetProperty("ControlObject")?.GetValue(control);
    var bounds = native?.GetType().GetMethod("GetSelectionBounds", [typeof(int).MakeByRefType(), typeof(int).MakeByRefType()]);
    if (bounds != null)
    {
        object[] arguments = [0, 0];
        bounds.Invoke(native, arguments);
        var first = Math.Min((int)arguments[0], (int)arguments[1]);
        var last = Math.Max((int)arguments[0], (int)arguments[1]);
        var text = (string)type.GetProperty("Text").GetValue(control);
        var selected = new StringBuilder();
        var position = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (position >= first && position < last)
                selected.Append(rune.ToString());
            position++;
        }
        nativeText = selected.ToString();
    }
    return JsonSerializer.Serialize(new { NativeText = nativeText, FrameworkSelectedText = frameworkText });
}
#EndCSharp

OnError((err, mode) => PortableSmoke.OnError(err, mode))
OnExit((*) => PortableSmoke.CleanUp())
SetTimer(() => PortableSmoke.Fail("Timed out after 25 seconds."), -25000)
PortableSmoke.Run()

class PortableSmoke {
    static Folder := "", File := "", Started := A_TickCount

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Mark(message) => FileAppend("PASS PORTABLE_SMOKE " message "`n", "*")

    static Run() {
        SetWinDelay(-1)
        PortableSmoke.Isolate()
        PortableSmoke.Configure()
        I18n.Init("en")
        Knowledge.Load()
        Usage.Load()
        ThemeManager.Load("Light")
        preview := ThemePreview.ForName("Light", 112, 76)
        PortableSmoke.Assert(preview.Width = 112 && preview.Height = 76, "The theme preview has incorrect dimensions.")
        preview.Dispose()
        previews := IL_Create(1, 1, true)
        try PortableSmoke.Assert(ThemePreview.AddTo(previews, "Light", 112, 76) = 0, "The theme preview was not added to its image list.")
        finally IL_Destroy(previews)
        PortableSmoke.Mark("portable theme preview")
        ProviderRegistry.Providers := []
        for provider in [ClipboardProvider, ApplicationProvider, CustomCommandProvider, SnippetProvider, SystemProvider
            , CalculatorProvider, WebSearchProvider, BookmarkProvider, WindowProvider, ScriptProvider
            , FileSearchProvider, TerminalProvider, HelpProvider, RecentProvider]
            ProviderRegistry.Register(provider)
        ProviderRegistry.InitAll()
        PortableSmoke.Assert(ProviderRegistry.Providers.Length = 14, "The provider registry was not initialized.")
        PortableSmoke.Assert(SystemProvider.Commands().Length > 0, "The system provider has no commands.")
        PortableSmoke.Mark("providers initialized")

        SearchWindow.Create()
        SearchWindow.Show("2 + 2", false)
        PortableSmoke.Assert(SearchWindow.IsVisible(), "The search window did not show.")
        PortableSmoke.Assert(SearchWindow.Results.Length > 0, "The calculator search returned no rows.")
        PortableSmoke.Assert(SearchWindow.Results[1].Title == "4", "The calculator result was not 4.")
        PortableSmoke.Assert(SearchWindow.List.GetCount() > 0, "The result ListView has no rows.")
        PortableSmoke.Assert(SearchWindow.List.GetText(1, 1) == "4", "The result ListView did not contain actual calculator text.")
        PortableSmoke.Mark("calculator ListView text")

        SearchWindow.Input.Value := "hello world"
        Platform.SelectEdit(SearchWindow.Input, 2, 5)
        selection := Platform.EditSelection(SearchWindow.Input)
        PortableSmoke.Assert(selection.Start = 2 && selection.End = 5, "Edit selection did not round trip.")
        Platform.SelectEdit(SearchWindow.Input, 11, 11)
        PortableSmoke.Assert(Platform.EditCaret(SearchWindow.Input) = 11, "The edit caret did not round trip.")
        PortableSmoke.Mark("edit selection")
        unicode := "A" Chr(0x1F600) "B"
        PortableSmoke.Assert(StrLen(unicode) = 4, "The Unicode test requires UTF-16 script offsets.")
        PortableSmoke.Assert(Url.Encode(unicode) == "A%F0%9F%98%80B", "URL encoding did not preserve supplementary Unicode.")
        SearchWindow.Input.Value := unicode
        Platform.SelectEdit(SearchWindow.Input, 1, 3)
        selection := Platform.EditSelection(SearchWindow.Input)
        PortableSmoke.Assert(selection.Start = 1 && selection.End = 3, "Unicode edit selection did not return UTF-16 offsets.")
        selectionReport := ALTRunSmokeSelectionReport(SearchWindow.Input.ToClr())
        selected := JSON.Parse(selectionReport)
        PortableSmoke.Assert(selected["NativeText"] == Chr(0x1F600), "Native edit selection did not select exactly the emoji: " selectionReport)
        FileAppend("INFO PORTABLE_SMOKE native Unicode selection " selectionReport "`n", "*")
        Platform.SelectEdit(SearchWindow.Input, StrLen(unicode), StrLen(unicode))
        selection := Platform.EditSelection(SearchWindow.Input)
        PortableSmoke.Assert(selection.Start = 4 && selection.End = 4 && Platform.EditCaret(SearchWindow.Input) = 4, "The Unicode edit caret did not reach the UTF-16 end.")
        PortableSmoke.Mark("Unicode edit selection and caret")

        SearchWindow.ShowActions(ResultItem("Portable text", "", {Kind: "text", Arg: "portable text"}))
        PortableSmoke.Assert(SearchWindow.Mode == "actions", "The action panel did not open.")
        PortableSmoke.Assert(SearchWindow.Results.Length > 0 && SearchWindow.List.GetText(1, 1) != "", "The action panel has no readable rows.")
        SearchWindow._CloseActions()
        PortableSmoke.Mark("action panel")

        SearchWindow.Show(Platform.Join(PortableSmoke.Folder, "Files") A_DirSeparator, false)
        found := false
        for index, item in SearchWindow.Results {
            if (item.Arg == PortableSmoke.File && item.Title == "note.txt") {
                found := true
                PortableSmoke.Assert(index <= SearchWindow.List.GetCount(), "The temporary file was not visible.")
                PortableSmoke.Assert(SearchWindow.List.GetText(index, 1) == "note.txt", "The temporary file's displayed title was incorrect.")
                SearchWindow.Selected := index
                PortableSmoke.Assert(SearchWindow.ToggleMark() && SearchWindow.IsMarked(item), "The file could not be marked.")
                break
            }
        }
        PortableSmoke.Assert(found, "Folder browsing did not return the isolated temporary file.")
        SearchWindow.Hide()
        PortableSmoke.Mark("file browser and marking")

        PreferencesWindow.Show("Prefs.Page.General")
        PortableSmoke.Assert(PreferencesWindow.Pages.Length = PreferencesWindow.PageKeys.Length, "Preferences pages were not built.")
        controls := 0
        for page in PreferencesWindow.Pages
            controls += page.Controls.Length
        PortableSmoke.Assert(controls >= 80 && PreferencesWindow.Binds.Length >= 30, "Preferences controls did not bind meaningful settings.")
        PortableSmoke.Assert(PreferencesWindow._lists.Has("CustomCommands"), "The custom command editor was not built.")
        PreferencesWindow._SelectRow(PreferencesWindow._PageIndex("Prefs.Page.Commands"))
        PortableSmoke.Assert(PreferencesWindow._lists["CustomCommands"].Items.Length = 1, "The command editor did not load settings.")
        fields := [ItemEditor.Field("Type", "Prefs.Col.Type", "choice", false, [["File", "File"], ["Folder", "Folder"]])
            , ItemEditor.Field("Target", "Prefs.Col.Target", "file", true)]
        editorItem := ItemEditor.WithDefaults(Map("Title", "Unicode " Chr(0x1F600)), Map("Type", "Folder", "Target", PortableSmoke.Folder))
        PortableSmoke.Assert(editorItem["Title"] == "Unicode " Chr(0x1F600) && editorItem["Type"] == "Folder", "Editor defaults did not preserve structured item data.")
        PortableSmoke.Assert(ItemEditor._ChoiceIndex(fields[1].Choices, editorItem["Type"]) = 2, "Editor choices did not resolve the stored value.")
        controlsForFields := Map("Type", {Value: 2})
        PortableSmoke.Assert(ItemEditor.KindFor(["Type", "Folder"], fields, controlsForFields) == "folder", "The structured editor did not select the folder field kind.")
        PreferencesWindow.Gui.Hide()
        PreferencesWindow.Close()
        PortableSmoke.Mark("preferences and command editor")

        AppSettings.General["HistorySize"] := 17
        JSON.WriteFile(AppSettings.File, AppSettings.Data)
        PortableSmoke.Assert(FileExist(AppSettings.File), "JSON settings were not saved.")
        AppSettings.Data := Map()
        AppSettings.Load()
        PortableSmoke.Assert(AppSettings.General["HistorySize"] = 17, "JSON settings did not reload.")
        PortableSmoke.Assert(AppSettings.CustomCommands.Length = 1 && AppSettings.CustomCommands[1]["Target"] == PortableSmoke.File, "Custom command settings did not round trip.")
        PortableSmoke.Mark("JSON settings round trip")

        PortableSmoke.Processes()
        PortableSmoke.Mark("complete " (A_TickCount - PortableSmoke.Started) "ms")
        ExitApp(0)
    }

    static Isolate() {
        root := Platform.FullPath("..", A_ScriptDir)
        PortableSmoke.Folder := Platform.Join(A_Temp, "ALTRun-PortableSmoke-" Platform.NewUuid())
        for name in ["Data", "Files", "Applications", "Scripts", "Themes"]
            DirCreate(Platform.Join(PortableSmoke.Folder, name))
        PortableSmoke.File := Platform.Join(PortableSmoke.Folder, "Files", "note.txt")
        FileAppend("Portable launcher smoke test.`n", PortableSmoke.File, "UTF-8")
        AppSettings.Portable := false
        AppSettings.UserDir := PortableSmoke.Folder
        AppSettings.DataDir := Platform.Join(PortableSmoke.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.LegacyFile := Platform.Join(PortableSmoke.Folder, "Legacy.json")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        Usage.File := Platform.Join(AppSettings.DataDir, "Usage.json")
        FileIndex.File := Platform.Join(AppSettings.DataDir, "FileIndex.json")
        ApplicationProvider.IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
        ClipboardProvider.File := Platform.Join(AppSettings.DataDir, "ClipboardHistory.json")
        ClipboardProvider.LocalDir := Platform.Join(PortableSmoke.Folder, "Clipboard")
        ScriptProvider.Folder := Platform.Join(PortableSmoke.Folder, "Scripts")
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(root, "Resources", "Themes")
        ThemeManager.UserDir := Platform.Join(PortableSmoke.Folder, "Themes")
        App.IconFile := Platform.Join(root, "Resources", "ALTRun.ico")
        Logger.Enabled := false
    }

    static Configure() {
        AppSettings.Data := AppSettings.Defaults()
        general := AppSettings.General
        for key in ["Hotkey", "SecondaryHotkey", "SelectionHotkey", "DoubleTap", "CapsLock"]
            general[key] := ""
        for key in ["LaunchAtLogin", "ShowTrayIcon", "HideOnDeactivate", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut", "CheckForUpdates", "SaveLog"]
            general[key] := 0
        general["Language"] := "en"
        AppSettings.Appearance["Theme"] := "Light"
        AppSettings.Appearance["ShowOn"] := "Primary"
        AppSettings.Appearance["RememberPosition"] := 0
        for name in ["Clipboard", "Bookmarks", "Windows"]
            AppSettings.Feature(name)["Enabled"] := 0
        clipboardOptions := AppSettings.Feature("Clipboard")
        for key in ["Persist", "Images", "LocalFiles", "MergeDoubleCopy"]
            clipboardOptions[key] := 0
        clipboardOptions["Hotkey"] := ""
        AppSettings.Feature("Calculator")["Currency"] := 0
        AppSettings.Feature("Snippets")["AutoExpand"] := 0
        applications := AppSettings.Feature("Applications")
        applications["Folders"] := [Platform.Join(PortableSmoke.Folder, "Applications")]
        applications["FileTypes"] := ["*.txt"]
        applications["Depth"] := 1
        applications["StoreApps"] := 0
        applications["RefreshMinutes"] := 0
        files := AppSettings.Feature("FileSearch")
        files["UseEverything"] := 0
        files["ScopeFolders"] := [Platform.Join(PortableSmoke.Folder, "Files")]
        files["ScopeDepth"] := 1
        files["MaxEntries"] := 16
        files["RefreshMinutes"] := 0
        for name in ["QuickSwitch", "AutoDate", "PTTools"]
            AppSettings.Extension(name)["Enabled"] := 0
        AppSettings.Data["Hotkeys"] := []
        AppSettings.Data["CustomCommands"] := [Map("Title", "Smoke command", "Type", "File", "Target", PortableSmoke.File, "Arguments", "", "Keyword", "smoke-command")]
    }

    static Processes() {
        if Platform.IsWindows {
            executable := EnvGet("ComSpec")
            arguments := ["/d", "/c", "echo portable-output & echo portable-error 1>&2 & exit /b 7"]
        } else {
            executable := "/bin/sh"
            arguments := ["-c", "printf portable-output; printf portable-error >&2; exit 7"]
        }
        job := ProcessRunner.Start(executable, arguments, PortableSmoke.Folder, true)
        started := A_TickCount
        while !ProcessRunner.IsFinished(job) {
            if (A_TickCount - started > 5000) {
                ProcessRunner.Finish(job, true)
                throw Error("The captured process did not finish within five seconds.")
            }
            Sleep(10)
        }
        output := ProcessRunner.Finish(job)
        PortableSmoke.Assert(InStr(output, "portable-output") && InStr(output, "portable-error"), "The process runner did not capture both output streams.")
        failed := false
        try ProcessRunner.Start(Platform.Join(PortableSmoke.Folder, "missing-executable"), [], "", true)
        catch
            failed := true
        PortableSmoke.Assert(failed, "A missing executable did not report a launch error.")
        PortableSmoke.Mark("process completion, capture and launch error")
    }

    static CleanUp() {
        try ProcessRunner.CancelAll()
        try PreferencesWindow.Close()
        try SearchWindow.Hide()
        try SearchWindow.Gui.Destroy()
        try IconCache.Clear()
        try {
            if (PortableSmoke.Folder != "" && InStr(PortableSmoke.Folder, "ALTRun-PortableSmoke-") && DirExist(PortableSmoke.Folder))
                DirDelete(PortableSmoke.Folder, true)
        }
    }

    static OnError(err, mode) {
        FileAppend("FAIL PORTABLE_SMOKE " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_SMOKE " message "`n", "**")
        ExitApp(1)
    }
}

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

MsgBox(args*) {
    throw Error("Unexpected portable UI dialog: " (args.Length ? args[1] : ""))
}
InputBox(args*) {
    throw Error("Unexpected portable UI input dialog.")
}
FileSelect(args*) {
    throw Error("Unexpected portable UI file picker.")
}

class PortableSmoke {
    static Folder := "", File := "", Started := A_TickCount
    static PrefetchChecks := 0

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
        ThemeManager.Load("Light", "Compact")
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
        PortableSmoke.Assert(SearchWindow.RowHeight = ThemeManager.Get("RowHeight") && SearchWindow.IconSize = ThemeManager.Get("IconSize"), "The portable layout ignored theme density.")
        SearchWindow.Show("2 + 2", false)
        PortableSmoke.Assert(SearchWindow.IsVisible(), "The search window did not show.")
        PortableSmoke.Assert(SearchWindow.Results.Length > 0, "The calculator search returned no rows.")
        PortableSmoke.Assert(SearchWindow.Results[1].Title == "4", "The calculator result was not 4.")
        PortableSmoke.AssertRenderedRow(1, "4")
        if (Platform.IsWindows || (Platform.IsLinux && !Platform.IsWayland)) {
            WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " SearchWindow.Gui.Hwnd)
            nativeScale := LauncherCanvas.ScreenScale(SearchWindow.Gui)
            PortableSmoke.Assert(Abs(windowWidth - Round(SearchWindow.Width * nativeScale)) <= 4 * nativeScale, "The visible launcher width does not match its display scale.")
            area := SearchWindow._ScreenArea(AppSettings.Appearance["ShowOn"])
            PortableSmoke.Assert(windowX >= area.Left - 4 && windowY >= area.Top - 4
                && windowX + windowWidth <= area.Right + 4 && windowY + windowHeight <= area.Bottom + 4, "The visible launcher extends beyond its screen work area.")
        }
        PortableSmoke.Mark("calculator painted row, image and hit testing")
        PortableSmoke.FooterNavigation()
        Platform.SelectEdit(SearchWindow.Input, 0, StrLen(SearchWindow.Input.Value))
        previousResults := SearchWindow.Results
        SearchWindow.Show("", false)
        selection := Platform.EditSelection(SearchWindow.Input)
        PortableSmoke.Assert(SearchWindow.Input.Value == "2 + 2" && SearchWindow.Results == previousResults && selection.Start = 0 && selection.End = 5, "Showing an open window changed its query, results or selection.")
        AppSettings.Appearance["Placeholder"] := "Find something"
        PortableSmoke.Assert(SearchWindow.Placeholder() == "Find something", "The custom placeholder was ignored.")
        AppSettings.Appearance["Placeholder"] := " "
        PortableSmoke.Assert(SearchWindow.Placeholder() == "", "A blank placeholder was not preserved.")
        AppSettings.Appearance["Placeholder"] := ""
        PortableSmoke.Navigation()
        PortableSmoke.Mark("density, visible query, placeholder and keyboard contracts")

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
        PortableSmoke.Assert(SearchWindow.Results.Length > 0, "The action panel has no rows.")
        PortableSmoke.AssertRenderedRow(1, SearchWindow.Results[1].Title)
        SearchWindow._CloseActions()
        PortableSmoke.Mark("action panel")

        SearchWindow.Show(Platform.Join(PortableSmoke.Folder, "Files") A_DirSeparator, false)
        found := false
        for index, item in SearchWindow.Results {
            if (item.Arg == PortableSmoke.File && item.Title == "note.txt") {
                found := true
                PortableSmoke.AssertRenderedRow(index - SearchWindow.Offset, "note.txt")
                SearchWindow.Selected := index
                PortableSmoke.Assert(SearchWindow.ToggleMark() && SearchWindow.IsMarked(item), "The file could not be marked.")
                break
            }
        }
        PortableSmoke.Assert(found, "Folder browsing did not return the isolated temporary file.")
        SearchWindow._SetFileMode(true)
        found := false
        for item in SearchWindow.Results {
            PortableSmoke.Assert(item.Provider == FileSearchProvider.Id, "File mode included another provider.")
            if (item.Arg == PortableSmoke.File)
                found := true
        }
        PortableSmoke.Assert(SearchWindow.FileMode && found, "File mode did not search the isolated folder.")
        SearchWindow._SetFileMode(false)
        SearchWindow.Hide()
        PortableSmoke.Mark("file browser, file mode and marking")
        PortableSmoke.BackgroundIcons()
        PortableSmoke.Actions()

        PreferencesWindow.Show("Prefs.Page.General")
        initialPreferencesBounds := PortableSmoke.PreferenceBounds()
        PortableSmoke.Assert(PreferencesWindow.Pages.Length = PreferencesWindow.PageKeys.Length, "Preferences pages were not built.")
        controls := 0
        for page in PreferencesWindow.Pages
            controls += page.Controls.Length
        PortableSmoke.Assert(controls >= 80 && PreferencesWindow.Binds.Length >= 30, "Preferences controls did not bind meaningful settings.")
        PortableSmoke.Assert(PreferencesWindow._lists.Has("CustomCommands"), "The custom command editor was not built.")
        PortableSmoke.Assert(PreferencesWindow._lists.Has("Hotkeys"), "The schema's custom hotkeys editor was not built.")
        bindings := Map()
        for bind in PreferencesWindow.Binds
            bindings[bind.Path] := bind.Read.Call()
        PortableSmoke.Assert(bindings["Features.Snippets.ExpandExclude"] is Array, "Snippet window exclusions lost their array shape.")
        PortableSmoke.Assert(bindings["Features.Snippets.PasteMode"] == "Auto", "The snippet Auto paste mode was changed by opening Preferences.")
        for path in ["Features.Clipboard.MaxItems", "Features.Clipboard.IgnoreApps", "Features.Windows.Enabled", "Features.Windows.Keyword", "Features.Bookmarks.Enabled", "Features.Bookmarks.Keyword", "Appearance.Density", "Appearance.Placeholder", "General.TabKey"]
            PortableSmoke.Assert(bindings.Has(path), "Preferences has no binding for " path)
        if Platform.IsMac
            PortableSmoke.Assert(bindings.Has("General.LaunchAtLogin"), "macOS Preferences has no launch-at-login setting.")
        PortableSmoke.Assert(!bindings.Has("Features.Applications.RefreshMinutes"), "Preferences retained the obsolete application refresh setting.")
        PreferencesWindow._SelectRow(PreferencesWindow._PageIndex("Prefs.Page.Commands"))
        PortableSmoke.Assert(PreferencesWindow._lists["CustomCommands"].Items.Length = 1, "The command editor did not load settings.")
        fields := [ItemEditor.Field("Type", "Prefs.Col.Type", "choice", false, [["File", "File"], ["Folder", "Folder"]])
            , ItemEditor.Field("Target", "Prefs.Col.Target", "file", true)]
        editorItem := ItemEditor.WithDefaults(Map("Title", "Unicode " Chr(0x1F600)), Map("Type", "Folder", "Target", PortableSmoke.Folder))
        PortableSmoke.Assert(editorItem["Title"] == "Unicode " Chr(0x1F600) && editorItem["Type"] == "Folder", "Editor defaults did not preserve structured item data.")
        PortableSmoke.Assert(ItemEditor._ChoiceIndex(fields[1].Choices, editorItem["Type"]) = 2, "Editor choices did not resolve the stored value.")
        controlsForFields := Map("Type", {Value: 2})
        PortableSmoke.Assert(ItemEditor.KindFor(["Type", "Folder"], fields, controlsForFields) == "folder", "The structured editor did not select the folder field kind.")
        PortableSmoke.PreferenceGeometry(initialPreferencesBounds)
        PreferencesWindow.Gui.Hide()
        PreferencesWindow.Close()
        PortableSmoke.Mark("preferences and command editor")

        AppSettings.General["HistorySize"] := 17
        JSON.WriteFile(AppSettings.File, AppSettings.Data)
        PortableSmoke.Assert(FileExist(AppSettings.File), "JSON settings were not saved.")
        previousCritical := A_IsCritical
        Critical("On")
        try {
            AppSettings.Data := Map()
            AppSettings.Load()
        } finally Critical(previousCritical)
        PortableSmoke.Assert(AppSettings.General["HistorySize"] = 17, "JSON settings did not reload.")
        PortableSmoke.Assert(AppSettings.CustomCommands.Length = 1 && AppSettings.CustomCommands[1]["Target"] == PortableSmoke.File, "Custom command settings did not round trip.")
        PortableSmoke.Mark("JSON settings round trip")

        Hud.Show(" `t`n")
        PortableSmoke.Assert(!IsObject(Hud.Gui), "An empty HUD message created a window.")
        Hud.Show("Synthetic notice`nSaved and ready.", 5000)
        PortableSmoke.Assert(IsObject(Hud.Gui) && IsObject(Hud.Picture), "The HUD did not create its painted notice.")
        Hud.Picture.GetPos(, , &noticeWidth, &noticeHeight)
        PortableSmoke.Assert(noticeWidth > 0 && noticeHeight > 0 && Hud._lines.Length = 2, "The HUD did not lay out its actual message.")
        Hud.Hide()
        Hud.Hide()
        PortableSmoke.Assert(!IsObject(Hud.Gui) && !IsObject(Hud.Picture), "The HUD retained its window after hiding.")
        PortableSmoke.Mark("painted HUD, multiline layout and disposal")

        PortableSmoke.Processes()
        PortableSmoke.Mark("complete " (A_TickCount - PortableSmoke.Started) "ms")
        ExitApp(0)
    }

    static AssertRenderedRow(visibleIndex, title) {
        PortableSmoke.Assert(SearchWindow.Canvas.Visible && IsObject(SearchWindow.Frame), "The launcher has no visible painted canvas.")
        PortableSmoke.Assert(visibleIndex >= 1 && visibleIndex <= SearchWindow.RowModel.Length, "The result has no visible painted row.")
        row := SearchWindow.RowModel[visibleIndex]
        PortableSmoke.Assert(row.Title == title && row.Index = SearchWindow.Offset + visibleIndex, "The painted row does not match its result.")
        PortableSmoke.Assert(row.Width > 0 && row.Height > 0, "The painted row has empty bounds.")
        PortableSmoke.Assert(SearchWindow.RowAt(row.X + row.Width // 2, row.Y + row.Height // 2) = visibleIndex, "The row's hit test did not match its painted bounds.")
        PortableSmoke.Assert(SearchWindow.RowAt(-1, -1) = 0, "The row hit test accepted coordinates outside the canvas.")
        rasterScale := SearchWindow.Frame.Width / SearchWindow.Width
        sampleX := Round((row.X + 4) * rasterScale)
        sampleY := Round((row.Y + row.Height // 2) * rasterScale)
        PortableSmoke.Assert(SearchWindow.Frame.Width >= Round((row.X + row.Width) * rasterScale)
            && SearchWindow.Frame.Height > sampleY, "The result row extends beyond its rendered image.")
        PortableSmoke.Assert((SearchWindow.Frame.GetPixel(sampleX, sampleY) & 0xFFFFFF) = Integer("0x" row.Background), "The displayed row background does not match its selection state.")
    }

    static PreferenceBounds() {
        Sleep(25)
        PreferencesWindow.Gui.GetClientPos(&clientX, &clientY, &clientWidth, &clientHeight)
        PreferencesWindow.Gui.GetPos(&outerX, &outerY, &outerWidth, &outerHeight)
        return {ClientWidth: clientWidth, ClientHeight: clientHeight, OuterWidth: outerWidth, OuterHeight: outerHeight}
    }

    static AssertPreferenceBounds(expected, actual, operation) {
        for dimension in ["ClientWidth", "ClientHeight", "OuterWidth", "OuterHeight"]
            PortableSmoke.Assert(expected.%dimension% = actual.%dimension%, operation " changed " dimension " from " expected.%dimension% " to " actual.%dimension%)
    }

    static PreferenceGeometry(initialBounds) {
        baselines := Map("Prefs.Page.General", initialBounds, "Prefs.Page.Commands", PortableSmoke.PreferenceBounds())
        for pageKey in ["Prefs.Page.Appearance", "Prefs.Page.General", "Prefs.Page.Commands", "Prefs.Page.Appearance", "Prefs.Page.General"] {
            pageIndex := PreferencesWindow._PageIndex(pageKey)
            PreferencesWindow._SelectRow(pageIndex)
            selectedBounds := PortableSmoke.PreferenceBounds()
            PortableSmoke.Assert(selectedBounds.OuterWidth = initialBounds.OuterWidth, "Selecting " pageKey " changed the Preferences outer width from " initialBounds.OuterWidth " to " selectedBounds.OuterWidth)
            if baselines.Has(pageKey)
                PortableSmoke.AssertPreferenceBounds(baselines[pageKey], selectedBounds, "Returning to " pageKey)
            else
                baselines[pageKey] := selectedBounds
            PreferencesWindow.SelectPage(pageIndex)
            PortableSmoke.AssertPreferenceBounds(selectedBounds, PortableSmoke.PreferenceBounds(), "Selecting " pageKey " again")
        }
        PreferencesWindow.Show("Prefs.Page.General")
        PortableSmoke.AssertPreferenceBounds(baselines["Prefs.Page.General"], PortableSmoke.PreferenceBounds(), "Showing the existing Preferences window")
        PortableSmoke.Mark("preferences client and outer geometry across sidebar selections and repeated Show")
    }

    static FooterNavigation() {
        PortableSmoke.Assert(SearchWindow.FooterHeight > 0, "The test launcher has no clickable footer.")
        footerY := SearchWindow._WindowHeight(SearchWindow._VisibleCount()) - SearchWindow.FooterHeight / 2
        PortableSmoke.ClickCanvas(SearchWindow.Width - SearchWindow.Padding - 20, footerY)
        PortableSmoke.Assert(SearchWindow.Mode == "actions" && SearchWindow.SavedQuery == "2 + 2", "The footer's Actions region did not open the selected result's actions.")
        footerY := SearchWindow._WindowHeight(SearchWindow._VisibleCount()) - SearchWindow.FooterHeight / 2
        PortableSmoke.ClickCanvas(SearchWindow.Padding + 30, footerY)
        PortableSmoke.Assert(SearchWindow.Mode == "results" && SearchWindow.Input.Value == "2 + 2", "The footer's Back region did not restore the query.")
        PortableSmoke.AssertRenderedRow(1, "4")
        PortableSmoke.Mark("footer Actions and Back clicks through scaled canvas coordinates")
    }

    static ClickCanvas(x, y) {
        coordinateScale := Platform.IsWindows ? SearchWindow.Gui.PixelScale : 1
        encodedPoint := ((Round(y * coordinateScale) & 0xFFFF) << 16) | (Round(x * coordinateScale) & 0xFFFF)
        SearchWindow._CanvasDown(encodedPoint)
    }

    static Navigation() {
        items := [ResultItem("First"), ResultItem("Second"), ResultItem.KeywordHint("Find scripts", "script", "")]
        SearchWindow.SetResults(items)
        AppSettings.General["TabKey"] := "Next"
        SearchWindow.Selected := 3
        SearchWindow._TabKey()
        PortableSmoke.Assert(SearchWindow.Selected = 1, "Tab did not wrap to the first result.")
        SearchWindow._TabKey(false, true)
        PortableSmoke.Assert(SearchWindow.Selected = 3, "Shift+Tab did not wrap to the last result.")
        SearchWindow._TabKey(true)
        PortableSmoke.Assert(SearchWindow.Input.Value == "script ", "Ctrl+Tab did not complete the keyword hint.")
        AppSettings.General["TabKey"] := "Complete"
        SearchWindow._SetInput("caret")
        Platform.SelectEdit(SearchWindow.Input, 0, 5)
        PortableSmoke.Assert(!SearchWindow._CanOpenActions(), "Right arrow opened actions with selected text.")
        Platform.SelectEdit(SearchWindow.Input, 5, 5)
        PortableSmoke.Assert(SearchWindow._CanOpenActions() && !SearchWindow._CanOpenActions(0x40000000), "Right arrow did not reject key repeat.")
        SearchWindow._SetInput("2 + 2")
    }

    static BackgroundIcons() {
        SearchWindow.Show("2 + 2", false)
        IconCache.Clear()
        IconCache.Prefetch([App.IconFile, App.IconFile])
        PortableSmoke.Assert(IconCache.PrefetchPending = 1, "Icon prefetch did not deduplicate its sources.")
        IconCache._PrefetchStep()
        PortableSmoke.Assert(IconCache.PrefetchPending = 1, "Icon prefetch ran while the search window was visible.")
        SearchWindow.Hide()
        SearchWindow.PrepareEmpty()
        PortableSmoke.Assert(SearchWindow.IsPrepared(), "The hidden empty search was not prepared.")
        IconCache._PrefetchStep()
        PortableSmoke.Assert(!IconCache.PrefetchPending && IconCache._images.Count = 1, "Idle icon prefetch did not decode its image.")
        cache := Platform.Join(PortableSmoke.Folder, "Data", "portable-icons.json")
        PortableSmoke.Assert(IconCache.SaveDisk(cache), "The portable icon cache was not saved.")
        IconCache.Clear()
        busy := BackgroundWork.IsBusy
        previousCritical := A_IsCritical
        Critical("On")
        try {
            PortableSmoke.Assert(IconCache.LoadDisk(cache) = 1, "The portable icon cache did not restore its warmup list.")
            PortableSmoke.PrefetchChecks := 0
            BackgroundWork.IsBusy := () => PortableSmoke.ReenterPrefetch()
        } finally Critical(previousCritical)
        try IconCache._PrefetchStep()
        finally BackgroundWork.IsBusy := busy
        PortableSmoke.Assert(PortableSmoke.PrefetchChecks = 1, "Icon prefetch reentered while checking background work.")
        PortableSmoke.Assert(IconCache._images.Count = 1, "The restored icon warmup did not decode its image.")
        PortableSmoke.Mark("idle icon prefetch, cache warmup and hidden search preparation")
    }

    static ReenterPrefetch() {
        if (++PortableSmoke.PrefetchChecks = 1)
            IconCache._PrefetchStep()
        return false
    }

    static Actions() {
        item := ResultItem("note.txt", "", {Kind: "file", Arg: PortableSmoke.File})
        titles := Map()
        for action in ResultActions.ListFor(item)
            titles[action.Title] := true
        PortableSmoke.Assert(titles.Has(I18n.T("Action.CopyFile")), "The file actions cannot copy portable files.")
        if !Platform.IsWindows {
            for key in ["Action.CutFile", "Action.OpenWith", "Action.Properties", "Action.RunAsAdmin"]
                PortableSmoke.Assert(!titles.Has(I18n.T(key)), "A Windows action was offered on a portable platform: " key)
        }
        PortableSmoke.Assert(titles.Has(I18n.T("Action.Recycle")) = ActionCatalog.CanRecyclePath(PortableSmoke.File), "The trash action did not follow platform support.")
        AppSettings.Feature("LargeType")["Enabled"] := 0
        PortableSmoke.Assert(!LargeType.Enabled(), "Large Type ignored its disabled setting.")
        AppSettings.Feature("LargeType")["Enabled"] := 1
        offered := false
        for action in ResultActions.ListFor(item)
            if action.Title == I18n.T("Action.LargeType")
                offered := true
        PortableSmoke.Assert(LargeType.Enabled() && offered, "The enabled Large Type action was not offered.")
        AppSettings.Feature("LargeType")["Enabled"] := 0
        PortableSmoke.Mark("portable result actions and platform availability")
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
        AppSettings.Appearance["StatusBar"] := 1
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
        try Hud.Hide()
        try SearchWindow.Hide()
        if (SearchWindow._prepareTimer != "")
            SetTimer(SearchWindow._prepareTimer, 0)
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

; StartupSmoke.ahk - Real startup and second-process handoff with isolated data.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => StartupSmoke.OnError(err, mode))
if (A_Args.Length && A_Args[1] == "--handoff-child")
    StartupSmoke.Child()
else
    StartupSmoke.Run()

; Unexpected dialogs must fail the smoke test without waiting for desktop input.
MsgBox(args*) {
    throw Error("Unexpected startup dialog: " (args.Length ? args[1] : ""))
}
InputBox(args*) {
    throw Error("Unexpected startup input dialog.")
}
FileSelect(args*) {
    throw Error("Unexpected startup file picker.")
}

#CSharp
public static long ALTRunStartupChildExitCode(long Job)
{
    return ALTRunProcessJobs.TryGetValue(Job, out var job) && job.Process.HasExited
        ? job.Process.ExitCode : -1;
}
public static string ALTRunStartupChildStatus(long Job)
{
    return ALTRunProcessJobs.TryGetValue(Job, out var job)
        ? "PID " + job.Process.Id + (job.Process.HasExited ? " exited " + job.Process.ExitCode : " running")
        : "process job missing";
}
#EndCSharp

class StartupSmoke {
    static Folder := "", Started := A_TickCount, Stopped := false
    static ExitHandler := "", ChildJob := 0, Received := "", OriginalHandler := "", ShellCalls := 0

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Mark(message) => FileAppend("PASS STARTUP_SMOKE " message "`n", "*")

    static Child() {
        StartupSmoke.Assert(A_Args.Length = 3 && InStr(A_Args[2], "汉字 report`nsecond ' quote.txt"), "The child's Unicode/newline argument was changed.")
        marker := Platform.FullPath(A_Args[3])
        prefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-StartupSmoke-"))
        StartupSmoke.Assert(InStr(Platform.Identity(marker), Platform.Identity(prefix)) = 1, "The child marker is outside isolated test data.")
        FileAppend("Entered child: " A_ScriptFullPath "`n", marker, "UTF-8-RAW")
        StartupSmoke.Assert(App.HandOff(), "The child started another instance instead of handing off.")
        FileAppend("Acknowledged handoff.`n", marker, "UTF-8-RAW")
        ALTRunInstanceClose()
        FileAppend("PASS STARTUP_CHILD handed off`n", "*")
        ExitApp(0)
    }

    static Run() {
        StartupSmoke.ExitHandler := (*) => StartupSmoke.CleanUp()
        OnExit(StartupSmoke.ExitHandler)
        SetTimer(() => StartupSmoke.Fail("Timed out after 45 seconds."), -45000)
        StartupSmoke.Isolate()
        StartupSmoke.Configure()
        StartupSmoke.OriginalHandler := App.GetOwnPropDesc("_HandleCommandLine").Call
        App.DefineProp("_HandleCommandLine", {Call: (self, args, forwarded := false) => StartupSmoke.HandleArgs(args, forwarded)})
        App.DefineProp("_UpdateShellShortcuts", {Call: (*) => StartupSmoke.ShellCalls += 1})
        App.Start()
        OnExit(StartupSmoke.ExitHandler, 0)
        OnExit(StartupSmoke.ExitHandler)
        StartupSmoke.Assert(ProviderRegistry.Providers.Length = 14, "App.Start did not register every provider.")
        StartupSmoke.Assert(StartupSmoke.ShellCalls = 1, "App.Start did not reach shell integration setup.")
        StartupSmoke.Assert(A_IconHidden, "The startup configuration did not suppress the tray icon.")
        StartupSmoke.Assert(SearchWindow.IsVisible(), "App.Start did not show its search window.")
        StartupSmoke.Assert(AppSettings.General["Language"] == "en" && ThemeManager.Resolved == "Light", "App.Start did not load the configured language and theme.")
        SearchWindow.Show("2 + 2", false)
        StartupSmoke.Assert(SearchWindow.Results.Length > 0 && SearchWindow.Results[1].Title == "4", "The started application did not return the calculator result.")
        StartupSmoke.Assert(SearchWindow.List.GetCount() > 0, "The started application has no visible result rows.")
        StartupSmoke.Mark("real App.Start, settings, providers and result rows")
        Hud.Hide()
        SearchWindow.Hide()
        StartupSmoke.Assert(!SearchWindow.IsVisible(), "The search window could not be hidden before handoff.")

        payload := Platform.Join(StartupSmoke.Folder, "Files", "汉字 report`nsecond ' quote.txt")
        marker := Platform.Join(StartupSmoke.Folder, "child-progress.txt")
        arguments := ["--handoff-child", payload, marker]
        host := ProcessRunner.ScriptHost(A_ScriptFullPath, arguments)
#if WINDOWS && ALTRUN_PORTABLE_UI
        host.Arguments.InsertAt(host.Arguments.Length - arguments.Length, "--define:ALTRUN_PORTABLE_UI")
#endif
        StartupSmoke.ChildJob := ProcessRunner.Start(host.Executable, host.Arguments, StartupSmoke.Folder, true)
        started := A_TickCount
        while !ProcessRunner.IsFinished(StartupSmoke.ChildJob) {
            progress := FileExist(marker) ? FileRead(marker, "UTF-8") : "Child did not enter its script."
            StartupSmoke.Assert(A_TickCount - started < 35000, "The handoff child did not exit within 35 seconds: " ALTRunStartupChildStatus(StartupSmoke.ChildJob) "`n" progress)
            Sleep(20)
        }
        code := ALTRunStartupChildExitCode(StartupSmoke.ChildJob)
        output := ProcessRunner.Finish(StartupSmoke.ChildJob)
        StartupSmoke.ChildJob := 0
        StartupSmoke.Assert(code = 0 && InStr(output, "PASS STARTUP_CHILD handed off"), "The handoff child failed with exit code " code ": " output)
        started := A_TickCount
        while (StartupSmoke.Received = "" || !SearchWindow.IsVisible()) {
            StartupSmoke.Assert(A_TickCount - started < 2000, "The child received an ACK, but the original app did not handle its request: received=" StartupSmoke.Received ", visible=" SearchWindow.IsVisible())
            Sleep(20)
        }
        StartupSmoke.Assert(StartupSmoke.Received == JSON.Stringify(arguments), "The forwarded Unicode/newline arguments were changed.")
        StartupSmoke.Assert(SearchWindow.IsVisible(), "Handoff did not reopen the original search window.")
        StartupSmoke.Mark("second process forwards arguments and reopens original window")
        StartupSmoke.ShutDown()
        StartupSmoke.Assert(FileExist(Knowledge.File) && FileExist(Usage.File), "App shutdown did not save isolated learning and usage data.")
        StartupSmoke.Mark("real app shutdown saves isolated data")
        StartupSmoke.Mark("complete " (A_TickCount - StartupSmoke.Started) "ms")
        ExitApp(0)
    }

    static HandleArgs(args, forwarded) {
        if forwarded
            StartupSmoke.Received := JSON.Stringify(args)
        return StartupSmoke.OriginalHandler.Call(App, args, forwarded)
    }

    static Isolate() {
        root := Platform.FullPath("..", A_ScriptDir)
        StartupSmoke.Folder := Platform.Join(A_Temp, "ALTRun-StartupSmoke-" Platform.NewUuid())
        for name in ["Data", "Files", "Applications", "Scripts", "Themes"]
            DirCreate(Platform.Join(StartupSmoke.Folder, name))
        AppSettings.Portable := false
        AppSettings.UserDir := StartupSmoke.Folder
        AppSettings.DataDir := Platform.Join(StartupSmoke.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.LegacyFile := Platform.Join(StartupSmoke.Folder, "Legacy.json")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        Usage.File := Platform.Join(AppSettings.DataDir, "Usage.json")
        FileIndex.File := Platform.Join(AppSettings.DataDir, "FileIndex.json")
        ApplicationProvider.IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
        ClipboardProvider.File := Platform.Join(AppSettings.DataDir, "ClipboardHistory.json")
        ClipboardProvider.LocalDir := Platform.Join(StartupSmoke.Folder, "Clipboard")
        CurrencyRates.File := Platform.Join(AppSettings.DataDir, "Currency.json")
        UpdateChecker.StateFile := Platform.Join(AppSettings.DataDir, "Update.json")
        UpdateChecker.TempDir := Platform.Join(StartupSmoke.Folder, "Update")
        ScriptProvider.Folder := Platform.Join(StartupSmoke.Folder, "Scripts")
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(root, "Resources", "Themes")
        ThemeManager.UserDir := Platform.Join(StartupSmoke.Folder, "Themes")
        WebSearchProvider.BuiltinIconDir := Platform.Join(root, "Resources", "Icons", "Web")
        App.IconFile := Platform.Join(root, "Resources", "ALTRun.ico")
        Logger.File := Platform.Join(StartupSmoke.Folder, "ALTRun.log")
        Logger.Enabled := false
    }

    static Configure() {
        data := AppSettings.Defaults()
        general := data["General"]
        for key in ["Hotkey", "SecondaryHotkey", "SelectionHotkey", "DoubleTap", "CapsLock"]
            general[key] := ""
        for key in ["LaunchAtLogin", "ShowTrayIcon", "HideOnDeactivate", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut", "CheckForUpdates", "SaveLog"]
            general[key] := 0
        general["Language"] := "en"
        general["ShowTips"] := 0
        data["Appearance"]["Theme"] := "Light"
        data["Appearance"]["ShowOn"] := "Primary"
        data["Appearance"]["RememberPosition"] := 0
        for name in ["Clipboard", "Bookmarks", "Windows"]
            data["Features"][name]["Enabled"] := 0
        clipboardOptions := data["Features"]["Clipboard"]
        for key in ["Persist", "Images", "LocalFiles", "MergeDoubleCopy"]
            clipboardOptions[key] := 0
        clipboardOptions["Hotkey"] := ""
        data["Features"]["Calculator"]["Currency"] := 0
        data["Features"]["Snippets"]["AutoExpand"] := 0
        applications := data["Features"]["Applications"]
        applications["Folders"] := [Platform.Join(StartupSmoke.Folder, "Applications")]
        applications["FileTypes"] := ["*.txt"]
        applications["Depth"] := 1
        applications["StoreApps"] := 0
        applications["RefreshMinutes"] := 0
        files := data["Features"]["FileSearch"]
        files["UseEverything"] := 0
        files["ScopeFolders"] := [Platform.Join(StartupSmoke.Folder, "Files")]
        files["ScopeDepth"] := 1
        files["MaxEntries"] := 16
        for name in ["QuickSwitch", "AutoDate", "PTTools"]
            data["Extensions"][name]["Enabled"] := 0
        data["Hotkeys"] := []
        data["CustomCommands"] := []
        JSON.WriteFile(AppSettings.File, data)
    }

    static ShutDown() {
        if (StartupSmoke.Folder = "" || StartupSmoke.Stopped)
            return
        StartupSmoke.Stopped := true
        try App._OnExit()
        finally App.DefineProp("_OnExit", {Call: (*) => 0})
    }

    static CleanUp() {
        try StartupSmoke.ShutDown()
        try ProcessRunner.CancelAll()
        try PreferencesWindow.Close()
        try Hud.Hide()
        try SearchWindow.Hide()
        try SearchWindow.Gui.Destroy()
        try IconCache.Clear()
        try {
            folder := Platform.FullPath(StartupSmoke.Folder)
            prefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-StartupSmoke-"))
            if (StartupSmoke.Folder != "" && InStr(Platform.Identity(folder), Platform.Identity(prefix)) = 1 && DirExist(folder))
                DirDelete(folder, true)
        }
    }

    static OnError(err, mode) {
        StartupSmoke.Fail(err.Message "`n" err.Stack)
        return true
    }

    static Fail(message) {
        if StartupSmoke.ChildJob {
            try {
                message .= "`nHandoff child: " ALTRunStartupChildStatus(StartupSmoke.ChildJob)
                message .= "`n" ProcessRunner.Finish(StartupSmoke.ChildJob, true)
                StartupSmoke.ChildJob := 0
            }
        }
        FileAppend("FAIL STARTUP_SMOKE " message "`n", "**")
        ExitApp(1)
    }
}

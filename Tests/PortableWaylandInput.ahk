; Native Wayland input regression with desktop services deliberately unavailable.
; Run PortableWaylandInput.sh to use a private nested Cinnamon compositor.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PortableWaylandInput.Fail(err.Message "`n" err.Stack))
OnExit((*) => PortableWaylandInput.CleanUp())
SetTimer(() => PortableWaylandInput.Fail("Timed out after 60 seconds."), -60000)
PortableWaylandInput.Run()

MsgBox(args*) {
    throw Error("Unexpected Wayland fixture dialog.")
}

class PortableWaylandInput {
    static Folder := "", Other := "", OriginalSearch := "", Outer := "", Runs := 0, Executed := 0

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            PortableWaylandInput.Assert(A_TickCount - started < 4000, message)
            Sleep(10)
        }
    }

    static Xdo(arguments*) {
        for index, argument in arguments
            arguments[index] := String(argument)
        job := ProcessRunner.Start("xdotool", arguments, "", true)
        started := A_TickCount
        while !ProcessRunner.IsFinished(job) {
            if (A_TickCount - started > 2000) {
                ProcessRunner.Finish(job, true)
                throw Error("xdotool did not finish.")
            }
            Sleep(10)
        }
        return Trim(ProcessRunner.Finish(job))
    }

    static Key(keys*) {
        arguments := ["windowfocus", PortableWaylandInput.Outer, "key", "--clearmodifiers", "--delay", "30"]
        for key in keys
            arguments.Push(key)
        PortableWaylandInput.Xdo(arguments*)
        Sleep(50)
    }

    static Search() {
        if (SearchWindow.Mode = "actions")
            return PortableWaylandInput.OriginalSearch.Call(SearchWindow)
        SearchWindow.SetResults([
            ResultItem("First synthetic result", "", {OnRun: (*) => PortableWaylandInput.RunItem(1)}),
            ResultItem("Second synthetic result", "", {OnRun: (*) => PortableWaylandInput.RunItem(2)}),
            ResultItem("Third synthetic result", "", {OnRun: (*) => PortableWaylandInput.RunItem(3)})
        ])
    }

    static RunItem(index) {
        PortableWaylandInput.Executed := index
        PortableWaylandInput.Runs += 1
    }

    static Show(text := "Wayland query") {
        SearchWindow.Show(text)
        PortableWaylandInput.Xdo("windowfocus", PortableWaylandInput.Outer)
        PortableWaylandInput.WaitFor(() => SearchWindow.IsActive(), "Show did not acquire native Wayland focus.")
        PortableWaylandInput.Assert(SearchWindow.Gui.ToClr().Topmost, "Show lost the requested topmost trait.")
    }

    static Hidden() {
        PortableWaylandInput.WaitFor(() => !SearchWindow.IsVisible() && !SearchWindow.Gui.ToClr().Visible
            , "Dismissal did not hide the actual native window without desktop geometry.")
    }

    static FocusOther() {
        PortableWaylandInput.Other.Show("Restore w500 h300")
        PortableWaylandInput.Other.ToClr().ControlObject.Present()
        PortableWaylandInput.WaitFor(() => PortableWaylandInput.Other.ToClr().HasFocus
            , "The other native fixture window did not acquire focus.")
    }

    static Run() {
        PortableWaylandInput.Folder := EnvGet("ALTRUN_WAYLAND_TEST_DIR")
        if (!Platform.IsWayland || EnvGet("ALTRUN_WAYLAND_TEST") != "nested-cinnamon"
            || PortableWaylandInput.Folder = ""
            || EnvGet("KEYSHARP_DESKTOP_SOCKET") != PortableWaylandInput.Folder "/runtime/no-desktop.sock"
            || EnvGet("KEYSHARP_INPUT_SOCKET") != PortableWaylandInput.Folder "/runtime/no-input.sock") {
            FileAppend("SKIP PORTABLE_WAYLAND_INPUT Run Tests/PortableWaylandInput.sh for an isolated desktop.`n", "*")
            ExitApp()
        }
        PortableWaylandInput.Isolate()
        I18n.Init("en")
        Knowledge.Load()
        Usage.Load()
        ThemeManager.Load("Light", "Compact")
        PortableWaylandInput.OriginalSearch := SearchWindow.GetOwnPropDesc("_RunSearch").Call
        SearchWindow.DefineProp("_RunSearch", {Call: (self) => PortableWaylandInput.Search()})
        SearchWindow.Create()
        SearchWindow.Show("fixture setup")
        PortableWaylandInput.Outer := EnvGet("ALTRUN_WAYLAND_OUTER")
        PortableWaylandInput.Assert(RegExMatch(PortableWaylandInput.Outer, "^0x[\da-f]+$"), "Expected one nested Cinnamon X11 window: " PortableWaylandInput.Outer)
        PortableWaylandInput.Other := Gui("", "ALTRun Wayland other fixture")
        PortableWaylandInput.Other.AddEdit("x20 y20 w400 h40", "Other native window")

        for remember in [0, 1] {
            AppSettings.Appearance["RememberPosition"] := remember
            AppSettings.Appearance["ShowOn"] := remember ? "Mouse" : "Active"
            PortableWaylandInput.Show()
            previousRuns := PortableWaylandInput.Runs
            PortableWaylandInput.Key("ctrl+n")
            PortableWaylandInput.Assert(SearchWindow.Selected = 2, "Ctrl+N did not move exactly one row.")
            PortableWaylandInput.Key("Return")
            PortableWaylandInput.Hidden()
            PortableWaylandInput.Assert(PortableWaylandInput.Executed = 2 && PortableWaylandInput.Runs = previousRuns + 1
                , "Enter did not run exactly the selected action once.")

            PortableWaylandInput.FocusOther()
            PortableWaylandInput.Show("reopened query")
            PortableWaylandInput.Xdo("type", "--clearmodifiers", "--delay", "20", " typed")
            PortableWaylandInput.WaitFor(() => SearchWindow.Input.Value = "reopened query typed", "Native typing failed after Hide and Show.")
            SearchWindow._FooterMenu()
            PortableWaylandInput.Assert(SearchWindow.Mode = "actions" && SearchWindow.Results.Length = 6, "Footer actions did not open.")
            PortableWaylandInput.Key("Escape")
            PortableWaylandInput.Assert(SearchWindow.Mode = "results" && SearchWindow.IsVisible()
                && SearchWindow.Input.Value = "reopened query typed", "Escape did not restore the query from actions.")
            PortableWaylandInput.Key("Escape")
            PortableWaylandInput.Hidden()
            PortableWaylandInput.Assert(PortableWaylandInput.Runs = previousRuns + 1, "Escape unexpectedly ran an action.")

            PortableWaylandInput.Show("visible query")
            PortableWaylandInput.FocusOther()
            PortableWaylandInput.Show("")
            PortableWaylandInput.Key("ctrl+n", "Escape")
            PortableWaylandInput.Hidden()
            FileAppend("PASS PORTABLE_WAYLAND_INPUT native Ctrl+N, Enter, Escape and Hide/Show with RememberPosition=" remember
                " ShowOn=" AppSettings.Appearance["ShowOn"] " and unavailable desktop geometry`n", "*")
        }
        AppSettings.General["HideOnDeactivate"] := 1
        PortableWaylandInput.Show()
        PortableWaylandInput.WaitFor(() => SearchWindow._focusArmed, "Hide-on-deactivate did not arm.")
        PortableWaylandInput.FocusOther()
        PortableWaylandInput.Hidden()
        PortableWaylandInput.Show()
        PortableWaylandInput.Key("Escape")
        PortableWaylandInput.Hidden()
        FileAppend("PASS PORTABLE_WAYLAND_INPUT native focus recovery and hide-on-deactivate without desktop services`n", "*")
        ExitApp()
    }

    static Isolate() {
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        dataRoot := PortableWaylandInput.Folder "/app"
        DirCreate(dataRoot "/Data")
        App.Name := "ALTRun native Wayland fixture"
        App.IconFile := sourceRoot "/Resources/ALTRun.ico"
        AppSettings.Portable := false
        AppSettings.UserDir := dataRoot
        AppSettings.DataDir := dataRoot "/Data"
        AppSettings.File := dataRoot "/Data/ALTRun.json"
        Knowledge.File := dataRoot "/Data/Knowledge.json"
        Usage.File := dataRoot "/Data/Usage.json"
        I18n.LangDir := sourceRoot "/Resources/Lang"
        ThemeManager.BuiltinDir := sourceRoot "/Resources/Themes"
        ThemeManager.UserDir := dataRoot "/Themes"
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        for key in ["Hotkey", "SecondaryHotkey", "SelectionHotkey", "DoubleTap", "CapsLock"]
            AppSettings.General[key] := ""
        for key in ["LaunchAtLogin", "ShowTrayIcon", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut", "CheckForUpdates", "SaveLog", "ShowTips", "KeepLastQuery", "HideOnDeactivate"]
            AppSettings.General[key] := 0
        AppSettings.Appearance["ShowOn"] := "Primary"
        AppSettings.Feature("Clipboard")["Enabled"] := 0
        AppSettings.Feature("FileSearch")["Enabled"] := 0
        AppSettings.Feature("Calculator")["Currency"] := 0
    }

    static CleanUp() {
        try ProcessRunner.CancelAll()
        try SearchWindow.Gui.Destroy()
        try PortableWaylandInput.Other.Destroy()
        try IconCache.Clear()
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_WAYLAND_INPUT " message "`n", "**")
        ExitApp(1)
        return true
    }
}

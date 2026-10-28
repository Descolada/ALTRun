; Native macOS keyboard delivery to an owned, isolated launcher. No permission prompts.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Import Ks { RequestCapabilities }
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacInput.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacInput.CleanUp())
SetTimer(() => MacInput.Fail("Timed out after 25 seconds."), -25000)
MacInput.Run()

MsgBox(args*) {
    throw Error("Unexpected macOS input fixture dialog.")
}

class MacInput {
    static Folder := "", Executed := 0, Runs := 0, Modifier := "", Registered := false, HotkeyCalls := 0

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            MacInput.Assert(A_TickCount - started < 2500, message)
            Sleep(10)
        }
    }

    static Key(keys) {
        MacInput.Assert(SearchWindow.IsVisible() && SearchWindow.Gui.ToClr().HasFocus
            , "Refusing to send keys because the owned launcher is not focused.")
        SendEvent(keys)
        Sleep(100)
    }

    static Search() {
        items := []
        Loop 3 {
            index := A_Index
            items.Push(ResultItem("Synthetic result " index, "", {OnRun: MacInput.Handler(index)}))
        }
        SearchWindow.SetResults(items)
    }

    static Handler(index) => (*) => (MacInput.Executed := index, MacInput.Runs += 1)

    static Show() {
        SearchWindow.Show("alpha beta", false)
        MacInput.WaitFor(() => SearchWindow.Gui.ToClr().HasFocus, "The launcher did not acquire native focus.")
        Sleep(150)
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_INPUT macOS-only fixture.`n", "*")
            ExitApp(0)
        }
        capabilities := RequestCapabilities()
        if (capabilities.InputControl != "Granted" || capabilities.InputMonitoring != "Granted"
            || capabilities.WindowMonitoring != "Granted" || capabilities.WindowControl != "Granted") {
            FileAppend("SKIP MAC_INPUT input and window permissions must already be granted.`n", "*")
            ExitApp(0)
        }
        MacInput.Folder := Platform.Join(A_Temp, "ALTRun-MacInput-" Platform.NewUuid())
        DirCreate(MacInput.Folder)
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        App.Name := "ALTRun macOS input fixture"
        App.IconFile := Platform.Join(sourceRoot, "Resources", "ALTRun.ico")
        AppSettings.Data := AppSettings.Defaults()
        for key in ["HideOnDeactivate", "ShowTips", "KeepLastQuery"]
            AppSettings.General[key] := 0
        AppSettings.General["TabKey"] := "Next"
        Knowledge.File := Platform.Join(MacInput.Folder, "Knowledge.json")
        Usage.File := Platform.Join(MacInput.Folder, "Usage.json")
        I18n.LangDir := Platform.Join(sourceRoot, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(sourceRoot, "Resources", "Themes")
        ThemeManager.UserDir := MacInput.Folder
        Logger.Enabled := false
        I18n.Init("en")
        Knowledge.Load()
        Usage.Load()
        ThemeManager.Load("Dark", "Compact")
        SearchWindow.DefineProp("_RunSearch", {Call: (self) => MacInput.Search()})
        ActionCatalog.DefineProp("RunModifier", {Call: (self, item, modifier) => MacInput.Modifier := modifier})
        SearchWindow.Create()
        MacInput.Show()

        MacInput.Key("#a")
        selection := Platform.EditSelection(SearchWindow.Input)
        MacInput.Assert(selection.Start = 0 && selection.End = 10, "Command+A did not select the native search text.")
        MacInput.Key("{Right}")
        MacInput.Key("#{Left}")
        MacInput.Assert(Platform.EditCaret(SearchWindow.Input) = 0 && SearchWindow.Mode = "results", "Command+Left was intercepted instead of moving the native caret.")
        MacInput.Key("#{Right}")
        MacInput.Assert(Platform.EditCaret(SearchWindow.Input) = 10 && SearchWindow.Mode = "results", "Command+Right opened actions instead of moving the native caret.")
        FileAppend("PASS MAC_INPUT native Command+A and Command+Left/Right editing`n", "*")

        MacInput.Key("{Down}")
        MacInput.Assert(SearchWindow.Selected = 2, "Down did not move exactly one result.")
        MacInput.Key("{Tab}")
        MacInput.Assert(SearchWindow.Selected = 3, "Tab did not move exactly one result.")
        MacInput.Key("#2")
        MacInput.WaitFor(() => MacInput.Executed = 2 && !SearchWindow.IsVisible(), "Command+2 did not execute the second result.")
        MacInput.Assert(MacInput.Runs = 1, "Command+2 executed more than once.")
        MacInput.Show()
        MacInput.Key("#{Enter}")
        MacInput.WaitFor(() => MacInput.Modifier = "ctrl" && !SearchWindow.IsVisible(), "Command+Enter did not dispatch the result modifier action.")
        FileAppend("PASS MAC_INPUT native arrows, Tab, Command+digits and Command+Enter`n", "*")

        MacInput.Show()
        Hotkey("^!F18", (*) => MacInput.HotkeyCalls += 1)
        MacInput.Registered := true
        ; Quartz posts asynchronously; allow each modifier/key transition to reach the hook
        ; before posting its release so this checks event delivery rather than sender batching.
        SetKeyDelay(80, 80)
        SendLevel(1)
        try MacInput.Key("^!{F18}")
        finally SendLevel(0)
        MacInput.WaitFor(() => MacInput.HotkeyCalls = 1, "The registered global hotkey did not receive a native event.")
        Hotkey("^!F18", "Off")
        MacInput.Registered := false
        FileAppend("PASS MAC_INPUT global hotkey registration, event delivery and removal`n", "*")
        ExitApp(0)
    }

    static CleanUp() {
        if MacInput.Registered
            try Hotkey("^!F18", "Off")
        if IsObject(SearchWindow.Gui)
            try SearchWindow.Gui.Destroy()
        IconCache.Clear()
        if (MacInput.Folder != "" && InStr(Platform.FullPath(MacInput.Folder), Platform.FullPath(Platform.Join(A_Temp, "ALTRun-MacInput-")), true) = 1)
            try DirDelete(MacInput.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL MAC_INPUT " message "`n", "**")
        ExitApp(1)
        return true
    }
}

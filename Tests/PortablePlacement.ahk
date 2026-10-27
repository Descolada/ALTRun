; PortablePlacement.ahk - Preserve the search field's screen position as result rows resize.
; Run with Keysharp in a desktop session with working window geometry services.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PortablePlacement.Fail(err.Message "`n" err.Stack))
OnExit((*) => PortablePlacement.CleanUp())
SetTimer(() => PortablePlacement.Fail("Timed out after 20 seconds."), -20000)
PortablePlacement.Run()

MsgBox(args*) {
    throw Error("Unexpected placement fixture dialog.")
}

class PortablePlacement {
    static Folder := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Bounds() {
        WinGetPos(&x, &y, &width, &height, "ahk_id " SearchWindow.Gui.Hwnd)
        return {X: x, Y: y, Width: width, Height: height}
    }

    static Run() {
        SetWinDelay(-1)
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        PortablePlacement.Folder := Platform.Join(A_Temp, "ALTRun-PortablePlacement-" Platform.NewUuid())
        DirCreate(PortablePlacement.Folder)
        App.Name := "ALTRun placement fixture"
        App.IconFile := Platform.Join(sourceRoot, "Resources", "ALTRun.ico")
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.Appearance["RememberPosition"] := 0
        AppSettings.Appearance["ShowOn"] := "Primary"
        for key in ["HideOnDeactivate", "ShowTips", "KeepLastQuery"]
            AppSettings.General[key] := 0
        Knowledge.File := Platform.Join(PortablePlacement.Folder, "Knowledge.json")
        Usage.File := Platform.Join(PortablePlacement.Folder, "Usage.json")
        I18n.LangDir := Platform.Join(sourceRoot, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(sourceRoot, "Resources", "Themes")
        ThemeManager.UserDir := PortablePlacement.Folder
        Logger.Enabled := false
        I18n.Init("en")
        Knowledge.Load()
        Usage.Load()
        ThemeManager.Load("Light", "Compact")
        SearchWindow.DefineProp("_RunSearch", {Call: (self) => SearchWindow.SetResults([])})
        SearchWindow.Create()
        SearchWindow.Show("Synthetic placement query", false)
        Sleep(500)
        try original := PortablePlacement.Bounds()
        catch {
            FileAppend("SKIP PORTABLE_PLACEMENT Desktop window geometry is unavailable.`n", "*")
            ExitApp(0)
        }
        PortablePlacement.Assert(original.Width > 0 && original.Height > 0, "Desktop window geometry is empty.")
        slowest := 0
        for count in [SearchWindow.VisibleRows, 1, 4, 0, SearchWindow.VisibleRows, 0] {
            results := []
            Loop count
                results.Push(ResultItem("Synthetic result " A_Index, "Fixture path " A_Index))
            started := Platform.Milliseconds()
            SearchWindow.SetResults(results)
            slowest := Max(slowest, Platform.Milliseconds() - started)
            displayed := SearchWindow.Canvas.ToClr().Image
            PortablePlacement.Assert(displayed.Width = SearchWindow.Frame.Width && displayed.Height = SearchWindow.Frame.Height
                , count " rows: the displayed bitmap was resampled from " SearchWindow.Frame.Width "x" SearchWindow.Frame.Height
                " to " displayed.Width "x" displayed.Height " before hover.")
            Sleep(200)
            actual := PortablePlacement.Bounds()
            expectedHeight := Round(SearchWindow._WindowHeight(count) * SearchWindow._ScreenScale())
            PortablePlacement.Assert(Abs(actual.X - original.X) <= 1 && Abs(actual.Y - original.Y) <= 1
                , count " rows moved the search field from " original.X "," original.Y " to " actual.X "," actual.Y)
            PortablePlacement.Assert(Abs(actual.Height - expectedHeight) <= 4
                , count " rows: expected height " expectedHeight ", got " actual.Height)
            PortablePlacement.Assert(SearchWindow.RowModel.Length = count, "The rendered row count is incorrect.")
            if (count = SearchWindow.VisibleRows) {
                SearchWindow.Hide()
                SearchWindow.PrepareEmpty()
                SearchWindow.Show("", false)
                started := A_TickCount
                loop {
                    Sleep(10)
                    reopened := PortablePlacement.Bounds()
                    if (reopened.Height = original.Height || A_TickCount - started >= 2000)
                        break
                }
                PortablePlacement.Assert(SearchWindow.RowModel.Length = 0 && reopened.Height = original.Height
                    , "Reopening an empty query retained " reopened.Height "px of window height instead of " original.Height "px.")
            }
            PortablePlacement.Assert(SearchWindow.IsActive(), "Resizing lost search input focus.")
        }
        FileAppend("PASS PORTABLE_PLACEMENT fixed top-left, height, rows, native bitmap dimensions and focus; slowest result update " Round(slowest) "ms`n", "*")
        ExitApp(0)
    }

    static CleanUp() {
        try SearchWindow.Hide()
        if (SearchWindow._prepareTimer != "")
            SetTimer(SearchWindow._prepareTimer, 0)
        try SearchWindow.Gui.Destroy()
        try IconCache.Clear()
        if (PortablePlacement.Folder != "" && InStr(PortablePlacement.Folder, "ALTRun-PortablePlacement-"))
            try DirDelete(PortablePlacement.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_PLACEMENT " message "`n", "**")
        ExitApp(1)
        return true
    }
}

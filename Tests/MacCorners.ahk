; Native macOS window-corner transparency across themes, result resizing and reopening.
; Pass baseline to capture the old behavior without requiring transparent corners.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Import Ks { RequestCapabilities }
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacCorners.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacCorners.CleanUp())
SetTimer(() => MacCorners.Fail("Timed out after 30 seconds."), -30000)
MacCorners.Run()

MsgBox(args*) {
    throw Error("Unexpected corner fixture dialog.")
}

class MacCorners {
    static Folder := "", Output := "/tmp/ALTRun-macos-corners", Backdrop := "", Baseline := false, Entries := []
    static BackdropColor := 0x16CF83

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_CORNERS macOS-only fixture.`n", "*")
            ExitApp(0)
        }
        capabilities := RequestCapabilities()
        if (capabilities.ScreenCapture != "Granted" || capabilities.WindowMonitoring != "Granted") {
            FileAppend("SKIP MAC_CORNERS ScreenCapture and WindowMonitoring must already be granted.`n", "*")
            ExitApp(0)
        }
        MacCorners.Baseline := A_Args.Length && A_Args[1] = "baseline"
        MacCorners.Folder := Platform.Join(A_Temp, "ALTRun-MacCorners-" Platform.NewUuid())
        DirCreate(MacCorners.Folder), DirCreate(MacCorners.Output)
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        App.Name := "ALTRun corner fixture"
        App.IconFile := Platform.Join(sourceRoot, "Resources", "ALTRun.ico")
        AppSettings.Data := AppSettings.Defaults()
        for key in ["HideOnDeactivate", "ShowTips", "KeepLastQuery"]
            AppSettings.General[key] := 0
        AppSettings.Appearance["Width"] := 640
        AppSettings.Appearance["VisibleRows"] := 5
        AppSettings.Appearance["ShowOn"] := "Primary"
        AppSettings.Appearance["RememberPosition"] := 0
        Knowledge.File := Platform.Join(MacCorners.Folder, "Knowledge.json")
        Usage.File := Platform.Join(MacCorners.Folder, "Usage.json")
        I18n.LangDir := Platform.Join(sourceRoot, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(sourceRoot, "Resources", "Themes")
        ThemeManager.UserDir := MacCorners.Folder
        Logger.Enabled := false
        I18n.Init("en"), Knowledge.Load(), Usage.Load()
        SearchWindow.DefineProp("_RunSearch", {Call: (self, args*) => SearchWindow.SetResults([])})
        backdrop := Gui("-Caption +ToolWindow +AlwaysOnTop", "ALTRun solid corner backdrop")
        backdrop.BackColor := Format("{:06X}", MacCorners.BackdropColor)
        MacCorners.Backdrop := backdrop
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        backdrop.Show("NA x" left " y" top " w" (right - left) " h" (bottom - top))
        for themeName in ["Light", "Dark"] {
            ThemeManager.Load(themeName, "Compact")
            SearchWindow.Create()
            SearchWindow.Show("Corner fixture", false)
            for count in [0, 5, 0] {
                items := []
                Loop count
                    items.Push(ResultItem("Synthetic result " A_Index, "Window transparency fixture"))
                SearchWindow.SetResults(items)
                MacCorners.Capture(themeName, "rows-" count "-" A_Index)
            }
            backdrop.Show()
            Sleep(100)
            MacCorners.Capture(themeName, "inactive", false)
            SearchWindow.Hide()
            SearchWindow.Show("Reopened corner fixture", false)
            MacCorners.Capture(themeName, "reopened")
            SearchWindow.Hide()
        }
        JSON.WriteFile(Platform.Join(MacCorners.Output, MacCorners.Baseline ? "before.json" : "after.json"), MacCorners.Entries)
        FileAppend("PASS MAC_CORNERS " (MacCorners.Baseline ? "baseline captured" : "native transparent corners, themes, result resize, focus loss and reopening") "`n", "*")
        ExitApp(0)
    }

    static Capture(themeName, state, activate := true) {
        if activate
            SearchWindow.Gui.Show()
        Sleep(180)
        prefix := MacCorners.Baseline ? "before-" : "after-"
        name := prefix StrLower(themeName) "-" state
        captured := Image.FromWindow("ahk_id " SearchWindow.Gui.Hwnd)
        try {
            captured.Save(Platform.Join(MacCorners.Output, name ".png"))
            points := [[0, 0], [captured.Width - 1, 0], [0, captured.Height - 1], [captured.Width - 1, captured.Height - 1]]
            alphas := []
            for point in points {
                alpha := (captured.GetPixel(point[1], point[2]) >> 24) & 255
                alphas.Push(alpha)
                if !MacCorners.Baseline
                    MacCorners.Assert(alpha = 0, name ": native corner alpha was " alpha " instead of transparent.")
            }
            if !MacCorners.Baseline {
                scale := captured.Width / SearchWindow.Width
                for inset in [0, Round(scale), Round(2 * scale)] {
                    for point in [[inset, inset], [captured.Width - 1 - inset, inset]
                        , [inset, captured.Height - 1 - inset], [captured.Width - 1 - inset, captured.Height - 1 - inset]]
                        MacCorners.Assert(((captured.GetPixel(point[1], point[2]) >> 24) & 255) = 0
                            , name ": an opaque fringe remains outside the rounded corner at " point[1] "," point[2] ".")
                }
                MacCorners.Assert(((SearchWindow.Frame.GetPixel(0, 0) >> 24) & 255) = 0
                    , name ": the retained launcher bitmap still has an opaque square corner.")
                expectedHeight := Round(SearchWindow._WindowHeight(SearchWindow._VisibleCount()) * scale)
                MacCorners.Assert(Abs(captured.Height - expectedHeight) <= 2, name ": native content height changed while clipping corners.")
            }
            MacCorners.Assert(((captured.GetPixel(captured.Width // 2, captured.Height // 2) >> 24) & 255) = 255
                , name ": the launcher center became translucent.")
            MacCorners.Entries.Push(Map("Name", name, "Width", captured.Width, "Height", captured.Height, "CornerAlpha", alphas))
            FileAppend("INFO MAC_CORNERS " name " " captured.Width "x" captured.Height " alpha=" StrReplace(StrReplace(JSON.Stringify(alphas), "`r", ""), "`n", "") "`n", "*")
        } finally captured.Dispose()
    }

    static CleanUp() {
        if IsObject(SearchWindow.Gui)
            try SearchWindow.Gui.Destroy()
        if IsObject(MacCorners.Backdrop)
            try MacCorners.Backdrop.Destroy()
        IconCache.Clear()
        if (MacCorners.Folder != "" && InStr(Platform.FullPath(MacCorners.Folder), Platform.FullPath(Platform.Join(A_Temp, "ALTRun-MacCorners-")), true) = 1)
            try DirDelete(MacCorners.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL MAC_CORNERS " message "`n", "**")
        ExitApp(1)
        return true
    }
}

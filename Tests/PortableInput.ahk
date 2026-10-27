; Native keyboard/focus regression. Run Tests/PortableInput.sh on a private X11 desktop.
; Unlike PortableSmoke's direct method checks, this sends keys through X11 and GTK.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

#CSharp
public static long ALTRunInputSelectionPixels(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, long expectedColor)
{
    var control = wrapper.Native;
    var widget = control.GetType().GetProperty("ControlObject").GetValue(control);
    var handle = (System.IntPtr)widget.GetType().GetProperty("Handle").GetValue(widget);
    int width = ALTRunInputGtk.AllocatedWidth(handle), height = ALTRunInputGtk.AllocatedHeight(handle);
    int scale = System.Math.Max(1, ALTRunInputGtk.ScaleFactor(handle));
    if (width <= 0 || height <= 0)
        throw new System.InvalidOperationException("The search entry has no allocated drawing area.");
    var surface = ALTRunInputGtk.CreateSurface(0, width * scale, height * scale);
    var context = ALTRunInputGtk.CreateContext(surface);
    try
    {
        // Render only this owned entry; screen capture can be routed to a different desktop's broker.
        ALTRunInputGtk.Scale(context, scale, scale);
        ALTRunInputGtk.Draw(handle, context);
        if (ALTRunInputGtk.ContextStatus(context) != 0)
            throw new System.InvalidOperationException("Rendering the search entry failed.");
        ALTRunInputGtk.Flush(surface);
        var pixels = ALTRunInputGtk.Data(surface);
        int stride = ALTRunInputGtk.Stride(surface), expected = (int)(expectedColor & 0xFFFFFF);
        long count = 0;
        for (int y = 2 * scale; y < (height - 2) * scale; y++)
            for (int x = 2 * scale; x < (width - 2) * scale; x++)
                if ((System.Runtime.InteropServices.Marshal.ReadInt32(pixels, y * stride + x * 4) & 0xFFFFFF) == expected)
                    count++;
        return count;
    }
    finally
    {
        ALTRunInputGtk.DestroyContext(context);
        ALTRunInputGtk.DestroySurface(surface);
    }
}

internal static class ALTRunInputGtk
{
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_get_allocated_width")]
    internal static extern int AllocatedWidth(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_get_allocated_height")]
    internal static extern int AllocatedHeight(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_get_scale_factor")]
    internal static extern int ScaleFactor(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_draw")]
    internal static extern void Draw(System.IntPtr widget, System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_image_surface_create")]
    internal static extern System.IntPtr CreateSurface(int format, int width, int height);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_create")]
    internal static extern System.IntPtr CreateContext(System.IntPtr surface);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_scale")]
    internal static extern void Scale(System.IntPtr context, double x, double y);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_status")]
    internal static extern int ContextStatus(System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_surface_flush")]
    internal static extern void Flush(System.IntPtr surface);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_image_surface_get_data")]
    internal static extern System.IntPtr Data(System.IntPtr surface);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_image_surface_get_stride")]
    internal static extern int Stride(System.IntPtr surface);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_destroy")]
    internal static extern void DestroyContext(System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", EntryPoint = "cairo_surface_destroy")]
    internal static extern void DestroySurface(System.IntPtr surface);
}
#EndCSharp

OnError((err, mode) => PortableInput.Fail(err.Message "`n" err.Stack))
OnExit((*) => PortableInput.CleanUp())
SetTimer(() => PortableInput.Fail("Timed out after 45 seconds."), -45000)
PortableInput.Run()

MsgBox(args*) {
    throw Error("Unexpected input fixture dialog: " (args.Length ? args[1] : ""))
}

class PortableInput {
    static Folder := "", Other := "", OtherInput := "", Executed := 0, Runs := 0, Clicked := false, OriginalSearch := "", RanTitle := ""
    static MenuCalls := []

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Mark(message) => FileAppend("PASS PORTABLE_INPUT " message "`n", "*")

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            PortableInput.Assert(A_TickCount - started < 2000, message)
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

    static Window(title) {
        id := PortableInput.Xdo("search", "--onlyvisible", "--name", "^" title "$")
        PortableInput.Assert(RegExMatch(id, "^\d+$"), "Expected one X11 fixture window for " title ": " id)
        return id
    }

    static Focus(title) {
        id := PortableInput.Window(title)
        PortableInput.Xdo("windowactivate", "--sync", id)
        Sleep(50)
    }

    static Key(keys*) {
        arguments := ["key", "--clearmodifiers", "--delay", "30"]
        for key in keys
            arguments.Push(key)
        PortableInput.Xdo(arguments*)
        Sleep(50)
    }

    static Type(text) {
        PortableInput.Xdo("type", "--clearmodifiers", "--delay", "20", text)
        Sleep(50)
    }

    static Search() {
        SearchWindow.SetResults([
            ResultItem("First synthetic result", "", {OnRun: (*) => PortableInput.RunItem(1)}),
            ResultItem("Second synthetic result", "", {OnRun: (*) => PortableInput.RunItem(2)}),
            ResultItem("Third synthetic result", "", {OnRun: (*) => PortableInput.RunItem(3)})
        ])
    }

    static RunItem(index) {
        PortableInput.Executed := index
        PortableInput.Runs += 1
    }

    static Query(text, count) {
        PortableInput.Key("ctrl+a")
        if (text = "")
            PortableInput.Key("BackSpace")
        else
            PortableInput.Type(text)
        PortableInput.WaitFor(() => SearchWindow.Input.Value == text && SearchWindow.Results.Length = count
            , "Query " text " did not produce " count " results (actual " SearchWindow.Results.Length ").")
        Sleep(100)
        PortableInput.Assert(SearchWindow.Gui.ToClr().HasFocus, "Query-driven resize lost native focus for " text ".")
    }

    static HoverRow(row) {
        model := SearchWindow.RowModel[row]
        id := PortableInput.Window(App.Name)
        PortableInput.Xdo("mousemove", "--window", id, Round(model.X + model.Width / 2), Round(model.Y + model.Height / 2))
        PortableInput.WaitFor(() => SearchWindow.Hovered = row, "Native mouse movement did not hover result " row ".")
    }

    static RecordFolderOpen(folder) {
        SplitPath(folder, &title)
        PortableInput.RanTitle := title
        PortableInput.Runs += 1
    }

    static RealQueries() {
        SearchWindow.DefineProp("_RunSearch", {Call: PortableInput.OriginalSearch})
        ; Keep the real provider/search/render paths, replacing only the external launch side effect.
        ActionCatalog.DefineProp("OpenFolder", {Call: (self, folder) => PortableInput.RecordFolderOpen(folder)})
        AppSettings.Data["CustomCommands"] := []
        for name in ["Downloads", "DownloadAlpha", "DownloadBeta", "DownloadGamma"] {
            folder := Platform.Join(PortableInput.Folder, name)
            DirCreate(folder)
            AppSettings.Data["CustomCommands"].Push(Map("Title", name, "Type", "Folder", "Target", folder, "Keyword", ""))
        }
        AppSettings.Feature("CustomCommands")["Enabled"] := 1
        AppSettings.Feature("Calculator")["Enabled"] := 1
        AppSettings.Feature("Calculator")["StructuralCalc"] := 0
        ProviderRegistry.Providers := []
        ProviderRegistry.Register(CustomCommandProvider)
        ProviderRegistry.Register(CalculatorProvider)
        ProviderRegistry.InitAll()
        Loop 2 {
            PortableInput.Show()
            PortableInput.Query("down", 4)
            PortableInput.Key("ctrl+n")
            PortableInput.Assert(SearchWindow.Selected = 2, "Ctrl+N stopped working after growing to four real folder results.")
            PortableInput.Query("DownloadAlpha", 1)
            PortableInput.Query("zzzzzz", 0)
            PortableInput.Query("1+1", 1)
            PortableInput.Assert(SearchWindow.Results[1].Title == "2", "The real calculator search did not return 2.")
            PortableInput.Query("", 0)
            PortableInput.Query("down", 4)
            PortableInput.HoverRow(3)
            PortableInput.Xdo("click", "1")
            PortableInput.WaitFor(() => SearchWindow.Selected = 3, "Native row click failed after query-driven resizing.")
            PortableInput.Key("ctrl+n")
            PortableInput.Assert(SearchWindow.Selected = 4, "Ctrl+N stopped working after a native row click.")
            PortableInput.HoverRow(2)
            expectedTitle := SearchWindow.Results[2].Title
            previousRuns := PortableInput.Runs
            PortableInput.Xdo("click", "--repeat", "2", "--delay", "100", "1")
            PortableInput.WaitFor(() => !SearchWindow.IsVisible() && PortableInput.RanTitle == expectedTitle
                , "Native row double-click did not execute its selected real provider result.")
            PortableInput.Assert(PortableInput.Runs = previousRuns + 1, "Native double-click ran more than one provider action.")
        }
        PortableInput.Show()
        PortableInput.Query("down", 4)
        PortableInput.Key("ctrl+n")
        expectedTitle := SearchWindow.Results[2].Title
        previousRuns := PortableInput.Runs
        PortableInput.Key("Return")
        PortableInput.WaitFor(() => !SearchWindow.IsVisible() && PortableInput.RanTitle == expectedTitle
            , "Enter did not open the selected real folder result after repeated searches and shows.")
        PortableInput.Assert(PortableInput.Runs = previousRuns + 1, "Enter ran the selected real folder action more than once.")
        PortableInput.Mark("real folder/calculator searches resize 0/4/1/0/1/0/4 rows across repeated shows; hover, click, Ctrl+N and double-click work")
    }

    static ClickFooter(repeat := 1, delay := 100) {
        id := PortableInput.Window(App.Name)
        footerY := SearchWindow._WindowHeight(SearchWindow._VisibleCount()) - SearchWindow.FooterHeight / 2
        PortableInput.Xdo("mousemove", "--window", id, SearchWindow.Padding + 10, Round(footerY)
            , "click", "--repeat", repeat, "--delay", delay, "1")
        Sleep(100)
    }

    static MenuCallback(name) => (self, args*) => PortableInput.MenuCalls.Push(name)

    static MenuNavigation() {
        originals := []
        for target in [[App, "OpenPreferences"], [App, "RebuildIndex"], [UpdateChecker, "Check"], [App, "Reload"], [App, "Quit"]] {
            originals.Push([target[1], target[2], target[1].GetOwnPropDesc(target[2])])
            target[1].DefineProp(target[2], {Call: PortableInput.MenuCallback(target[2])})
        }
        try {
            PortableInput.Show()
            for originalQuery in [["down", 4], ["zzzzzz", 0]] {
                PortableInput.Query(originalQuery[1], originalQuery[2])
                for delay in [100, 700] {
                    PortableInput.ClickFooter(2, delay)
                    PortableInput.Assert(PortableInput.MenuCalls.Length = 0, "Repeated footer clicks invoked a menu command (delay " delay ").")
                    PortableInput.Assert(SearchWindow.IsVisible(), "Repeated footer clicks hid the launcher.")
                    if SearchWindow.Mode == "actions"
                        PortableInput.Key("Escape")
                    PortableInput.Assert(SearchWindow.Mode == "results" && SearchWindow.Input.Value == originalQuery[1], "Repeated footer clicks lost the original query.")
                }
            }
            PortableInput.Query("down", 4)
            PortableInput.Key("ctrl+n")
            PortableInput.Assert(SearchWindow.Selected = 2, "Keyboard navigation stopped after repeated footer clicks.")
            PortableInput.ClickFooter()
            PortableInput.WaitFor(() => SearchWindow.Mode == "actions" && SearchWindow._footerMenuActive && SearchWindow.Results.Length = 6
                , "The native footer click did not show all six menu commands inside the launcher.")
            PortableInput.Query(I18n.T("Tray.Preferences"), 1)
            PortableInput.Key("Return")
            PortableInput.WaitFor(() => PortableInput.MenuCalls.Length = 1 && !SearchWindow.IsVisible(), "Enter did not execute the filtered Preferences menu command.")
            PortableInput.Assert(PortableInput.MenuCalls[1] == "OpenPreferences", "The footer executed the wrong command.")
            Sleep(150)
            PortableInput.Assert(PortableInput.MenuCalls.Length = 1, "The menu command executed more than once.")

            PortableInput.Show()
            PortableInput.Query("down", 4)
            PortableInput.ClickFooter()
            PortableInput.WaitFor(() => SearchWindow._footerMenuActive, "The footer menu did not reopen for mouse activation.")
            PortableInput.HoverRow(3)
            PortableInput.Xdo("click", "--repeat", "2", "--delay", "100", "1")
            PortableInput.WaitFor(() => PortableInput.MenuCalls.Length = 2 && !SearchWindow.IsVisible(), "Moving to and double-clicking Rebuild Index did not execute its command.")
            PortableInput.Assert(PortableInput.MenuCalls[2] == "RebuildIndex", "The footer mouse activation executed the wrong command.")
            Sleep(150)
            PortableInput.Assert(PortableInput.MenuCalls.Length = 2, "The footer mouse activation executed its command more than once.")

            PortableInput.Show()
            PortableInput.Query("down", 4)
            PortableInput.ClickFooter()
            PortableInput.WaitFor(() => SearchWindow._footerMenuActive, "The footer menu did not reopen.")
            PortableInput.Query(I18n.T("Menu.CheatSheet"), 1)
            PortableInput.Key("Return")
            PortableInput.WaitFor(() => SearchWindow.Mode == "results" && SearchWindow.Input.Value == "?" && SearchWindow.IsVisible()
                , "The Cheat Sheet menu command did not return to a visible '?' search.")
            PortableInput.Assert(!SearchWindow._footerMenuActive && PortableInput.MenuCalls.Length = 2, "The Cheat Sheet left menu state active or invoked an external command.")
            PortableInput.Query("down", 4)
            PortableInput.HoverRow(2)
            PortableInput.Xdo("click", "3")
            PortableInput.WaitFor(() => SearchWindow.Mode == "actions" && !SearchWindow._footerMenuActive, "A native result right-click did not open its in-window actions.")
            PortableInput.Key("Escape")
            PortableInput.Assert(SearchWindow.Mode == "results" && SearchWindow.Input.Value == "down", "Escape from right-click actions did not restore the query.")
            PortableInput.Key("ctrl+n")
            PortableInput.Assert(SearchWindow.Selected = 2, "Keyboard navigation stopped after result right-click actions.")
            PortableInput.Assert(PortableInput.MenuCalls.Length = 2, "Result right-click actions invoked a footer command.")
            expectedTitle := SearchWindow.Results[2].Title
            previousRuns := PortableInput.Runs
            PortableInput.Key("Return")
            PortableInput.WaitFor(() => !SearchWindow.IsVisible() && !SearchWindow.Gui.ToClr().Visible && PortableInput.RanTitle == expectedTitle
                , "Enter after menu navigation did not run the selected result and hide the native window.")
            PortableInput.Assert(PortableInput.Runs = previousRuns + 1, "Enter after menu navigation ran the result more than once.")
            PortableInput.Show()
            PortableInput.Query("down", 4)
            PortableInput.ClickFooter()
            PortableInput.WaitFor(() => SearchWindow._footerMenuActive, "The footer did not reopen before Escape dismissal.")
            PortableInput.Key("Escape")
            PortableInput.Assert(SearchWindow.Mode == "results" && SearchWindow.Input.Value == "down" && SearchWindow.IsVisible()
                , "The first Escape did not restore visible results from the footer menu.")
            PortableInput.Key("Escape")
            PortableInput.WaitFor(() => !SearchWindow.IsVisible() && !SearchWindow.Gui.ToClr().Visible
                , "The second Escape did not hide the native launcher after closing its menu.")
            PortableInput.Mark("double/slow repeated footer clicks remain safe; filtering, single execution, Cheat Sheet, right-click, Enter and final Escape work")
        } finally {
            for original in originals
                original[1].DefineProp(original[2], original[3])
        }
    }

    static Show() {
        SearchWindow.Show("", false)
        PortableInput.WaitFor(() => SearchWindow.Gui.ToClr().HasFocus, "The launcher did not acquire native focus.")
    }

    static SelectionHighlight() {
        previousTheme := ThemeManager.Name, previousDensity := ThemeManager.Density
        try {
            for themeName in ["Light", "Dark"] {
                SearchWindow.Hide()
                ThemeManager.Load(themeName, "Compact")
                SearchWindow.Create()
                PortableInput.Show()
                PortableInput.Type("Selection should be visible")
                PortableInput.Key("ctrl+a")
                selection := Platform.EditSelection(SearchWindow.Input)
                PortableInput.Assert(selection.Start = 0 && selection.End = 27 && SearchWindow.Input.ToClr().HasFocus
                    , themeName ": Ctrl+A did not select the whole focused query.")
                expectedColor := Integer("0x" ThemeManager.Get("SelectedBackground"))
                fullPixels := ALTRunInputSelectionPixels(SearchWindow.Input.ToClr(), expectedColor)
                PortableInput.Assert(fullPixels > 1000, themeName ": Ctrl+A selection has no visible themed background (pixels " fullPixels ").")
                PortableInput.Key("Right")
                plainPixels := ALTRunInputSelectionPixels(SearchWindow.Input.ToClr(), expectedColor)
                PortableInput.Assert(plainPixels < fullPixels / 10, themeName ": Clearing selection did not remove its background.")
                PortableInput.Key("shift+Left")
                selection := Platform.EditSelection(SearchWindow.Input)
                PortableInput.Assert(selection.Start = 26 && selection.End = 27, themeName ": Shift+Left did not select the last character.")
                partialPixels := ALTRunInputSelectionPixels(SearchWindow.Input.ToClr(), expectedColor)
                PortableInput.Assert(partialPixels > 40 && partialPixels < fullPixels / 4
                    , themeName ": Partial selection did not paint the selected character (pixels " partialPixels ").")
                PortableInput.Key("ctrl+a")
                PortableInput.Type("replacement")
                PortableInput.Assert(SearchWindow.Input.Value == "replacement", themeName ": Typing did not replace the selected query.")
                PortableInput.Mark(themeName " native Ctrl+A/Shift+Left selection bounds and rendered highlight; typing replaces selection")
            }
        } finally {
            SearchWindow.Hide()
            ThemeManager.Load(previousTheme, previousDensity)
            SearchWindow.Create()
        }
    }

    static Run() {
        if (!Platform.IsLinux || Platform.IsWayland || EnvGet("ALTRUN_INPUT_TEST") != "isolated-xvfb") {
            FileAppend("SKIP PORTABLE_INPUT Run Tests/PortableInput.sh to use a private X11 desktop.`n", "*")
            ExitApp(0)
        }
        SetWinDelay(-1)
        PortableInput.Isolate()
        I18n.Init("en")
        Knowledge.Load()
        Usage.Load()
        ThemeManager.Load("Light", "Compact")
        PortableInput.OriginalSearch := SearchWindow.GetOwnPropDesc("_RunSearch").Call
        SearchWindow.DefineProp("_RunSearch", {Call: (self) => PortableInput.Search()})
        SearchWindow.Create()
        PortableInput.Show()

        PortableInput.Type("alpha beta")
        PortableInput.WaitFor(() => SearchWindow.Input.Value == "alpha beta", "Native typing did not reach the search box.")
        PortableInput.Key("Left", "BackSpace")
        PortableInput.Assert(SearchWindow.Input.Value == "alpha bea", "Native caret movement/backspace was swallowed.")
        PortableInput.Key("ctrl+a")
        PortableInput.Type("1+1")
        PortableInput.Assert(SearchWindow.Input.Value == "1+1", "Select-all and replacement typing failed.")
        PortableInput.Mark("native typing, caret movement, Backspace and Ctrl+A")

        PortableInput.WaitFor(() => SearchWindow.Results.Length = 3, "The synthetic query did not create results.")
        PortableInput.Key("ctrl+n")
        PortableInput.Assert(SearchWindow.Selected = 2, "Ctrl+N did not move to the second result.")
        PortableInput.Key("ctrl+p")
        PortableInput.Assert(SearchWindow.Selected = 1, "Ctrl+P did not move to the first result.")
        PortableInput.Key("Down")
        PortableInput.Assert(SearchWindow.Selected = 2, "Down did not move exactly one row (selected " SearchWindow.Selected ").")
        PortableInput.Key("Tab")
        PortableInput.Assert(SearchWindow.Selected = 3, "Tab did not move exactly one row (selected " SearchWindow.Selected ").")
        PortableInput.Assert(SearchWindow.Input.Value == "1+1", "Navigation modified the query.")
        PortableInput.Mark("Ctrl+N, Ctrl+P, Down and Tab through native key delivery")

        PortableInput.Key("Return")
        PortableInput.WaitFor(() => PortableInput.Executed = 3 && !SearchWindow.IsVisible(), "Enter did not run the selected result and hide the launcher.")
        PortableInput.Assert(PortableInput.Runs = 1, "Enter ran the selected action more than once.")
        PortableInput.Mark("Enter runs exactly the selected action")
        PortableInput.Show()
        PortableInput.Type("query")
        PortableInput.Key("Right")
        PortableInput.Assert(SearchWindow.Mode == "actions", "Right arrow did not open the action panel.")
        PortableInput.Key("Escape")
        PortableInput.Assert(SearchWindow.Mode == "results" && SearchWindow.IsVisible(), "Escape did not return from the action panel to results.")
        PortableInput.Key("Escape")
        PortableInput.WaitFor(() => !SearchWindow.IsVisible(), "Escape did not hide the launcher.")
        PortableInput.Assert(PortableInput.Runs = 1, "Escape unexpectedly ran an action.")
        PortableInput.Mark("Right opens actions; Escape returns to results, then dismisses")
        PortableInput.SelectionHighlight()
        PortableInput.RealQueries()
        PortableInput.MenuNavigation()

        PortableInput.Other := Gui("", "ALTRun input fixture other window")
        PortableInput.OtherInput := PortableInput.Other.AddEdit("x10 y10 w300 h30")
        otherButton := PortableInput.Other.AddButton("x10 y55 w300 h30", "Click fixture button")
        otherButton.OnEvent("Click", (*) => PortableInput.Clicked := true)
        PortableInput.Other.Show("x20 y20 w340 h140")
        PortableInput.OtherInput.Focus()
        PortableInput.Focus("ALTRun input fixture other window")
        PortableInput.WaitFor(() => PortableInput.Other.ToClr().HasFocus, "The other fixture window did not acquire focus.")
        PortableInput.Show()
        PortableInput.Query("down", 4)
        PortableInput.Query("1+1", 1)
        PortableInput.WaitFor(() => SearchWindow._focusArmed, "The hide-on-deactivate timer did not observe launcher focus.")
        otherId := PortableInput.Window("ALTRun input fixture other window")
        PortableInput.Xdo("mousemove", "--window", otherId, "150", "25", "click", "1")
        PortableInput.WaitFor(() => !SearchWindow.IsVisible(), "Moving focus to another window did not hide the launcher.")
        PortableInput.WaitFor(() => PortableInput.Other.ToClr().HasFocus, "Clicking the other window did not transfer native focus.")
        PortableInput.Show()
        PortableInput.Query("down", 4)
        PortableInput.Key("ctrl+n")
        PortableInput.Assert(SearchWindow.Selected = 2, "Keyboard input did not work after reopening from another focused window.")
        PortableInput.WaitFor(() => SearchWindow._focusArmed, "The reopened launcher's inactivity timer did not arm.")
        PortableInput.Mark("native Show reacquires focus after query-driven resizing and activation of another window")
        PortableInput.Xdo("mousemove", "--window", otherId, "150", "25", "click", "1")
        PortableInput.WaitFor(() => !SearchWindow.IsVisible(), "A reopened launcher did not hide when another window was clicked.")
        PortableInput.Type("desktop remains usable")
        PortableInput.Assert(PortableInput.OtherInput.Value == "desktop remains usable", "The launcher blocked keyboard input to another window.")
        PortableInput.Xdo("mousemove", "--window", otherId, "150", "70", "click", "1")
        PortableInput.WaitFor(() => PortableInput.Clicked, "The launcher blocked mouse clicks to another window.")
        PortableInput.Mark("clicking another window hides the launcher; that window accepts typing and button clicks")
        ExitApp(0)
    }

    static Isolate() {
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        PortableInput.Folder := Platform.Join(A_Temp, "ALTRun-PortableInput-" Platform.NewUuid())
        DirCreate(Platform.Join(PortableInput.Folder, "Data"))
        App.Name := "ALTRun portable input fixture"
        App.IconFile := Platform.Join(sourceRoot, "Resources", "ALTRun.ico")
        AppSettings.Portable := false
        AppSettings.UserDir := PortableInput.Folder
        AppSettings.DataDir := Platform.Join(PortableInput.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        Usage.File := Platform.Join(AppSettings.DataDir, "Usage.json")
        I18n.LangDir := Platform.Join(sourceRoot, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(sourceRoot, "Resources", "Themes")
        ThemeManager.UserDir := Platform.Join(PortableInput.Folder, "Themes")
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        for key in ["Hotkey", "SecondaryHotkey", "SelectionHotkey", "DoubleTap", "CapsLock"]
            AppSettings.General[key] := ""
        for key in ["LaunchAtLogin", "ShowTrayIcon", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut", "CheckForUpdates", "SaveLog", "ShowTips", "KeepLastQuery"]
            AppSettings.General[key] := 0
        AppSettings.General["HideOnDeactivate"] := 1
        AppSettings.General["TabKey"] := "Next"
        AppSettings.Appearance["ShowOn"] := "Primary"
        AppSettings.Appearance["RememberPosition"] := 0
        AppSettings.Feature("Clipboard")["Enabled"] := 0
        AppSettings.Feature("FileSearch")["Enabled"] := 0
        AppSettings.Feature("Calculator")["Currency"] := 0
    }

    static CleanUp() {
        try ProcessRunner.CancelAll()
        try SearchWindow.Hide()
        if (SearchWindow._prepareTimer != "")
            SetTimer(SearchWindow._prepareTimer, 0)
        try SearchWindow.Gui.Destroy()
        try PortableInput.Other.Destroy()
        try IconCache.Clear()
        if (PortableInput.Folder != "" && InStr(PortableInput.Folder, "ALTRun-PortableInput-") && DirExist(PortableInput.Folder))
            try DirDelete(PortableInput.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_INPUT " message "`n", "**")
        ExitApp(1)
        return true
    }
}

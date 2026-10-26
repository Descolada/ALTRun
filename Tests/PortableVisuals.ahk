; PortableVisuals - synthetic launcher and preferences screenshots in an explicit output folder.
; Keysharp --errorstdout Tests/PortableVisuals.ahk <output-folder>
; On Linux, use xvfb-run -a to keep capture on an isolated X11 desktop.
; If window capture is unavailable, the GTK fallback renders the owned widget hierarchy through Cairo.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PortableVisuals.Fail(err.Message "`n" err.Stack))
OnExit((*) => PortableVisuals.CleanUp())
SetTimer(() => PortableVisuals.Fail("Timed out after 45 seconds."), -45000)
PortableVisuals.Run()

MsgBox(args*) {
    throw Error("Unexpected visual fixture dialog: " (args.Length ? args[1] : ""))
}
InputBox(args*) {
    throw Error("Unexpected visual fixture input dialog.")
}
FileSelect(args*) {
    throw Error("Unexpected visual fixture file picker.")
}

class PortableVisuals {
    static Folder := "", OutputDir := "", File := "", OriginalSearch := "", Entries := [], Items := [], EditorCaptured := false, CaptureMethod := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        PortableVisuals.Assert(A_Args.Length = 1 && A_Args[1] != "", "Supply one explicit screenshot output folder.")
        PortableVisuals.OutputDir := Platform.FullPath(A_Args[1], A_WorkingDir)
        DirCreate(PortableVisuals.OutputDir)
        SetWinDelay(-1)
        PortableVisuals.Isolate()
        PortableVisuals.Configure()
        App._SetApplicationIdentity()
        App._SetIcon()
        PortableVisuals.Assert(A_IconHidden, "Setting the fixture window icon made the tray icon visible.")
        I18n.Init("en")
        PortableVisuals.BuildItems()
        PortableVisuals.OriginalSearch := SearchWindow.GetOwnPropDesc("_RunSearch").Call
        SearchWindow.DefineProp("_RunSearch", {Call: (self) => PortableVisuals.Search()})
        for themeName in ["Light", "Dark"]
            PortableVisuals.Theme(themeName)
        JSON.WriteFile(Platform.Join(PortableVisuals.OutputDir, "manifest.json")
            , Map("Platform", A_OSType, "Data", "synthetic", "Screenshots", PortableVisuals.Entries))
        FileAppend("PASS PORTABLE_VISUALS " PortableVisuals.Entries.Length " screenshots`n", "*")
        ExitApp(0)
    }

    static Isolate() {
        sourceRoot := Platform.FullPath("..", A_ScriptDir)
        PortableVisuals.Folder := Platform.Join(A_Temp, "ALTRun-PortableVisuals-" Platform.NewUuid())
        for name in ["Data", "Files", "Scripts", "Applications", "Themes"]
            DirCreate(Platform.Join(PortableVisuals.Folder, name))
        PortableVisuals.File := Platform.Join(PortableVisuals.Folder, "Files", "Quarterly report.txt")
        FileAppend("Synthetic screenshot fixture.`n", PortableVisuals.File, "UTF-8")
        AppSettings.Portable := false
        AppSettings.UserDir := PortableVisuals.Folder
        AppSettings.DataDir := Platform.Join(PortableVisuals.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.LegacyFile := Platform.Join(PortableVisuals.Folder, "Legacy.json")
        AppSettings.ThemesDir := Platform.Join(PortableVisuals.Folder, "Themes")
        Knowledge.File := Platform.Join(AppSettings.DataDir, "Knowledge.json")
        Usage.File := Platform.Join(AppSettings.DataDir, "Usage.json")
        FileIndex.File := Platform.Join(AppSettings.DataDir, "FileIndex.json")
        ApplicationProvider.IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
        ClipboardProvider.File := Platform.Join(AppSettings.DataDir, "ClipboardHistory.json")
        ClipboardProvider.LocalDir := Platform.Join(PortableVisuals.Folder, "Clipboard")
        CurrencyRates.File := Platform.Join(AppSettings.DataDir, "Currency.json")
        UpdateChecker.StateFile := Platform.Join(AppSettings.DataDir, "Update.json")
        UpdateChecker.TempDir := Platform.Join(PortableVisuals.Folder, "Update")
        ScriptProvider.Folder := Platform.Join(PortableVisuals.Folder, "Scripts")
        I18n.LangDir := Platform.Join(sourceRoot, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(sourceRoot, "Resources", "Themes")
        ThemeManager.UserDir := AppSettings.ThemesDir
        WebSearchProvider.BuiltinIconDir := Platform.Join(sourceRoot, "Resources", "Icons", "Web")
        App.IconFile := Platform.Join(sourceRoot, "Resources", "ALTRun.ico")
        Logger.File := Platform.Join(PortableVisuals.Folder, "ALTRun.log")
        Logger.Enabled := false
    }

    static Configure() {
        AppSettings.Data := AppSettings.Defaults()
        general := AppSettings.General
        for key in ["Hotkey", "SecondaryHotkey", "SelectionHotkey", "DoubleTap", "CapsLock"]
            general[key] := ""
        for key in ["LaunchAtLogin", "ShowTrayIcon", "HideOnDeactivate", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut", "CheckForUpdates", "SaveLog", "ShowTips", "KeepLastQuery"]
            general[key] := 0
        general["Language"] := "en"
        AppSettings.Appearance["Density"] := "Normal"
        AppSettings.Appearance["Width"] := 700
        AppSettings.Appearance["VisibleRows"] := 5
        AppSettings.Appearance["ShowOn"] := "Primary"
        AppSettings.Appearance["RememberPosition"] := 0
        AppSettings.Appearance["Placeholder"] := "Search applications, files and more"
        for name in ["Clipboard", "Bookmarks", "Windows"]
            AppSettings.Feature(name)["Enabled"] := 0
        for key in ["Persist", "Images", "LocalFiles", "MergeDoubleCopy"]
            AppSettings.Feature("Clipboard")[key] := 0
        AppSettings.Feature("Clipboard")["Hotkey"] := ""
        AppSettings.Feature("Calculator")["Currency"] := 0
        AppSettings.Feature("Snippets")["AutoExpand"] := 0
        AppSettings.Feature("Applications")["Folders"] := [Platform.Join(PortableVisuals.Folder, "Applications")]
        AppSettings.Feature("Applications")["StoreApps"] := 0
        AppSettings.Feature("FileSearch")["ScopeFolders"] := [Platform.Join(PortableVisuals.Folder, "Files")]
        AppSettings.Feature("FileSearch")["UseEverything"] := 0
        AppSettings.Feature("LargeType")["Enabled"] := 1
        for name in ["QuickSwitch", "AutoDate", "PTTools"]
            AppSettings.Extension(name)["Enabled"] := 0
        AppSettings.Data["Hotkeys"] := []
        AppSettings.Data["CustomCommands"] := [Map("Title", "Quarterly report", "Type", "File", "Target", PortableVisuals.File, "Arguments", "", "Keyword", "report")]
        AppSettings.Data["Snippets"] := [Map("Name", "Meeting follow-up", "Keyword", "followup", "Text", "Thank you for the useful discussion. Here are the next steps.", "AutoExpand", 0)]
        ProviderRegistry.Providers := []
    }

    static BuildItems() {
        PortableVisuals.Items := [
            ResultItem("Quarterly report", "Projects / Atlas / Reports", {Kind: "file", Arg: PortableVisuals.File, Icon: "", Uid: "visual:report", Pinned: true}),
            ResultItem("Report templates", "Reusable documents for your next project", {Kind: "folder", Arg: Platform.Join(PortableVisuals.Folder, "Files"), Icon: "", Uid: "visual:templates"}),
            ResultItem("Search reports on the web", "Google · report", {Kind: "url", Arg: "https://example.com/search?q=report", Icon: Platform.Join(WebSearchProvider.BuiltinIconDir, "google.png"), Uid: "visual:web"}),
            ResultItem("128 × 24 = 3,072", "Calculator · copy the result", {Kind: "text", Arg: "3072", Icon: IconCache.Own("Calculator"), Uid: "visual:calculator"}),
            ResultItem.KeywordHint("Find files by name", "file", IconCache.Own("Help"))
        ]
    }

    static Search() {
        if SearchWindow.Mode = "actions"
            return PortableVisuals.OriginalSearch.Call(SearchWindow)
        SearchWindow.HighlightText := SearchWindow.Input.Value
        SearchWindow.SetResults(PortableVisuals.Items)
    }

    static Theme(themeName) {
        PreferencesWindow.Close()
        Hud.Hide()
        SearchWindow.Hide()
        IconCache.Clear()
        AppSettings.Appearance["Theme"] := themeName
        ThemeManager.Load(themeName, "Normal")
        SearchWindow.Create()
        SearchWindow.Show("report", false)
        PortableVisuals.Capture("launcher-" StrLower(themeName), SearchWindow.Gui, "launcher", themeName)
        PortableVisuals.SaveFrame("launcher-" StrLower(themeName) "-frame", themeName)
        actionItem := ResultItem("Meeting follow-up", "Synthetic text selection", {Kind: "text", Arg: "Thanks for the discussion. Here are the next steps.", Icon: IconCache.Own("Snippet")})
        actionItem.Actions := [ResultItem("Save as snippet", "Keep this text for later", {Icon: IconCache.Own("Snippet"), OnRun: (*) => 0})]
        SearchWindow.ShowActions(actionItem)
        PortableVisuals.Capture("actions-" StrLower(themeName), SearchWindow.Gui, "actions", themeName)
        PortableVisuals.SaveFrame("actions-" StrLower(themeName) "-frame", themeName)
        Hud.Show("Saved to your collection.`nReady for the next idea.", 10000)
        PortableVisuals.Assert(IsObject(Hud.Gui) && IsObject(Hud.Picture), "The HUD did not create its painted window.")
        PortableVisuals.Capture("hud-" StrLower(themeName), Hud.Gui, "hud", themeName)
        Hud.Hide()
        SearchWindow.Hide()
        for pageKey in ["Prefs.Page.General", "Prefs.Page.Appearance", "Prefs.Page.Clipboard"] {
            PreferencesWindow.Show(pageKey)
            pageName := pageKey = "Prefs.Page.General" ? "general" : pageKey = "Prefs.Page.Appearance" ? "appearance" : "clipboard"
            PortableVisuals.Capture("preferences-" pageName "-" StrLower(themeName), PreferencesWindow.Gui, pageKey, themeName)
            if (Platform.IsWindows && themeName = "Dark" && pageKey = "Prefs.Page.Appearance")
                PortableVisuals.CaptureDropdown(themeName)
        }
        PortableVisuals.EditorCaptured := false
        SetTimer(() => PortableVisuals.CaptureEditor(themeName), -250)
        ItemEditor.Edit(PreferencesWindow.Gui, "Edit sample command", CustomCommandProvider.EditorFields(), AppSettings.CustomCommands[1])
        PortableVisuals.Assert(PortableVisuals.EditorCaptured, "The synthetic command editor was not captured.")
        PreferencesWindow.Close()
    }

    static CaptureEditor(themeName) {
        if !IsObject(ItemEditor.Gui) {
            SetTimer(() => PortableVisuals.CaptureEditor(themeName), -50)
            return
        }
        try {
            PortableVisuals.Capture("editor-" StrLower(themeName), ItemEditor.Gui, "editor", themeName)
            PortableVisuals.EditorCaptured := true
        } finally ItemEditor.Cancel()
    }

    static CaptureDropdown(themeName) {
        popup := ALTRunVisualOpenDropdown(PreferencesWindow.Gui.ToClr())
        PortableVisuals.Assert(popup != 0, "The density dropdown could not be opened for capture.")
        try {
            Sleep(250)
            popupImage := Image.FromWindow("ahk_id " popup)
            try {
                PortableVisuals.Assert(PortableVisuals.HasContent(popupImage), "The open density dropdown capture was uniformly blank.")
                filename := "density-dropdown-" StrLower(themeName) ".png"
                popupImage.Save(Platform.Join(PortableVisuals.OutputDir, filename))
                PortableVisuals.Entries.Push(Map("File", filename, "Kind", "dropdown", "Theme", themeName, "Capture", "owned-window-popup", "Width", popupImage.Width, "Height", popupImage.Height))
            } finally popupImage.Dispose()
        } finally ALTRunVisualCloseDropdown()
    }

    static Capture(name, windowGui, kind, themeName) {
        windowGui.Show()
        WinActivate("ahk_id " windowGui.Hwnd)
        Sleep(250)
        captureImage := PortableVisuals.CaptureWindow(windowGui)
        PortableVisuals.Assert(IsObject(captureImage) && captureImage.Width > 0 && captureImage.Height > 0, "The window screenshot was empty: " name)
        try {
            PortableVisuals.Assert(PortableVisuals.HasContent(captureImage), "The captured window is uniformly blank: " name)
            filename := name ".png"
            captureImage.Save(Platform.Join(PortableVisuals.OutputDir, filename))
            PortableVisuals.Entries.Push(Map("File", filename, "Kind", kind, "Theme", themeName, "Capture", PortableVisuals.CaptureMethod, "Width", captureImage.Width, "Height", captureImage.Height))
        } finally captureImage.Dispose()
        FileAppend("PASS PORTABLE_VISUALS captured " name "`n", "*")
    }

    static CaptureWindow(windowGui) {
        try {
            captured := Image.FromWindow("ahk_id " windowGui.Hwnd)
            if (IsObject(captured) && PortableVisuals.HasContent(captured)) {
                PortableVisuals.CaptureMethod := "owned-window"
                return captured
            }
            if IsObject(captured)
                captured.Dispose()
            throw Error("Image.FromWindow returned an empty or uniform image.")
        } catch as captureFailure {
            if !Platform.IsLinux
                throw captureFailure
            temporaryCapture := Platform.Join(PortableVisuals.Folder, "window-" Platform.NewUuid() ".png")
            try {
                ALTRunVisualCaptureGtk(windowGui.ToClr(), temporaryCapture)
                PortableVisuals.CaptureMethod := "gtk-widget-cairo"
                FileAppend("INFO PORTABLE_VISUALS rendered own GTK widget hierarchy to Cairo after Image.FromWindow failed: " captureFailure.Message "`n", "*")
                return Image.FromFile(temporaryCapture)
            } finally {
                if FileExist(temporaryCapture)
                    FileDelete(temporaryCapture)
            }
        }
    }

    static HasContent(captured) {
        if (!IsObject(captured) || captured.Width < 2 || captured.Height < 2)
            return false
        firstPixel := captured.GetPixel(0, 0)
        Loop 17 {
            sampleY := Round((A_Index - 1) * (captured.Height - 1) / 16)
            Loop 17 {
                sampleX := Round((A_Index - 1) * (captured.Width - 1) / 16)
                if (captured.GetPixel(sampleX, sampleY) != firstPixel)
                    return true
            }
        }
        return false
    }

    static SaveFrame(name, themeName) {
        PortableVisuals.Assert(IsObject(SearchWindow.Frame) && SearchWindow.RowModel.Length > 0, "The painted launcher has no rows.")
        filename := name ".png"
        SearchWindow.Frame.Save(Platform.Join(PortableVisuals.OutputDir, filename))
        rows := []
        for row in SearchWindow.RowModel
            rows.Push(Map("Index", row.Index, "Title", row.Title, "Subtitle", row.Subtitle, "Shortcut", row.Shortcut, "Selected", row.Selected
                , "X", row.X, "Y", row.Y, "Width", row.Width, "Height", row.Height, "Background", row.Background))
        PortableVisuals.Entries.Push(Map("File", filename, "Kind", "frame", "Theme", themeName, "Capture", "retained-launcher-image", "Width", SearchWindow.Frame.Width, "Height", SearchWindow.Frame.Height, "Rows", rows))
    }

    static CleanUp() {
        try PreferencesWindow.Close()
        try ItemEditor.Cancel()
        try Hud.Hide()
        try SearchWindow.Hide()
        if (SearchWindow._prepareTimer != "")
            try SetTimer(SearchWindow._prepareTimer, 0)
        if (SearchWindow._searchTimer != "")
            try SetTimer(SearchWindow._searchTimer, 0)
        try SearchWindow.Gui.Destroy()
        try SearchWindow.Frame.Dispose()
        try IconCache.Clear()
        try ProcessRunner.CancelAll()
        if (PortableVisuals.Folder = "")
            return
        fixtureFolder := Platform.FullPath(PortableVisuals.Folder)
        allowedPrefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-PortableVisuals-"))
        if (InStr(Platform.Identity(fixtureFolder), Platform.Identity(allowedPrefix), true) = 1 && DirExist(fixtureFolder))
            try DirDelete(fixtureFolder, true)
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_VISUALS " message "`n", "**")
        ExitApp(1)
        return true
    }
}

#CSharp
private static object ALTRunVisualDropdownControl;
private static class ALTRunVisualWindows
{
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    internal struct Rect { internal int Left, Top, Right, Bottom; }
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    internal struct ComboInfo
    {
        internal uint Size;
        internal Rect Item, Button;
        internal uint State;
        internal System.IntPtr Combo, Edit, List;
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    internal static extern bool GetComboBoxInfo(System.IntPtr combo, ref ComboInfo info);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(System.IntPtr window, out uint processId);
}

public static long ALTRunVisualOpenDropdown(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapper)
{
    if (!System.OperatingSystem.IsWindows()) return 0;
    var pending = new System.Collections.Generic.Stack<object>();
    pending.Push(Wrapper.Native);
    while (pending.Count > 0)
    {
        var control = pending.Pop();
        var type = control.GetType();
        var dropdown = type.GetProperty("DroppedDown");
        if (dropdown != null && type.GetProperty("Items")?.GetValue(control) is System.Collections.IList items
            && items.Count == 3 && System.Convert.ToString(items[0]) == "Comfortable")
        {
            type.GetMethod("Focus", System.Type.EmptyTypes)?.Invoke(control, null);
            dropdown.SetValue(control, true);
            ALTRunVisualDropdownControl = control;
            var handle = (System.IntPtr)type.GetProperty("Handle").GetValue(control);
            var info = new ALTRunVisualWindows.ComboInfo { Size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<ALTRunVisualWindows.ComboInfo>() };
            if (!ALTRunVisualWindows.GetComboBoxInfo(handle, ref info)) return 0;
            ALTRunVisualWindows.GetWindowThreadProcessId(info.List, out var owner);
            return owner == System.Environment.ProcessId ? info.List.ToInt64() : 0;
        }
        if (type.GetProperty("Controls")?.GetValue(control) is System.Collections.IEnumerable children)
            foreach (var child in children) pending.Push(child);
    }
    return 0;
}

public static void ALTRunVisualCloseDropdown()
{
    var control = ALTRunVisualDropdownControl;
    ALTRunVisualDropdownControl = null;
    control?.GetType().GetProperty("DroppedDown")?.SetValue(control, false);
}

private static class ALTRunVisualGtk
{
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern void gtk_container_check_resize(System.IntPtr container);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern int gtk_widget_get_allocated_width(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern int gtk_widget_get_allocated_height(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern int gtk_widget_get_scale_factor(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern void gtk_widget_draw(System.IntPtr widget, System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern System.IntPtr cairo_image_surface_create(int format, int width, int height);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern System.IntPtr cairo_create(System.IntPtr surface);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern void cairo_scale(System.IntPtr context, double x, double y);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern int cairo_status(System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern int cairo_surface_write_to_png(System.IntPtr surface,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string filename);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern void cairo_destroy(System.IntPtr context);
    [System.Runtime.InteropServices.DllImport("libcairo.so.2", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal static extern void cairo_surface_destroy(System.IntPtr surface);

}

public static void ALTRunVisualCaptureGtk(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapper, string Filename)
{
    if (!System.OperatingSystem.IsLinux())
        throw new System.PlatformNotSupportedException("The own-window GTK capture fallback is Linux-only.");
    var form = Wrapper.Native;
    var widget = form.GetType().GetProperty("ControlObject")?.GetValue(form);
    var rawHandle = widget?.GetType().GetProperty("Handle")?.GetValue(widget);
    if (rawHandle is not System.IntPtr widgetHandle || widgetHandle == System.IntPtr.Zero)
        throw new System.InvalidOperationException("The fixture GUI has no native GTK widget handle.");
    ALTRunVisualGtk.gtk_container_check_resize(widgetHandle);
    var width = ALTRunVisualGtk.gtk_widget_get_allocated_width(widgetHandle);
    var height = ALTRunVisualGtk.gtk_widget_get_allocated_height(widgetHandle);
    if (width <= 0 || height <= 0)
        throw new System.InvalidOperationException("The fixture's GTK window has empty bounds.");
    var scale = System.Math.Max(1, ALTRunVisualGtk.gtk_widget_get_scale_factor(widgetHandle));
    var surface = ALTRunVisualGtk.cairo_image_surface_create(0, checked(width * scale), checked(height * scale));
    var context = ALTRunVisualGtk.cairo_create(surface);
    try
    {
        ALTRunVisualGtk.cairo_scale(context, scale, scale);
        ALTRunVisualGtk.gtk_widget_draw(widgetHandle, context);
        var status = ALTRunVisualGtk.cairo_status(context);
        if (status != 0) throw new System.InvalidOperationException("Drawing the fixture's GTK hierarchy failed: Cairo status " + status);
        status = ALTRunVisualGtk.cairo_surface_write_to_png(surface, Filename);
        if (status != 0) throw new System.IO.IOException("Saving the fixture's GTK render failed: Cairo status " + status);
    }
    finally
    {
        ALTRunVisualGtk.cairo_destroy(context);
        ALTRunVisualGtk.cairo_surface_destroy(surface);
    }
}
#EndCSharp

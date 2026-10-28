; Native accessibility, opacity, nonactivating fades and Space policy on isolated launcher windows.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#SingleInstance Off
#NoTrayIcon
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacNativeWindow.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacNativeWindow.CleanUp())
SetTimer(() => MacNativeWindow.Fail("Timed out after 20 seconds."), -20000)
MacNativeWindow.Run()

class MacNativeWindow {
    static Folder := "", Executed := 0
    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }
    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            MacNativeWindow.Assert(A_TickCount - started < 2500, message)
            Sleep(15)
        }
    }
    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_NATIVE_WINDOW macOS-only fixture.`n", "*")
            ExitApp(0)
        }
        MacNativeWindow.Folder := Platform.Join(A_Temp, "ALTRun-MacNativeWindow-" Platform.NewUuid())
        DirCreate(MacNativeWindow.Folder)
        AppSettings.Data := AppSettings.Defaults()
        for key in ["HideOnDeactivate", "KeepLastQuery", "ShowTips", "SwitchToEnglishInput"]
            AppSettings.General[key] := 0
        AppSettings.Appearance["Fade"] := 1
        Knowledge.File := Platform.Join(MacNativeWindow.Folder, "Knowledge.json")
        Usage.File := Platform.Join(MacNativeWindow.Folder, "Usage.json")
        I18n.LangDir := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "Themes")
        ThemeManager.UserDir := MacNativeWindow.Folder
        Logger.Enabled := false
        I18n.Init("en"), ThemeManager.Load("Dark", "Compact"), Knowledge.Load(), Usage.Load()
        App.Name := "ALTRun native window fixture"
        SearchWindow.DefineProp("_RunSearch", {Call: (self, args*) => SearchWindow.SetResults([
            ResultItem("First accessible result", "A real native accessibility button", {Uid: "fixture:1", OnRun: (*) => MacNativeWindow.Executed := 1}),
            ResultItem("Second accessible result", "A second native accessibility button", {Uid: "fixture:2", OnRun: (*) => MacNativeWindow.Executed := 2})])})
        SearchWindow.Create()
        SearchWindow.Show("fixture", false)
        Sleep(220)
        SearchWindow._Repaint()
        report := JSON.Parse(ALTRunMacWindowReport(SearchWindow.Gui.ToClr(), SearchWindow.Canvas.ToClr()))
        MacNativeWindow.Assert((report["Behavior"] & 329) = 329, "The launcher lacks auxiliary/all-Spaces collection behavior.")
        MacNativeWindow.Assert(report["Children"] = 2 && report["Role"] = "AXButton", "Results do not expose separate native accessibility buttons.")
        MacNativeWindow.Assert(report["Alpha"] > 0.99, "Fade-in did not restore the theme's window opacity.")
        SearchWindow.MoveSelection(1)
        report := JSON.Parse(ALTRunMacWindowReport(SearchWindow.Gui.ToClr(), SearchWindow.Canvas.ToClr()))
        MacNativeWindow.Assert(InStr(report["Selected"], "Second accessible result"), "The native accessibility label did not follow keyboard selection.")
        FileAppend("PASS MAC_NATIVE_WINDOW auxiliary Space policy and native result accessibility tree`n", "*")
        MacNativeWindow.Assert(ALTRunMacPressFixtureResult(SearchWindow.Canvas.ToClr()), "The native result did not expose a press action.")
        MacNativeWindow.WaitFor(() => MacNativeWindow.Executed = 1 && !SearchWindow.IsVisible(), "The native accessibility action did not run its intended result.")
        Sleep(180)
        FileAppend("PASS MAC_NATIVE_WINDOW native accessibility press activates the correct result`n", "*")
        SearchWindow.Show("fixture", false)
        Sleep(180)
        SearchWindow.Hide()
        MacNativeWindow.Assert(!SearchWindow.IsVisible() && !SearchWindow.Gui.ToClr().Visible, "Fade-out delayed hiding the real launcher.")
        Sleep(180)
        report := JSON.Parse(ALTRunMacWindowReport(SearchWindow.Gui.ToClr(), SearchWindow.Canvas.ToClr()))
        MacNativeWindow.Assert(!report["Ghost"], "The nonactivating fade overlay was not released.")
        FileAppend("PASS MAC_NATIVE_WINDOW nonblocking fade lifecycle and overlay cleanup`n", "*")
        ExitApp(0)
    }
    static CleanUp() {
        if IsObject(SearchWindow.Gui)
            try SearchWindow.Gui.Destroy()
        IconCache.Clear()
        if (MacNativeWindow.Folder != "" && InStr(Platform.FullPath(MacNativeWindow.Folder), Platform.FullPath(Platform.Join(A_Temp, "ALTRun-MacNativeWindow-")), true) = 1)
            try DirDelete(MacNativeWindow.Folder, true)
    }
    static Fail(message) {
        FileAppend("FAIL MAC_NATIVE_WINDOW " message "`n", "*")
        ExitApp(1)
    }
}

#if OSX
#CSharp
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_msgSend")]
private static extern double ALTRunMacFixtureDouble(System.IntPtr target, System.IntPtr selector);
public static string ALTRunMacWindowReport(Keysharp.Builtins.Ks.Clr.ManagedInstance formWrapper,
    Keysharp.Builtins.Ks.Clr.ManagedInstance canvasWrapper)
{
    var form = (Eto.Forms.Form)formWrapper.Native;
    var canvas = (Eto.Forms.Control)canvasWrapper.Native;
    var window = (System.IntPtr)form.ControlObject.GetType().GetProperty("Handle").GetValue(form.ControlObject);
    var view = (System.IntPtr)canvas.ControlObject.GetType().GetProperty("Handle").GetValue(canvas.ControlObject);
    var children = ALTRunMacDesktopNative.Send(view, "accessibilityChildren");
    long count = ALTRunMacDesktopNative.Send(children, "count").ToInt64();
    string role = "", selected = "";
    for (long i = 0; i < count; ++i)
    {
        var child = ALTRunMacDesktopNative.Arg(children, "objectAtIndex:", (nint)i);
        var roleString = ALTRunMacDesktopNative.Send(child, "accessibilityRole");
        role = System.Runtime.InteropServices.Marshal.PtrToStringUTF8(ALTRunMacDesktopNative.Send(roleString, "UTF8String"));
        var labelString = ALTRunMacDesktopNative.Send(child, "accessibilityLabel");
        string label = System.Runtime.InteropServices.Marshal.PtrToStringUTF8(ALTRunMacDesktopNative.Send(labelString, "UTF8String"));
        if (label?.StartsWith("Selected. ") == true) selected = label;
    }
    var overlay = (System.IntPtr)typeof(ALTRunMacFade).GetField("ghost", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic).GetValue(null);
    return System.Text.Json.JsonSerializer.Serialize(new { Behavior = ALTRunMacDesktopNative.Send(window, "collectionBehavior").ToInt64(),
        Children = count, Role = role, Selected = selected, Alpha = ALTRunMacFixtureDouble(window, ALTRunMacDesktopNative.Sel("alphaValue")), Ghost = overlay != System.IntPtr.Zero });
}
public static bool ALTRunMacPressFixtureResult(Keysharp.Builtins.Ks.Clr.ManagedInstance canvasWrapper)
{
    var canvas = (Eto.Forms.Control)canvasWrapper.Native;
    var view = (System.IntPtr)canvas.ControlObject.GetType().GetProperty("Handle").GetValue(canvas.ControlObject);
    var children = ALTRunMacDesktopNative.Send(view, "accessibilityChildren");
    var child = ALTRunMacDesktopNative.Arg(children, "objectAtIndex:", 0);
    return ALTRunMacObjC.GetBool(child, ALTRunMacDesktopNative.Sel("accessibilityPerformPress")) != 0;
}
#EndCSharp
#endif

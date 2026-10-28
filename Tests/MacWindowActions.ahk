; Native window actions target only a separate, fixture-owned process and restore the previous app's focus.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Import Ks { RequestCapabilities }
#Include ../ALTRun.Modules.ahk

OnError((error, mode) => MacWindowActions.Fail(error.Message "`n" error.Stack))
OnExit((*) => MacWindowActions.CleanUp())
SetTimer(() => MacWindowActions.Fail("Timed out after 50 seconds."), -50000)
MacWindowActions.Run()

class MacWindowActions {
    static Folder := "", Job := 0, Pid := 0, Window := 0, PreviousPid := 0, PreviousWindow := 0
    static LastActual := "", LastExpected := ""

    static Check(condition, message) {
        if !condition
            throw Error(message)
    }

    static WaitFor(predicate, message, timeout := 5000) {
        started := A_TickCount
        while !predicate.Call() {
            MacWindowActions.Check(A_TickCount - started < timeout, message)
            Sleep(30)
        }
    }

    static Guard() {
        MacWindowActions.Check(MacWindowActions.Job && !ProcessRunner.IsFinished(MacWindowActions.Job), "The fixture child exited before the action.")
        MacWindowActions.Check(MacWindowActions.Pid > 0 && MacWindowActions.Pid != ProcessExist()
            && ALTRunMacWindowFixtureJobPid(MacWindowActions.Job) = MacWindowActions.Pid, "The action's process was not the owned child.")
        MacWindowActions.Check(MacWindowActions.Window > 0 && ALTRunMacWindowFixtureOwner(MacWindowActions.Window) = MacWindowActions.Pid
            , "The action's native window no longer belongs to the captured child.")
    }

    static Bounds() {
        MacWindowActions.Guard()
        WinGetPos(&x, &y, &width, &height, "ahk_id " MacWindowActions.Window)
        return {X: x, Y: y, W: width, H: height}
    }

    static Near(expected) {
        actual := MacWindowActions.Bounds()
        MacWindowActions.LastActual := actual, MacWindowActions.LastExpected := expected
        return Abs(actual.X - expected.X) <= 6 && Abs(actual.Y - expected.Y) <= 6
            && Abs(actual.W - expected.W) <= 6 && Abs(actual.H - expected.H) <= 6
    }

    static Action(operation) {
        MacWindowActions.Guard()
        MacWindowActions.Check(MacDesktop.WindowAction(MacWindowActions.Window, MacWindowActions.Pid, operation), "The native action was rejected: " operation " " ALTRunMacWindowFixtureAppState(MacWindowActions.Pid))
    }

    static Area(bounds) {
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if bounds.X + bounds.W / 2 >= left && bounds.X + bounds.W / 2 < right && bounds.Y + bounds.H / 2 >= top && bounds.Y + bounds.H / 2 < bottom
                return {X: left, Y: top, W: right - left, H: bottom - top}
        }
        throw Error("The fixture window was outside the available monitor work areas.")
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_WINDOW_ACTIONS requires macOS`n", "*")
            ExitApp(0)
        }
        status := RequestCapabilities()
        if status.WindowControl != "Granted" || status.WindowMonitoring != "Granted" {
            FileAppend("SKIP MAC_WINDOW_ACTIONS existing WindowControl and WindowMonitoring grants are required; no prompt requested.`n", "*")
            ExitApp(0)
        }
        MacWindowActions.PreviousPid := ALTRunMacFrontPid()
        try MacWindowActions.PreviousWindow := WinExist("A")
        MacWindowActions.Folder := Platform.Join(A_Temp, "ALTRun-MacWindowActions-" Platform.NewUuid())
        DirCreate(MacWindowActions.Folder)
        AppSettings.DataDir := MacWindowActions.Folder
        AppSettings.Data := AppSettings.Defaults()
        root := Platform.FullPath("..", A_ScriptDir)
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        Pinyin.DataFile := Platform.Join(root, "Resources", "Pinyin.txt")
        Logger.Enabled := false
        I18n.Init("en")
        host := ProcessRunner.ScriptHost(Platform.Join(A_ScriptDir, "Fixtures", "MacWindowTarget.ahk"), [MacWindowActions.Folder])
        MacWindowActions.Job := ProcessRunner.Start(host.Executable, host.Arguments, "", true)
        MacWindowActions.WaitFor(() => FileExist(Platform.Join(MacWindowActions.Folder, "ready")), "The separate native window fixture did not start.")
        MacWindowActions.Pid := Integer(FileRead(Platform.Join(MacWindowActions.Folder, "ready"), "UTF-8"))
        criteria := "ALTRun isolated window action target 1 ahk_pid " MacWindowActions.Pid
        MacWindowActions.WaitFor(() => WinExist(criteria), "The fixture's native window was not discoverable.")
        MacWindowActions.Window := WinExist(criteria)
        MacWindowActions.Guard()
        WindowProvider._listTime := -10000
        ownWindows := []
        for window in WindowProvider.List()
            if ALTRunMacWindowFixtureOwner(window.Hwnd) = MacWindowActions.Pid && RegExMatch(window.Title, "^ALTRun isolated window action target [12]$")
                ownWindows.Push(WindowProvider.ItemFor(window, 100))
        MacWindowActions.Check(ownWindows.Length = 2 && ProviderRegistry._Dedupe(ownWindows).Length = 2, "Two windows of the same owned application were deduplicated (listed=" ownWindows.Length ", deduped=" ProviderRegistry._Dedupe(ownWindows).Length ").")
        FileAppend("PASS MAC_WINDOW_ACTIONS two native windows retain distinct result identities`n", "*")
        WindowProvider.Activate(MacWindowActions.Window)
        MacWindowActions.WaitFor(() => ALTRunMacFrontPid() = MacWindowActions.Pid, "WindowProvider did not activate the separate fixture.")
        MacWindowActions.Guard()
        WinMinimize("ahk_id " MacWindowActions.Window)
        MacWindowActions.WaitFor(() => WinGetMinMax("ahk_id " MacWindowActions.Window) = -1, "The fixture did not minimize.")
        MacWindowActions.Guard()
        WindowProvider.Activate(MacWindowActions.Window)
        MacWindowActions.WaitFor(() => WinGetMinMax("ahk_id " MacWindowActions.Window) != -1 && ALTRunMacFrontPid() = MacWindowActions.Pid
            , "WindowProvider did not restore and activate a minimized window.")
        FileAppend("PASS MAC_WINDOW_ACTIONS separate native target discovery, minimize, restore and activation`n", "*")

        bounds := MacWindowActions.Bounds(), area := MacWindowActions.Area(bounds)
        expected := {X: area.X + (area.W - Min(bounds.W, area.W)) / 2, Y: area.Y + (area.H - Min(bounds.H, area.H)) / 2
            , W: Min(bounds.W, area.W), H: Min(bounds.H, area.H)}
        MacWindowActions.Action("Center")
        MacWindowActions.WaitFor(() => MacWindowActions.Near(expected), "Center did not match the target monitor's work area.")
        half := Floor(area.W / 2)
        expected := {X: area.X, Y: area.Y, W: half, H: area.H}
        MacWindowActions.Action("Left")
        MacWindowActions.WaitFor(() => MacWindowActions.Near(expected), "Left half did not match the target monitor's work area.")
        expected := {X: area.X + half, Y: area.Y, W: area.W - half, H: area.H}
        MacWindowActions.Action("Right")
        MacWindowActions.WaitFor(() => MacWindowActions.Near(expected), "Right half did not match the target monitor's work area.")
        expected := {X: area.X, Y: area.Y, W: area.W, H: area.H}
        MacWindowActions.Action("Maximize")
        MacWindowActions.WaitFor(() => MacWindowActions.Near(expected), "Maximize did not match the target monitor's work area.")
        FileAppend("PASS MAC_WINDOW_ACTIONS native center, left/right halves and work-area maximize`n", "*")

        MacWindowActions.Action("Hide")
        MacWindowActions.WaitFor(() => ALTRunMacWindowFixtureHidden(MacWindowActions.Pid), "The owned application did not hide.")
        MacWindowActions.Guard()
        WindowProvider.Activate(MacWindowActions.Window)
        MacWindowActions.WaitFor(() => !ALTRunMacWindowFixtureHidden(MacWindowActions.Pid) && ALTRunMacFrontPid() = MacWindowActions.Pid
            , "WindowProvider did not reactivate the hidden owned application.")
        FileAppend("PASS MAC_WINDOW_ACTIONS native hide and reactivation`n", "*")

        MacWindowActions.Action("Quit")
        MacWindowActions.WaitFor(() => ProcessRunner.IsFinished(MacWindowActions.Job), "Normal application quit did not stop the owned child.")
        result := ProcessRunner.Result(MacWindowActions.Job)
        MacWindowActions.Job := 0
        MacWindowActions.Check(result["ExitCode"] = 0, "Normal application quit returned an abnormal exit code: " result["ExitCode"] " " result["Error"])
        MacWindowActions.Check(FileExist(Platform.Join(MacWindowActions.Folder, "quit-requested")), "The child did not receive a native termination request.")
        MacWindowActions.Check(FileExist(Platform.Join(MacWindowActions.Folder, "exited")), "Normal application quit skipped the child's OnExit cleanup.")
        FileAppend("PASS MAC_WINDOW_ACTIONS normal quit of owned child with OnExit cleanup`n", "*")
        ExitApp(0)
    }

    static CleanUp() {
        if MacWindowActions.Job {
            try {
                FileAppend("stop", Platform.Join(MacWindowActions.Folder, "stop"), "UTF-8-RAW")
                started := A_TickCount
                while !ProcessRunner.IsFinished(MacWindowActions.Job) && A_TickCount - started < 1000
                    Sleep(25)
                ProcessRunner.Finish(MacWindowActions.Job, true)
            }
        }
        if MacWindowActions.PreviousPid > 0 && MacWindowActions.PreviousPid != MacWindowActions.Pid
            try ALTRunMacWindowFixtureFocus(MacWindowActions.PreviousPid)
        if MacWindowActions.Folder != ""
            try DirDelete(MacWindowActions.Folder, true)
    }

    static Fail(message) {
        if IsObject(MacWindowActions.LastActual) {
            a := MacWindowActions.LastActual, e := MacWindowActions.LastExpected
            message .= "`nLast geometry actual=" a.X "," a.Y "," a.W "," a.H " expected=" e.X "," e.Y "," e.W "," e.H
        }
        FileAppend("FAIL MAC_WINDOW_ACTIONS " message "`n", "*")
        ExitApp(1)
    }
}

#if OSX
#CSharp
[System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")]
private static extern nint CGWindowListCreateDescriptionFromArray(nint array);
[System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")]
private static extern nint CFArrayCreate(nint allocator,nint[] values,nint count,nint callbacks);
public static long ALTRunMacWindowFixtureJobPid(long job) => ALTRunProcessJobs.TryGetValue(job,out var entry)?entry.Process.Id:0;
public static long ALTRunMacWindowFixtureOwner(long window)
{
    if(window<=0 || window>uint.MaxValue)return 0;
    var ids=CFArrayCreate(0,[(nint)window],1,0); if(ids==0)return 0;
    var array=CGWindowListCreateDescriptionFromArray(ids); ALTRunMacDesktopNative.CFRelease(ids); if(array==0)return 0;
    try {
        for(long index=0;index<(long)ALTRunMacDesktopNative.CFArrayGetCount(array);index++) {
            var item=ALTRunMacDesktopNative.CFArrayGetValueAtIndex(array,(nint)index);
            var number=ALTRunMacDesktopNative.Arg(item,ALTRunMacDesktopNative.Sel("objectForKey:"),ALTRunMacDesktopNative.Text("kCGWindowNumber"));
            if((long)ALTRunMacDesktopNative.Send(number,ALTRunMacDesktopNative.Sel("unsignedIntValue"))!=window)continue;
            var owner=ALTRunMacDesktopNative.Arg(item,ALTRunMacDesktopNative.Sel("objectForKey:"),ALTRunMacDesktopNative.Text("kCGWindowOwnerPID"));
            return (long)ALTRunMacDesktopNative.Send(owner,ALTRunMacDesktopNative.Sel("intValue"));
        }
        return 0;
    }finally{ALTRunMacDesktopNative.CFRelease(array);}
}
public static bool ALTRunMacWindowFixtureHidden(long pid)
{
    var app=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSRunningApplication"),ALTRunMacDesktopNative.Sel("runningApplicationWithProcessIdentifier:"),(nint)pid);
    return app!=0 && ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("isHidden"))!=0;
}
public static string ALTRunMacWindowFixtureAppState(long pid)
{
    var app=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSRunningApplication"),ALTRunMacDesktopNative.Sel("runningApplicationWithProcessIdentifier:"),(nint)pid);
    return app==0?"app-not-found":System.Text.Json.JsonSerializer.Serialize(new {
        Pid=(long)ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("processIdentifier")),
        Policy=(long)ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("activationPolicy")),
        Hidden=(long)ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("isHidden")),
        Terminated=(long)ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("isTerminated")),
        Bundle=ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Send(app,ALTRunMacDesktopNative.Sel("bundleIdentifier"))) });
}
public static void ALTRunMacWindowFixtureFocus(long pid) => Eto.Forms.Application.Instance.Invoke(() => {
    var app=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSRunningApplication"),ALTRunMacDesktopNative.Sel("runningApplicationWithProcessIdentifier:"),(nint)pid);
    if(app!=0)ALTRunMacDesktopNative.Arg(app,ALTRunMacDesktopNative.Sel("activateWithOptions:"),2);
});
#EndCSharp
#endif

; Owned separate process for native window actions. Never opens user files or accepts external commands.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Import Ks { Clr }

if A_Args.Length != 1 || !DirExist(A_Args[1])
    ExitApp(2)
MacWindowTarget.Start(A_Args[1])

class MacWindowTarget {
    static Folder := "", Windows := [], QuitRequested := false

    static Start(folder) {
        MacWindowTarget.Folder := folder
        OnExit((reason, code) => MacWindowTarget.Exiting(reason, code))
        ; Persistent Keysharp hosts veto native Quit by default. This fixture models an
        ; application that consents and performs its normal asynchronous cleanup.
        ALTRunMacWindowTargetAcceptQuit(() => MacWindowTarget.RequestQuit())
        Loop 2 {
            title := "ALTRun isolated window action target " A_Index
            window := Gui("+Resize", title)
            window.AddText("w300", "Owned native window fixture " A_Index)
            window.OnEvent("Close", (*) => ExitApp(0))
            window.Show("x" (120 + A_Index * 60) " y" (120 + A_Index * 50) " w480 h240")
            MacWindowTarget.Windows.Push(window)
        }
        ALTRunMacWindowTargetActivate(MacWindowTarget.Windows[1].ToClr())
        FileAppend(ProcessExist() "", folder "/ready-next", "UTF-8-RAW")
        FileMove(folder "/ready-next", folder "/ready")
        SetTimer(() => MacWindowTarget.Poll(), 50)
        SetTimer(() => ExitApp(3), -60000)
    }

    static Poll() {
        commandFile := MacWindowTarget.Folder "/stop"
        if FileExist(commandFile)
            ExitApp(0)
    }

    static Exiting(reason, code) {
        ALTRunMacWindowTargetExiting()
        try FileAppend(reason ":" code, MacWindowTarget.Folder "/exited", "UTF-8-RAW")
    }

    static RequestQuit() {
        if MacWindowTarget.QuitRequested
            return
        MacWindowTarget.QuitRequested := true
        FileAppend("native request", MacWindowTarget.Folder "/quit-requested", "UTF-8-RAW")
        SetTimer(() => ExitApp(0), -1)
    }
}

#CSharp
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib",EntryPoint="objc_getClass")]
private static extern nint ALTRunMacWindowTargetClass(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib",EntryPoint="sel_registerName")]
private static extern nint ALTRunMacWindowTargetSel(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib",EntryPoint="objc_msgSend")]
private static extern nint ALTRunMacWindowTargetSend(nint target,nint selector);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib",EntryPoint="objc_msgSend")]
private static extern void ALTRunMacWindowTargetBool(nint target,nint selector,byte value);
private static bool ALTRunMacWindowTargetIsExiting;
public static void ALTRunMacWindowTargetExiting() => ALTRunMacWindowTargetIsExiting=true;
public static void ALTRunMacWindowTargetAcceptQuit(Keysharp.Builtins.KeysharpFunc callback)
    => Eto.Forms.Application.Instance.Invoke(() => Eto.Forms.Application.Instance.Terminating += (_,e) => {
        if(ALTRunMacWindowTargetIsExiting) { e.Cancel=false; return; }
        e.Cancel=true; callback.Call();
    });
public static void ALTRunMacWindowTargetActivate(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper)
{
    var form=(Eto.Forms.Form)wrapper.Native;
    Eto.Forms.Application.Instance.Invoke(() => {
        form.Show(); form.BringToFront();
        var application=ALTRunMacWindowTargetSend(ALTRunMacWindowTargetClass("NSApplication"),ALTRunMacWindowTargetSel("sharedApplication"));
        ALTRunMacWindowTargetBool(application,ALTRunMacWindowTargetSel("activateIgnoringOtherApps:"),1);
    });
}
#EndCSharp

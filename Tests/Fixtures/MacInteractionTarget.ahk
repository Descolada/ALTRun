; A separate, fixture-owned native receiver. The pass-through paste monitor is active only in its own window.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#SingleInstance Off
#NoTrayIcon
#Import Ks { Clr, Clipboard }

if (A_Args.Length != 1 || !DirExist(A_Args[1]))
    ExitApp(2)
MacInteractionTarget.Start(A_Args[1])

class MacInteractionTarget {
    static Folder := "", Gui := "", Edit := ""
    static Start(folder) {
        MacInteractionTarget.Folder := folder
        g := Gui("+AlwaysOnTop", "ALTRun isolated native interaction target")
        MacInteractionTarget.Gui := g
        MacInteractionTarget.Edit := g.AddEdit("w500 r4", "")
        MacInteractionTarget.Edit.OnEvent("Change", (*) => MacInteractionTarget.PublishText())
        HotIf((*) => IsObject(MacInteractionTarget.Gui) && MacInteractionTarget.Gui.ToClr().HasFocus)
        Hotkey("~#v", (*) => MacInteractionTarget.Paste())
        HotIf()
        g.OnEvent("Close", (*) => ExitApp())
        g.Show(), MacInteractionTarget.Edit.Focus()
        ALTRunMacTargetActivate(g.ToClr())
        FileAppend(ProcessExist() "", folder "/ready-next", "UTF-8")
        FileMove(folder "/ready-next", folder "/ready")
        SetTimer(() => MacInteractionTarget.Tick(), 50)
        SetTimer(() => ExitApp(3), -45000)
    }

    static Tick() {
        path := MacInteractionTarget.Folder "/command"
        if !FileExist(path)
            return
        command := FileRead(path, "UTF-8")
        FileDelete(path)
        if (command = "stop")
            ExitApp(0)
        if (command = "clear")
            MacInteractionTarget.Edit.Value := ""
        MacInteractionTarget.Edit.Focus()
        ALTRunMacTargetActivate(MacInteractionTarget.Gui.ToClr())
        MacInteractionTarget.PublishText()
        FileAppend("ready", MacInteractionTarget.Folder "/ack", "UTF-8")
    }

    static PublishText() {
        stream := FileOpen(MacInteractionTarget.Folder "/text", "w", "UTF-8-RAW")
        try stream.Write(MacInteractionTarget.Edit.Value)
        finally stream.Close()
    }

    static Paste() {
        kind := Clipboard.Has("Files") ? "files" : Clipboard.Has("Image") ? "image" : "text"
        stream := FileOpen(MacInteractionTarget.Folder "/paste", "w", "UTF-8-RAW")
        try stream.Write(kind)
        finally stream.Close()
        return kind != "text"
    }
}

#CSharp
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_getClass")]
private static extern System.IntPtr ALTRunMacTargetClass(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="sel_registerName")]
private static extern System.IntPtr ALTRunMacTargetSelector(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_msgSend")]
private static extern System.IntPtr ALTRunMacTargetSend(System.IntPtr target, System.IntPtr selector);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_msgSend")]
private static extern void ALTRunMacTargetSendBool(System.IntPtr target, System.IntPtr selector, byte value);
public static void ALTRunMacTargetActivate(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper)
{
    var form = (Eto.Forms.Form)wrapper.Native;
    form.Show(); form.BringToFront();
    var app = ALTRunMacTargetSend(ALTRunMacTargetClass("NSApplication"), ALTRunMacTargetSelector("sharedApplication"));
    ALTRunMacTargetSendBool(app, ALTRunMacTargetSelector("activateIgnoringOtherApps:"), 1);
}
#EndCSharp

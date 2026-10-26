; WindowsIdentity - check process taskbar identity and injected icon ordering; no shell settings changes or GUI.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => WindowsIdentity.OnError(err, mode))
OnExit((*) => WindowsIdentity.CleanUp())
WindowsIdentity.Run()

class WindowsIdentity {
    static Calls := [], Icons := [], Fixture := "", PreviousIcon := "", PreviousIdentity := false

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        Logger.Enabled := false
        WindowsIdentity.PreviousIcon := App.IconFile
        WindowsIdentity.PreviousIdentity := App._applicationIdentitySet
        WindowsIdentity.Fixture := Platform.Join(A_Temp, "ALTRun-Identity-" Platform.NewUuid() ".ico")
        FileAppend("Inert icon fixture; the injected setter never decodes it.", WindowsIdentity.Fixture, "UTF-8-RAW")
        App.IconFile := WindowsIdentity.Fixture
        result := App._SetApplicationIdentity((identity) => WindowsIdentity.SetIdentity(identity))
        WindowsIdentity.Assert(result = Platform.IsWindows && WindowsIdentity.Calls.Length = (Platform.IsWindows ? 1 : 0), "Only Windows should set the process taskbar identity.")
        if Platform.IsWindows {
            WindowsIdentity.Assert(WindowsIdentity.Calls[1] == "Keysharp.ALTRun", "ALTRun must use its own stable identity.")
            WindowsIdentity.Assert(App._SetIcon((icon) => WindowsIdentity.SetIcon(icon)), "The isolated ALTRun process should receive its icon.")
            WindowsIdentity.Assert(WindowsIdentity.Icons.Length = 1 && WindowsIdentity.Icons[1] == WindowsIdentity.Fixture, "The icon setter must receive only ALTRun's icon.")
            WindowsIdentity.Assert(!App._SetApplicationIdentity((identity) => -1), "A failed identity setter must be reported.")
            WindowsIdentity.Assert(!App._SetIcon((icon) => WindowsIdentity.SetIcon(icon)) && WindowsIdentity.Icons.Length = 1, "An unisolated host must not receive ALTRun's taskbar icon.")
        } else {
            WindowsIdentity.Assert(App._SetIcon((icon) => WindowsIdentity.SetIcon(icon)), "Other platforms should retain their normal icon path.")
        }
#if WINDOWS
        WindowsIdentity.Assert(App._SetApplicationIdentity(), "The Windows process identity could not be set.")
        pointer := 0
        try {
            status := DllCall("shell32\GetCurrentProcessExplicitAppUserModelID", "Ptr*", &pointer, "Int")
            WindowsIdentity.Assert(status = 0 && pointer != 0, "Windows did not return the explicit process identity.")
            WindowsIdentity.Assert(StrGet(pointer, "UTF-16") == App.ApplicationId, "Windows associated the process with the wrong taskbar identity.")
        } finally {
            if pointer
                DllCall("ole32\CoTaskMemFree", "Ptr", pointer)
        }
#endif
        FileAppend("PASS WINDOWS_IDENTITY separate taskbar identity, platform gating and guarded icon assignment`n", "*")
        ExitApp(0)
    }

    static SetIdentity(identity) {
        WindowsIdentity.Calls.Push(identity)
        return 0
    }

    static SetIcon(icon) {
        WindowsIdentity.Icons.Push(icon)
    }

    static CleanUp() {
        App.IconFile := WindowsIdentity.PreviousIcon
        App._applicationIdentitySet := WindowsIdentity.PreviousIdentity
        if (WindowsIdentity.Fixture != "")
            try FileDelete(WindowsIdentity.Fixture)
    }

    static OnError(err, mode) {
        FileAppend("FAIL WINDOWS_IDENTITY " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }
}

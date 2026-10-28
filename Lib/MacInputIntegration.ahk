; Native macOS input sources and focused-field metadata. Permission checks never prompt.
class MacInputIntegration {
    static _before := "", _selected := ""
    static _capsPressed := false, _capsHeld := false, _capsShift := false
    static _capsTimer := () => MacInputIntegration._CapsHold()

    static Init() {
        if (!Platform.IsMac || AppSettings.General["CapsLock"] != "Layout")
            return
        try {
            Hotkey("*$CapsLock", (*) => MacInputIntegration._CapsDown())
            Hotkey("*$CapsLock up", (*) => MacInputIntegration._CapsUp())
        } catch as e
            Logger.Error("macOS Caps Lock: " e.Message)
    }

    static Stop() {
        MacInputIntegration.OnHide()
        SetTimer(MacInputIntegration._capsTimer, 0)
    }

    static CaptureBeforeShow(wasVisible := false) {
        if (Platform.IsMac && !wasVisible && AppSettings.General["SwitchToEnglishInput"] = 1)
            MacInputIntegration._before := MacInputIntegration.CurrentSource()
    }

    static OnShow(wasVisible := false) {
        if (!Platform.IsMac || AppSettings.General["SwitchToEnglishInput"] != 1)
            return
        if (wasVisible && MacInputIntegration._selected != "")
            return
        if (MacInputIntegration._before = "")
            MacInputIntegration._before := MacInputIntegration.CurrentSource()
        preferred := AppSettings.General.Has("MacInputSource") ? AppSettings.General["MacInputSource"] : ""
        selected := MacInputIntegration.EnglishSource(preferred)
        if (selected != "" && MacInputIntegration.SelectSource(selected))
            MacInputIntegration._selected := selected
    }

    static OnHide() {
        before := MacInputIntegration._before, selected := MacInputIntegration._selected
        MacInputIntegration._before := "", MacInputIntegration._selected := ""
        ; A manual source change while searching wins over the remembered source.
        if (Platform.IsMac && before != "" && selected != "" && AppSettings.General["RestoreInput"]
            && MacInputIntegration.CurrentSource() = selected)
            MacInputIntegration.SelectSource(before)
    }

    static Sources() {
        sources := []
#if OSX
        for line in StrSplit(ALTRunMacInputSources(), "`n") {
            parts := StrSplit(line, "`t")
            if (parts.Length >= 3)
                sources.Push({Id: parts[1], Label: parts[2], Ascii: parts[3] = "1"})
        }
#endif
        return sources
    }

    static EnglishSource(preferred := "") {
        sources := MacInputIntegration.Sources(), fallback := ""
        for source in sources {
            if (preferred != "" && source.Id = preferred)
                return source.Id
            if source.Ascii {
                if (fallback = "" || source.Id = "com.apple.keylayout.US" || source.Id = "com.apple.keylayout.ABC")
                    fallback := source.Id
            }
        }
        return fallback
    }

    static CurrentSource() {
#if OSX
        return ALTRunMacCurrentInputSource()
#else
        return ""
#endif
    }

    static SelectSource(id) {
#if OSX
        return ALTRunMacSelectInputSource(id)
#else
        return false
#endif
    }

    static NextSource() {
        sources := MacInputIntegration.Sources(), current := MacInputIntegration.CurrentSource()
        for index, source in sources
            if (source.Id = current)
                return MacInputIntegration.SelectSource(sources[Mod(index, sources.Length) + 1].Id)
        return false
    }

    static IsSecureField() {
#if OSX
        return ALTRunMacSecureField()
#else
        return false
#endif
    }

    static FrontmostBundleId() {
#if OSX
        return ALTRunMacFrontmostBundleId()
#else
        return ""
#endif
    }

    static FrontmostProcessName() {
#if OSX
        return ALTRunMacFrontmostProcessName()
#else
        return ""
#endif
    }

    static IsExcluded(exclusions) {
        bundle := MacInputIntegration.FrontmostBundleId()
        for excluded in exclusions {
            value := RegExReplace(Trim(excluded), "i)^bundle(?:id)?:\s*")
            if (bundle != "" && bundle = value)
                return true
        }
        return false
    }

    static _CapsDown() {
        if MacInputIntegration._capsPressed
            return
        MacInputIntegration._capsPressed := true, MacInputIntegration._capsHeld := false
        MacInputIntegration._capsShift := GetKeyState("Shift")
        SetTimer(MacInputIntegration._capsTimer, -300)
    }

    static _CapsHold() {
        if !MacInputIntegration._capsPressed
            return
        MacInputIntegration._capsHeld := true
        MacInputIntegration._ToggleCaps()
    }

    static _ToggleCaps() {
        on := !GetKeyState("CapsLock", "T")
        SetCapsLockState(on ? "On" : "Off")
        App.CapsLockNotice(on)
    }

    static _CapsUp() {
        if !MacInputIntegration._capsPressed
            return
        MacInputIntegration._capsPressed := false
        SetTimer(MacInputIntegration._capsTimer, 0)
        if !MacInputIntegration._capsHeld {
            if MacInputIntegration._capsShift
                MacInputIntegration._ToggleCaps()
            else
                MacInputIntegration.NextSource()
        }
    }
}

#if OSX
#CSharp
public static string ALTRunMacInputSources() => ALTRunMacInputNative.Sources();
public static string ALTRunMacCurrentInputSource() => ALTRunMacInputNative.Current();
public static bool ALTRunMacSelectInputSource(string id) => ALTRunMacInputNative.Select(id);
public static bool ALTRunMacSecureField() => ALTRunMacInputNative.SecureField();
public static string ALTRunMacFrontmostBundleId() => ALTRunMacInputNative.FrontmostBundle();
public static string ALTRunMacFrontmostProcessName() => ALTRunMacInputNative.FrontmostProcess();

private static class ALTRunMacInputNative
{
    private const string Carbon = "/System/Library/Frameworks/Carbon.framework/Carbon";
    private static readonly nint carbon = System.Runtime.InteropServices.NativeLibrary.Load(Carbon);
    private static readonly nint focusedAttribute = ALTRunMacDesktopNative.CFRetain(ALTRunMacDesktopNative.Text("AXFocusedUIElement"));
    private static readonly nint subroleAttribute = ALTRunMacDesktopNative.CFRetain(ALTRunMacDesktopNative.Text("AXSubrole"));
    private static nint Key(string name) => System.Runtime.InteropServices.Marshal.ReadIntPtr(System.Runtime.InteropServices.NativeLibrary.GetExport(carbon, name));
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISCreateInputSourceList(nint properties, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)] bool all);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISCopyCurrentKeyboardInputSource();
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISGetInputSourceProperty(nint source, nint key);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern int TISSelectInputSource(nint source);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern byte IsSecureEventInputEnabled();
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")]
    private static extern byte CFBooleanGetValue(nint value);
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")]
    private static extern byte AXIsProcessTrusted();

    private static string Id(nint source) => ALTRunMacDesktopNative.String(TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceID")));
    private static bool KeyboardSource(nint source)
    {
        string type = ALTRunMacDesktopNative.String(TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceType")));
        return type == "TISTypeKeyboardLayout" || type == "TISTypeKeyboardInputMode";
    }

    private static System.Collections.Generic.IEnumerable<nint> EnabledSources()
    {
        nint list = TISCreateInputSourceList(0, false);
        if (list == 0) yield break;
        try
        {
            nint count = ALTRunMacDesktopNative.CFArrayGetCount(list);
            for (nint index = 0; index < count; ++index)
            {
                nint source = ALTRunMacDesktopNative.CFArrayGetValueAtIndex(list, index);
                if (KeyboardSource(source)) yield return source;
            }
        }
        finally { ALTRunMacDesktopNative.CFRelease(list); }
    }

    internal static string Sources()
    {
        var lines = new System.Collections.Generic.List<string>();
        foreach (nint source in EnabledSources())
        {
            string id = Id(source), label = ALTRunMacDesktopNative.String(TISGetInputSourceProperty(source, Key("kTISPropertyLocalizedName")));
            nint ascii = TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceIsASCIICapable"));
            if (id.Length > 0) lines.Add(id + "\t" + label.Replace('\t', ' ').Replace('\n', ' ') + "\t" + (ascii != 0 && CFBooleanGetValue(ascii) != 0 ? "1" : "0"));
        }
        return string.Join("\n", lines);
    }

    internal static string Current()
    {
        nint source = TISCopyCurrentKeyboardInputSource();
        try { return source == 0 ? "" : Id(source); }
        finally { if (source != 0) ALTRunMacDesktopNative.CFRelease(source); }
    }

    internal static bool Select(string id)
    {
        if (string.IsNullOrEmpty(id)) return false;
        foreach (nint source in EnabledSources())
            if (Id(source) == id) return TISSelectInputSource(source) == 0;
        return false;
    }

    internal static bool SecureField()
    {
        // Never request permission from a hotstring callback. Without a trustworthy focus read, do not expand.
        if (IsSecureEventInputEnabled() != 0 || AXIsProcessTrusted() == 0) return true;
        int pid = ALTRunMacDesktopNative.FrontPid();
        if (pid <= 0) return true;
        nint system = ALTRunMacDesktopNative.AXUIElementCreateApplication(pid), focused = 0, subrole = 0;
        try
        {
            ALTRunMacDesktopNative.AXUIElementSetMessagingTimeout(system, 0.05f);
            if (ALTRunMacDesktopNative.AXUIElementCopyAttributeValue(system, focusedAttribute, out focused) != 0 || focused == 0) return true;
            ALTRunMacDesktopNative.AXUIElementSetMessagingTimeout(focused, 0.05f);
            int status = ALTRunMacDesktopNative.AXUIElementCopyAttributeValue(focused, subroleAttribute, out subrole);
            // Text areas need not have a subrole; failed/time-out reads must never enable expansion.
            return status == 0 ? ALTRunMacDesktopNative.String(subrole) == "AXSecureTextField" : status != -25205 && status != -25212;
        }
        finally
        {
            if (subrole != 0) ALTRunMacDesktopNative.CFRelease(subrole);
            if (focused != 0) ALTRunMacDesktopNative.CFRelease(focused);
            if (system != 0) ALTRunMacDesktopNative.CFRelease(system);
        }
    }

    private static nint FrontmostApp() => ALTRunMacDesktopNative.Send(
        ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSWorkspace"), "sharedWorkspace"),
        "frontmostApplication");

    internal static string FrontmostBundle() => ALTRunMacDesktopNative.String(
        ALTRunMacDesktopNative.Send(FrontmostApp(), "bundleIdentifier"));

    internal static string FrontmostProcess()
    {
        nint url = ALTRunMacDesktopNative.Send(FrontmostApp(), "executableURL");
        return ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Send(
            ALTRunMacDesktopNative.Send(url, "path"), "lastPathComponent"));
    }

}
#EndCSharp
#endif

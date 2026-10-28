; Native macOS input sources and focused-field metadata. Permission checks never prompt.
class MacInputIntegration {
    static _before := "", _selected := ""
    static _capsPressed := false, _capsHeld := false, _capsShift := false, _capsTimer := ""

    static Init() {
        if !Platform.IsMac
            return
        if (AppSettings.General["CapsLock"] != "Layout")
            return
        try {
            Hotkey("*$CapsLock", (*) => MacInputIntegration._CapsDown())
            Hotkey("*$CapsLock up", (*) => MacInputIntegration._CapsUp())
        } catch as e
            Logger.Error("macOS Caps Lock: " e.Message)
    }

    static Stop() {
        MacInputIntegration.OnHide()
        if IsObject(MacInputIntegration._capsTimer)
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

    static IsExcluded(exclusions, processName := "") {
        bundle := MacInputIntegration.FrontmostBundleId()
        for excluded in exclusions {
            value := RegExReplace(Trim(excluded), "i)^bundle(?:id)?:\s*")
            if (bundle != "" && bundle = value)
                return true
            if (processName != "" && processName = RegExReplace(value, "i)\.exe$"))
                return true
        }
        return false
    }

    static _CapsDown() {
        if MacInputIntegration._capsPressed
            return
        MacInputIntegration._capsPressed := true, MacInputIntegration._capsHeld := false
        MacInputIntegration._capsShift := GetKeyState("Shift")
        MacInputIntegration._capsTimer := () => MacInputIntegration._CapsHold()
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
        if IsObject(MacInputIntegration._capsTimer)
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
    private const string CF = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const string AX = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
    private const string ObjC = "/usr/lib/libobjc.A.dylib";
    private static readonly nint carbon = System.Runtime.InteropServices.NativeLibrary.Load(Carbon);
    private static nint Key(string name) => System.Runtime.InteropServices.Marshal.ReadIntPtr(System.Runtime.InteropServices.NativeLibrary.GetExport(carbon, name));
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISCreateInputSourceList(nint properties, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)] bool all);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISCopyCurrentKeyboardInputSource();
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern nint TISGetInputSourceProperty(nint source, nint key);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern int TISSelectInputSource(nint source);
    [System.Runtime.InteropServices.DllImport(Carbon)] private static extern byte IsSecureEventInputEnabled();
    [System.Runtime.InteropServices.DllImport(CF)] private static extern long CFArrayGetCount(nint array);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern nint CFArrayGetValueAtIndex(nint array, long index);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern void CFRelease(nint value);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern long CFStringGetLength(nint value);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern byte CFStringGetCString(nint value, byte[] buffer, long length, uint encoding);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern byte CFBooleanGetValue(nint value);
    [System.Runtime.InteropServices.DllImport(CF)] private static extern nint CFStringCreateWithCString(nint allocator, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string value, uint encoding);
    [System.Runtime.InteropServices.DllImport(AX)] private static extern nint AXUIElementCreateApplication(int pid);
    [System.Runtime.InteropServices.DllImport(AX)] private static extern int AXUIElementSetMessagingTimeout(nint element, float seconds);
    [System.Runtime.InteropServices.DllImport(AX)] private static extern int AXUIElementCopyAttributeValue(nint element, nint attribute, out nint value);
    [System.Runtime.InteropServices.DllImport(AX)] private static extern byte AXIsProcessTrusted();
    [System.Runtime.InteropServices.DllImport(ObjC)] private static extern nint objc_getClass(string name);
    [System.Runtime.InteropServices.DllImport(ObjC)] private static extern nint sel_registerName(string name);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] private static extern nint Send(nint target, nint selector);

    private static string Text(nint value)
    {
        if (value == 0) return "";
        var buffer = new byte[checked((int)CFStringGetLength(value) * 4 + 1)];
        if (CFStringGetCString(value, buffer, buffer.Length, 0x08000100) == 0) return "";
        int end = System.Array.IndexOf(buffer, (byte)0);
        return System.Text.Encoding.UTF8.GetString(buffer, 0, end < 0 ? buffer.Length : end);
    }

    private static string Id(nint source) => Text(TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceID")));
    private static bool KeyboardSource(nint source)
    {
        string type = Text(TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceType")));
        return type == "TISTypeKeyboardLayout" || type == "TISTypeKeyboardInputMode";
    }

    internal static string Sources()
    {
        nint list = TISCreateInputSourceList(0, false);
        if (list == 0) return "";
        try
        {
            var lines = new System.Collections.Generic.List<string>();
            for (long i = 0; i < CFArrayGetCount(list); ++i)
            {
                nint source = CFArrayGetValueAtIndex(list, i);
                if (!KeyboardSource(source)) continue;
                string id = Id(source), label = Text(TISGetInputSourceProperty(source, Key("kTISPropertyLocalizedName")));
                nint ascii = TISGetInputSourceProperty(source, Key("kTISPropertyInputSourceIsASCIICapable"));
                if (id.Length > 0) lines.Add(id + "\t" + label.Replace('\t', ' ').Replace('\n', ' ') + "\t" + (ascii != 0 && CFBooleanGetValue(ascii) != 0 ? "1" : "0"));
            }
            return string.Join("\n", lines);
        }
        finally { CFRelease(list); }
    }

    internal static string Current()
    {
        nint source = TISCopyCurrentKeyboardInputSource();
        try { return source == 0 ? "" : Id(source); }
        finally { if (source != 0) CFRelease(source); }
    }

    internal static bool Select(string id)
    {
        if (string.IsNullOrEmpty(id)) return false;
        nint list = TISCreateInputSourceList(0, false);
        if (list == 0) return false;
        try
        {
            for (long i = 0; i < CFArrayGetCount(list); ++i)
            {
                nint source = CFArrayGetValueAtIndex(list, i);
                if (KeyboardSource(source) && Id(source) == id) return TISSelectInputSource(source) == 0;
            }
            return false;
        }
        finally { CFRelease(list); }
    }

    internal static bool SecureField()
    {
        // Never request permission from a hotstring callback. Without a trustworthy focus read, do not expand.
        if (IsSecureEventInputEnabled() != 0 || AXIsProcessTrusted() == 0) return true;
        nint workspace = Send(objc_getClass("NSWorkspace"), sel_registerName("sharedWorkspace"));
        nint app = Send(workspace, sel_registerName("frontmostApplication"));
        int pid = checked((int)Send(app, sel_registerName("processIdentifier")));
        if (pid <= 0) return true;
        nint system = AXUIElementCreateApplication(pid), focused = 0, attr = 0, subrole = 0;
        try
        {
            AXUIElementSetMessagingTimeout(system, 0.05f);
            attr = CFStringCreateWithCString(0, "AXFocusedUIElement", 0x08000100);
            if (AXUIElementCopyAttributeValue(system, attr, out focused) != 0 || focused == 0) return true;
            AXUIElementSetMessagingTimeout(focused, 0.05f);
            CFRelease(attr); attr = CFStringCreateWithCString(0, "AXSubrole", 0x08000100);
            int status = AXUIElementCopyAttributeValue(focused, attr, out subrole);
            // Text areas need not have a subrole; failed/time-out reads must never enable expansion.
            return status == 0 ? Text(subrole) == "AXSecureTextField" : status != -25205 && status != -25212;
        }
        finally
        {
            if (subrole != 0) CFRelease(subrole);
            if (focused != 0) CFRelease(focused);
            if (attr != 0) CFRelease(attr);
            if (system != 0) CFRelease(system);
        }
    }

    internal static string FrontmostBundle()
    {
        nint workspace = Send(objc_getClass("NSWorkspace"), sel_registerName("sharedWorkspace"));
        nint app = Send(workspace, sel_registerName("frontmostApplication"));
        return Text(Send(app, sel_registerName("bundleIdentifier")));
    }

    internal static string FrontmostProcess()
    {
        nint workspace = Send(objc_getClass("NSWorkspace"), sel_registerName("sharedWorkspace"));
        nint app = Send(workspace, sel_registerName("frontmostApplication"));
        nint url = Send(app, sel_registerName("executableURL"));
        return Text(Send(Send(url, sel_registerName("path")), sel_registerName("lastPathComponent")));
    }
}
#EndCSharp
#endif

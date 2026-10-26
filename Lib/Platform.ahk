; Shared desktop services. Native integrations live behind platform checks.
class Platform {
    static IsWindows => A_OSType = "Windows"
    static IsMac => A_OSType = "OSX"
    static IsLinux => A_OSType = "Linux"
    static CopyShortcut => Platform.IsMac ? "#c" : "^c"
    static PasteShortcut => Platform.IsMac ? "#v" : "^v"
    static Home => ALTRunHome()
    static UserDataDir => Platform.IsWindows ? A_AppData : Platform.IsMac
        ? Platform.Join(Platform.Home, "Library", "Application Support")
        : ALTRunXdgDataHome()

    static Join(segments*) {
        joined := ""
        for segment in segments {
            if (segment = "")
                continue
            segment := Platform.IsWindows ? segment : StrReplace(segment, "\", "/")
            joined := (joined = "") ? segment : Clr.System.IO.Path.Combine(joined, segment)
        }
        return joined
    }

    static ExpandEnvironment(raw) {
        raw := Clr.System.Environment.ExpandEnvironmentVariables(raw)
        if !Platform.IsWindows {
            if (raw = "~" || SubStr(raw, 1, 2) = "~/")
                raw := Platform.Home SubStr(raw, 2)
            offset := 1
            while RegExMatch(raw, "\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", &match, offset) {
                value := EnvGet(match[1] != "" ? match[1] : match[2])
                if (value != "") {
                    raw := SubStr(raw, 1, match.Pos - 1) value SubStr(raw, match.Pos + match.Len)
                    offset := match.Pos + StrLen(value)
                } else
                    offset := match.Pos + match.Len
            }
        }
        return raw
    }

    static FullPath(raw, base := A_ScriptDir) {
        raw := Platform.ExpandEnvironment(raw)
        if !Platform.IsWindows
            raw := StrReplace(raw, "\", "/")
        return Clr.System.IO.Path.GetFullPath(raw, base)
    }

    static FindExecutable(name) {
        if (name = "")
            return ""
        return ALTRunFindExecutable(name)
    }

    static Locale() => Clr.System.Globalization.CultureInfo.InstalledUICulture.Name
    static Milliseconds() => Clr.System.Diagnostics.Stopwatch.GetTimestamp() * 1000 / Clr.System.Diagnostics.Stopwatch.Frequency
    static NewUuid() => Clr.System.Guid.NewGuid().ToString()

    static Open(target, arguments := "") {
        target := Path.Resolve(target)
        if Platform.IsWindows
            return Run('"' target '" ' arguments)
        if (arguments != "" || Platform.FindExecutable(target) != "")
            return Run('"' target '" ' arguments)
        opener := Platform.IsMac ? "/usr/bin/open" : Platform.FindExecutable("xdg-open")
        if (opener = "")
            throw Error("No desktop opener is installed (xdg-open).")
        return ProcessRunner.Start(opener, [target])
    }

    static Reveal(target) {
        target := Path.Full(target)
        if Platform.IsWindows
            return Run('explorer.exe /select,"' target '"')
        if Platform.IsMac
            return ProcessRunner.Start("/usr/bin/open", ["-R", target])
        if (Platform.IsLinux && DesktopIntegration.TryReveal(target))
            return true
        SplitPath(target, , &folder)
        return Platform.Open(DirExist(target) ? target : folder)
    }

    static Edit(file) => Platform.IsWindows ? Run('notepad.exe "' file '"') : Platform.Open(file)

    static EditSelection(control) {
        offsets := ALTRunEditSelection(control.ToClr())
        return {Start: offsets[1], End: offsets[2]}
    }
    static EditCaret(control) => Platform.EditSelection(control).End
    static SelectEdit(control, start, end) => ALTRunSelectEdit(control.ToClr(), start, end)

    static Identity(path) => Platform.IsWindows ? StrLower(path) : path
    static ObjectId(value) => ALTRunObjectId(value)
}

#CSharp
public static string ALTRunHome() => System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile);
private sealed class ALTRunIdentity { internal readonly long Value; internal ALTRunIdentity(long value) { Value = value; } }
private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<object, ALTRunIdentity> ALTRunIdentities = new();
private static long ALTRunNextIdentity;
public static long ALTRunObjectId(object value) => ALTRunIdentities.GetValue(value,
    _ => new ALTRunIdentity(System.Threading.Interlocked.Increment(ref ALTRunNextIdentity))).Value;

public static string ALTRunFindExecutable(string name)
{
    bool windows = System.OperatingSystem.IsWindows();
    var extensions = windows ? (System.Environment.GetEnvironmentVariable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD").Split(';') : new[] { "" };
    var candidates = name.Contains('/') || name.Contains('\\')
        ? new[] { "" } : (System.Environment.GetEnvironmentVariable("PATH") ?? "").Split(System.IO.Path.PathSeparator);
    foreach (var folder in candidates)
        foreach (var ext in windows && System.IO.Path.HasExtension(name) ? new[] { "" } : extensions)
        {
            var file = System.IO.Path.Combine(folder, name + ext);
            if (!System.IO.File.Exists(file)) continue;
            if (!windows && (System.IO.File.GetUnixFileMode(file) & (System.IO.UnixFileMode.UserExecute | System.IO.UnixFileMode.GroupExecute | System.IO.UnixFileMode.OtherExecute)) == 0) continue;
            return System.IO.Path.GetFullPath(file);
        }
    return "";
}

public static Keysharp.Builtins.Array ALTRunEditSelection(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper)
{
    var control = wrapper.Native;
    var type = control.GetType();
    var startProperty = type.GetProperty("SelectionStart");
    if (startProperty != null)
    {
        long start = System.Convert.ToInt64(startProperty.GetValue(control));
        return new Keysharp.Builtins.Array(start, start + System.Convert.ToInt64(type.GetProperty("SelectionLength").GetValue(control)));
    }
    var selection = type.GetProperty("Selection").GetValue(control);
    var range = selection.GetType();
    long first = System.Convert.ToInt64(range.GetProperty("Start").GetValue(selection));
    long last = System.Convert.ToInt64(range.GetProperty("End").GetValue(selection));
    long end = System.Math.Max(first, last + 1);
    if (System.OperatingSystem.IsLinux())
    {
        string text = (string)type.GetProperty("Text").GetValue(control);
        first = ALTRunUtf16Offset(text, (int)first);
        end = ALTRunUtf16Offset(text, (int)end);
    }
    return new Keysharp.Builtins.Array(first, end);
}

private static int ALTRunUtf16Offset(string text, int scalarOffset)
{
    int offset = 0;
    for (int count = 0; count < scalarOffset && offset < text.Length; count++)
        offset += offset + 1 < text.Length && char.IsSurrogatePair(text, offset) ? 2 : 1;
    return offset;
}

private static int ALTRunScalarOffset(string text, int utf16Offset)
{
    int count = 0;
    for (int offset = 0; offset < utf16Offset && offset < text.Length; count++)
        offset += offset + 1 < text.Length && char.IsSurrogatePair(text, offset) ? 2 : 1;
    return count;
}

public static void ALTRunSelectEdit(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, long start, long end)
{
    var control = wrapper.Native;
    var type = control.GetType();
    string text = (string)type.GetProperty("Text").GetValue(control);
    int length = text.Length;
    int first = (int)System.Math.Clamp(start, 0, length);
    int last = (int)System.Math.Clamp(end < 0 ? length : end, first, length);
    if (type.GetProperty("SelectionStart") is {} selectionStart)
    {
        selectionStart.SetValue(control, first);
        type.GetProperty("SelectionLength").SetValue(control, last - first);
    }
    else
    {
        if (System.OperatingSystem.IsLinux())
        {
            first = ALTRunScalarOffset(text, first);
            last = ALTRunScalarOffset(text, last);
        }
        var selection = type.GetProperty("Selection");
        selection.SetValue(control, System.Activator.CreateInstance(selection.PropertyType, first, last - 1));
    }
}
#EndCSharp

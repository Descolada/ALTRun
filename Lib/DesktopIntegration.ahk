; Desktop integration: owned login entries, recent files and file-manager selection.
class DesktopIntegration {
    static ConfigHome => Platform.IsMac ? Platform.Join(Platform.Home, "Library") : ALTRunXdgConfigHome()
    static _recentTimer := ""

    static UpdateAutostart(enabled, configHome := "") {
        host := ProcessRunner.ScriptHost(A_ScriptFullPath, ["-Startup"])
        if Platform.IsMac
            return ALTRunMacAutostartSet(configHome != "" ? configHome : DesktopIntegration.ConfigHome
                , enabled, host.Executable, JSON.Stringify(host.Arguments), A_ScriptFullPath)
        return ALTRunAutostartSet(configHome != "" ? configHome : DesktopIntegration.ConfigHome
            , enabled, host.Executable, JSON.Stringify(host.Arguments), A_ScriptFullPath, App.IconFile)
    }

    static RecentItems(maxItems, file := "") {
        if (Platform.IsMac && file = "") {
            snapshot := JSON.Parse(ALTRunMacRecentSnapshot(maxItems))
            entries := snapshot["Items"]
            if snapshot["Pending"] {
                if !IsObject(DesktopIntegration._recentTimer)
                    DesktopIntegration._recentTimer := (*) => DesktopIntegration._RecentReady()
                SetTimer(DesktopIntegration._recentTimer, 100)
            }
        } else {
            if (file = "")
                file := Platform.Join(Platform.UserDataDir, "recently-used.xbel")
            entries := JSON.Parse(ALTRunRecentItems(file, maxItems))
        }
        items := []
        for entry in entries
            items.Push({Path: entry["Path"], Name: entry["Name"], IsFolder: entry["IsFolder"]})
        return items
    }

    static _RecentReady() {
        snapshot := JSON.Parse(ALTRunMacRecentSnapshot(0))
        if snapshot["Pending"]
            return
        SetTimer(DesktopIntegration._recentTimer, 0)
        if (failure := snapshot["Error"]) != ""
            Logger.Debug("Spotlight recent documents unavailable: " failure)
        ; Refresh only a still-visible recent-document query when the background Spotlight lookup completes.
        if (SearchWindow.IsVisible() && SearchWindow.Mode = "results") {
            query := SearchQuery(SearchWindow.Input.Value), term := ""
            if query.MatchKeyword(AppSettings.Feature("FileSearch")["RecentKeywords"], &term)
                SearchWindow._RunSearch()
        }
    }

    static TryReveal(target) => ALTRunTryReveal(target)
}

#CSharp
// launchd reads per-user agents at the next login. Do not bootstrap or stop the running launcher here.
// https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
public static bool ALTRunMacAutostartSet(string library, bool enabled, string executable, string arguments, string script)
{
    string file = System.IO.Path.Combine(library, "LaunchAgents", "org.keysharp.ALTRun.plist");
    string owner = System.IO.Path.GetFullPath(script);
    if (System.IO.File.Exists(file))
    {
        try
        {
            var settings = new System.Xml.XmlReaderSettings { DtdProcessing = System.Xml.DtdProcessing.Ignore, XmlResolver = null };
            using var reader = System.Xml.XmlReader.Create(file, settings);
            var dict = System.Xml.Linq.XDocument.Load(reader).Root?.Element("dict");
            if (dict == null) return false;
            var values = System.Linq.Enumerable.ToArray(dict.Elements());
            bool owned = false;
            for (int index = 0; index + 1 < values.Length; index += 2)
                if (values[index].Name == "key" && values[index].Value == "ALTRunSource"
                    && values[index + 1].Name == "string" && values[index + 1].Value == owner) owned = true;
            if (!owned) return false;
        }
        catch (System.Xml.XmlException) { return false; }
    }
    if (!enabled)
    {
        if (System.IO.File.Exists(file)) System.IO.File.Delete(file);
        return true;
    }
    var args = new System.Xml.Linq.XElement("array", new System.Xml.Linq.XElement("string", executable));
    foreach (string argument in System.Text.Json.JsonSerializer.Deserialize<string[]>(arguments) ?? [])
        args.Add(new System.Xml.Linq.XElement("string", argument));
    var document = new System.Xml.Linq.XDocument(new System.Xml.Linq.XDeclaration("1.0", "utf-8", null),
        new System.Xml.Linq.XElement("plist", new System.Xml.Linq.XAttribute("version", "1.0"),
            new System.Xml.Linq.XElement("dict",
                new System.Xml.Linq.XElement("key", "Label"), new System.Xml.Linq.XElement("string", "org.keysharp.ALTRun"),
                new System.Xml.Linq.XElement("key", "ProgramArguments"), args,
                new System.Xml.Linq.XElement("key", "WorkingDirectory"), new System.Xml.Linq.XElement("string", System.IO.Path.GetDirectoryName(owner)),
                new System.Xml.Linq.XElement("key", "RunAtLoad"), new System.Xml.Linq.XElement("true"),
                new System.Xml.Linq.XElement("key", "LimitLoadToSessionType"), new System.Xml.Linq.XElement("string", "Aqua"),
                new System.Xml.Linq.XElement("key", "ALTRunSource"), new System.Xml.Linq.XElement("string", owner))));
    string text = document.Declaration + "\n" + document.ToString() + "\n";
    return ALTRunWriteAutostart(file, text, true);
}

private static bool ALTRunWriteAutostart(string file, string text, bool privateFile = false)
{
    if (System.IO.File.Exists(file) && System.IO.File.ReadAllText(file) == text) return true;
    System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file));
    string temporary = file + "." + System.Guid.NewGuid().ToString("N") + ".tmp";
    try
    {
        System.IO.File.WriteAllText(temporary, text, new System.Text.UTF8Encoding(false));
        if (privateFile && !System.OperatingSystem.IsWindows())
            System.IO.File.SetUnixFileMode(temporary, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite);
        System.IO.File.Move(temporary, file, true);
    }
    finally { if (System.IO.File.Exists(temporary)) System.IO.File.Delete(temporary); }
    return true;
}

// Spotlight's public metadata API reports documents opened through LaunchServices. It does not read
// private shared-file-list archives or change Spotlight settings. Keep all metadata work off the GUI thread.
// https://developer.apple.com/documentation/coreservices/kmditemlastuseddate
private static readonly object ALTRunMacRecentLock = new();
private static System.Threading.Tasks.Task<ALTRunMacRecentEntry[]> ALTRunMacRecentJob;
private static ALTRunMacRecentEntry[] ALTRunMacRecentCache = [];
private static string ALTRunMacRecentFailure = "";
private static System.DateTime ALTRunMacRecentStarted = System.DateTime.MinValue;

public static string ALTRunMacRecentSnapshot(long maxItems)
{
    lock (ALTRunMacRecentLock)
    {
        if (ALTRunMacRecentJob?.IsCompleted == true)
        {
            try { ALTRunMacRecentCache = ALTRunMacRecentJob.GetAwaiter().GetResult(); ALTRunMacRecentFailure = ""; }
            catch (System.Exception error) { ALTRunMacRecentCache = []; ALTRunMacRecentFailure = error.Message; }
            ALTRunMacRecentJob = null;
        }
        if (System.OperatingSystem.IsMacOS() && maxItems > 0 && ALTRunMacRecentJob == null
            && (System.DateTime.UtcNow - ALTRunMacRecentStarted).TotalSeconds >= 60)
        {
            ALTRunMacRecentStarted = System.DateTime.UtcNow;
            ALTRunMacRecentJob = System.Threading.Tasks.Task.Run(ALTRunMacRecentQuery);
        }
        return System.Text.Json.JsonSerializer.Serialize(new {
            Items = System.Linq.Enumerable.Take(ALTRunMacRecentCache, (int)System.Math.Clamp(maxItems, 0, 1000)),
            Pending = ALTRunMacRecentJob != null, Error = ALTRunMacRecentFailure });
    }
}

private sealed record ALTRunMacRecentEntry(string Path, string Name, bool IsFolder);
private sealed record ALTRunMacRecentCandidate(string Path, string Name, double Time);

private static ALTRunMacRecentEntry[] ALTRunFilterMacRecent(System.Collections.Generic.IEnumerable<ALTRunMacRecentCandidate> entries, string scope, long maxItems)
{
    if (maxItems <= 0) return [];
    string prefix = System.IO.Path.TrimEndingDirectorySeparator(System.IO.Path.GetFullPath(scope)) + System.IO.Path.DirectorySeparatorChar;
    var result = new System.Collections.Generic.List<ALTRunMacRecentEntry>();
    var seen = new System.Collections.Generic.HashSet<string>(System.StringComparer.Ordinal);
    foreach (var entry in System.Linq.Enumerable.OrderByDescending(entries, item => item?.Time ?? 0))
    {
        if (entry == null || string.IsNullOrEmpty(entry.Path) || !System.IO.Path.IsPathRooted(entry.Path)
            || !double.IsFinite(entry.Time) || entry.Time <= 0) continue;
        string path;
        try { path = System.IO.Path.GetFullPath(entry.Path); }
        catch (System.ArgumentException) { continue; }
        // Spotlight may expose the APFS data-volume path for a document reached through /Users.
        // Return the same user-facing path used by the scope and deduplicate both spellings.
        const string dataVolume = "/System/Volumes/Data";
        if (System.OperatingSystem.IsMacOS() && path.StartsWith(dataVolume + prefix, System.StringComparison.Ordinal))
            path = path[dataVolume.Length..];
        if (!path.StartsWith(prefix, System.StringComparison.Ordinal) || !seen.Add(path)) continue;
        bool folder = System.IO.Directory.Exists(path);
        if (!folder && !System.IO.File.Exists(path)) continue;
        string name = System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(path));
        result.Add(new ALTRunMacRecentEntry(path, string.IsNullOrEmpty(entry.Name) ? name : entry.Name, folder));
        if (result.Count >= maxItems) break;
    }
    return result.ToArray();
}

private static ALTRunMacRecentEntry[] ALTRunMacRecentQuery()
{
    const string queryText = "kMDItemLastUsedDate >= $time.today(-90) && kMDItemContentTypeTree != 'com.apple.application-bundle'";
    var handles = new System.Collections.Generic.List<System.IntPtr>();
    System.IntPtr String(string text)
    {
        var value = ALTRunMacMetadata.CFStringCreateWithCString(System.IntPtr.Zero, text, 0x08000100);
        if (value == System.IntPtr.Zero) throw new System.InvalidOperationException("Could not create a metadata string.");
        handles.Add(value);
        return value;
    }
    try
    {
        string home = ALTRunHome();
        var scopePath = String(home);
        var scope = ALTRunMacMetadata.CFArrayCreate(System.IntPtr.Zero, new[] { scopePath }, 1, System.IntPtr.Zero);
        if (scope == System.IntPtr.Zero) return [];
        handles.Add(scope);
        var query = ALTRunMacMetadata.MDQueryCreate(System.IntPtr.Zero, String(queryText), System.IntPtr.Zero, System.IntPtr.Zero);
        if (query == System.IntPtr.Zero) return [];
        handles.Add(query);
        ALTRunMacMetadata.MDQuerySetSearchScope(query, scope, 0);
        if (!ALTRunMacMetadata.MDQueryExecute(query, 1)) return []; // kMDQuerySynchronous, on a worker thread
        var pathKey = String("kMDItemPath");
        var nameKey = String("kMDItemDisplayName");
        var dateKey = String("kMDItemLastUsedDate");
        var result = new System.Collections.Generic.List<ALTRunMacRecentCandidate>();
        long count = ALTRunMacMetadata.MDQueryGetResultCount(query);
        for (long index = 0; index < count; index++)
        {
            var item = ALTRunMacMetadata.MDQueryGetResultAtIndex(query, (System.IntPtr)index);
            if (item == System.IntPtr.Zero) continue;
            string path = ALTRunMacMetadata.AttributeString(item, pathKey);
            if (path.Length == 0) continue;
            var date = ALTRunMacMetadata.MDItemCopyAttribute(item, dateKey);
            if (date == System.IntPtr.Zero) continue;
            try
            {
                if (ALTRunMacMetadata.CFGetTypeID(date) != ALTRunMacMetadata.CFDateGetTypeID()) continue;
                result.Add(new ALTRunMacRecentCandidate(path, ALTRunMacMetadata.AttributeString(item, nameKey),
                    ALTRunMacMetadata.CFDateGetAbsoluteTime(date)));
            }
            finally { ALTRunMacMetadata.CFRelease(date); }
        }
        return ALTRunFilterMacRecent(result, home, 1000);
    }
    finally
    {
        for (int index = handles.Count - 1; index >= 0; index--) ALTRunMacMetadata.CFRelease(handles[index]);
    }
}

private static class ALTRunMacMetadata
{
    private const string CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const string CoreServices = "/System/Library/Frameworks/CoreServices.framework/CoreServices";
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern System.IntPtr CFStringCreateWithCString(System.IntPtr allocator,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string text, uint encoding);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern System.IntPtr CFArrayCreate(System.IntPtr allocator, System.IntPtr[] values, System.IntPtr count, System.IntPtr callbacks);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern void CFRelease(System.IntPtr value);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern nuint CFGetTypeID(System.IntPtr value);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern nuint CFDateGetTypeID();
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern nuint CFStringGetTypeID();
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] internal static extern double CFDateGetAbsoluteTime(System.IntPtr value);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] private static extern System.IntPtr CFStringGetLength(System.IntPtr value);
    [System.Runtime.InteropServices.DllImport(CoreFoundation)] [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)]
    private static extern bool CFStringGetCString(System.IntPtr value, byte[] buffer, System.IntPtr size, uint encoding);
    [System.Runtime.InteropServices.DllImport(CoreServices)] internal static extern System.IntPtr MDQueryCreate(System.IntPtr allocator, System.IntPtr query, System.IntPtr values, System.IntPtr sorting);
    [System.Runtime.InteropServices.DllImport(CoreServices)] internal static extern void MDQuerySetSearchScope(System.IntPtr query, System.IntPtr scope, nuint options);
    [System.Runtime.InteropServices.DllImport(CoreServices)] [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)]
    internal static extern bool MDQueryExecute(System.IntPtr query, nuint options);
    [System.Runtime.InteropServices.DllImport(CoreServices)] internal static extern System.IntPtr MDQueryGetResultCount(System.IntPtr query);
    [System.Runtime.InteropServices.DllImport(CoreServices)] internal static extern System.IntPtr MDQueryGetResultAtIndex(System.IntPtr query, System.IntPtr index);
    [System.Runtime.InteropServices.DllImport(CoreServices)] internal static extern System.IntPtr MDItemCopyAttribute(System.IntPtr item, System.IntPtr attribute);

    internal static string AttributeString(System.IntPtr item, System.IntPtr key)
    {
        var value = MDItemCopyAttribute(item, key);
        if (value == System.IntPtr.Zero) return "";
        try
        {
            if (CFGetTypeID(value) != CFStringGetTypeID()) return "";
            var buffer = new byte[checked((int)CFStringGetLength(value) * 3 + 1)];
            if (!CFStringGetCString(value, buffer, (System.IntPtr)buffer.Length, 0x08000100)) return "";
            return System.Text.Encoding.UTF8.GetString(buffer, 0, System.Array.IndexOf(buffer, (byte)0));
        }
        finally { CFRelease(value); }
    }
}

public static string ALTRunXdgConfigHome()
{
    string value = System.Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
    return !string.IsNullOrEmpty(value) && System.IO.Path.IsPathRooted(value)
        ? value : System.IO.Path.Combine(ALTRunHome(), ".config");
}

public static string ALTRunXdgDataHome()
{
    string value = System.Environment.GetEnvironmentVariable("XDG_DATA_HOME");
    return !string.IsNullOrEmpty(value) && System.IO.Path.IsPathRooted(value)
        ? value : System.IO.Path.Combine(ALTRunHome(), ".local", "share");
}

private static string ALTRunDesktopValue(string value) => value.Replace("\\", "\\\\")
    .Replace("\n", "\\n").Replace("\r", "\\r").Replace("\t", "\\t");

private static string ALTRunDesktopArgument(string value) => ALTRunDesktopValue("\"" + value.Replace("%", "%%")
    .Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("$", "\\$").Replace("`", "\\`") + "\"");

public static bool ALTRunAutostartSet(string configHome, bool enabled, string executable, string arguments, string script, string icon)
{
    string file = System.IO.Path.Combine(configHome, "autostart", "org.keysharp.ALTRun.desktop");
    string owner = "X-ALTRun-Source=" + ALTRunDesktopValue(System.IO.Path.GetFullPath(script));
    if (System.IO.File.Exists(file) && !System.Array.Exists(System.IO.File.ReadAllLines(file), line => line == owner))
        return false;
    if (!enabled)
    {
        if (System.IO.File.Exists(file)) System.IO.File.Delete(file);
        return true;
    }
    var command = new System.Text.StringBuilder(ALTRunDesktopArgument(executable));
    foreach (string argument in System.Text.Json.JsonSerializer.Deserialize<string[]>(arguments) ?? [])
        command.Append(' ').Append(ALTRunDesktopArgument(argument));
    string text = "[Desktop Entry]\nType=Application\nName=ALTRun\nComment=Application launcher\nExec=" + command
        + "\nPath=" + ALTRunDesktopValue(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(script)))
        + "\nIcon=" + ALTRunDesktopValue(icon) + "\nTerminal=false\n" + owner + "\n";
    return ALTRunWriteAutostart(file, text);
}

public static string ALTRunRecentItems(string filename, long maxItems)
{
    var items = new System.Collections.Generic.List<(string Path, string Name, bool IsFolder, System.DateTimeOffset Time)>();
    if (maxItems <= 0 || !System.IO.File.Exists(filename)) return "[]";
    try
    {
        var settings = new System.Xml.XmlReaderSettings { DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null };
        using var reader = System.Xml.XmlReader.Create(filename, settings);
        var document = System.Xml.Linq.XDocument.Load(reader);
        foreach (var bookmark in document.Descendants("bookmark"))
        {
            if (System.Linq.Enumerable.Any(bookmark.Descendants(), element => element.Name.LocalName == "private")) continue;
            if (!System.Uri.TryCreate((string)bookmark.Attribute("href"), System.UriKind.Absolute, out var uri)
                || !uri.IsFile || !(uri.Host == "" || uri.Host.Equals("localhost", System.StringComparison.OrdinalIgnoreCase))) continue;
            string path = uri.LocalPath;
            bool folder = System.IO.Directory.Exists(path);
            if (!folder && !System.IO.File.Exists(path)) continue;
            var time = System.DateTimeOffset.MinValue;
            foreach (string field in new[] { "modified", "visited", "added" })
                if (System.DateTimeOffset.TryParse((string)bookmark.Attribute(field), System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.AssumeUniversal, out var parsed) && parsed > time) time = parsed;
            string name = System.IO.Path.GetFileName(System.IO.Path.TrimEndingDirectorySeparator(path));
            items.Add((path, name.Length > 0 ? name : path, folder, time));
        }
    }
    catch (System.Exception error) when (error is System.Xml.XmlException || error is System.IO.IOException || error is System.UnauthorizedAccessException)
    { return "[]"; }
    items.Sort((left, right) => right.Time.CompareTo(left.Time));
    var seen = new System.Collections.Generic.HashSet<string>(System.StringComparer.Ordinal);
    var result = new System.Collections.Generic.List<object>();
    foreach (var item in items)
        if (seen.Add(item.Path))
        {
            result.Add(new { item.Path, item.Name, item.IsFolder });
            if (result.Count >= maxItems) break;
        }
    return System.Text.Json.JsonSerializer.Serialize(result);
}

public static bool ALTRunTryReveal(string path)
{
    string executable = ALTRunFindExecutable("gdbus");
    if (executable.Length == 0) return false;
    string uri = new System.Uri(System.IO.Path.GetFullPath(path)).AbsoluteUri;
    var start = new System.Diagnostics.ProcessStartInfo(executable) { UseShellExecute = false,
        RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
    foreach (string argument in new[] { "call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path",
        "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems", "['" + uri.Replace("'", "\\'") + "']", "''" })
        start.ArgumentList.Add(argument);
    try
    {
        using var process = System.Diagnostics.Process.Start(start);
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        if (process.WaitForExit(1000)) return process.ExitCode == 0;
        process.Kill(true);
    }
    catch (System.Exception error) when (error is System.IO.IOException || error is System.ComponentModel.Win32Exception || error is System.InvalidOperationException) { }
    return false;
}
#EndCSharp

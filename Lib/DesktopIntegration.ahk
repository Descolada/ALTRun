; Linux desktop integration: owned XDG autostart entries, recent files and file-manager selection.
class DesktopIntegration {
    static ConfigHome => ALTRunXdgConfigHome()

    static UpdateAutostart(enabled, configHome := "") {
        host := ProcessRunner.ScriptHost(A_ScriptFullPath, ["-Startup"])
        return ALTRunAutostartSet(configHome != "" ? configHome : DesktopIntegration.ConfigHome
            , enabled, host.Executable, JSON.Stringify(host.Arguments), A_ScriptFullPath, App.IconFile)
    }

    static RecentItems(maxItems, file := "") {
        if (file = "")
            file := Platform.Join(Platform.UserDataDir, "recently-used.xbel")
        items := []
        for entry in JSON.Parse(ALTRunRecentItems(file, maxItems))
            items.Push({Path: entry["Path"], Name: entry["Name"], IsFolder: entry["IsFolder"]})
        return items
    }

    static TryReveal(target) => ALTRunTryReveal(target)
}

#CSharp
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
    if (System.IO.File.Exists(file) && System.IO.File.ReadAllText(file) == text) return true;
    System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file));
    string temporary = file + "." + System.Guid.NewGuid().ToString("N") + ".tmp";
    try
    {
        System.IO.File.WriteAllText(temporary, text, new System.Text.UTF8Encoding(false));
        System.IO.File.Move(temporary, file, true);
    }
    finally { if (System.IO.File.Exists(temporary)) System.IO.File.Delete(temporary); }
    return true;
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

; ProcessRunner - starts programs with argument arrays and captures UTF-8 background output without a shell.
; Poll IsFinished, then Finish; passing true to Finish cancels the process and its children.

#CSharp
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

private sealed class ALTRunProcessJob : IDisposable
{
    internal readonly Process Process;
    internal readonly Task<string> Output;
    internal readonly Task<string> Error;

    internal ALTRunProcessJob(Process Process)
    {
        this.Process = Process;
        Output = Process.StandardOutput.ReadToEndAsync();
        Error = Process.StandardError.ReadToEndAsync();
    }

    public void Dispose() => Process.Dispose();
}

private static readonly ConcurrentDictionary<long, ALTRunProcessJob> ALTRunProcessJobs = new();
private static long ALTRunProcessNextJob;

private static long ALTRunStartInfo(ProcessStartInfo Start, bool Capture, bool Application)
{
    // Nix's Keysharp wrapper adds native libraries that can conflict with another application's own closure.
    // Keep them for child Keysharp scripts, and change only the external application's environment.
    if (Application && OperatingSystem.IsLinux()
        && (File.Exists("/etc/NIXOS") || (Environment.ProcessPath ?? "").StartsWith("/nix/store/", StringComparison.Ordinal)))
        Start.Environment.Remove("LD_LIBRARY_PATH");
    Start.UseShellExecute = false;
    Start.CreateNoWindow = Capture;
    Start.RedirectStandardOutput = Capture;
    Start.RedirectStandardError = Capture;
    if (Capture)
    {
        Start.WindowStyle = ProcessWindowStyle.Hidden;
        Start.StandardOutputEncoding = Encoding.UTF8;
        Start.StandardErrorEncoding = Encoding.UTF8;
    }
    var process = Process.Start(Start) ?? throw new InvalidOperationException("The program did not start.");
    if (!Capture)
    {
        var pid = process.Id;
        process.Dispose();
        return pid;
    }
    var job = Interlocked.Increment(ref ALTRunProcessNextJob);
    ALTRunProcessJobs[job] = new ALTRunProcessJob(process);
    return job;
}

public static long ALTRunProcessStart(string Executable, string Arguments, string WorkingDirectory, bool Capture, bool Application = false)
{
    var start = new ProcessStartInfo(Executable);
    if (!string.IsNullOrEmpty(WorkingDirectory))
        start.WorkingDirectory = WorkingDirectory;
    foreach (var argument in JsonSerializer.Deserialize<string[]>(Arguments) ?? [])
        start.ArgumentList.Add(argument);
    return ALTRunStartInfo(start, Capture, Application);
}

public static long ALTRunProcessStartCommand(string Command, string WorkingDirectory, bool Capture, bool Application = false)
{
    var command = Command.Trim();
    var end = command.StartsWith('"') ? command.IndexOf('"', 1) + 1 : command.IndexOf(' ');
    if (end <= 0)
        end = command.Length;
    var start = new ProcessStartInfo(command[..end].Trim('"')) { Arguments = command[end..].TrimStart() };
    if (!string.IsNullOrEmpty(WorkingDirectory))
        start.WorkingDirectory = WorkingDirectory;
    return ALTRunStartInfo(start, Capture, Application);
}

public static bool ALTRunProcessIsFinished(long Job)
    => !ALTRunProcessJobs.TryGetValue(Job, out var job) || (job.Process.HasExited && job.Output.IsCompleted && job.Error.IsCompleted);

private sealed record ALTRunProcessOutput(string Output, string Error, int ExitCode);
private static ALTRunProcessOutput ALTRunCompleteProcess(long Job, bool Terminate)
{
    if (!ALTRunProcessJobs.TryRemove(Job, out var job))
        return null;
    using (job)
    {
        if (Terminate && !job.Process.HasExited)
            job.Process.Kill(entireProcessTree: true);
        if (!job.Process.WaitForExit(3000))
            throw new TimeoutException("The script did not stop after cancellation.");
        if (!Task.WaitAll([job.Output, job.Error], TimeSpan.FromSeconds(3)))
            throw new TimeoutException("The script's output streams did not close.");
        return new(job.Output.GetAwaiter().GetResult(), job.Error.GetAwaiter().GetResult(), job.Process.ExitCode);
    }
}

public static string ALTRunProcessFinish(long Job, bool Terminate)
{
    var result = ALTRunCompleteProcess(Job, Terminate);
    return result == null ? "" : result.Output + (result.Output.Length > 0 && result.Error.Length > 0 ? Environment.NewLine : "") + result.Error;
}

public static string ALTRunProcessResult(long Job, bool Terminate)
    => ALTRunCompleteProcess(Job, Terminate) is { } result ? JsonSerializer.Serialize(result) : "{}";

public static object ALTRunProcessCancelAll()
{
    foreach (var id in ALTRunProcessJobs.Keys)
    {
        if (!ALTRunProcessJobs.TryRemove(id, out var job))
            continue;
        using (job)
            try { if (!job.Process.HasExited) job.Process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
    }
    return null;
}

public static string ALTRunScriptHost(string ScriptPath, string Arguments, bool Compiled)
{
    var executable = Environment.ProcessPath ?? throw new InvalidOperationException("The script host could not be identified.");
    var args = new List<string>();
    var current = Environment.GetCommandLineArgs();
    if (System.IO.Path.GetFileNameWithoutExtension(executable).Equals("dotnet", StringComparison.OrdinalIgnoreCase)
        && current.Length > 0 && current[0].EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        args.Add(current[0]);
    if (Compiled)
        args.Add("--script");
    args.Add("--errorstdout");
    args.Add(ScriptPath);
    args.AddRange(JsonSerializer.Deserialize<string[]>(Arguments) ?? []);
    return JsonSerializer.Serialize(new { Executable = executable, Arguments = args });
}

public static string ALTRunPosixQuote(string Value) => "'" + Value.Replace("'", "'\"'\"'") + "'";
public static string ALTRunAppleScriptQuote(string Value)
    => "\"" + Value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n") + "\"";

public static string ALTRunScriptInterpreter(string Filename)
{
    using var reader = new StreamReader(Filename, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
    var first = reader.ReadLine() ?? "";
    if (!first.StartsWith("#!", StringComparison.Ordinal)) return "{}";
    var command = first[2..].Trim();
    var end = command.IndexOfAny([' ', '\t']);
    var executable = end < 0 ? command : command[..end];
    if (!System.IO.Path.IsPathRooted(executable))
        throw new FormatException("The script's interpreter must be an absolute path.");
    var optional = end < 0 ? "" : command[end..].Trim();
    return JsonSerializer.Serialize(new { Executable = executable, Arguments = optional.Length == 0 ? Array.Empty<string>() : new[] { optional } });
}

private static string ALTRunDesktopUnescape(string Value)
{
    var text = new StringBuilder();
    for (var index = 0; index < Value.Length; index++)
    {
        if (Value[index] != '\\' || index + 1 == Value.Length)
        {
            text.Append(Value[index]);
            continue;
        }
        var next = Value[index + 1];
        switch (next)
        {
            case 's': text.Append(' '); break;
            case 'n': text.Append('\n'); break;
            case 't': text.Append('\t'); break;
            case 'r': text.Append('\r'); break;
            case '\\': text.Append('\\'); break;
            default: text.Append('\\').Append(next); break;
        }
        index++;
    }
    return text.ToString();
}

public static string ALTRunDesktopLocale(string Fallback)
{
    if (!OperatingSystem.IsWindows())
        foreach (var variable in new[] { "LC_ALL", "LC_MESSAGES", "LANG" })
            if (Environment.GetEnvironmentVariable(variable) is { Length: > 0 } value)
                return value;
    return Fallback;
}

public static string ALTRunDesktopRead(string Filename, string Locale, string CurrentDesktop)
{
    var values = new Dictionary<string, string>(StringComparer.Ordinal);
    var inEntry = false;
    foreach (var raw in File.ReadLines(Filename))
    {
        var line = raw.Trim();
        if (line.Length == 0 || line[0] == '#') continue;
        if (line[0] == '[') { inEntry = line == "[Desktop Entry]"; continue; }
        var equals = line.IndexOf('=');
        if (inEntry && equals > 0)
            values[line[..equals].Trim()] = line[(equals + 1)..];
    }
    string Get(string key) => values.TryGetValue(key, out var value) ? value : "";
    bool IsTrue(string key) => Get(key).Equals("true", StringComparison.OrdinalIgnoreCase);
    var desktops = CurrentDesktop.Split(':', StringSplitOptions.RemoveEmptyEntries);
    bool Matches(string list) => Array.Exists(desktops, desktop => Array.Exists(list.Split(';'), item => item == desktop));
    if (Get("Type") != "Application" || IsTrue("Hidden") || IsTrue("NoDisplay")
        || (Get("OnlyShowIn") != "" && !Matches(Get("OnlyShowIn")))
        || (Get("NotShowIn") != "" && Matches(Get("NotShowIn"))))
        return "{}";
    var localeParts = Locale.Replace('-', '_').Split('@', 2);
    var locale = localeParts[0].Split('.')[0];
    var language = locale.Split('_')[0];
    var modifier = localeParts.Length > 1 ? "@" + localeParts[1] : "";
    string Localized(string key)
    {
        foreach (var suffix in new[] { locale + modifier, locale, language + modifier, language })
            if (Get(key + "[" + suffix + "]") is { Length: > 0 } translated)
                return ALTRunDesktopUnescape(translated);
        return ALTRunDesktopUnescape(Get(key));
    }
    return JsonSerializer.Serialize(new { Name = Localized("Name"), Exec = ALTRunDesktopUnescape(Get("Exec")), Icon = Localized("Icon"),
        GenericName = Localized("GenericName"), Keywords = Localized("Keywords").Replace(';', ' '), Comment = Localized("Comment"),
        Path = ALTRunDesktopUnescape(Get("Path")), TryExec = ALTRunDesktopUnescape(Get("TryExec")), Terminal = IsTrue("Terminal") });
}

public static string ALTRunDesktopCommand(string Command, string Filename, string Name, string Icon)
{
    var tokens = new List<string>();
    var token = new StringBuilder();
    var quoted = false;
    var started = false;
    for (var index = 0; index < Command.Length; index++)
    {
        var character = Command[index];
        if (character == '"') { quoted = !quoted; started = true; continue; }
        if (character == '\\' && index + 1 < Command.Length)
        {
            var next = Command[index + 1];
            if (!quoted || next is '"' or '`' or '$' or '\\')
            {
                token.Append(next); index++; started = true; continue;
            }
        }
        if (char.IsWhiteSpace(character) && !quoted)
        {
            if (started) { tokens.Add(token.ToString()); token.Clear(); started = false; }
            continue;
        }
        token.Append(character); started = true;
    }
    if (quoted) throw new FormatException("Unclosed quote in the desktop entry's Exec command.");
    if (started) tokens.Add(token.ToString());
    var expanded = new List<string>();
    foreach (var value in tokens)
    {
        if (value is "%f" or "%F" or "%u" or "%U" or "%d" or "%D" or "%n" or "%N" or "%v" or "%m") continue;
        if (value == "%i") { if (Icon.Length > 0) { expanded.Add("--icon"); expanded.Add(Icon); } continue; }
        var argument = new StringBuilder();
        for (var index = 0; index < value.Length; index++)
        {
            if (value[index] != '%') { argument.Append(value[index]); continue; }
            if (++index == value.Length) throw new FormatException("Incomplete field code in the desktop entry.");
            switch (value[index])
            {
                case '%': argument.Append('%'); break;
                case 'c': argument.Append(Name); break;
                case 'k': argument.Append(Filename); break;
                case 'f': case 'u': case 'd': case 'D': case 'n': case 'N': case 'v': case 'm': break;
                default: throw new FormatException("Unsupported field code in the desktop entry: %" + value[index]);
            }
        }
        expanded.Add(argument.ToString());
    }
    if (expanded.Count == 0 || expanded[0].Length == 0) throw new FormatException("The desktop entry has no executable.");
    return JsonSerializer.Serialize(new { Executable = expanded[0], Arguments = expanded.GetRange(1, expanded.Count - 1) });
}

private static readonly Dictionary<string, string> ALTRunDesktopIcons = new(StringComparer.Ordinal);

public static object ALTRunDesktopClearIcons()
{
    ALTRunDesktopIcons.Clear();
    return null;
}

public static string ALTRunDesktopIcon(string Icon, int Size, string DataHome, string DataDirectories)
{
    if (Icon.Length == 0) return "";
    if (System.IO.Path.IsPathRooted(Icon)) return File.Exists(Icon) ? Icon : "";
    if (Icon.Contains('/') || Icon.Contains('\\')) return "";
    var key = Icon + "\n" + Size + "\n" + DataHome + "\n" + DataDirectories + "\n" + Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
    if (ALTRunDesktopIcons.TryGetValue(key, out var cached)) return cached;
    var roots = new List<string> { System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".icons"),
        System.IO.Path.Combine(DataHome, "icons") };
    var dataRoots = new List<string> { DataHome };
    dataRoots.AddRange(DataDirectories.Split(':', StringSplitOptions.RemoveEmptyEntries));
    foreach (var root in dataRoots)
        if (!roots.Contains(System.IO.Path.Combine(root, "icons"))) roots.Add(System.IO.Path.Combine(root, "icons"));
    var themes = new List<string>();
    void AddTheme(string name)
    {
        if (name.Length == 0 || name is "." or ".." || name.Contains('/') || name.Contains('\\') || themes.Contains(name)) return;
        themes.Add(name);
        foreach (var root in roots)
        {
            var index = System.IO.Path.Combine(root, name, "index.theme");
            try
            {
                if (!File.Exists(index)) continue;
                foreach (var line in File.ReadLines(index))
                    if (line.StartsWith("Inherits=", StringComparison.Ordinal))
                        foreach (var inherited in line[9..].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
                            AddTheme(inherited);
                break;
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
    foreach (var version in new[] { "gtk-4.0", "gtk-3.0" })
    {
        var config = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (string.IsNullOrEmpty(config)) config = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config");
        try
        {
            var settings = System.IO.Path.Combine(config, version, "settings.ini");
            if (File.Exists(settings))
                foreach (var line in File.ReadLines(settings))
                    if (line.StartsWith("gtk-icon-theme-name=", StringComparison.Ordinal)) AddTheme(line[20..].Trim());
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    AddTheme("Adwaita");
    themes.Remove("hicolor");
    AddTheme("hicolor");
    var sizes = new List<int> { Size };
    foreach (var size in new[] { 32, 48, 64, 24, 16, 128, 256, 512 })
        if (!sizes.Contains(size)) sizes.Add(size);
    var extensions = System.IO.Path.GetExtension(Icon).ToLowerInvariant() is ".png" or ".ico" or ".jpg" or ".bmp" or ".gif"
        ? new[] { "" } : new[] { ".png", ".ico", ".jpg", ".bmp", ".gif" };
    foreach (var theme in themes)
        foreach (var size in sizes)
            foreach (var root in roots)
                foreach (var context in new[] { "apps", "applications", "mimetypes", "categories", "places", "devices", "status", "actions", "" })
                    foreach (var extension in extensions)
                    {
                        var file = System.IO.Path.Combine(root, theme, size + "x" + size, context, Icon + extension);
                        if (File.Exists(file)) return ALTRunDesktopIcons[key] = file;
                    }
    foreach (var root in roots)
        foreach (var extension in extensions)
        {
            var file = System.IO.Path.Combine(root, Icon + extension);
            if (File.Exists(file)) return ALTRunDesktopIcons[key] = file;
        }
    foreach (var root in dataRoots)
        foreach (var extension in extensions)
        {
            var file = System.IO.Path.Combine(root, "pixmaps", Icon + extension);
            if (File.Exists(file)) return ALTRunDesktopIcons[key] = file;
        }
    return ALTRunDesktopIcons[key] = "";
}
#EndCSharp

class ProcessRunner {
    static Start(executable, arguments := [], workingDirectory := "", capture := false) {
        return ALTRunProcessStart(executable, JSON.Stringify(arguments), workingDirectory, capture)
    }

    static StartCommand(command, workingDirectory := "", capture := false) {
        return ALTRunProcessStartCommand(command, workingDirectory, capture)
    }

    static StartApplication(executable, arguments := [], workingDirectory := "", capture := false) {
        return ALTRunProcessStart(executable, JSON.Stringify(arguments), workingDirectory, capture, true)
    }

    static StartApplicationCommand(command, workingDirectory := "", capture := false) {
        return ALTRunProcessStartCommand(command, workingDirectory, capture, true)
    }

    static IsFinished(job) => ALTRunProcessIsFinished(job)
    static Finish(job, terminate := false) => ALTRunProcessFinish(job, terminate)
    static Result(job, terminate := false) => JSON.Parse(ALTRunProcessResult(job, terminate))
    static CancelAll() => ALTRunProcessCancelAll()
    static QuoteShell(value) => ALTRunPosixQuote(value)
    static QuoteAppleScript(value) => ALTRunAppleScriptQuote(value)

    static DesktopEntry(filename) => JSON.Parse(ALTRunDesktopRead(filename, ALTRunDesktopLocale(Platform.Locale()), EnvGet("XDG_CURRENT_DESKTOP")))

    static DesktopIcon(icon, size := 32) => Platform.IsLinux ? ALTRunDesktopIcon(icon, size, Platform.UserDataDir,
        EnvGet("XDG_DATA_DIRS") != "" ? EnvGet("XDG_DATA_DIRS") : "/usr/local/share:/usr/share") : icon

    static ClearDesktopIcons() => ALTRunDesktopClearIcons()

    static ScriptInterpreter(filename) {
        spec := JSON.Parse(ALTRunScriptInterpreter(filename))
        return spec.Has("Executable") ? {Executable: spec["Executable"], Arguments: spec["Arguments"]} : ""
    }

    static DesktopCommand(entry, filename) {
        spec := JSON.Parse(ALTRunDesktopCommand(entry["Exec"], filename, entry["Name"], entry["Icon"]))
        return {Executable: spec["Executable"], Arguments: spec["Arguments"]}
    }

    static ScriptHost(scriptPath, arguments := []) {
        spec := JSON.Parse(ALTRunScriptHost(scriptPath, JSON.Stringify(arguments), A_IsCompiled))
        if Platform.IsMac && Platform.AppBundle != "" {
            packagedArguments := ["--keysharp"]
            for value in spec["Arguments"]
                packagedArguments.Push(value)
            return {Executable: Platform.Join(Platform.AppBundle, "Contents", "MacOS", "ALTRun"), Arguments: packagedArguments}
        }
        return {Executable: spec["Executable"], Arguments: spec["Arguments"]}
    }
}

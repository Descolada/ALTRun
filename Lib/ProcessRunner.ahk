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

private static long ALTRunStartInfo(ProcessStartInfo Start, bool Capture)
{
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

public static long ALTRunProcessStart(string Executable, string Arguments, string WorkingDirectory, bool Capture)
{
    var start = new ProcessStartInfo(Executable);
    if (!string.IsNullOrEmpty(WorkingDirectory))
        start.WorkingDirectory = WorkingDirectory;
    foreach (var argument in JsonSerializer.Deserialize<string[]>(Arguments) ?? [])
        start.ArgumentList.Add(argument);
    return ALTRunStartInfo(start, Capture);
}

public static long ALTRunProcessStartCommand(string Command, string WorkingDirectory, bool Capture)
{
    var command = Command.Trim();
    var end = command.StartsWith('"') ? command.IndexOf('"', 1) + 1 : command.IndexOf(' ');
    if (end <= 0)
        end = command.Length;
    var start = new ProcessStartInfo(command[..end].Trim('"')) { Arguments = command[end..].TrimStart() };
    if (!string.IsNullOrEmpty(WorkingDirectory))
        start.WorkingDirectory = WorkingDirectory;
    return ALTRunStartInfo(start, Capture);
}

public static bool ALTRunProcessIsFinished(long Job)
    => !ALTRunProcessJobs.TryGetValue(Job, out var job) || job.Process.HasExited;

public static string ALTRunProcessFinish(long Job, bool Terminate)
{
    if (!ALTRunProcessJobs.TryRemove(Job, out var job))
        return "";
    using (job)
    {
        if (Terminate && !job.Process.HasExited)
            job.Process.Kill(entireProcessTree: true);
        if (!job.Process.WaitForExit(3000))
            throw new TimeoutException("The script did not stop after cancellation.");
        if (!Task.WaitAll([job.Output, job.Error], TimeSpan.FromSeconds(3)))
            throw new TimeoutException("The script's output streams did not close.");
        var output = job.Output.GetAwaiter().GetResult();
        var error = job.Error.GetAwaiter().GetResult();
        return output + (output.Length > 0 && error.Length > 0 ? Environment.NewLine : "") + error;
    }
}

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
    var name = Get("Name");
    var locale = Locale.Replace('-', '_').Split('.')[0];
    var language = locale.Split('_')[0];
    if (Get("Name[" + language + "]") is { Length: > 0 } languageName) name = languageName;
    if (Get("Name[" + locale + "]") is { Length: > 0 } localName) name = localName;
    string Unescape(string value) => value.Replace("\\s", " ").Replace("\\n", "\n").Replace("\\t", "\t").Replace("\\r", "\r").Replace("\\\\", "\\");
    return JsonSerializer.Serialize(new { Name = Unescape(name), Exec = Get("Exec"), Icon = Unescape(Get("Icon")),
        Path = Unescape(Get("Path")), TryExec = Unescape(Get("TryExec")), Terminal = IsTrue("Terminal") });
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
            token.Append(Command[++index]); started = true; continue;
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
                case 'f': case 'F': case 'u': case 'U': break;
                default: throw new FormatException("Unsupported field code in the desktop entry: %" + value[index]);
            }
        }
        expanded.Add(argument.ToString());
    }
    if (expanded.Count == 0 || expanded[0].Length == 0) throw new FormatException("The desktop entry has no executable.");
    return JsonSerializer.Serialize(new { Executable = expanded[0], Arguments = expanded.GetRange(1, expanded.Count - 1) });
}
#EndCSharp

class ProcessRunner {
    static Start(executable, arguments := [], workingDirectory := "", capture := false) {
        return ALTRunProcessStart(executable, JSON.Stringify(arguments), workingDirectory, capture)
    }

    static StartCommand(command, workingDirectory := "", capture := false) {
        return ALTRunProcessStartCommand(command, workingDirectory, capture)
    }

    static IsFinished(job) => ALTRunProcessIsFinished(job)
    static Finish(job, terminate := false) => ALTRunProcessFinish(job, terminate)
    static CancelAll() => ALTRunProcessCancelAll()
    static QuoteShell(value) => ALTRunPosixQuote(value)
    static QuoteAppleScript(value) => ALTRunAppleScriptQuote(value)

    static DesktopEntry(filename) => JSON.Parse(ALTRunDesktopRead(filename, Platform.Locale(), EnvGet("XDG_CURRENT_DESKTOP")))

    static DesktopCommand(entry, filename) {
        spec := JSON.Parse(ALTRunDesktopCommand(entry["Exec"], filename, entry["Name"], entry["Icon"]))
        return {Executable: spec["Executable"], Arguments: spec["Arguments"]}
    }

    static ScriptHost(scriptPath, arguments := []) {
        spec := JSON.Parse(ALTRunScriptHost(scriptPath, JSON.Stringify(arguments), A_IsCompiled))
        return {Executable: spec["Executable"], Arguments: spec["Arguments"]}
    }
}

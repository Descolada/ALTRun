; Isolated macOS LaunchAgent and recent-metadata checks. Never installs an actual login agent.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((error, mode) => MacDesktopTest.Fail(error))
OnExit((*) => MacDesktopTest.CleanUp())
SetTimer(() => MacDesktopTest.Fail(Error("macOS desktop check timed out.")), -15000)
MacDesktopTest.Run()

class MacDesktopTest {
    static Folder := ""
    static Assert(value, message) {
        if !value
            throw Error(message)
    }

    static Run() {
        MacDesktopTest.Folder := Platform.Join(A_Temp, "ALTRun-MacDesktop-" Platform.NewUuid())
        folder := MacDesktopTest.Folder
        DirCreate(folder)
        library := Platform.Join(folder, "Library")
        executable := Platform.Join(folder, 'Keysharp & "汉字"')
        script := Platform.Join(folder, 'launcher %$ & 汉字.ahk')
        args := ["--errorstdout", script, "-Startup", 'quotes " and backslash\ and spaces']
        MacDesktopTest.Assert(ALTRunMacAutostartSet(library, true, executable, JSON.Stringify(args), script), "LaunchAgent was not created.")
        file := Platform.Join(library, "LaunchAgents", "org.keysharp.ALTRun.plist")
        details := JSON.Parse(ALTRunMacAgentReport(file))
        MacDesktopTest.Assert(details["Label"] == "org.keysharp.ALTRun" && details["RunAtLoad"], "LaunchAgent label or login startup is missing.")
        MacDesktopTest.Assert(details["WorkingDirectory"] == folder && details["Source"] == script, "LaunchAgent ownership or working directory changed.")
        MacDesktopTest.Assert(details["Arguments"][1] == executable && details["Arguments"].Length = args.Length + 1, "LaunchAgent executable or argument count changed.")
        for arg in args
            MacDesktopTest.Assert(details["Arguments"][A_Index + 1] == arg, "A LaunchAgent argument did not round trip XML escaping.")
        if Platform.IsMac {
            MacDesktopTest.Assert(details["Permissions"] = 0x180, "LaunchAgent permissions must remain 0600.")
            job := ProcessRunner.Start("/usr/bin/plutil", ["-lint", "--", file], "", true)
            while !ProcessRunner.IsFinished(job)
                Sleep(10)
            result := ProcessRunner.Finish(job)
            MacDesktopTest.Assert(InStr(result, ": OK"), "macOS rejected the generated property list: " result)
        }
        original := FileRead(file, "UTF-8")
        FileSetTime("20000102030405", file, "M")
        MacDesktopTest.Assert(ALTRunMacAutostartSet(library, true, executable, JSON.Stringify(args), script), "LaunchAgent update failed.")
        MacDesktopTest.Assert(FileRead(file, "UTF-8") == original && FileGetTime(file, "M") = "20000102030405", "An unchanged LaunchAgent was rewritten.")
        MacDesktopTest.Assert(!ALTRunMacAutostartSet(library, false, executable, "[]", script ".other") && FileExist(file), "Another checkout removed this checkout's login agent.")
        MacDesktopTest.Assert(ALTRunMacAutostartSet(library, false, executable, "[]", script) && !FileExist(file), "Owned login agent was not removed.")
        FileAppend('<plist version="1.0"><dict><key>Label</key><string>User agent</string></dict></plist>', file, "UTF-8-RAW")
        MacDesktopTest.Assert(!ALTRunMacAutostartSet(library, true, executable, "[]", script), "A user-created login agent was overwritten.")
        MacDesktopTest.Assert(!ALTRunMacAutostartSet(library, false, executable, "[]", script) && FileExist(file), "A user-created login agent was removed.")
        FileAppend("PASS MAC_DESKTOP owned LaunchAgent, XML arguments and plist validation`n", "*")

        fixture := JSON.Parse(ALTRunMacRecentFixture(folder))
        items := JSON.Parse(ALTRunMacRecentFilter(JSON.Stringify(fixture["Items"]), folder, 10))
        MacDesktopTest.Assert(items.Length = 2, "Recent metadata did not filter duplicate, missing, invalid or out-of-scope paths.")
        MacDesktopTest.Assert(items[1]["Path"] == fixture["Newest"] && items[2]["Path"] == fixture["Older"], "Recent metadata order changed.")
        MacDesktopTest.Assert(items[2]["IsFolder"], "Recent folder metadata lost the folder type.")
        MacDesktopTest.Assert(JSON.Parse(ALTRunMacRecentFilter(JSON.Stringify(fixture["Items"]), folder, 1)).Length = 1, "Recent limit was ignored.")
        MacDesktopTest.Assert(ALTRunMacRecentFilter(JSON.Stringify(fixture["Items"]), folder, 0) == "[]", "Zero recent limit returned results.")
        FileAppend("PASS MAC_DESKTOP recent metadata sorting, scope, stale paths and limits`n", "*")
        if Platform.IsMac {
            idle := JSON.Parse(ALTRunMacRecentSnapshot(0))
            MacDesktopTest.Assert(!idle["Pending"] && idle["Items"].Length = 0, "A status-only read started a Spotlight query.")
            started := Platform.Milliseconds()
            first := JSON.Parse(ALTRunMacRecentSnapshot(10))
            MacDesktopTest.Assert(Platform.Milliseconds() - started < 250 && first["Pending"], "Spotlight lookup did not start in the background.")
            SetTimer(() => MacDesktopTest.NativeReady(), 50)
        } else
            ExitApp(0)
    }

    static NativeReady() {
        snapshot := JSON.Parse(ALTRunMacRecentSnapshot(10))
        if snapshot["Pending"]
            return
        MacDesktopTest.Assert(snapshot["Error"] == "", "Native metadata lookup failed: " snapshot["Error"])
        limited := JSON.Parse(ALTRunMacRecentSnapshot(1)), status := JSON.Parse(ALTRunMacRecentSnapshot(0))
        MacDesktopTest.Assert(snapshot["Items"].Length <= 10 && limited["Items"].Length = Min(1, snapshot["Items"].Length), "Cached metadata ignored its result limit.")
        MacDesktopTest.Assert(!limited["Pending"] && !status["Pending"] && status["Items"].Length = 0, "Cached or status-only reads restarted Spotlight.")
        failure := JSON.Parse(ALTRunMacRecentFailureFixture())
        MacDesktopTest.Assert(!failure["Pending"] && failure["Items"].Length = 0 && failure["Error"] == "Fixture metadata unavailable", "A failed query did not return an atomic error snapshot.")
        FileAppend("PASS MAC_DESKTOP atomic Spotlight snapshot, cache, status and errors (" snapshot["Items"].Length " cached recent documents)`n", "*")
        ExitApp(0)
    }

    static Fail(error) {
        FileAppend("FAIL MAC_DESKTOP " error.Message " (" error.File ":" error.Line ")`n", "**")
        ExitApp(1)
    }

    static CleanUp() {
        if (MacDesktopTest.Folder != "" && DirExist(MacDesktopTest.Folder))
            DirDelete(MacDesktopTest.Folder, true)
    }
}

#CSharp
public static string ALTRunMacAgentReport(string file)
{
    var dictionary = System.Xml.Linq.XDocument.Load(file).Root.Element("dict");
    var elements = System.Linq.Enumerable.ToArray(dictionary.Elements());
    var values = new System.Collections.Generic.Dictionary<string, System.Xml.Linq.XElement>();
    for (int index = 0; index + 1 < elements.Length; index += 2) values.Add(elements[index].Value, elements[index + 1]);
    return System.Text.Json.JsonSerializer.Serialize(new
    {
        Label = values["Label"].Value, Source = values["ALTRunSource"].Value,
        WorkingDirectory = values["WorkingDirectory"].Value, RunAtLoad = values["RunAtLoad"].Name == "true",
        Permissions = System.OperatingSystem.IsWindows() ? 0 : (long)System.IO.File.GetUnixFileMode(file),
        Arguments = System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Select(values["ProgramArguments"].Elements(), value => value.Value))
    });
}

public static string ALTRunMacRecentFilter(string json, string scope, long maxItems)
    => System.Text.Json.JsonSerializer.Serialize(ALTRunFilterMacRecent(
        System.Text.Json.JsonSerializer.Deserialize<ALTRunMacRecentCandidate[]>(json) ?? [], scope, maxItems));

public static string ALTRunMacRecentFailureFixture()
{
    lock (ALTRunMacRecentLock)
    {
        var job = ALTRunMacRecentJob; var cached = ALTRunMacRecentCache; string error = ALTRunMacRecentFailure;
        try
        {
            ALTRunMacRecentJob = System.Threading.Tasks.Task.FromException<ALTRunMacRecentEntry[]>(new System.InvalidOperationException("Fixture metadata unavailable"));
            return ALTRunMacRecentSnapshot(0);
        }
        finally { ALTRunMacRecentJob = job; ALTRunMacRecentCache = cached; ALTRunMacRecentFailure = error; }
    }
}

public static string ALTRunMacRecentFixture(string folder)
{
    string newer = System.IO.Path.Combine(folder, "Report 汉字 & %.txt");
    string older = System.IO.Path.Combine(folder, "older folder");
    System.IO.File.WriteAllText(newer, "fixture");
    System.IO.Directory.CreateDirectory(older);
    object Entry(string path, double time) => new { Path = path, Name = "", IsFolder = false, Time = time };
    return System.Text.Json.JsonSerializer.Serialize(new { Newest = newer, Older = older, Items = new[] {
        Entry(older, 100), Entry(newer, 200), Entry(newer, 50), Entry("/System/Volumes/Data" + newer, 250),
        Entry(System.IO.Path.Combine(folder, "missing.txt"), 300),
        Entry(System.IO.Path.GetDirectoryName(folder), 400), Entry("relative.txt", 500), Entry(newer, 0) } });
}
#EndCSharp

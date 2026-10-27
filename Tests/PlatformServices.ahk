; PlatformServices.ahk - Bounded process, path and application-index checks with isolated data.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PlatformServices.OnError(err, mode))
OnExit((*) => PlatformServices.CleanUp())
SetTimer(() => PlatformServices.Fail("Timed out after 35 seconds."), -35000)
PlatformServices.Run()

#CSharp
public static bool ALTRunTestProcessAlive(long Pid)
{
    try
    {
        if (System.OperatingSystem.IsLinux())
        {
            var state = System.IO.File.ReadAllText("/proc/" + Pid + "/stat");
            if (state[state.LastIndexOf(')') + 2] == 'Z') return false;
        }
        using var process = System.Diagnostics.Process.GetProcessById((int)Pid);
        return !process.HasExited;
    }
    catch (System.ArgumentException) { return false; }
    catch (System.IO.IOException) { return false; }
}
public static void ALTRunTestStopProcess(long Pid)
{
    try
    {
        using var process = System.Diagnostics.Process.GetProcessById((int)Pid);
        if (!process.HasExited) process.Kill(entireProcessTree: true);
    }
    catch (System.ArgumentException) { }
    catch (System.InvalidOperationException) { }
}
#EndCSharp

class PlatformServices {
    static Folder := "", Children := [], Environment := Map(), Started := A_TickCount

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Equal(actual, expected, message) => PlatformServices.Assert(actual == expected, message " (expected: " expected ", actual: " actual ")")
    static Mark(message) => FileAppend("PASS PLATFORM_SERVICES " message "`n", "*")

    static Run() {
        PlatformServices.Folder := Platform.Join(A_Temp, "ALTRun-PlatformServices-" Platform.NewUuid())
        for folder in ["Data", "Fixtures", "ApplicationsUser", "ApplicationsSystem", "args % ' 漢字"]
            DirCreate(Platform.Join(PlatformServices.Folder, folder))
        AppSettings.Portable := false
        AppSettings.UserDir := PlatformServices.Folder
        AppSettings.DataDir := Platform.Join(PlatformServices.Folder, "Data")
        AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
        AppSettings.Data := AppSettings.Defaults()
        ApplicationProvider.IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
        Logger.Enabled := false
        PlatformServices.Paths()
        PlatformServices.FolderActions()
        PlatformServices.Processes()
        PlatformServices.Cancellation()
        PlatformServices.DesktopEntries()
        PlatformServices.ApplicationIndex()
        PlatformServices.Mark("complete " (A_TickCount - PlatformServices.Started) "ms")
        ExitApp(0)
    }

    static Write(relative, text, encoding := "UTF-8-RAW") {
        filename := Platform.Join(PlatformServices.Folder, relative)
        FileAppend(text, filename, encoding)
        return filename
    }

    static SetEnvironment(name, value) {
        if !PlatformServices.Environment.Has(name)
            PlatformServices.Environment[name] := EnvGet(name)
        EnvSet(name, value)
    }

    static Paths() {
        base := Platform.Join(PlatformServices.Folder, "args % ' 漢字")
        PlatformServices.Equal(Platform.Join(base, "child", "file.txt"), base A_DirSeparator "child" A_DirSeparator "file.txt", "Join must use the platform separator")
        PlatformServices.Equal(Platform.FullPath("../note.txt", base), Platform.Join(PlatformServices.Folder, "note.txt"), "FullPath must resolve relative segments")
        PlatformServices.SetEnvironment("ALTRUN_TEST_PATH", base)
        PlatformServices.Equal(Platform.ExpandEnvironment("%ALTRUN_TEST_PATH%"), base, "Percent environment expansion")
        if !Platform.IsWindows {
            PlatformServices.Equal(Platform.ExpandEnvironment("$ALTRUN_TEST_PATH/${ALTRUN_TEST_PATH}"), base "/" base, "Dollar environment expansion")
            PlatformServices.Equal(Platform.ExpandEnvironment("~/note.txt"), Platform.Home "/note.txt", "Home expansion")
            browse := FileSearchProvider.BrowsePath("~/")
            PlatformServices.Assert(IsObject(browse) && browse.Dir == Platform.Home "/", "Home folder browsing")
            browse := FileSearchProvider.BrowsePath("$ALTRUN_TEST_PATH/")
            PlatformServices.Assert(IsObject(browse) && browse.Dir == base "/", "Environment folder browsing")
            upper := PlatformServices.Write("Fixtures/Case.txt", "upper")
            lower := PlatformServices.Write("Fixtures/case.txt", "lower")
            commands := [CustomCommandProvider.FromPath(upper)]
            PlatformServices.Assert(!IsObject(CustomCommandProvider.FindByTarget(lower, commands)), "Unix paths must preserve case")
        }
        shell := Platform.FindExecutable(Platform.IsWindows ? "powershell.exe" : "sh")
        PlatformServices.Assert(shell != "" && FileExist(shell), "Executable discovery must search PATH")
        PlatformServices.Equal(Platform.FindExecutable("ALTRun-missing-" Platform.NewUuid()), "", "Missing executable discovery")
        PlatformServices.Equal(Platform.FindExecutable(shell), shell, "Absolute executable discovery")
        PlatformServices.Mark("paths, environment and executable discovery")
    }

    static FolderActions() {
        if Platform.IsWindows
            return
        parent := Platform.Join(PlatformServices.Folder, "Fixtures")
        existing := Platform.Join(parent, "ALTRun")
        DirCreate(existing)
        originalOpen := Platform.GetOwnPropDesc("Open").Call
        commands := AppSettings.Data["CustomCommands"], opened := []
        AppSettings.Data["CustomCommands"] := [Map("Title", "Documents subfolder", "Type", "Folder"
            , "Keyword", "docs", "Target", parent "/{query}", "Arguments", "")]
        Platform.DefineProp("Open", {Call: (self, target, arguments := "") => opened.Push(target)})
        try {
            results := CustomCommandProvider.Search(SearchQuery("docs ALTRun"))
            PlatformServices.Assert(results.Length = 1 && results[1].Arg == existing, "Custom folder queries must preserve path case")
            ActionCatalog.RunDefault(results[1])
            missing := Platform.Join(parent, "missing"), message := ""
            try ActionCatalog.OpenFolder(missing)
            catch as error
                message := error.Message
            PlatformServices.Equal(message, I18n.T("Files.FolderNotFound") ": " missing, "Missing folders must report the exact target")
            uri := "smb://example.test/Share"
            ActionCatalog.OpenFolder(uri)
            PlatformServices.Assert(opened.Length = 2 && opened[1] == existing && opened[2] == uri
                , "Only the existing folder and remote URI must reach the desktop opener")
        } finally {
            Platform.DefineProp("Open", {Call: originalOpen})
            AppSettings.Data["CustomCommands"] := commands
        }
        PlatformServices.Mark("custom folder path case, missing-target error and remote URI")
    }

    static Wait(job, timeout := 6000) {
        started := A_TickCount
        while !ProcessRunner.IsFinished(job) {
            if A_TickCount - started >= timeout {
                ProcessRunner.Finish(job, true)
                throw Error("Captured process timed out.")
            }
            Sleep(10)
        }
        return ProcessRunner.Finish(job)
    }

    static Processes() {
        if Platform.IsWindows {
            executable := Platform.FindExecutable("powershell.exe")
            command := '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); [Console]::WriteLine([Environment]::CurrentDirectory); [Console]::WriteLine("漢字 café % output"); [Console]::Error.WriteLine("Ελληνικά stderr"); exit 7'
            arguments := ["-NoProfile", "-NonInteractive", "-Command", command]
        } else {
            executable := Platform.FindExecutable("sh")
            arguments := ["-c", 'pwd; printf "%s\n" "$1"; printf "%s\n" "$2" >&2; exit 7', "capture", "漢字 café % output", "Ελληνικά stderr"]
        }
        workingDirectory := Platform.Join(PlatformServices.Folder, "args % ' 漢字")
        output := PlatformServices.Wait(ProcessRunner.Start(executable, arguments, workingDirectory, true))
        PlatformServices.Assert(InStr(output, "漢字 café % output") && InStr(output, "Ελληνικά stderr"), "Unicode output and stderr must be captured")
        PlatformServices.Assert(InStr(output, workingDirectory), "A working directory with spaces, percent, quotes and Unicode must remain literal")
        failed := false
        try ProcessRunner.Start(Platform.Join(PlatformServices.Folder, "no-such-program"), [], "", true)
        catch
            failed := true
        PlatformServices.Assert(failed, "A missing executable must report an exception")

        script := PlatformServices.Write("args % ' 漢字/argv % ' café.ks", "#ErrorStdOut`n#Warn All, StdOut`n#Warn Experimental, Off`n#NoTrayIcon`n"
            . 'FileAppend(A_WorkingDir Chr(10), "*", "UTF-8")' "`n"
            . 'for value in A_Args' "`n    " 'FileAppend(value Chr(10), "*", "UTF-8")' "`n")
        values := ["space value", "100%literal", 'a"b', "Ελληνικά漢字"]
        spec := ProcessRunner.ScriptHost(script, values)
        workingDirectory := Platform.Join(PlatformServices.Folder, "args % ' 漢字")
        output := PlatformServices.Wait(ProcessRunner.Start(spec.Executable, spec.Arguments, workingDirectory, true), 10000)
        lines := StrSplit(Trim(output, "`r`n"), "`n", "`r")
        PlatformServices.Equal(lines.Length, values.Length + 1, "The child script must receive every argument; output=" JSON.Stringify(output) "; args=" JSON.Stringify(spec.Arguments))
        PlatformServices.Equal(lines[1], workingDirectory, "Script directories with spaces and Unicode")
        for index, value in values
            PlatformServices.Equal(lines[index + 1], value, "Argument " index " must remain literal")
        PlatformServices.Mark("Unicode capture, missing program and literal argument arrays")
    }

    static Cancellation() {
        pidFile := Platform.Join(PlatformServices.Folder, "Data", "child.pid")
        if Platform.IsWindows {
            parent := PlatformServices.Write("Fixtures/parent.ps1", "param([string]$pidFile)`r`n"
                . '$child = Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-NoProfile -NonInteractive -Command Start-Sleep -Seconds 60" -PassThru -WindowStyle Hidden' "`r`n"
                . '[IO.File]::WriteAllText($pidFile, $child.Id.ToString())' "`r`nStart-Sleep -Seconds 60`r`n")
            executable := Platform.FindExecutable("powershell.exe")
            arguments := ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", parent, pidFile]
        } else {
            parent := PlatformServices.Write("Fixtures/parent.sh", "#!/bin/sh`nsleep 60 &`n" 'printf "%s" "$!" > "$1"' "`nwait`n")
            executable := Platform.FindExecutable("sh")
            arguments := [parent, pidFile]
        }
        job := ProcessRunner.Start(executable, arguments, PlatformServices.Folder, true)
        started := A_TickCount
        while !FileExist(pidFile) || FileGetSize(pidFile) = 0 {
            PlatformServices.Assert(A_TickCount - started < 5000, "The parent process did not create its child")
            Sleep(10)
        }
        child := Integer(Trim(FileRead(pidFile)))
        PlatformServices.Children.Push(child)
        PlatformServices.Assert(ALTRunTestProcessAlive(child), "The child must be alive before cancellation")
        ProcessRunner.Finish(job, true)
        started := A_TickCount
        while ALTRunTestProcessAlive(child) && A_TickCount - started < 2000
            Sleep(10)
        PlatformServices.Assert(!ALTRunTestProcessAlive(child) && ProcessRunner.IsFinished(job), "Cancellation must stop the process tree and release its job")
        PlatformServices.Children.Pop()
        PlatformServices.Mark("process tree cancellation")
    }

    static DesktopEntries() {
        filename := PlatformServices.Write("Fixtures/localized.desktop", "[Desktop Entry]`nType=Application`nName=Base Name`nName[fr]=Nom français`nName[fr_FR]=Nom régional`n"
            . 'Exec=/usr/bin/tool "space arg" %% %c %k %i %F %u' "`nIcon=example-icon`nTryExec=sh`nTerminal=true`nOnlyShowIn=GNOME;`n")
        entry := JSON.Parse(ALTRunDesktopRead(filename, "fr-FR", "GNOME:Example"))
        PlatformServices.Equal(entry["Name"], "Nom régional", "Desktop entries must select the most specific localized name")
        PlatformServices.Assert(entry["Terminal"] && entry["TryExec"] == "sh", "Desktop entry launch attributes")
        spec := ProcessRunner.DesktopCommand(entry, filename)
        PlatformServices.Equal(spec.Executable, "/usr/bin/tool", "The desktop executable must remain separate from its arguments")
        expected := ["space arg", "%", "Nom régional", filename, "--icon", "example-icon"]
        PlatformServices.Equal(spec.Arguments.Length, expected.Length, "Desktop field code argument count")
        for index, value in expected
            PlatformServices.Equal(spec.Arguments[index], value, "Desktop field code argument " index)
        PlatformServices.Assert(JSON.Parse(ALTRunDesktopRead(filename, "en", "KDE")).Count = 0, "OnlyShowIn must filter other desktops")
        for key in ["Hidden", "NoDisplay"] {
            hidden := PlatformServices.Write("Fixtures/" key ".desktop", "[Desktop Entry]`nType=Application`nName=Hidden`nExec=sh`n" key "=true`n")
            PlatformServices.Assert(ProcessRunner.DesktopEntry(hidden).Count = 0, key " must suppress an application")
        }
        PlatformServices.Mark("desktop localization, visibility and Exec field codes")
    }

    static ApplicationIndex() {
        cache := Map("Platform", "DifferentOS", "Apps", [])
        JSON.WriteFile(ApplicationProvider.IndexFile, cache)
        PlatformServices.Assert(!ApplicationProvider._LoadCache(), "Application caches from another OS must be rejected")
        ApplicationProvider.Apps := []
        ApplicationProvider._SaveCache()
        cache := JSON.Parse(FileRead(ApplicationProvider.IndexFile, "UTF-8"))
        PlatformServices.Assert(cache["Platform"] == A_OSType && ApplicationProvider._LoadCache(), "Application caches must save and load their platform tag")
        if !Platform.IsLinux
            return PlatformServices.Mark("application cache platform identity")
        user := Platform.Join(PlatformServices.Folder, "ApplicationsUser")
        system := Platform.Join(PlatformServices.Folder, "ApplicationsSystem")
        PlatformServices.Write("ApplicationsUser/shared.desktop", "[Desktop Entry]`nType=Application`nName=User Override`nExec=sh`n")
        PlatformServices.Write("ApplicationsSystem/shared.desktop", "[Desktop Entry]`nType=Application`nName=System Entry`nExec=sh`n")
        PlatformServices.Write("ApplicationsUser/masked.desktop", "[Desktop Entry]`nHidden=true`n")
        PlatformServices.Write("ApplicationsSystem/masked.desktop", "[Desktop Entry]`nType=Application`nName=Masked System Entry`nExec=sh`n")
        PlatformServices.Write("ApplicationsUser/missing.desktop", "[Desktop Entry]`nType=Application`nName=Missing Interpreter`nExec=sh`nTryExec=ALTRun-program-that-does-not-exist`n")
        options := AppSettings.Feature("Applications")
        options["Folders"] := [user, system], options["FileTypes"] := ["*.desktop"], options["StoreApps"] := 0
        options["Depth"] := 2, options["Exclude"] := "", options["MatchPinyin"] := 0
        PlatformServices.Equal(ApplicationProvider.Rebuild(), 1, "User overrides, hidden desktop IDs and TryExec filtering")
        PlatformServices.Equal(ApplicationProvider.Apps[1]["Title"], "User Override", "The user desktop entry must override the system entry")
        PlatformServices.Equal(ApplicationProvider.Apps[1]["Target"], Platform.Join(user, "shared.desktop"), "The indexed target must be the user desktop entry")
        PlatformServices.Mark("desktop ID override, hidden masking and interpreter filtering")
    }

    static CleanUp() {
        try ProcessRunner.CancelAll()
        for child in PlatformServices.Children
            try ALTRunTestStopProcess(child)
        for name, value in PlatformServices.Environment
            try EnvSet(name, value)
        try {
            if PlatformServices.Folder != "" && InStr(PlatformServices.Folder, "ALTRun-PlatformServices-") && DirExist(PlatformServices.Folder)
                DirDelete(PlatformServices.Folder, true)
        }
    }

    static OnError(err, mode) {
        FileAppend("FAIL PLATFORM_SERVICES " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }

    static Fail(message) {
        FileAppend("FAIL PLATFORM_SERVICES " message "`n", "**")
        ExitApp(1)
    }
}

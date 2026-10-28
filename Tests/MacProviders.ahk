; Isolated macOS bundle discovery, terminal quoting and inert system-command dispatch.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacProviders.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacProviders.CleanUp())
SetTimer(() => MacProviders.Fail("Timed out after 20 seconds."), -20000)
MacProviders.Run()

MsgBox(args*) {
    MacProviders.Confirmations++
    return "No"
}

Send(keys) {
    MacProviders.SentKeys.Push(keys)
}

class MacProviders {
    static Folder := "", Captured := [], SentKeys := [], Wrappers := [], Confirmations := 0, OriginalRunner := ""

    static Check(condition, message) {
        if !condition
            throw Error(message)
    }

    static Write(relative, text) {
        file := Platform.Join(MacProviders.Folder, relative)
        SplitPath(file, , &folder)
        DirCreate(folder)
        FileAppend(text, file, "UTF-8-RAW")
        return file
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_PROVIDERS requires macOS`n", "*")
            ExitApp(0)
        }
        MacProviders.Folder := Platform.Join(A_Temp, "ALTRun-MacProviders-" Platform.NewUuid())
        DirCreate(MacProviders.Folder)
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.DataDir := MacProviders.Folder
        ApplicationProvider.IndexFile := Platform.Join(MacProviders.Folder, "AppIndex.json")
        MacProviders.Hotkeys()
        MacProviders.Bundles()
        MacProviders.Terminals()
        MacProviders.Commands()
        FileAppend("PASS MAC_PROVIDERS hotkey labels, native bundle metadata, binary plist, discovery, terminal quoting and safe command dispatch`n", "*")
        ExitApp(0)
    }

    static Hotkeys() {
        MacProviders.Check(Win.HotkeyLabel("!Space") == "Option+Space" && Win.HotkeyLabel("#c") == "Cmd+C", "macOS hotkey labels must use Option and Cmd.")
        for pair in [["Command+Option+R", "!#r"], ["cmd + SHIFT + Space Up", "+#Space up"], ["Option++", "!+"]
            , ["Ctrl+Alt+Shift+Win+C", "^!+#c"], ["Cmd+Win+Option+Alt+R", "!#r"]] {
            normalized := Win.NormalizeHotkeyLabel(pair[1])
            MacProviders.Check(normalized == pair[2] && Win.NormalizeHotkeyLabel(normalized) == normalized, "Display-label normalization must accept platform aliases and remain idempotent: " pair[1])
        }
        for key in ["!Space", "#c", "^!+#c", "^+", "!+", "+#Space up"]
            MacProviders.Check(Win.NormalizeHotkeyLabel(Win.HotkeyLabel(key)) == key, "macOS labels must round-trip through persisted hotkey syntax: " key)
        for key in ["Option", "Command", "Cmd+UnknownKey", "Option+UnknownKey", "~*^!c"]
            MacProviders.Check(Win.NormalizeHotkeyLabel(key) == key, "Normalization must preserve native syntax and unsupported labels: " key)
    }

    static Bundles() {
        plist := '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
            . '<key>CFBundleName</key><string>Bundle Name</string><key>CFBundleDisplayName</key><string>Display 漢字</string>'
            . '<key>CFBundleIdentifier</key><string>org.altrun.MacFixture</string><key>CFBundlePackageType</key><string>APPL</string>'
            . '<key>CFBundleExecutable</key><string>fixture</string></dict></plist>'
        file := MacProviders.Write("Applications/Filename.app/Contents/Info.plist", plist)
        bundle := Platform.Join(MacProviders.Folder, "Applications", "Filename.app")
        metadata := ApplicationProvider.MacBundle(bundle)
        MacProviders.Check(metadata["Name"] == "Display 漢字" && metadata["Identifier"] == "org.altrun.MacFixture", "Native bundle metadata must use the display name and bundle identifier.")
        binary := MacProviders.Write("Applications/Binary.app/Contents/Info.plist", StrReplace(plist, "Display 漢字", "Binary Name"))
        job := ProcessRunner.Start("/usr/bin/plutil", ["-convert", "binary1", binary], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        result := ProcessRunner.Finish(job)
        MacProviders.Check(result = "" && SubStr(FileRead(binary), 1, 6) == "bplist" && ApplicationProvider.MacBundle(Platform.Join(MacProviders.Folder, "Applications", "Binary.app"))["Name"] == "Binary Name", "Binary Info.plist must be read without an XML-only fallback.")
        MacProviders.Write("Applications/Helper.app/Contents/Info.plist", StrReplace(plist, "</dict>", "<key>LSBackgroundOnly</key><true/></dict>"))
        MacProviders.Write("Applications/Filename.app/Contents/Hidden.app/Contents/Info.plist", plist)
        MacProviders.Write("Applications/Other/Unrelated.txt", "text")
        options := AppSettings.Feature("Applications")
        options["Folders"] := [Platform.Join(MacProviders.Folder, "Applications")]
        options["FileTypes"] := ["*.app"], options["Depth"] := 5, options["Exclude"] := "", options["MatchPinyin"] := 0
        MacProviders.Check(ApplicationProvider.Rebuild() = 2, "Bundle discovery must skip background helpers and avoid recursing inside applications.")
        for term in ["filename", "org.altrun.MacFixture", "display"]
            MacProviders.Check(ApplicationProvider.Search(SearchQuery(term)).Length > 0, "The original filename, identifier and display name must remain searchable: " term)
        options["FileTypes"] := ["*.desktop"]
        MacProviders.Check(ApplicationProvider.Rebuild() = 0, "macOS application discovery must respect configured file types.")
        real := ApplicationProvider.MacBundle("/System/Applications/Utilities/Terminal.app")
        MacProviders.Check(real["Name"] != "" && real["Identifier"] == "com.apple.Terminal", "A real system bundle must resolve through CoreFoundation.")
    }

    static Terminals() {
        folder := Platform.Join(MacProviders.Folder, "quotes ' `" $() `` 漢字`nfolder")
        DirCreate(folder)
        command := 'printf "%s" "literal" # trailing comment'
        launch := TerminalProvider.MacLaunch(command, folder, "/bin/zsh")
        MacProviders.Wrappers.Push(launch.Path)
        MacProviders.Check(InStr(launch.Script, 'com.apple.Terminal') && InStr(launch.Line, "exec /bin/sh ")
            && !InStr(launch.Line, "`n") && !InStr(launch.Line, "`r"), "Terminal input must be a single short wrapper command.")
        MacProviders.Check(InStr(TerminalProvider.MacScript(launch.Line, "iTerm"), "com.googlecode.iterm2"), "The iTerm setting must select its own scripting target.")
        MacProviders.Check(ALTRunMacFixtureMode(launch.Path) = 384, "Terminal wrapper must be created with private 0600 permissions.")
        MacProviders.Check(!InStr(launch.Script, ProcessRunner.QuoteAppleScript(command)), "User commands must stay in the private wrapper instead of terminal input.")
        literal := folder "`n" command
        job := ProcessRunner.Start("/bin/zsh", ["-fc", "printf %s " ProcessRunner.QuoteShell(literal)], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        result := ProcessRunner.Finish(job)
        MacProviders.Check(result == literal, "POSIX quoting must preserve spaces, quotes, shell metacharacters and Unicode literally.")
        job := ProcessRunner.Start("/usr/bin/osascript", ["-e", "return " ProcessRunner.QuoteAppleScript(literal)], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        result := ProcessRunner.Finish(job)
        MacProviders.Check(RTrim(result, "`r`n") == literal, "AppleScript quoting must round-trip paths and commands without evaluating their contents.")
        MacProviders.TerminalWrappers(folder)

        ; Replace the entire application block so the real cleanup handler runs without contacting Terminal.
        failure := RegExReplace(launch.Script, 's)tell application id "com.apple.Terminal".*?end tell', 'error "Synthetic automation failure" number 117')
        job := ProcessRunner.Start("/usr/bin/osascript", ["-e", failure], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        result := ProcessRunner.Finish(job)
        MacProviders.Check(!FileExist(launch.Path) && InStr(result, "Synthetic automation failure"), "Failed automation must delete the private wrapper and preserve its error.")
    }

    static TerminalWrappers(folder) {
        log := Platform.Join(MacProviders.Folder, "terminal-calls.txt")
        received := Platform.Join(MacProviders.Folder, "terminal-command.txt")
        cwd := Platform.Join(MacProviders.Folder, "terminal-folder.txt")
        status := Platform.Join(MacProviders.Folder, "terminal-status.txt")
        shell := MacProviders.Write("shell ' `" 漢字.sh", "#!/bin/sh`n"
            . 'if [ "$1" = "-lc" ]; then' "`nprintf 'COMMAND\n' >> " ProcessRunner.QuoteShell(log) "`n"
            . 'printf %s "$2" > ' ProcessRunner.QuoteShell(received) "`n"
            . '/bin/sh -c "$2"' "`nresult=$?`nprintf %s `"$result`" > " ProcessRunner.QuoteShell(status) "`nexit `"$result`"`nfi`n"
            . 'if [ "$1" = "-i" ]; then' "`nprintf 'INTERACTIVE\n' >> " ProcessRunner.QuoteShell(log) "`n"
            . "/bin/pwd > " ProcessRunner.QuoteShell(cwd) "`nexit 0`nfi`nexit 99`n")
        ALTRunMacFixtureExecutable(shell)
        for fixture in [["printf 'one\n'", "one`n", 0]
            , ["printf 'two\n' # trailing comment", "two`n", 0]
            , ["printf '%s\n' " ProcessRunner.QuoteShell("quote `" ' $ literal"), "quote `" ' $ literal`n", 0]
            , ["printf 'first\n'`nprintf 'second\n'", "first`nsecond`n", 0]
            , ["exit 7", "", 7], ["false", "", 0], ["", "", 0]] {
            for file in [log, received, cwd, status]
                try FileDelete(file)
            launch := TerminalProvider.MacLaunch(fixture[1], folder, shell)
            MacProviders.Wrappers.Push(launch.Path)
            MacProviders.Check(ALTRunMacFixtureMode(launch.Path) = 384 && !InStr(launch.Line, "`n"), "A wrapper exposed command data or multiline terminal input.")
            job := ProcessRunner.Start("/bin/sh", ["-c", launch.Line], "", true)
            while !ProcessRunner.IsFinished(job)
                Sleep(10)
            result := ProcessRunner.Finish(job)
            MacProviders.Check(result == fixture[2], "The wrapper changed command output: " fixture[1])
            MacProviders.Check(!FileExist(launch.Path), "The running wrapper did not remove itself.")
            calls := fixture[1] = "" ? "INTERACTIVE`n" : fixture[3] = 7 ? "COMMAND`n" : "COMMAND`nINTERACTIVE`n"
            MacProviders.Check(FileRead(log) == calls, "The command or interactive continuation did not run exactly once.")
            if (fixture[3] != 7)
                MacProviders.Check(RTrim(FileRead(cwd), "`r`n") == folder, "The configured working folder did not survive quoting.")
            if (fixture[1] != "")
                MacProviders.Check(FileRead(received) == fixture[1] "`nexec " ProcessRunner.QuoteShell(shell) " -i"
                    && Integer(FileRead(status)) = fixture[3], "Command text or its explicit exit status changed.")
        }
        powerLog := Platform.Join(MacProviders.Folder, "powershell-arguments.txt")
        power := MacProviders.Write("pwsh", "#!/bin/sh`nprintf '%s\n' `"$@`" > " ProcessRunner.QuoteShell(powerLog) "`n")
        ALTRunMacFixtureExecutable(power)
        text := "Write-Output 'quotes `" 漢字'`nexit 3"
        launch := TerminalProvider.MacLaunch(text, folder, power)
        MacProviders.Wrappers.Push(launch.Path)
        job := ProcessRunner.Start("/bin/sh", ["-c", launch.Line], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        MacProviders.Check(ProcessRunner.Finish(job) == "" && FileRead(powerLog) == "-NoExit`n-Command`n" text "`n"
            && !FileExist(launch.Path), "PowerShell must receive -NoExit and the unchanged command as its own argument.")
        MacProviders.TerminalState(folder)
    }

    static TerminalState(folder) {
        stateDir := Platform.Join(MacProviders.Folder, "Zdotdir")
        report := Platform.Join(MacProviders.Folder, "terminal-state.txt")
        MacProviders.Write("Zdotdir/.zshrc", "printf '%s\n%s\n' `"$PWD`" `"$ALTRUN_TERMINAL_STATE`" > " ProcessRunner.QuoteShell(report) "`nexit`n")
        value := "preserved ' `" 漢字"
        command := "cd -- " ProcessRunner.QuoteShell(folder) "`nexport ALTRUN_TERMINAL_STATE=" ProcessRunner.QuoteShell(value)
        launch := TerminalProvider.MacLaunch(command, Platform.Home, "/bin/zsh")
        MacProviders.Wrappers.Push(launch.Path)
        previous := EnvGet("ZDOTDIR")
        try {
            EnvSet("ZDOTDIR", stateDir)
            job := ProcessRunner.Start("/bin/sh", ["-c", launch.Line], "", true)
        } finally EnvSet("ZDOTDIR", previous)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        ProcessRunner.Finish(job)
        MacProviders.Check(FileExist(report) && FileRead(report) == folder "`n" value "`n" && !FileExist(launch.Path)
            , "A real interactive zsh must inherit the command's changed directory and exported state.")
    }

    static Commands() {
        SystemProvider._commands := ""
        SystemProvider.RunCommand("Lock")
        MacProviders.Check(MacProviders.SentKeys.Length = 1 && MacProviders.SentKeys[1] == "^#q", "Lock must use the documented Control+Command+Q shortcut.")
        commands := Map()
        for command in SystemProvider.MacCommands() {
            MacProviders.Check(!commands.Has(command["Id"]), "Duplicate system command: " command["Id"])
            commands[command["Id"]] := command
        }
        for id in ["Sleep", "MonitorOff", "Shutdown", "Restart", "Logoff", "EmptyRecycle", "Mute", "VolumeUp", "VolumeDown", "Settings", "TaskManager", "Calculator", "Notepad", "Explorer"]
            MacProviders.Check(commands.Has(id), "Missing macOS command: " id)
        for id in ["Shutdown", "Restart", "Logoff", "EmptyRecycle"]
            MacProviders.Check(commands[id]["Confirm"], "Destructive commands must retain confirmation: " id)
        MacProviders.OriginalRunner := SystemProvider.NativeRunner
        SystemProvider.NativeRunner := (executable, arguments) => MacProviders.Captured.Push({Executable: executable, Arguments: arguments})
        SystemProvider._commands := []
        for id, command in commands
            SystemProvider._commands.Push(Map("Id", id, "Title", id, "Confirm", command["Confirm"], "Run", SystemProvider._NativeCommand(command)))
        AppSettings.Feature("System")["ConfirmActions"] := 1
        SystemProvider.RunCommand("Shutdown")
        MacProviders.Check(MacProviders.Confirmations = 1 && MacProviders.Captured.Length = 0, "Declining shutdown must prevent native dispatch.")
        AppSettings.Feature("System")["ConfirmActions"] := 0
        for id, command in commands {
            SystemProvider.RunCommand(id)
            captured := MacProviders.Captured[MacProviders.Captured.Length]
            MacProviders.Check(captured.Executable == command["Executable"] && JSON.Stringify(captured.Arguments) == JSON.Stringify(command["Arguments"]), "Dispatch must preserve native argument boundaries: " id)
        }
    }

    static CleanUp() {
        if IsObject(MacProviders.OriginalRunner)
            SystemProvider.NativeRunner := MacProviders.OriginalRunner
        for file in MacProviders.Wrappers
            try FileDelete(file)
        try {
            if (MacProviders.Folder != "" && InStr(MacProviders.Folder, Platform.Join(A_Temp, "ALTRun-MacProviders-")) = 1)
                DirDelete(MacProviders.Folder, true)
        }
    }

    static Fail(message) {
        FileAppend("FAIL MAC_PROVIDERS " message "`n", "**")
        ExitApp(1)
        return true
    }
}

#CSharp
public static long ALTRunMacFixtureMode(string path) => (long)System.IO.File.GetUnixFileMode(path);
public static void ALTRunMacFixtureExecutable(string path)
    => System.IO.File.SetUnixFileMode(path, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
#EndCSharp

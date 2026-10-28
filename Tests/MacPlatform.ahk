; macOS desktop opener contracts, without launching external applications.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacPlatform.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacPlatform.CleanUp())
SetTimer(() => MacPlatform.Fail("Timed out after 15 seconds."), -15000)
MacPlatform.Run()

class MacPlatform {
    static Folder := "", Calls := []

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_PLATFORM requires macOS`n", "*")
            ExitApp(0)
        }
        MacPlatform.Folder := Platform.Join(A_Temp, "ALTRun-MacPlatform-" Platform.NewUuid())
        bundle := Platform.Join(MacPlatform.Folder, '漢字 "quoted" App.app')
        DirCreate(bundle)
        originalStart := ProcessRunner.GetOwnPropDesc("StartApplication").Call
        originalCommand := ProcessRunner.GetOwnPropDesc("StartApplicationCommand").Call
        ProcessRunner.DefineProp("StartApplication", {Call: (self, executable, arguments := [], workingDirectory := "", capture := false)
            => MacPlatform.Calls.Push({Executable: executable, Arguments: arguments})})
        ProcessRunner.DefineProp("StartApplicationCommand", {Call: (self, command, workingDirectory := "", capture := false)
            => MacPlatform.Calls.Push({Command: command})})
        try {
            Platform.Open(bundle)
            call := MacPlatform.Calls.Pop()
            MacPlatform.Assert(call.Executable == "/usr/bin/open" && JSON.Stringify(call.Arguments) == JSON.Stringify(["-a", bundle]), "Application bundles must launch through Launch Services.")
            arguments := '--flag "space value" "漢字"'
            ActionCatalog.OpenFile(bundle, arguments)
            call := MacPlatform.Calls.Pop()
            MacPlatform.Assert(call.Command == '"/usr/bin/open" -a ' ALTRunQuoteArgument(bundle) ' --args ' arguments, "Custom application arguments must reach open --args.")
            Platform.Open("https://example.test/path?q=漢字")
            call := MacPlatform.Calls.Pop()
            MacPlatform.Assert(call.Executable == "/usr/bin/open" && call.Arguments[1] == "https://example.test/path?q=漢字", "URLs must remain literal arguments.")
            Platform.Edit(Platform.Join(MacPlatform.Folder, "settings.json"))
            call := MacPlatform.Calls.Pop()
            MacPlatform.Assert(call.Executable == "/usr/bin/open" && call.Arguments[1] == "-t", "Edit must use a text editor.")
        } finally {
            ProcessRunner.DefineProp("StartApplication", {Call: originalStart})
            ProcessRunner.DefineProp("StartApplicationCommand", {Call: originalCommand})
        }
        ; Exercise the same raw argument parser used by StartApplicationCommand.
        values := ["space value", 'a"b', "trailing\", 'slash\"quote', "", "100%literal", "漢字`nline"]
        command := '"/usr/bin/printf" "%s\n"'
        expected := ""
        for value in values {
            command .= " " ALTRunQuoteArgument(value)
            expected .= value "`n"
        }
        job := ProcessRunner.StartCommand(command, "", true)
        started := A_TickCount
        while !ProcessRunner.IsFinished(job) {
            MacPlatform.Assert(A_TickCount - started < 5000, "Argument capture timed out.")
            Sleep(10)
        }
        MacPlatform.Assert(ProcessRunner.Finish(job) == expected, "Raw process argument quoting changed a literal value.")
        FileAppend("PASS MAC_PLATFORM bundles, application arguments, URLs, editor and literal process quoting`n", "*")
        ExitApp(0)
    }

    static CleanUp() {
        try ProcessRunner.CancelAll()
        if (MacPlatform.Folder != "" && InStr(MacPlatform.Folder, "ALTRun-MacPlatform-") && DirExist(MacPlatform.Folder))
            try DirDelete(MacPlatform.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL MAC_PLATFORM " message "`n", "**")
        ExitApp(1)
        return true
    }
}

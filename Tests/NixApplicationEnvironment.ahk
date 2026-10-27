; NixApplicationEnvironment - external apps must not inherit Keysharp's native library closure.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => NixApplicationEnvironment.Fail(err.Message "`n" err.Stack))
OnExit((*) => ProcessRunner.CancelAll())
SetTimer(() => NixApplicationEnvironment.Fail("Timed out after 20 seconds."), -20000)
NixApplicationEnvironment.Run()

class NixApplicationEnvironment {
    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Wait(job) {
        started := A_TickCount
        while !ProcessRunner.IsFinished(job) {
            if (A_TickCount - started > 5000) {
                ProcessRunner.Finish(job, true)
                throw Error("The environment fixture child timed out.")
            }
            Sleep(10)
        }
        return Trim(ProcessRunner.Finish(job), "`r`n")
    }

    static Run() {
        if (!Platform.IsLinux || !FileExist("/etc/NIXOS")) {
            FileAppend("SKIP NIX_APPLICATION_ENVIRONMENT NixOS only.`n", "*")
            ExitApp(0)
        }
        shell := Platform.FindExecutable("sh")
        NixApplicationEnvironment.Assert(shell != "", "A POSIX shell is required.")
        original := EnvGet("LD_LIBRARY_PATH")
        hadLibraryPath := Clr.System.Environment.GetEnvironmentVariables().Contains("LD_LIBRARY_PATH")
        arguments := ["-c", 'printf "%s" "${LD_LIBRARY_PATH-<unset>}"']
        inherited := NixApplicationEnvironment.Wait(ProcessRunner.Start(shell, arguments, "", true))
        NixApplicationEnvironment.Assert(inherited == (hadLibraryPath ? original : "<unset>")
            , "Runtime child processes must retain their native libraries.")
        clean := NixApplicationEnvironment.Wait(ProcessRunner.StartApplication(shell, arguments, "", true))
        NixApplicationEnvironment.Assert(clean == "<unset>", "External applications inherited Keysharp's native libraries.")
        clean := NixApplicationEnvironment.Wait(ProcessRunner.StartApplicationCommand('"' shell '" -c "printenv LD_LIBRARY_PATH || true"', "", true))
        NixApplicationEnvironment.Assert(clean == "", "External command strings inherited Keysharp's native libraries.")
        NixApplicationEnvironment.Assert(EnvGet("LD_LIBRARY_PATH") == original
            && Clr.System.Environment.GetEnvironmentVariables().Contains("LD_LIBRARY_PATH") = hadLibraryPath
            , "Launching an application changed the runtime's environment.")
        FileAppend("PASS NIX_APPLICATION_ENVIRONMENT isolated external libraries; runtime child environment preserved`n", "*")

        browser := Platform.FindExecutable("firefox")
        if (browser != "") {
            report := NixApplicationEnvironment.Wait(ProcessRunner.StartApplication(browser, ["--version"], "", true))
            NixApplicationEnvironment.Assert(InStr(report, "Firefox") && !InStr(report, "XPCOM")
                , "Firefox failed to load its native libraries: " report)
            FileAppend("PASS NIX_APPLICATION_ENVIRONMENT Firefox --version loads its own native libraries`n", "*")
        }
        ExitApp(0)
    }

    static Fail(message) {
        FileAppend("FAIL NIX_APPLICATION_ENVIRONMENT " message "`n", "**")
        ExitApp(1)
        return true
    }
}

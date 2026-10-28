; Bundled diagnostics: inspect path/data resolution without starting ALTRun or changing settings.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ALTRun.Modules.ahk

login := ProcessRunner.ScriptHost(Platform.Join(A_ScriptDir, "ALTRun.ahk"), ["-Startup"])
FileAppend("ALTRUN_PACKAGE " JSON.Stringify(Map("Bundle", Platform.AppBundle, "Portable", AppSettings.Portable
    , "Source", A_ScriptDir, "Data", AppSettings.DataDir, "Host", A_AhkPath
    , "LoginExecutable", login.Executable, "LoginArguments", login.Arguments)) "`n", "*")
if (A_Args.Length >= 2 && A_Args[1] = "--child") {
    arguments := []
    for index, value in A_Args
        if (index >= 3)
            arguments.Push(value)
    child := ProcessRunner.ScriptHost(A_Args[2], arguments)
    job := ProcessRunner.Start(child.Executable, child.Arguments, "", true), started := A_TickCount
    while !ProcessRunner.IsFinished(job) {
        if (A_TickCount - started > 20000) {
            ProcessRunner.Finish(job, true)
            throw Error("Packaged child script timed out.")
        }
        Sleep(20)
    }
    result := ProcessRunner.Result(job)
    if result["ExitCode"]
        throw Error("Packaged child script failed: " result["Error"])
    FileAppend("ALTRUN_CHILD " result["Output"], "*")
}
if (A_Args.Length >= 2 && A_Args[1] = "--archive")
    FileAppend("ALTRUN_ARCHIVE " ALTRunMacValidateUpdateArchive(A_Args[2]) "`n", "*")
ExitApp(0)

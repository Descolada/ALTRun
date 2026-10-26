; LinuxSystemCommands - inspect native command selection and dispatch using inert PATH fixtures.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => LinuxSystemCommands.OnError(err, mode))
OnExit((*) => LinuxSystemCommands.CleanUp())
SetTimer(() => LinuxSystemCommands.Fail("Timed out after 15 seconds."), -15000)
LinuxSystemCommands.Run()

; A regression must never turn this unattended check into a desktop prompt.
MsgBox(args*) {
    throw Error("Unexpected confirmation dialog.")
}

#CSharp
public static void ALTRunSystemFixtureExecutable(string Filename)
{
    if (!System.OperatingSystem.IsWindows())
        System.IO.File.SetUnixFileMode(Filename, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
}
#EndCSharp

class LinuxSystemCommands {
    static Folder := "", Environment := Map(), Captured := [], OriginalRunner := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static EqualJson(actual, expected, message) {
        LinuxSystemCommands.Assert(JSON.Stringify(actual) == JSON.Stringify(expected), message)
    }

    static Run() {
        if !Platform.IsLinux {
            FileAppend("SKIP LINUX_SYSTEM_COMMANDS requires Linux`n", "*")
            ExitApp(0)
        }
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.Feature("System")["ConfirmActions"] := 0
        LinuxSystemCommands.Folder := Platform.Join(A_Temp, "ALTRun-SystemCommands-" Platform.NewUuid(), "commands 漢字")
        DirCreate(LinuxSystemCommands.Folder)
        LinuxSystemCommands.SetEnvironment("PATH", LinuxSystemCommands.Folder)
        LinuxSystemCommands.SetEnvironment("XDG_SESSION_ID", "c42")
        LinuxSystemCommands.SetEnvironment("XDG_CURRENT_DESKTOP", "GNOME")
        LinuxSystemCommands.Assert(SystemProvider.LinuxCommands(1).Length = 0, "Missing tools must not produce native commands.")

        for executable in ["loginctl", "systemctl", "wpctl", "pactl", "playerctl", "gio", "gnome-control-center", "gnome-system-monitor"
            , "gnome-calculator", "gnome-text-editor", "systemsettings", "plasma-systemmonitor", "kcalc", "kate"
            , "xfce4-settings-manager", "xfce4-taskmanager", "galculator", "mousepad"]
            LinuxSystemCommands.MakeExecutable(executable)
        commands := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(1))
        LinuxSystemCommands.Assert(commands.Count = 18, "Every supported native command should be offered once.")
        LinuxSystemCommands.Arguments(commands, "Lock", "loginctl", ["lock-session", "c42"])
        LinuxSystemCommands.Arguments(commands, "Logoff", "loginctl", ["terminate-session", "c42"])
        LinuxSystemCommands.Arguments(commands, "Sleep", "systemctl", ["suspend"])
        LinuxSystemCommands.Arguments(commands, "Hibernate", "systemctl", ["hibernate"])
        LinuxSystemCommands.Arguments(commands, "Shutdown", "systemctl", ["poweroff"])
        LinuxSystemCommands.Arguments(commands, "Restart", "systemctl", ["reboot"])
        LinuxSystemCommands.Arguments(commands, "EmptyRecycle", "gio", ["trash", "--empty"])
        LinuxSystemCommands.Arguments(commands, "Mute", "wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        LinuxSystemCommands.Arguments(commands, "VolumeUp", "wpctl", ["set-volume", "--limit", "1.0", "@DEFAULT_AUDIO_SINK@", "10%+"])
        LinuxSystemCommands.Arguments(commands, "VolumeDown", "wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "10%-"])
        for pair in [["MediaPlayPause", "play-pause"], ["MediaNext", "next"], ["MediaPrev", "previous"], ["MediaStop", "stop"]]
            LinuxSystemCommands.Arguments(commands, pair[1], "playerctl", [pair[2]])
        LinuxSystemCommands.Arguments(commands, "Settings", "gnome-control-center", [])
        LinuxSystemCommands.Arguments(commands, "TaskManager", "gnome-system-monitor", [])
        LinuxSystemCommands.Arguments(commands, "Calculator", "gnome-calculator", [])
        LinuxSystemCommands.Arguments(commands, "Notepad", "gnome-text-editor", [])
        for id in ["Logoff", "Hibernate", "Shutdown", "Restart", "EmptyRecycle"]
            LinuxSystemCommands.Assert(commands[id]["Confirm"], id " must retain its confirmation flag.")
        LinuxSystemCommands.Assert(!commands["Sleep"]["Confirm"] && commands["Notepad"]["English"] == "Text Editor", "Sleep and tool search metadata.")

        LinuxSystemCommands.OriginalRunner := SystemProvider.NativeRunner
        SystemProvider.NativeRunner := (executable, arguments) => LinuxSystemCommands.Capture(executable, arguments)
        SystemProvider._commands := []
        for id, command in commands {
            SystemProvider._commands.Push(Map("Id", id, "Title", id, "Confirm", command["Confirm"], "Run", SystemProvider._NativeCommand(command)))
            SystemProvider.RunCommand(id)
            captured := LinuxSystemCommands.Captured[LinuxSystemCommands.Captured.Length]
            LinuxSystemCommands.Assert(captured.Executable == command["Executable"], "Dispatch must preserve the executable's literal path.")
            LinuxSystemCommands.EqualJson(captured.Arguments, command["Arguments"], "Dispatch must preserve argument arrays.")
        }
        SystemProvider.RunCommand("MuteVolume")
        LinuxSystemCommands.EqualJson(LinuxSystemCommands.Captured[LinuxSystemCommands.Captured.Length].Arguments, commands["Mute"]["Arguments"], "Legacy command aliases must keep working.")
        LinuxSystemCommands.Assert(LinuxSystemCommands.Captured.Length = commands.Count + 1, "Dispatch must call only the injected runner.")

        noSystemd := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(0))
        for id in ["Sleep", "Hibernate", "Shutdown", "Restart"]
            LinuxSystemCommands.Assert(!noSystemd.Has(id), "Power commands need an active systemd runtime.")
        LinuxSystemCommands.Assert(noSystemd.Has("Logoff"), "An explicit session may be provided by elogind.")
        LinuxSystemCommands.SetEnvironment("XDG_SESSION_ID", "../untrusted session")
        noSession := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(1))
        LinuxSystemCommands.Assert(!noSession.Has("Logoff"), "An invalid session must never offer logoff.")
        LinuxSystemCommands.Arguments(noSession, "Lock", "loginctl", ["lock-session"])
        LinuxSystemCommands.SetEnvironment("XDG_SESSION_ID", "")
        noSession := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(0))
        LinuxSystemCommands.Assert(!noSession.Has("Lock") && !noSession.Has("Logoff"), "Session commands need a session or systemd runtime.")

        FileDelete(Platform.Join(LinuxSystemCommands.Folder, "wpctl"))
        pulse := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(1))
        LinuxSystemCommands.Arguments(pulse, "Mute", "pactl", ["set-sink-mute", "@DEFAULT_SINK@", "toggle"])
        LinuxSystemCommands.Arguments(pulse, "VolumeUp", "pactl", ["set-sink-volume", "@DEFAULT_SINK@", "+10%"])
        LinuxSystemCommands.Arguments(pulse, "VolumeDown", "pactl", ["set-sink-volume", "@DEFAULT_SINK@", "-10%"])
        LinuxSystemCommands.SetEnvironment("XDG_CURRENT_DESKTOP", "KDE")
        kde := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(1))
        LinuxSystemCommands.Arguments(kde, "Settings", "systemsettings", [])
        LinuxSystemCommands.Arguments(kde, "TaskManager", "plasma-systemmonitor", [])
        LinuxSystemCommands.Arguments(kde, "Calculator", "kcalc", [])
        LinuxSystemCommands.Arguments(kde, "Notepad", "kate", [])
        LinuxSystemCommands.SetEnvironment("XDG_CURRENT_DESKTOP", "XFCE")
        xfce := LinuxSystemCommands.ById(SystemProvider.LinuxCommands(1))
        LinuxSystemCommands.Arguments(xfce, "Settings", "xfce4-settings-manager", [])
        LinuxSystemCommands.Arguments(xfce, "TaskManager", "xfce4-taskmanager", [])
        LinuxSystemCommands.Arguments(xfce, "Calculator", "galculator", [])
        LinuxSystemCommands.Arguments(xfce, "Notepad", "mousepad", [])
        FileAppend("PASS LINUX_SYSTEM_COMMANDS prerequisites, session validation, audio backends, media, desktop tools and inert argument dispatch`n", "*")
        ExitApp(0)
    }

    static MakeExecutable(name) {
        filename := Platform.Join(LinuxSystemCommands.Folder, name)
        FileAppend("#!/bin/sh`nexit 97`n", filename, "UTF-8-RAW")
        ALTRunSystemFixtureExecutable(filename)
    }

    static ById(commands) {
        result := Map()
        for command in commands {
            id := command["Id"]
            LinuxSystemCommands.Assert(!result.Has(id), "Duplicate command: " id)
            result[id] := command
        }
        return result
    }

    static Arguments(commands, id, executable, arguments) {
        LinuxSystemCommands.Assert(commands.Has(id), "Missing command: " id)
        LinuxSystemCommands.Assert(commands[id]["Executable"] == Platform.Join(LinuxSystemCommands.Folder, executable), id " selected the wrong program.")
        LinuxSystemCommands.EqualJson(commands[id]["Arguments"], arguments, id " composed the wrong arguments.")
    }

    static Capture(executable, arguments) {
        LinuxSystemCommands.Captured.Push({Executable: executable, Arguments: arguments})
        return 1
    }

    static SetEnvironment(name, value) {
        if !LinuxSystemCommands.Environment.Has(name)
            LinuxSystemCommands.Environment[name] := EnvGet(name)
        EnvSet(name, value)
    }

    static CleanUp() {
        if IsObject(LinuxSystemCommands.OriginalRunner)
            SystemProvider.NativeRunner := LinuxSystemCommands.OriginalRunner
        for name, value in LinuxSystemCommands.Environment
            try EnvSet(name, value)
        try {
            if (LinuxSystemCommands.Folder != "" && InStr(LinuxSystemCommands.Folder, "ALTRun-SystemCommands-"))
                DirDelete(Platform.FullPath("..", LinuxSystemCommands.Folder), true)
        }
    }

    static OnError(err, mode) {
        FileAppend("FAIL LINUX_SYSTEM_COMMANDS " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }

    static Fail(message) {
        FileAppend("FAIL LINUX_SYSTEM_COMMANDS " message "`n", "**")
        ExitApp(1)
    }
}

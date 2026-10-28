;===============================================================================
; TerminalProvider.ahk - runs commands in a terminal (AutoHotkey v2)
;-------------------------------------------------------------------------------
; 输入 ">ipconfig /all" (前缀见 Features.Terminal.Prefix) 在终端里运行这条命令,
; 窗口保持打开。Windows 使用配置的命令行程序，其它平台使用已安装的终端和 shell。
;
; Usage (from other modules):
;   TerminalProvider.OpenAt(folder)          opens a terminal in the folder
;   TerminalProvider.RunCommand(command)
;===============================================================================

class TerminalProvider {
    static Id := "Terminal"

    static Search(query) {
        options := AppSettings.Feature("Terminal")
        if !query.MatchPrefix(options["Prefix"], &command)
            return []
        icon := Platform.IsWindows ? "res:imageres.dll,-5323" : App.IconFile
        if (command = "")
            return [ResultItem(I18n.T("Terminal.Empty"), options["Prefix"] " ...", {Icon: icon, Valid: false, Score: 150, Exclusive: true})]
        actions := []
#if WINDOWS
        actions.Push(ResultItem(I18n.T("Action.RunAsAdmin"), "", {Icon: "res:imageres.dll,-78", OnRun: (*) => TerminalProvider.RunCommand(command, true)}))
#endif
        return [ResultItem(I18n.T("Terminal.Run", command), options["Shell"], {
            Icon: icon, Score: 150, Uid: "terminal:" (Platform.IsWindows ? StrLower(command) : command), Arg: command, Exclusive: true,
            OnRun: (*) => TerminalProvider.RunCommand(command),
            Actions: actions
        })]
    }

    static RunCommand(command, asAdmin := false) {
#if WINDOWS
        shell := AppSettings.Feature("Terminal")["Shell"]
        prefix := asAdmin ? "*RunAs " : ""
        switch shell, false {
            case "powershell": Run(prefix 'powershell.exe -NoExit -Command ' command, A_MyDocuments)
            case "pwsh"      : Run(prefix 'pwsh.exe -NoExit -Command ' command, A_MyDocuments)
            case "wt"        : Run(prefix 'wt.exe cmd /k ' command, A_MyDocuments)
            default          : Run(prefix A_ComSpec ' /k ' command, A_MyDocuments)
        }
#else
        if asAdmin
            throw Error("Administrator terminal actions are available only on Windows.")
        TerminalProvider._Launch(command, A_MyDocuments)
#endif
    }

    static OpenAt(folder) {
        if (folder = "" || !DirExist(folder))
            folder := A_MyDocuments
#if WINDOWS
        shell := AppSettings.Feature("Terminal")["Shell"]
        switch shell, false {
            case "powershell": Run("powershell.exe -NoExit", folder)
            case "pwsh"      : Run("pwsh.exe -NoExit", folder)
            case "wt"        : Run('wt.exe -d "' folder '"', folder)
            default          : Run(A_ComSpec, folder)
        }
#else
        TerminalProvider._Launch("", folder)
#endif
    }

    static _Shell() {
        configured := AppSettings.Feature("Terminal")["Shell"]
        if (configured = "powershell" || configured = "pwsh")
            executable := Platform.FindExecutable("pwsh")
        else if (configured = "" || configured = "auto" || configured = "cmd" || configured = "wt")
            executable := Platform.FindExecutable(EnvGet("SHELL"))
        else
            executable := Platform.FindExecutable(configured)
        if (executable = "" && configured != "powershell" && configured != "pwsh")
            executable := Platform.FindExecutable("sh")
        if (executable = "")
            throw Error("The configured shell is not installed: " configured)
        return executable
    }

    static _Launch(command, folder) {
        shell := TerminalProvider._Shell()
#if OSX
        options := AppSettings.Feature("Terminal")
        terminal := options.Has("Terminal") ? options["Terminal"] : "auto"
        launch := TerminalProvider.MacLaunch(command, folder, shell, terminal)
        try return ProcessRunner.StartApplication("/usr/bin/osascript", ["-e", launch.Script])
        catch as e {
            try FileDelete(launch.Path)
            throw e
        }
#else
        options := AppSettings.Feature("Terminal")
        configured := options.Has("Terminal") ? options["Terminal"] : EnvGet("TERMINAL")
        terminal := (configured != "" && configured != "auto") ? Platform.FindExecutable(configured) : ""
        if (terminal = "") {
            for candidate in ["x-terminal-emulator", "gnome-terminal", "konsole", "kgx", "xfce4-terminal", "mate-terminal", "tilix", "kitty", "alacritty", "wezterm", "foot", "qterminal", "lxterminal", "terminator", "xterm", "urxvt", "st"] {
                terminal := Platform.FindExecutable(candidate)
                if (terminal != "")
                    break
            }
        }
        if (terminal = "")
            throw Error("No supported terminal is installed. Set the TERMINAL environment variable to its executable.")
        args := []
        SplitPath(terminal, &name)
        switch name {
            case "gnome-terminal", "kgx": args := ["--working-directory=" folder, "--"]
            case "xfce4-terminal": args := ["--working-directory=" folder, "--disable-server", "-x"]
            case "mate-terminal": args := ["--working-directory=" folder, "-x"]
            case "tilix": args := ["--working-directory=" folder, "-e"]
            case "konsole": args := ["--workdir", folder, "-e"]
            case "kitty": args := ["--directory", folder]
            case "alacritty": args := ["--working-directory", folder, "-e"]
            case "wezterm": args := ["start", "--cwd", folder, "--"]
            case "foot": args := ["--working-directory=" folder, "--"]
            case "qterminal": args := ["--workdir", folder, "-e"]
            case "lxterminal": args := ["--working-directory=" folder, "-e"]
            default: args := ["-e"]
        }
        args.Push(shell)
        if InStr(shell, "pwsh") {
            if (command != "")
                args.Push("-NoExit", "-Command", command)
        } else if (command != "") {
            args.Push("-lc", command "; exec " ProcessRunner.QuoteShell(shell) " -i")
        } else {
            args.Push("-i")
        }
        return ProcessRunner.StartApplication(terminal, args, folder)
#endif
    }

    static _MacTerminal(terminal) {
        if (terminal = "" || terminal = "auto" || terminal = "Terminal" || terminal = "Terminal.app")
            return "com.apple.Terminal"
        if (terminal = "iTerm" || terminal = "iTerm2" || terminal = "iTerm.app")
            return "com.googlecode.iterm2"
        throw Error("Unsupported macOS terminal: " terminal ". Choose auto, Terminal or iTerm in Features.Terminal.Terminal.")
    }

    static MacShellScript(command, folder, shell) {
        quoted := ProcessRunner.QuoteShell(shell)
        script := "#!/bin/sh`n/bin/rm -f -- `"$0`"`ncd -- " ProcessRunner.QuoteShell(folder) " || exit`n"
        SplitPath(shell, &name)
        if RegExMatch(name, "i)^pwsh(?:\.exe)?$")
            return script "exec " quoted (command != "" ? " -NoExit -Command " ProcessRunner.QuoteShell(command) : "") "`n"
        if (command != "")
            return script "exec " quoted " -lc " ProcessRunner.QuoteShell(command "`nexec " quoted " -i") "`n"
        return script "exec " quoted " -i`n"
    }

    static MacLaunch(command, folder, shell, terminal := "auto") {
        TerminalProvider._MacTerminal(terminal)
        path := ALTRunMacTerminalFile(TerminalProvider.MacShellScript(command, folder, shell))
        line := "exec /bin/sh " ProcessRunner.QuoteShell(path)
        try return {Path: path, Line: line, Script: TerminalProvider.MacScript(line, terminal, path)}
        catch as e {
            try FileDelete(path)
            throw e
        }
    }

    static MacScript(line, terminal := "auto", wrapperPath := "") {
        if (InStr(line, "`r") || InStr(line, "`n"))
            throw Error("Terminal launch input must fit on one line.")
        target := TerminalProvider._MacTerminal(terminal)
        script := 'tell application id "' target '"' "`nactivate`n"
        if (target = "com.apple.Terminal")
            script .= "do script " ProcessRunner.QuoteAppleScript(line)
        else
            script .= "create window with default profile`ntell current session of current window to write text " ProcessRunner.QuoteAppleScript(line)
        script .= "`nend tell"
        if (wrapperPath = "")
            return script
        cleanup := "/bin/rm -f -- " ProcessRunner.QuoteShell(wrapperPath)
        return "try`n" script "`non error failureMessage number failureNumber`ntry`ndo shell script " ProcessRunner.QuoteAppleScript(cleanup)
            . "`nend try`nerror failureMessage number failureNumber`nend try"
    }

    ; The folder open in Explorer / Total Commander (the window active before ALTRun was shown)
    static OpenAtCurrentFolder() {
#if WINDOWS
        folder := QuickSwitch.FolderOfWindow(App.PreviousWindow)
        if (folder = "")
            return MsgBox(I18n.T("Sys.NoFolder"), App.Name, 48)
        TerminalProvider.OpenAt(folder)
#else
        return TerminalProvider.OpenAt(Platform.Home)
#endif
    }
}

#CSharp
public static string ALTRunMacTerminalFile(string text)
{
    string directory = System.IO.Path.GetTempPath();
    if (directory.IndexOfAny(['\r', '\n']) >= 0) directory = "/tmp";
    string path = System.IO.Path.Combine(directory, "ALTRun-terminal-" + System.Guid.NewGuid().ToString("N") + ".sh");
    try
    {
        var options = new System.IO.FileStreamOptions { Mode = System.IO.FileMode.CreateNew,
            Access = System.IO.FileAccess.Write, Share = System.IO.FileShare.None,
            UnixCreateMode = System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite };
        using var stream = new System.IO.FileStream(path, options);
        using var writer = new System.IO.StreamWriter(stream, new System.Text.UTF8Encoding(false));
        writer.Write(text);
        return path;
    }
    catch
    {
        if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
        throw;
    }
}
#EndCSharp

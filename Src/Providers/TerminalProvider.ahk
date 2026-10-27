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

    static Init() {
    }

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
        text := "cd -- " ProcessRunner.QuoteShell(folder)
        if (command != "") {
            shellArgs := InStr(shell, "pwsh") ? " -NoExit -Command " : " -lc "
            shellCommand := InStr(shell, "pwsh") ? command : command "; exec " ProcessRunner.QuoteShell(shell) " -i"
            text .= "; " ProcessRunner.QuoteShell(shell) shellArgs ProcessRunner.QuoteShell(shellCommand)
        } else
            text .= "; " ProcessRunner.QuoteShell(shell) (InStr(shell, "pwsh") ? "" : " -i")
        apple := 'tell application "Terminal"' "`nactivate`ndo script " ProcessRunner.QuoteAppleScript(text) "`nend tell"
        return ProcessRunner.Start("/usr/bin/osascript", ["-e", apple])
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

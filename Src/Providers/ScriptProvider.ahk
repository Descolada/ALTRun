;===============================================================================
; ScriptProvider.ahk - Scripts extension: scripts in the Scripts\ folder become commands (AutoHotkey v2)
;-------------------------------------------------------------------------------
; 和 Raycast 的 Script Commands、RunZ 的插件一样: 把脚本放进 Scripts\ (程序目录, 程序目录不能写入时
; 在用户数据目录的 ALTRun/Scripts), 就能按名称或关键字搜到并运行。支持 .ahk .ks .ps1 .py .sh, Windows 还支持 .bat .cmd。
; 脚本开头的注释里可以写 (注释符 ; # REM :: // 都行, 都可以不写):
;   @altrun.title     名称              (默认用文件名)
;   @altrun.keyword   关键字            输入完全相同时排在最前面
;   @altrun.argument  提示文字          需要参数: 输入 "关键字 文字", 文字作为第一个参数传给脚本
;   @altrun.mode      window | silent | output
;                     window (默认) 正常运行, 有窗口; silent 在后台运行, 结束后把输出的最后一行显示成通知;
;                     output 在后台运行, 结束后用 .txt 的默认程序 (一般是记事本) 打开全部输出
; 文件夹有变化时 (修改时间) 重新读取, 不用重新载入 ALTRun。F3 用默认编辑程序打开脚本。
;
; Settings (ALTRun.json -> Features.Scripts): Enabled / Keyword ("script backup" searches scripts only, "script " lists all,
; like the snippets' "snip"; just "script" without the space still shows the commands with that word)
;===============================================================================

class ScriptProvider {
    static Id := "Scripts"
    static Extensions := Map("ahk", 1, "ks", 1, "ps1", 1, "bat", 1, "cmd", 1, "py", 1, "sh", 1)
    static Scripts := []
    static _lastStamp := "", _checked := 0, _refreshTimer := ""
    static TimeoutMs := 120000                                              ; how long to wait for a background script at most

    static HintIcon := "res:imageres.dll,-5323"
    static Folder := ""                                                     ; 不为空时用这个文件夹 (测试用)
    static Dir => (ScriptProvider.Folder != "") ? ScriptProvider.Folder : Platform.Join(AppSettings.Portable ? A_ScriptDir : AppSettings.UserDir, "Scripts")

    static Init() {
        ScriptProvider.Load()
        if !IsObject(ScriptProvider._refreshTimer)
            ScriptProvider._refreshTimer := Logger.Watch("scripts refresh", () => ScriptProvider._RefreshIfChanged())
        SetTimer(ScriptProvider._refreshTimer, 2000)
    }

    static Search(query) {
        results := [], keyword := AppSettings.Feature("Scripts")["Keyword"], full := ""
        onlyScripts := (keyword != "" && query.HasRest && query.MatchKeyword([keyword], &term))
        needle := StrLower(onlyScripts ? term : query.Text)
        if (keyword != "" && !query.HasRest && query.MatchKeyword([keyword], &term))   ; "script" without the space: a hint, like the other keywords (ResultItem.KeywordHintScore); Enter completes "script "
            results.Push(ResultItem.KeywordHint(I18n.T("Scripts.Keyword"), keyword, ScriptProvider.HintIcon))
        else if (keyword != "" && query.StartsKeyword([keyword], &full))       ; "scrip": the same hint at the end of the list
            results.Push(ResultItem.KeywordHint(I18n.T("Scripts.Keyword"), full, ScriptProvider.HintIcon, true))
        for script in ScriptProvider.Scripts {
            if onlyScripts {                                                ; "script " / "script name": scripts only, all of them for no name
                score := (needle = "") ? 50 : FuzzyMatcher.BestKey(needle, script.Keys)
                if (score > 0) {
                    item := ScriptProvider.ItemFor(script, score + 40)
                    item.Exclusive := true
                    results.Push(item)
                }
                continue
            }
            if (script.Keyword != "" && query.Keyword = script.Keyword && script.Argument != "" && query.HasRest) {
                item := ScriptProvider.ItemFor(script, 150, query.Rest)
                item.Exclusive := true
                return [item]
            }
            score := FuzzyMatcher.BestKey(needle, script.Keys)
            if (script.Keyword != "" && query.Keyword = script.Keyword)
                score := Max(score, 100)
            if (score > 0)
                results.Push(ScriptProvider.ItemFor(script, score + 10))
        }
        return results
    }

    static ItemFor(script, score, argument := "") {
        props := {Kind: "file", Arg: script.Path, Icon: ScriptProvider._Icon(script), Score: score, Source: script
            , Uid: "script:" (Platform.IsWindows ? StrLower(script.Path) : script.Path), OnRun: (*) => ScriptProvider.Run(script, argument)}
        title := script.Title, subtitle := I18n.T("Script.Subtitle", script.Name)
        if (script.Argument != "") {
            if (argument = "") {
                props.Valid := (script.Keyword = "")                        ; with a keyword: Enter completes "keyword " so the argument can be typed next
                props.AutoComplete := (script.Keyword != "") ? script.Keyword " " : ""
                subtitle := ((script.Keyword != "") ? I18n.T("Search.TypeArgAfter", script.Keyword, script.Argument) : script.Argument) " · " subtitle
            } else
                title .= ": " argument
        }
        return ResultItem(title, subtitle, props)
    }

    static _Icon(script) {
#if WINDOWS
        switch script.Ext {
            case "ahk", "ks": return A_IsCompiled ? A_ScriptFullPath : A_AhkPath
            case "ps1": return A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
            default:    return A_ComSpec
        }
#else
        return script.Path
#endif
    }

    ; The command line that runs the script
    static CommandLine(script, argument := "") {
#if WINDOWS
        quoted := '"' script.Path '"' ((argument != "") ? ' "' StrReplace(argument, '"', '\"') '"' : "")
        switch script.Ext {
            case "ahk", "ks": return ScriptProvider._CommandText(ScriptProvider._Spec(script, argument))
            case "ps1": return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' quoted
            case "py":  return 'py ' quoted
            case "sh": return ScriptProvider._CommandText(ScriptProvider._Spec(script, argument))
            default:   return A_ComSpec ' /c "' quoted '"'
        }
#else
        return ScriptProvider._CommandText(ScriptProvider._Spec(script, argument))
#endif
    }

    static _CommandText(spec) {
        quote := Platform.IsWindows ? (value) => '"' StrReplace(value, '"', '\"') '"' : (value) => ProcessRunner.QuoteShell(value)
        command := quote(spec.Executable)
        for argument in spec.Arguments
            command .= " " quote(argument)
        return command
    }

    static _Spec(script, argument := "") {
        arguments := argument != "" ? [argument] : []
        if script.Ext = "ahk" || script.Ext = "ks"
            return ProcessRunner.ScriptHost(script.Path, arguments)
        if !Platform.IsWindows && (script.Ext = "sh" || script.Ext = "py") {
            if IsObject(spec := ProcessRunner.ScriptInterpreter(script.Path)) {
                if Platform.FindExecutable(spec.Executable) = ""
                    throw Error("The script's interpreter is not installed: " spec.Executable)
                spec.Arguments.Push(script.Path)
                for value in arguments
                    spec.Arguments.Push(value)
                return spec
            }
        }
        switch script.Ext {
            case "ps1":
                executable := Platform.FindExecutable(Platform.IsWindows ? "powershell.exe" : "pwsh")
                prefix := Platform.IsWindows ? ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"] : ["-NoProfile", "-File"]
            case "py":
                executable := Platform.FindExecutable(Platform.IsWindows ? "py" : "python3")
                if executable = ""
                    executable := Platform.FindExecutable("python")
                prefix := []
            case "sh":
                executable := Platform.FindExecutable("bash")
                if executable = ""
                    executable := Platform.FindExecutable("sh")
                prefix := []
            default:
                throw Error("This script type is unavailable on this platform: " script.Ext)
        }
        if executable = ""
            throw Error("No interpreter was found for ." script.Ext " scripts.")
        prefix.Push(script.Path)
        for value in arguments
            prefix.Push(value)
        return {Executable: executable, Arguments: prefix}
    }

    static Run(script, argument := "") {
        SplitPath(script.Path, , &dir)
#if WINDOWS
        if script.Ext = "bat" || script.Ext = "cmd" {
            command := ScriptProvider.CommandLine(script, argument)
            if script.Mode = "window"
                return Run(command, dir)
            job := ProcessRunner.StartCommand(command, dir, true)
        } else {
#endif
            spec := ScriptProvider._Spec(script, argument)
            if script.Mode = "window" {
#if WINDOWS
                return ProcessRunner.Start(spec.Executable, spec.Arguments, dir)
#else
                if script.Ext != "ahk" && script.Ext != "ks"
                    return TerminalProvider._Launch(ScriptProvider._CommandText(spec), dir)
                return ProcessRunner.Start(spec.Executable, spec.Arguments, dir)
#endif
            }
            job := ProcessRunner.Start(spec.Executable, spec.Arguments, dir, true)
#if WINDOWS
        }
#endif
        output := Platform.Join(A_Temp, "ALTRun-script-" Platform.NewUuid() ".txt")
        started := A_TickCount
        check() {
            finished := ProcessRunner.IsFinished(job)
            if (!finished && A_TickCount - started < ScriptProvider.TimeoutMs)
                return
            SetTimer(check, 0)
            try {
                text := ProcessRunner.Finish(job, !finished)
                if !finished
                    text .= "`nScript timed out after " ScriptProvider.TimeoutMs " ms."
                FileAppend(text, output, "UTF-8")
            } catch as e {
                Logger.Error("ScriptProvider: " script.Path " - " e.Message)
                App.Notify(e.Message, 4000)
                return
            }
            ScriptProvider._Finished(script, output)
        }
        SetTimer(check, 300)
    }

    static _Finished(script, output) {
        text := ""
        try text := FileRead(output)
        if (script.Mode = "output") {
            Path.OpenText(output)                                           ; the default program for .txt (usually Notepad); the temporary file stays in %Temp%
            return
        }
        try FileDelete(output)
        last := ""
        Loop Parse, text, "`n", "`r"
            if (Trim(A_LoopField) != "")
                last := Trim(A_LoopField)
        message := (last != "") ? last : I18n.T("Script.Done", script.Title)
        App.Notify(message, 3000)
        return message
    }

    ; F3: 用平台的编辑程序打开脚本
    static EditItem(item) {
        Platform.Edit(item.Source.Path)
        return false
    }

    static Load() {
        scripts := []
        if DirExist(ScriptProvider.Dir) {
            Loop Files, Platform.Join(ScriptProvider.Dir, "*.*"), "F" {
                ext := StrLower(A_LoopFileExt)
                if !ScriptProvider.Extensions.Has(ext)
                    continue
                if !Platform.IsWindows && (ext = "bat" || ext = "cmd")
                    continue
                if IsObject(script := ScriptProvider.ReadScript(A_LoopFileFullPath))
                    scripts.Push(script)
            }
        }
        ScriptProvider.Scripts := scripts
        ScriptProvider._lastStamp := ScriptProvider._Stamp()
        ScriptProvider._checked := A_TickCount
    }

    ; Script file -> {Path, Name, Ext, Title, Keyword, Argument, Mode, Keys}; reads @altrun.xxx in the first 30 lines
    static ReadScript(path) {
        SplitPath(path, &name, , &ext, &baseName)
        meta := Map("title", baseName, "keyword", "", "argument", "", "mode", "window")
        try {
            Loop Read, path {
                if (A_Index > 30)
                    break
                if RegExMatch(A_LoopReadLine, "i)^\s*(?:;|#|//|::|rem\b)\s*@altrun\.(\w+)\s+(.*?)\s*$", &m)
                    meta[StrLower(m[1])] := m[2]
            }
        } catch
            return ""
        mode := StrLower(meta["mode"])
        if !(mode = "silent" || mode = "output")
            mode := "window"
        title := meta["title"], keyword := StrLower(Trim(meta["keyword"]))
        pinyinText := Pinyin.Initials(title)
        return {Path: path, Name: name, Ext: StrLower(ext), Title: title, Keyword: keyword, Argument: Trim(meta["argument"]), Mode: mode
              , Keys: [FuzzyMatcher.Key(title), (keyword != "") ? FuzzyMatcher.Key(keyword) : "", (pinyinText != title) ? FuzzyMatcher.Key(pinyinText) : ""]}
    }

    ; the modified times of the folder and each file in it joined: read again when it changes
    static _Stamp() {
        stamp := ""
        if DirExist(ScriptProvider.Dir)
            Loop Files, Platform.Join(ScriptProvider.Dir, "*.*"), "F"
                stamp .= A_LoopFileName A_LoopFileTimeModified "|"
        return stamp
    }

    static _RefreshIfChanged() {
        if (!BackgroundWork.CanRun() || A_TickCount - ScriptProvider._checked < 2000 || !ProviderRegistry.IsEnabled(ScriptProvider))
            return
        ScriptProvider._checked := A_TickCount
        if (ScriptProvider._Stamp() != ScriptProvider._lastStamp)
            ScriptProvider.Load()
    }

    ; Example scripts, each showing one form: background with a notification (ahk, silent), a keyword with an argument (bat, window; the keyword mustn't clash with the default commands),
    ; all output in Notepad (ps1, output). ASCII only: Windows PowerShell 5 reads files without BOM as ANSI
    static ExampleScripts() {
        if !Platform.IsWindows
            return Map("Today.ks", "#ErrorStdOut`n#Warn All, StdOut`n; @altrun.title Example: Today's Date`n; @altrun.mode silent`n"
                . 'FileAppend(FormatTime(, "dddd, d MMMM yyyy"), "*")' "`n"
                , "Echo.sh", "#!/bin/sh`n# @altrun.title Example: Echo`n# @altrun.keyword echo`n# @altrun.argument some text`n# @altrun.mode silent`n"
                . 'printf "%s\n" "$1"' "`n")
        return Map(
            "Today.ahk",
                "; @altrun.title  Example: Today's Date`r`n"
              . "; @altrun.mode   silent`r`n"
              . "; Runs in the background; the last line it prints is shown as a notification.`r`n"
              . "; Change the mode to output to read everything it prints in your text editor, or remove it to run normally.`r`n"
              . 'FileAppend(FormatTime(, "dddd, d MMMM yyyy") ", week " SubStr(FormatTime(, "YWeek"), 5), "*")' "`r`n",
            "Port.bat",
                "@echo off`r`n"
              . "rem @altrun.title     Example: Who Uses a Port`r`n"
              . "rem @altrun.keyword   port`r`n"
              . "rem @altrun.argument  a port number`r`n"
              . 'rem Type "port 8080" in ALTRun: the text after the keyword is passed to the script as %1.' "`r`n"
              . "rem No mode line: it runs normally in its own window.`r`n"
              . 'netstat -ano | findstr /c:":%~1 "' "`r`n"
              . "pause`r`n",
            "IP Addresses.ps1",
                "# @altrun.title  Example: IP Addresses`r`n"
              . "# @altrun.mode   output`r`n"
              . "# Runs in the background, then opens everything it prints in your text editor.`r`n"
              . "Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -ne '127.0.0.1' | Format-Table InterfaceAlias, IPAddress -AutoSize`r`n")
    }

    ; Opens the Scripts folder; creates a few example scripts first if it doesn't exist yet (ExampleScripts)
    static OpenFolder() {
        dir := ScriptProvider.Dir
        if !DirExist(dir) {
            DirCreate(dir)
            for name, text in ScriptProvider.ExampleScripts()
                FileAppend(text, Platform.Join(dir, name), "UTF-8-RAW")
        }
        ActionCatalog.OpenFolder(dir)                                       ; the file manager in the settings (e.g. Total Commander)
    }
}

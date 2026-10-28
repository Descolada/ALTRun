#CSharp
public static object ALTRunShortcutInput(string Filename, string Text)
{
    using var stream = new System.IO.FileStream(Filename, new System.IO.FileStreamOptions { Mode = System.IO.FileMode.CreateNew, Access = System.IO.FileAccess.Write,
        Share = System.IO.FileShare.None, UnixCreateMode = System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite });
    using var writer = new System.IO.StreamWriter(stream, new System.Text.UTF8Encoding(false));
    writer.Write(Text);
    return null;
}
#EndCSharp
; Apple Shortcuts are indexed asynchronously; execution is explicit and may open the shortcut's own UI.
class ShortcutsProvider {
    static Id := "Shortcuts", Items := [], _job := 0, _timer := "", _checked := 0
    static Executable := "/usr/bin/shortcuts", Runner := (exe, args, capture := false) => ProcessRunner.Start(exe, args, "", capture)
    static _runs := Map(), _runTimer := () => ShortcutsProvider._FinishRuns()
    static Icon := "/System/Applications/Shortcuts.app"

    static Init() {
        if !Platform.IsMac || !FileExist(ShortcutsProvider.Executable)
            return
        if !IsObject(ShortcutsProvider._timer)
            ShortcutsProvider._timer := () => ShortcutsProvider._Tick()
        SetTimer(ShortcutsProvider._timer, 500)
    }

    static _Tick() {
        if ShortcutsProvider._job {
            if !ProcessRunner.IsFinished(ShortcutsProvider._job) {
                if A_TickCount - ShortcutsProvider._checked > 10000 {
                    ProcessRunner.Finish(ShortcutsProvider._job, true)
                    ShortcutsProvider._job := 0
                }
                return
            }
            if SearchWindow.IsVisible() && A_TickCount - SearchWindow.LastInputAt < 150
                return
            result := ProcessRunner.Result(ShortcutsProvider._job)
            ShortcutsProvider._job := 0
            if result.Has("ExitCode") && result["ExitCode"] = 0
                ShortcutsProvider.Items := ShortcutsProvider.Parse(result["Output"])
            else
                Logger.Debug("Shortcuts: listing is unavailable.")
            if SearchWindow.IsVisible()
                SearchWindow.RefreshResults()
            return
        }
        if !ProviderRegistry.IsEnabled(ShortcutsProvider) || !BackgroundWork.CanRun() || (ShortcutsProvider._checked && A_TickCount - ShortcutsProvider._checked < 60000)
            return
        ShortcutsProvider._checked := A_TickCount
        try ShortcutsProvider._job := ShortcutsProvider.Runner.Call(ShortcutsProvider.Executable, ["list", "--show-identifiers"], true)
        catch as error
            Logger.Debug("Shortcuts: " error.Message)
    }

    static Parse(text) {
        items := [], seen := Map()
        for line in StrSplit(text, "`n", "`r") {
            if !RegExMatch(line, "^(.*?)\s+\(([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})\)\s*$", &match)
                continue
            name := Trim(match[1]), id := StrLower(match[2])
            if (name = "" || seen.Has(id))
                continue
            seen[id] := true
            items.Push({Name: name, Id: id, Keys: [FuzzyMatcher.Key(name), FuzzyMatcher.Key(Pinyin.Initials(name))]})
        }
        return items
    }

    static Search(query) {
        if !Platform.IsMac
            return []
        keyword := AppSettings.Feature("Shortcuts")["Keyword"], term := "", full := ""
        exclusive := keyword != "" && query.HasRest && query.MatchKeyword([keyword], &term)
        if !query.HasRest && query.MatchKeyword([keyword], &term)
            return [ResultItem.KeywordHint("Run an Apple Shortcut", keyword, ShortcutsProvider.Icon)]
        if !exclusive && query.StartsKeyword([keyword], &full)
            return [ResultItem.KeywordHint("Run an Apple Shortcut", full, ShortcutsProvider.Icon, true)]
        needle := StrLower(exclusive ? term : query.Text), results := [], scores := Map()
        for index, shortcut in ShortcutsProvider.Items {
            score := needle = "" ? 70 : FuzzyMatcher.BestKey(needle, shortcut.Keys)
            if score > 0
                scores[index] := score
        }
        for index in FuzzyMatcher.TopIndexes(scores, exclusive ? ProviderRegistry.MaxResults : 5) {
            shortcut := ShortcutsProvider.Items[index]
            actions := [ResultItem("Edit Shortcut", "Open in Shortcuts", {OnRun: ShortcutsProvider._Editor(shortcut.Id)})
                , ResultItem("Run with Clipboard Text", "Pass the clipboard as shortcut input", {OnRun: ShortcutsProvider._Runner(shortcut.Id, true)})]
            results.Push(ResultItem(shortcut.Name, "Apple Shortcuts", {Uid: "shortcut:" shortcut.Id, Icon: ShortcutsProvider.Icon, Score: scores[index] + (exclusive ? 40 : -12)
                , Exclusive: exclusive, OnRun: ShortcutsProvider._Runner(shortcut.Id), RunTitle: "Run Shortcut", Actions: actions}))
        }
        if exclusive && !results.Length
            results.Push(ResultItem("No matching shortcuts", "Create a shortcut in the Shortcuts app; ALTRun refreshes while idle.", {Valid: false, Exclusive: true, Score: 100}))
        return results
    }

    static _Editor(id) => (*) => ShortcutsProvider.Runner.Call(ShortcutsProvider.Executable, ["view", id])
    static _Runner(id, clipboard := false, text := "", paths := "") => (*) => ShortcutsProvider.Run(id, clipboard ? A_Clipboard : text, paths)

    static ChooseFor(item) {
        actions := [], text := "", paths := []
        if item.Kind = "file" || item.Kind = "folder"
            paths.Push(Path.Resolve(item.Arg))
        else
            text := item.CopyText()
        for shortcut in ShortcutsProvider.Items
            actions.Push(ResultItem(shortcut.Name, "Run with selected content", {OnRun: ShortcutsProvider._Runner(shortcut.Id, false, text, paths)}))
        if !actions.Length
            return App.Notify("No shortcuts are available. Open Shortcuts to create one.")
        return SearchWindow.ShowActions(ResultItem("Run Shortcut", item.Title, {Kind: "actions", Actions: actions}))
    }

    static Run(id, text := "", paths := "") {
        if !RegExMatch(id, "i)^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")
            throw Error("Invalid shortcut identifier.")
        args := ["run", id], temporary := ""
        if IsObject(paths) && paths.Length {
            args.Push("--input-path")
            for path in paths
                args.Push(path)
        } else if text != "" {
            temporary := Platform.Join(A_Temp, "ALTRun-shortcut-" Platform.NewUuid() ".txt")
            ALTRunShortcutInput(temporary, text)
            args.Push("--input-path", temporary)
        }
        try job := ShortcutsProvider.Runner.Call(ShortcutsProvider.Executable, args, true)
        catch {
            if temporary != ""
                FileDelete(temporary)
            throw
        }
        ShortcutsProvider._runs[job] := {File: temporary, Started: A_TickCount}
        SetTimer(ShortcutsProvider._runTimer, 100)
        return job
    }

    static _FinishRuns() {
        for job, run in ShortcutsProvider._runs.Clone() {
            if !ProcessRunner.IsFinished(job) && A_TickCount - run.Started < 300000
                continue
            try {
                result := ProcessRunner.Result(job, !ProcessRunner.IsFinished(job))
                if result.Has("ExitCode") && result["ExitCode"] = 0 {
                    if result["Output"] != ""
                        ActionCatalog.CopyText(RTrim(result["Output"], "`r`n"))
                    else
                        App.Notify("Shortcut completed.")
                } else
                    App.Notify("Shortcut failed. " (result.Has("Error") ? SubStr(result["Error"], 1, 400) : ""), 4000)
            } finally {
                ShortcutsProvider._runs.Delete(job)
                if run.File != ""
                    try FileDelete(run.File)
            }
        }
        if !ShortcutsProvider._runs.Count
            SetTimer(ShortcutsProvider._runTimer, 0)
    }

    static Stop() {
        if IsObject(ShortcutsProvider._timer)
            SetTimer(ShortcutsProvider._timer, 0)
        SetTimer(ShortcutsProvider._runTimer, 0)
        if ShortcutsProvider._job
            try ProcessRunner.Finish(ShortcutsProvider._job, true)
        ShortcutsProvider._job := 0
        for job, run in ShortcutsProvider._runs {
            try ProcessRunner.Finish(job, true)
            if run.File != ""
                try FileDelete(run.File)
        }
        ShortcutsProvider._runs := Map()
    }
}

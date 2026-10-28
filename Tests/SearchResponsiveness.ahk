; Search scheduling contracts using an owned hidden GUI and synthetic results.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => SearchResponsiveness.Fail(err.Message "`n" err.Stack))
OnExit((*) => SearchResponsiveness.CleanUp())
SetTimer(() => SearchResponsiveness.Fail("Timed out after 20 seconds."), -20000)
SearchResponsiveness.Run()

class SearchResponsiveness {
    static Calls := 0, Painted := [], Folder := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            SearchResponsiveness.Assert(A_TickCount - started < 2500, message)
            Sleep(10)
        }
    }

    static Search(query) {
        SearchResponsiveness.Calls += 1
        if (query.Text == "stale")
            SearchWindow.Input.Value := "fresh"
        if (query.Text == "transient")
            SearchWindow.Input.Value := "alpha"
        return [ResultItem(query.Text " synthetic result", "Synthetic details")]
    }

    static Run() {
        SetWinDelay(-1)
        Logger.Enabled := false
        root := Platform.FullPath("..", A_ScriptDir)
        SearchResponsiveness.Folder := Platform.Join(A_Temp, "ALTRun-SearchResponsiveness-" Platform.NewUuid())
        DirCreate(SearchResponsiveness.Folder)
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.General["HideOnDeactivate"] := 0
        AppSettings.General["ShowTips"] := 0
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(root, "Resources", "Themes")
        ThemeManager.UserDir := SearchResponsiveness.Folder
        App.IconFile := Platform.Join(root, "Resources", "ALTRun.ico")
        I18n.Init("en")
        ThemeManager.Load("Dark", "Compact")
        ApplicationProvider.DefineProp("Search", {Call: (self, query) => SearchResponsiveness.Search(query)})
        ProviderRegistry.Providers := [ApplicationProvider]
        SearchWindow.Create()
        originalResults := SearchWindow.GetOwnPropDesc("SetResults").Call
        SearchWindow.DefineProp("SetResults", {Call: (self, items) => SearchResponsiveness.Observe(originalResults, self, items)})

        before := SearchResponsiveness.Calls
        SearchWindow._SetInput("alpha")
        Sleep(100)
        SearchResponsiveness.Assert(SearchResponsiveness.Calls - before = 1, "Programmatic input ran duplicate provider searches.")

        before := SearchResponsiveness.Calls
        previousCritical := A_IsCritical
        Critical("On")
        try {
            for value in ["al", "alp", "alph", "alphabet"]
                SearchWindow.Input.Value := value
        } finally Critical(previousCritical)
        SearchResponsiveness.WaitFor(() => SearchWindow.Results[1].Title == "alphabet synthetic result", "The latest edit in a burst was not searched.")
        Sleep(100)
        SearchResponsiveness.Assert(SearchResponsiveness.Calls - before = 1, "A burst of edits repeated the same final search.")

        before := SearchResponsiveness.Calls
        SearchWindow._RunSearch()
        SearchResponsiveness.Assert(SearchResponsiveness.Calls - before = 1, "An explicit provider refresh was incorrectly skipped.")
        FileAppend("PASS SEARCH_RESPONSIVENESS single programmatic search, coalesced edits and explicit refresh`n", "*")

        SearchWindow.AllActions := [ResultItem("alphabet action")]
        SearchWindow.Mode := "actions"
        SearchWindow._SetInput("alphabet")
        SearchResponsiveness.Assert(SearchWindow.Results[1].Title == "alphabet action", "An unchanged query ignored a new search mode.")
        SearchWindow.Mode := "results"
        SearchWindow._SetInput("stale")
        SearchResponsiveness.WaitFor(() => SearchWindow.Results[1].Title == "fresh synthetic result", "A newer query was lost during a provider search.")
        for title in SearchResponsiveness.Painted
            SearchResponsiveness.Assert(title != "stale synthetic result", "A superseded query was painted.")
        SearchWindow._SetInput("alpha")
        SearchWindow._SetInput("transient")
        Sleep(100)
        SearchResponsiveness.Assert(SearchWindow.Results[1].Title == "alpha synthetic result" && SearchWindow.HighlightText == "alpha"
            , "A rejected query changed the accepted result's highlight text.")
        FileAppend("PASS SEARCH_RESPONSIVENESS mode changes and rejection of superseded results`n", "*")

        IconCache.Clear()
        canQueue := IconCache.CanQueueVisible
        IconCache.CanQueueVisible := () => true
        IconCache.Peek(App.IconFile)
        SearchResponsiveness.Assert(IconCache._visible.Length = 1, "The cancellation fixture did not queue a cold icon.")
        IconCache.CanQueueVisible := canQueue
        AppSettings.General["KeepLastQuery"] := 1
        SearchWindow.Hide()
        SearchResponsiveness.Assert(!IconCache._visible.Length, "Hiding a retained query left its icon timer queued.")
        IconCache.Peek(App.IconFile)
        SearchResponsiveness.Assert(!IconCache._visible.Length, "Hidden preparation recreated the icon queue.")
        FileAppend("PASS SEARCH_RESPONSIVENESS hiding cancels pending visible icons`n", "*")
        ExitApp(0)
    }

    static Observe(original, self, items) {
        if items.Length
            SearchResponsiveness.Painted.Push(items[1].Title)
        return original(self, items)
    }

    static CleanUp() {
        if IsObject(SearchWindow.Gui)
            try SearchWindow.Gui.Destroy()
        try IconCache.Clear()
        if (SearchResponsiveness.Folder != "" && DirExist(SearchResponsiveness.Folder))
            try DirDelete(SearchResponsiveness.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL SEARCH_RESPONSIVENESS " message "`n", "**")
        ExitApp(1)
        return true
    }
}

; Search keeps desktop discovery and folder refreshes outside the typing path. No windows or real files are changed.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => SearchDesktopCache.Fail(err))
OnExit((*) => SearchDesktopCache.CleanUp())
SetTimer(() => SearchDesktopCache.Fail(Error("Desktop search cache check timed out.")), -15000)
SearchDesktopCache.Run()

class SearchDesktopCache {
    static Saved := Map(), Reads := 0, FailRead := false, FileReads := 0, StampReads := 0

    static Assert(value, message) {
        if !value
            throw Error(message)
    }

    static Run() {
        Logger.Enabled := false
        AppSettings.Data := AppSettings.Defaults()
        root := Platform.FullPath("..", A_ScriptDir)
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        Pinyin.DataFile := Platform.Join(root, "Resources", "Pinyin.txt")
        I18n.Init("en")

        ; Report the real cold enumeration cost and expired default-search cost before using deterministic doubles.
        WindowProvider._listTime := -10000
        started := Platform.Milliseconds()
        WindowProvider.List()
        nativeMs := Platform.Milliseconds() - started
        WindowProvider._listTime := -10000
        started := Platform.Milliseconds()
        Loop 20
            WindowProvider.Search(SearchQuery("fixture search"))
        cachedMs := (Platform.Milliseconds() - started) / 20
        FileAppend("PERF DESKTOP_SEARCH native snapshot=" Round(nativeMs, 2) "ms expired default search=" Round(cachedMs, 2) "ms`n", "*")

        SearchDesktopCache.Saved["Windows"] := WindowProvider.GetOwnPropDesc("_Enumerate")
        WindowProvider.DefineProp("_Enumerate", {Call: (*) => SearchDesktopCache.ReadWindows()})
        WindowProvider._list := [SearchDesktopCache.Window("Cached Workbench")]
        WindowProvider._listTime := -10000
        results := WindowProvider.Search(SearchQuery("workbench"))
        SearchDesktopCache.Assert(results.Length = 1 && SearchDesktopCache.Reads = 0, "Default typing enumerated windows or lost cached window results.")
        results := WindowProvider.Search(SearchQuery("w workbench"))
        SearchDesktopCache.Assert(results.Length = 1 && results[1].Exclusive && SearchDesktopCache.Reads = 1, "Explicit window search did not refresh an expired snapshot.")
        WindowProvider._listTime := -10000
        Loop 20
            WindowProvider.Search(SearchQuery("workbench"))
        SearchDesktopCache.Assert(SearchDesktopCache.Reads = 1, "Expired default searches refreshed windows while typing.")
        first := SearchDesktopCache.Window("First Workbench"), second := SearchDesktopCache.Window("Second Workbench")
        second.Hwnd := 124
        firstItem := WindowProvider.ItemFor(first, 100), secondItem := WindowProvider.ItemFor(second, 100)
        distinct := ProviderRegistry._Dedupe([firstItem, secondItem, firstItem])
        SearchDesktopCache.Assert(distinct.Length = 2 && firstItem.Uid == secondItem.Uid && firstItem.Identity() != secondItem.Identity()
            , "Windows from one application must remain distinct while sharing learned app ranking.")

        BackgroundWork.IsBusy := () => true
        WindowProvider._RefreshIfIdle()
        SearchDesktopCache.Assert(SearchDesktopCache.Reads = 1, "Window refresh ignored the busy guard.")
        BackgroundWork.IsBusy := () => false
        WindowProvider._RefreshIfIdle()
        SearchDesktopCache.Assert(SearchDesktopCache.Reads = 2, "Idle window refresh did not run.")
        SearchDesktopCache.FailRead := true
        WindowProvider._listTime := -10000
        retained := WindowProvider.List()
        WindowProvider.List()
        SearchDesktopCache.Assert(SearchDesktopCache.Reads = 3 && retained.Length = 1, "Failed window refresh was retried immediately or discarded the prior snapshot.")
        FileAppend("PASS DESKTOP_SEARCH cached default windows, explicit refresh, idle guard and failure caching`n", "*")

        SearchDesktopCache.Saved["Bookmarks"] := BookmarkProvider.GetOwnPropDesc("Files")
        BookmarkProvider.DefineProp("Files", {Call: (*) => (SearchDesktopCache.FileReads += 1, [])})
        BookmarkProvider._checked := -30000, BookmarkProvider._stamp := ""
        BackgroundWork.IsBusy := () => true
        BookmarkProvider._RefreshIfChanged()
        SearchDesktopCache.Assert(SearchDesktopCache.FileReads = 0 && BookmarkProvider._checked = -30000, "Bookmark refresh inspected files while typing.")
        BackgroundWork.IsBusy := () => false
        BookmarkProvider._RefreshIfChanged()
        SearchDesktopCache.Assert(SearchDesktopCache.FileReads = 1, "Idle bookmark refresh did not inspect its files.")

        SearchDesktopCache.Saved["Scripts"] := ScriptProvider.GetOwnPropDesc("_Stamp")
        ScriptProvider.DefineProp("_Stamp", {Call: (*) => (SearchDesktopCache.StampReads += 1, "fixture")})
        ScriptProvider.Scripts := [{Path: "fixture.ahk", Name: "Fixture.ahk", Title: "Fixture", Ext: "ahk"
            , Keyword: "", Argument: "", Mode: "silent", Keys: [FuzzyMatcher.Key("fixture")]}]
        ScriptProvider._checked := -30000, ScriptProvider._lastStamp := "fixture"
        results := ScriptProvider.Search(SearchQuery("fixture"))
        SearchDesktopCache.Assert(results.Length = 1 && SearchDesktopCache.StampReads = 0, "Script search inspected the folder during typing.")
        BackgroundWork.IsBusy := () => true
        ScriptProvider._RefreshIfChanged()
        SearchDesktopCache.Assert(SearchDesktopCache.StampReads = 0, "Script refresh ignored the busy guard.")
        BackgroundWork.IsBusy := () => false
        ScriptProvider._RefreshIfChanged()
        SearchDesktopCache.Assert(SearchDesktopCache.StampReads = 1, "Idle script refresh did not inspect the folder.")
        FileAppend("PASS DESKTOP_SEARCH bookmark and script refreshes wait while typing`n", "*")

        FileIndex.Names := ["fixture.txt", "second.txt"]
        BackgroundWork.IsBusy := () => true
        FileIndex.BuildInitials()
        FileIndex._InitialsSome()
        SearchDesktopCache.Assert(IsObject(FileIndex._initialsJob) && FileIndex._initialsJob.Pos = 0, "File initials were built while typing.")
        BackgroundWork.IsBusy := () => false
        FileIndex._InitialsSome()
        SearchDesktopCache.Assert(!IsObject(FileIndex._initialsJob) && FileIndex._initialsFor == FileIndex.Names, "Deferred file initials did not resume and complete while idle.")
        FileAppend("PASS DESKTOP_SEARCH file initials pause and resume around typing`n", "*")
        ExitApp(0)
    }

    static Window(title) => {Hwnd: 123, Title: title, Process: "Fixture", Path: "", Keys: [FuzzyMatcher.Key(title)]}
    static ReadWindows() {
        SearchDesktopCache.Reads += 1
        if SearchDesktopCache.FailRead
            throw Error("Fixture desktop unavailable")
        return [SearchDesktopCache.Window("Fresh Workbench")]
    }

    static CleanUp() {
        if SearchDesktopCache.Saved.Has("Windows")
            WindowProvider.DefineProp("_Enumerate", SearchDesktopCache.Saved["Windows"])
        if SearchDesktopCache.Saved.Has("Bookmarks")
            BookmarkProvider.DefineProp("Files", SearchDesktopCache.Saved["Bookmarks"])
        if SearchDesktopCache.Saved.Has("Scripts")
            ScriptProvider.DefineProp("_Stamp", SearchDesktopCache.Saved["Scripts"])
    }

    static Fail(err) {
        FileAppend("FAIL DESKTOP_SEARCH " err.Message " (" err.File ":" err.Line ")`n", "**")
        ExitApp(1)
    }
}

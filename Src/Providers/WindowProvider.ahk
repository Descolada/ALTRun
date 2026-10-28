;===============================================================================
; WindowProvider.ahk - switches to windows that are already open (AutoHotkey v2)
;-------------------------------------------------------------------------------
; Like PowerToys Run's Window Walker and Raycast's Switch Windows: type a window title or program name,
; Enter switches to it (restoring it first if minimized).
;   "w word" (Keyword)     searches windows only; only "w " lists all windows (in z-order)
;   typing directly        with InDefaultResults = 1, windows whose title matches well show too (after applications and commands, at most 3)
; Actions panel (→): close the window.
; Only windows visible on the taskbar are listed: visible, with a title, not tool windows / windows owned by another window,
; not on another virtual desktop (DWM cloaked), and none of ALTRun's own windows.
; Default searches use the last window snapshot; a timer refreshes it while the launcher is closed.
; The explicit window keyword can refresh a snapshot older than 1 s.
;
; Settings (ALTRun.json -> Features.Windows): Enabled / Keyword / InDefaultResults
;===============================================================================

class WindowProvider {
    static Id := "Windows"
    static CacheMs := 1000, RefreshMs := 5000
    static _list := [], _listTime := 0, _refreshTimer := ""

    static Init() {
        WindowProvider.List()
        if !IsObject(WindowProvider._refreshTimer)
            WindowProvider._refreshTimer := Logger.Watch("window list refresh", () => WindowProvider._RefreshIfIdle())
        SetTimer(WindowProvider._refreshTimer, WindowProvider.RefreshMs)
    }

    static _RefreshIfIdle() {
        if (BackgroundWork.CanRun() && ProviderRegistry.IsEnabled(WindowProvider))
            WindowProvider.List()
    }

    static Search(query) {
        options := AppSettings.Feature("Windows")
        exclusive := false, term := query.Text
        if query.MatchKeyword([options["Keyword"]], &rest) {
            term := rest, exclusive := true
        } else if (!options["InDefaultResults"] || StrLen(query.Text) < 2) {
            return []
        }
        windows := WindowProvider.List(exclusive)
        needle := StrLower(Trim(term))
        scores := Map()
        for index, window in windows {
            score := (needle = "") ? 100 - index * 0.01 : FuzzyMatcher.BestKey(needle, window.Keys)
            if (score > 0 && (exclusive || score >= 60))                   ; only good matches in the default results, to avoid a pile of browser tabs
                scores[index] := score
        }
        results := []
        for index in FuzzyMatcher.TopIndexes(scores, exclusive ? ProviderRegistry.MaxResults : 3) {
            window := windows[index]
            results.Push(WindowProvider.ItemFor(window, scores[index] - (exclusive ? 0 : 14), exclusive))
        }
        return results
    }

    static ItemFor(window, score, exclusive := false) {
        hwnd := window.Hwnd
        return ResultItem(window.Title, I18n.T("Win.Subtitle", window.Process), {
            Icon: (window.Path != "") ? window.Path : "res:imageres.dll,-102", Score: score, Exclusive: exclusive,
            Uid: "window:" StrLower(window.Process), Arg: window.Title,
            OnRun: (*) => WindowProvider.Activate(hwnd),
            Actions: [ResultItem(I18n.T("Action.CloseWindow"), window.Title, {Icon: "res:imageres.dll,-98", OnRun: (*) => WindowProvider.Close(hwnd)})]
        })
    }

    ; The windows on the taskbar, in z-order (frontmost first): [{Hwnd, Title, Process, Path, Keys}]
    static List(refresh := true) {
        if (!refresh || A_TickCount - WindowProvider._listTime < WindowProvider.CacheMs)
            return WindowProvider._list
        try WindowProvider._list := WindowProvider._Enumerate()
        catch as e
            Logger.Debug("WindowProvider: window enumeration is unavailable - " e.Message)
        ; Cache failed attempts too; retain a useful snapshot if a desktop backend is temporarily unavailable.
        WindowProvider._listTime := A_TickCount
        return WindowProvider._list
    }

    static _Enumerate() {
        list := []
        handles := WinGetList()
        for hwnd in handles {
            if !WindowProvider.IsSwitchable(hwnd)
                continue
            try {
                title := WinGetTitle("ahk_id " hwnd)
            } catch {
                continue
            }
            process := ""
            try process := WinGetProcessName("ahk_id " hwnd)
            exePath := ""
            try exePath := WinGetProcessPath("ahk_id " hwnd)
            name := RegExReplace(process, "i)\.exe$")
            pinyinText := Pinyin.Initials(title)
            list.Push({Hwnd: hwnd, Title: title, Process: process, Path: exePath
                , Keys: [FuzzyMatcher.Key(title), FuzzyMatcher.Key(name), (pinyinText != title) ? FuzzyMatcher.Key(pinyinText) : ""]})
        }
        return list
    }

    ; The same test as the taskbar: visible, with a title, not a tool window, no owner, not hidden by DWM (another virtual desktop / a suspended Store app)
    static IsSwitchable(hwnd) {
        try {
#if WINDOWS
            if !DllCall("IsWindowVisible", "Ptr", hwnd) || WinGetTitle("ahk_id " hwnd) = ""
                return false
            exStyle := WinGetExStyle("ahk_id " hwnd)
            if (exStyle & 0x80) && !(exStyle & 0x40000)                     ; WS_EX_TOOLWINDOW, unless WS_EX_APPWINDOW
                return false
            if DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") && !(exStyle & 0x40000)   ; GW_OWNER: dialogs etc.
                return false
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4)   ; DWMWA_CLOAKED
            if cloaked
                return false
            if (WinGetPID("ahk_id " hwnd) = DllCall("GetCurrentProcessId"))  ; ALTRun's own windows
                return false
            return WinGetClass("ahk_id " hwnd) != "Progman"
#else
            if (hwnd = A_ScriptHwnd || (IsObject(SearchWindow.Gui) && hwnd = SearchWindow.Gui.Hwnd))
                return false
            if (WinGetTitle("ahk_id " hwnd) = "")
                return false
            pid := WinGetPID("ahk_id " hwnd)
            return !pid || pid != ProcessExist()
#endif
        }
        return false
    }

    static Activate(hwnd) {
        if !WinExist("ahk_id " hwnd)
            return App.Notify(I18n.T("Win.Gone"))
        try {
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                WinRestore("ahk_id " hwnd)
        }
        WinActivate("ahk_id " hwnd)
    }

    static Close(hwnd) {
        if WinExist("ahk_id " hwnd)
            WinClose("ahk_id " hwnd)
        WindowProvider._listTime := 0
    }
}

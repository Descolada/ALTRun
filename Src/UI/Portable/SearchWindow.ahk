; SearchWindow.ahk - Portable launcher UI with provider actions, history and keyboard navigation.

class SearchWindow {
    static _visible := false, _focusArmed := false, _imageList := 0
    static Gui := "", Input := "", List := "", Canvas := "", Frame := "", Separator := ""
    static RowModel := [], FooterHeight := 38, Hovered := 0, _painting := false, _paintAgain := false, _drag := ""
    static Results := [], Selected := 0, Offset := 0
    static Mode := "results"                        ; results = 搜索结果; actions = 操作面板
    static HighlightText := ""                      ; 搜索结果标题里高亮和它匹配的字 (Highlight 颜色)
    static FileMode := false                        ; 文件搜索模式: 空的搜索框里按空格进入, 只搜文件
    static ActionSource := "", SavedQuery := "", AllActions := []
    static _actionsOnly := false                                            ; 直接打开的操作面板 (选中内容的操作): Esc / ← 关掉窗口
    static _footerMenuActive := false, _footerMenuOrigin := ""
    static HistoryIndex := 0                         ; 正在看第几条搜索记录 (Knowledge.History, 1 = 最近), 0 = 没有在翻
    static Marked := SearchWindow._MarkedMap()
    static _historyDraft := ""                       ; 开始翻记录之前输入框里的文字, Ctrl+↓ 翻回来时恢复
    static Width := 0, Padding := 0, InputHeight := 0, RowHeight := 0, IconSize := 0, VisibleRows := 8
    static SelectedRadius := 0
    static _searchTimer := "", _hideTimer := ""
    static _shownRows := -1                                                 ; 窗口当前按几行结果的高度显示
    static _tip := ""                                                       ; 这次显示时的使用提示 (HelpProvider.NextTip)
    static LastArea := "", HiddenAt := 0, _shownArea := ""                   ; 上次隐藏时所在屏幕的工作区和时间 (Hud 用)
    static _last := ""                                                      ; 上次隐藏时的搜索 {Text, FileMode, Selected} (KeepLastQuery)
    static _keepOpen := false                        ; 右键菜单 / 删除确认期间不因失去焦点而隐藏
    static IconPrefetchDelay := 2000, PrepareDelay := 200, _prepareTimer := "", _prepared := false
    static ListTop := 58

    static Create() {
        SearchWindow._CanvasUp()
        if IsObject(SearchWindow.Canvas)
            try SearchWindow.Canvas.Value := ""
        if IsObject(SearchWindow.Frame)
            SearchWindow.Frame.Dispose()
        SearchWindow.Frame := "", SearchWindow.RowModel := [], SearchWindow.Hovered := 0
        if IsObject(SearchWindow.Gui)
            SearchWindow.Gui.Destroy()
        SearchWindow.Width := Max(480, AppSettings.Appearance["Width"])
        SearchWindow.VisibleRows := Max(1, Min(9, AppSettings.Appearance["VisibleRows"]))
        SearchWindow.Padding := Max(8, ThemeManager.Get("Padding"))
        SearchWindow.InputHeight := Max(34, Round(ThemeManager.Get("InputFontSize") * 1.8))
        SearchWindow.RowHeight := Max(24, ThemeManager.Get("RowHeight"))
        SearchWindow.IconSize := Max(16, ThemeManager.Get("IconSize"))
        SearchWindow.ListTop := SearchWindow.InputHeight + SearchWindow.Padding * 2 + 20
        SearchWindow.FooterHeight := AppSettings.Appearance["StatusBar"] ? 38 : 0
        IconCache.Size := SearchWindow.IconSize
        SearchWindow._visible := false, SearchWindow._focusArmed := false
        g := Gui("-Caption +AlwaysOnTop +ToolWindow -MinimizeBox", App.Name)
        g.MarginX := 0, g.MarginY := 0
        g.BackColor := ThemeManager.Get("Background")
        g.SetFont("s" ThemeManager.Get("InputFontSize") " c" ThemeManager.Get("InputText"), ThemeManager.FontName())
        pad := SearchWindow.Padding, contentWidth := SearchWindow.Width - pad * 2
        surface := LauncherCanvas.Blend(ThemeManager.Get("Background"), ThemeManager.Get("InputText"), 0.035)
        canvasControl := g.AddPicture("x0 y0 w" SearchWindow.Width " h" SearchWindow._WindowHeight(0))
        searchBox := g.AddEdit("x" (pad + 40) " y" (pad + 6) " w" (contentWidth - 54) " h" SearchWindow.InputHeight
            . " r1 -Multi -WantReturn -Border -E0x200 Background" surface)
        if !Platform.IsWindows
            try searchBox.ToClr().ShowBorder := false
        if Platform.IsLinux {
            ; Some GTK themes lose their selection colors when the entry surface is customized.
            selectionStyle := Clr.Gtk.CssProvider()
            try {
                selectionStyle.LoadFromData("entry selection { background-color: #" ThemeManager.Get("SelectedBackground")
                    . "; color: #" ThemeManager.Get("SelectedTitle") "; }")
                searchBox.ToClr().ControlObject.StyleContext.AddProvider(selectionStyle, 801)
            } finally selectionStyle.Dispose()
        }
        searchBox.SetCue(SearchWindow.Placeholder())
        LauncherCanvas.AccessibleLabel(searchBox, I18n.T("Search.Placeholder"))
        searchBox.OnEvent("Change", (*) => SearchWindow._OnInputChange())
        g.OnEvent("Close", (*) => (SearchWindow.Hide(), true))
#if WINDOWS
        g.OnEvent("Escape", (*) => SearchWindow.Hide())
#endif
        SearchWindow.Gui := g, SearchWindow.Input := searchBox, SearchWindow.Canvas := canvasControl, SearchWindow.List := canvasControl
#if !WINDOWS
        ; GTK routes some keys to the focused entry and others to the form. Share one dispatcher.
        ALTRunLauncherAttachKeys(g.ToClr(), searchBox.ToClr(), canvasControl.ToClr()
            , (vk, repeat, msg, modifiers) => SearchWindow._OnKeyDown(vk, repeat, msg, SearchWindow.Gui.Hwnd, modifiers))
#endif
        for control in [searchBox, canvasControl] {
#if WINDOWS
            control.OnMessage(0x100, (ctrl, w, l, msg) => SearchWindow._OnKeyDown(w, l, msg, ctrl.Hwnd))
            control.OnMessage(0x104, (ctrl, w, l, msg) => SearchWindow._OnKeyDown(w, l, msg, ctrl.Hwnd))
#endif
            control.OnMessage(0x20A, (ctrl, w, l, msg) => SearchWindow._OnMouseWheel(w, l, msg, ctrl.Hwnd))
        }
        canvasControl.OnMessage(0x200, (ctrl, w, l, msg) => SearchWindow._CanvasMove(w, l))
        canvasControl.OnMessage(0x201, (ctrl, w, l, msg) => SearchWindow._CanvasDown(l))
        canvasControl.OnMessage(0x202, (*) => SearchWindow._CanvasUp())
#if WINDOWS
        canvasControl.OnMessage(0x203, (ctrl, w, l, msg) => SearchWindow._CanvasDoubleClick(l))
#else
        ALTRunLauncherAttachDoubleClick(canvasControl.ToClr(), (point) => SearchWindow._CanvasDoubleClick(point))
#endif
        canvasControl.OnMessage(0x204, (ctrl, w, l, msg) => SearchWindow._CanvasRightClick(l))
        canvasControl.OnMessage(0x2A3, (*) => SearchWindow._CanvasLeave())
#if WINDOWS
        canvasControl.OnMessage(0x215, (*) => SearchWindow._CanvasUp())
#endif
        canvasControl.OnEvent("ContextMenu", (ctrl, info, right, x, y) => SearchWindow._OnRowContextMenu(SearchWindow.Hovered, x, y))
        g.OnEvent("DpiChanged", (*) => SearchWindow._Repaint())
        g.Show("Hide w" SearchWindow.Width " h" SearchWindow._WindowHeight(0))
        SearchWindow._hideTimer := () => SearchWindow._HideIfInactive()
        BackgroundWork.IsBusy := () => !SearchWindow._AllowsBackgroundWork()
        SearchWindow._Layout()
    }

    static IsVisible() {
        return IsObject(SearchWindow.Gui) && SearchWindow._visible
    }

    static IsActive() {
#if WINDOWS
        return IsObject(SearchWindow.Gui) && WinActive("ahk_id " SearchWindow.Gui.Hwnd) ? true : false
#else
        ; Unix GUI handles name toolkit widgets, not desktop window IDs. Ask the owning native form.
        return IsObject(SearchWindow.Gui) && SearchWindow.Gui.ToClr().HasFocus ? true : false
#endif
    }

    static _showing := false
    static Show(text := "", catchTyping := true) {
        if (!IsObject(SearchWindow.Gui) || SearchWindow._showing)
            return
        SearchWindow._showing := true
        if (SearchWindow._prepareTimer != "")
            SetTimer(SearchWindow._prepareTimer, 0)
#if WINDOWS
        if catchTyping
            TypeAhead.Start()
#endif
        try SearchWindow._Show(text)
        finally {
            SearchWindow._showing := false
#if WINDOWS
            typed := TypeAhead.Take()
#endif
        }
#if WINDOWS
        if (typed.Text = "" && typed.Key = "")
            return
        if Logger.Enabled
            Logger.Debug("SearchWindow: typed while showing " TypeAhead.Summary(typed))
        if (typed.Key = "Escape")
            return SearchWindow.Hide()
        captured := typed.Text
        if (captured != "") {
            if (SubStr(captured, 1, 1) = " " && SearchWindow.Mode = "results" && !SearchWindow.FileMode) {
                if SearchWindow._AllTextSelected()
                    SearchWindow._SetInput("")
                if SearchWindow._CanEnterFileMode() {
                    SearchWindow._SetFileMode(true)
                    captured := SubStr(captured, 2)
                }
            }
            selection := Platform.EditSelection(SearchWindow.Input)
            current := SearchWindow.Input.Value
            SearchWindow._SetInput(SubStr(current, 1, selection.Start) captured SubStr(current, selection.End + 1))
            caret := selection.Start + StrLen(captured)
            Platform.SelectEdit(SearchWindow.Input, caret, caret)
        }
        if (typed.Key != "")
            SearchWindow._Execute(typed.Modifier)
#endif
    }

    static _Show(text) {
        if (text = "" && SearchWindow.IsVisible()) {
            selection := Platform.EditSelection(SearchWindow.Input)
            Usage.Count("Show")
            SearchWindow.Gui.Show(Platform.IsWindows ? "" : "Restore")
            SearchWindow._FocusInput()
            Platform.SelectEdit(SearchWindow.Input, selection.Start, selection.End)
#if WINDOWS
            SearchInputLanguage.SwitchOnShow(true)
#endif
            return
        }
        App.RememberActiveWindow()
        SearchWindow._actionsOnly := false, SearchWindow._footerMenuActive := false, SearchWindow._footerMenuOrigin := "", SearchWindow.Marked := SearchWindow._MarkedMap()
        Usage.Count("Show")
        last := SearchWindow._last
        restore := text = "" && AppSettings.General["KeepLastQuery"] && IsObject(last) && last.Text != ""
        prepared := !restore && text = "" && SearchWindow.IsPrepared()
        SearchWindow._prepared := false
        SearchWindow.Mode := "results", SearchWindow.FileMode := restore ? last.FileMode : false
        SearchWindow._tip := AppSettings.General["ShowTips"] ? HelpProvider.NextTip() : ""
        SearchWindow._UpdateCueBanner()
        SearchWindow.HistoryIndex := 0
        if !prepared
            SearchWindow._SetInput(restore ? last.Text : text)
        if restore
            SearchWindow.MoveSelection(last.Selected - SearchWindow.Selected)
        appearance := AppSettings.Appearance
        scale := SearchWindow._ScreenScale()
        SearchWindow._shownArea := SearchWindow._ScreenArea(appearance["ShowOn"])
        pos := SearchWindow.Place(SearchWindow._shownArea, Round(SearchWindow.Width * scale)
            , Round(SearchWindow._WindowHeight(SearchWindow.VisibleRows) * scale), appearance["RememberPosition"] ? appearance["Position"] : "")
        wasVisible := SearchWindow.IsVisible()
        SearchWindow._ApplyFade(true)
        ; Restore also clears the toolkit's persistent no-activation flag left by a layout-only Show("NA").
        SearchWindow.Gui.Show((Platform.IsWindows ? "" : "Restore ") "x" pos.X " y" pos.Y " w" SearchWindow.Width " h" SearchWindow._WindowHeight(SearchWindow._VisibleCount()))
        SearchWindow._visible := true, SearchWindow._focusArmed := false
        SearchWindow._shownRows := SearchWindow._VisibleCount()
        SearchWindow._FocusInput()
        length := StrLen(SearchWindow.Input.Value)
        Platform.SelectEdit(SearchWindow.Input, restore ? 0 : length, length)
#if WINDOWS
        SearchInputLanguage.SwitchOnShow(wasVisible)
#endif
        if AppSettings.General["HideOnDeactivate"]
            SetTimer(SearchWindow._hideTimer, 200)
        if prepared
            SetTimer(() => SearchWindow._RunSearch(), -1)
    }

    static _FocusInput() {
        ; GTK needs a toplevel activation request as well as focus on the entry.
        if Platform.IsLinux {
            nativeWindow := SearchWindow.Gui.ToClr().ControlObject
            x11DisplayType := DllCall("libgdk-3.so.0\gdk_x11_display_get_type", "Ptr")
            if DllCall("libgobject-2.0.so.0\g_type_check_instance_is_a", "Ptr", nativeWindow.Display.Handle, "Ptr", x11DisplayType, "Int") {
                ; A stale user time can make the window manager reject activation after another app was used.
                stamp := DllCall("libgdk-3.so.0\gdk_x11_get_server_time", "Ptr", nativeWindow.Window.Handle, "UInt")
                nativeWindow.PresentWithTime(stamp)
            } else
                nativeWindow.Present()
        }
        SearchWindow.Input.Focus()
    }

    static Place(area, width, maxHeight, position := "") {
        fx := 500, fy := 200
        if (position is Map && position.Has("X") && position.Has("Y") && IsNumber(position["X"]) && IsNumber(position["Y"]))
            fx := position["X"], fy := position["Y"]
        areaW := area.Right - area.Left, areaH := area.Bottom - area.Top
        x := area.Left + Round((areaW - width) * Max(0, Min(fx, 1000)) / 1000)
        y := area.Top + Round(areaH * Max(0, Min(fy, 1000)) / 1000)
        x := Max(area.Left, Min(x, area.Right - width))
        y := Max(area.Top, Min(y, area.Bottom - maxHeight))
        return {X: x, Y: y}
    }

    static RelativePosition(area, width, x, y) {
        areaW := area.Right - area.Left, areaH := area.Bottom - area.Top
        fx := (areaW > width) ? Round((x - area.Left) * 1000 / (areaW - width)) : 500
        fy := (areaH > 0) ? Round((y - area.Top) * 1000 / areaH) : 200
        return Map("X", Max(0, Min(fx, 1000)), "Y", Max(0, Min(fy, 1000)))
    }

    static _ScreenArea(showOn) {
        switch showOn, false {
            case "Primary": return Win.WorkArea(MonitorGetPrimary())
            case "Active":
                area := Win.WorkAreaOfWindow(App.PreviousWindow)
                if IsObject(area)
                    return area
        }
        try return Win.WorkAreaAtMouse()
        catch
            return Win.WorkArea(MonitorGetPrimary())
    }

    static _OnMoved(*) {
        if (!SearchWindow.IsVisible() || !AppSettings.Appearance["RememberPosition"])
            return
        try {
            WinGetPos(&x, &y, &width, &height, "ahk_id " SearchWindow.Gui.Hwnd)
            area := Win.WorkAreaAt(x + width // 2, y + height // 2)
            AppSettings.Appearance["Position"] := SearchWindow.RelativePosition(area, width, x, y)
        }
    }

    static _ScreenScale() => LauncherCanvas.ScreenScale(SearchWindow.Gui)

    static Hide() {
        SearchWindow._CanvasUp()
        if IsObject(SearchWindow._hideTimer)
            SetTimer(SearchWindow._hideTimer, 0)
        if SearchWindow.IsVisible() {
            SearchWindow._OnMoved()
            ; Desktop geometry is optional on Wayland, including while its broker recovers.
            SearchWindow.LastArea := SearchWindow._shownArea
            try {
                WinGetPos(&x, &y, &w, &h, "ahk_id " SearchWindow.Gui.Hwnd)
                SearchWindow.LastArea := Win.WorkAreaAt(x + w // 2, y + h // 2)
            }
            SearchWindow.HiddenAt := A_TickCount
            SearchWindow._RememberQuery()
#if WINDOWS
            SearchInputLanguage.Restore()
#endif
            SearchWindow._ApplyFade(false)
            SearchWindow._visible := false
            SearchWindow.Gui.Hide()
            SearchWindow._PrepareLater()
        }
        LargeType.Close()
    }

    static _ApplyFade(showing) {
#if WINDOWS
        if showing {
            WindowFade.Stop()
            opacity := ThemeManager.Get("Opacity")
            opacity := IsNumber(opacity) && opacity >= 1 && opacity < 255 ? Round(opacity) : 255
            if (!SearchWindow.IsVisible() && AppSettings.Appearance["Fade"])
                WindowFade.In(SearchWindow.Gui.Hwnd, opacity)
            else
                WindowFade.SetAlpha(SearchWindow.Gui.Hwnd, opacity)
        } else if AppSettings.Appearance["Fade"] {
            WindowFade.Out(SearchWindow.Gui.Hwnd)
        }
#endif
    }

    static _RememberQuery() {
        actions := (SearchWindow.Mode = "actions")
        SearchWindow._last := {Text: actions ? SearchWindow.SavedQuery : SearchWindow.Input.Value
                             , FileMode: SearchWindow.FileMode, Selected: actions ? 1 : Max(1, SearchWindow.Selected)}
    }

    static _AllowsBackgroundWork() => !SearchWindow._showing && !SearchWindow.IsVisible()

    static _PrepareLater() {
        if AppSettings.General["KeepLastQuery"]
            return
        if (SearchWindow._prepareTimer = "")
            SearchWindow._prepareTimer := () => SearchWindow.PrepareEmpty()
        SetTimer(SearchWindow._prepareTimer, -SearchWindow.PrepareDelay)
    }

    static PrepareEmpty() {
        if (!IsObject(SearchWindow.Gui) || !SearchWindow._AllowsBackgroundWork())
            return
        SearchWindow.Mode := "results", SearchWindow.FileMode := false
        SearchWindow._SetInput("")
        SearchWindow._prepared := true
    }

    static IsPrepared() => SearchWindow._prepared && SearchWindow.Mode = "results" && !SearchWindow.FileMode && SearchWindow.Input.Value = ""

    static _MarkedMap() {
        marks := Map()
        marks.CaseSense := "On"
        return marks
    }

    static Toggle() {
        if (SearchWindow.IsVisible() && SearchWindow.IsActive())
            SearchWindow.Hide()
        else
            SearchWindow.Show()
    }

    static _SetInput(text) {
        SearchWindow.Input.Value := text
        length := StrLen(text)
        Platform.SelectEdit(SearchWindow.Input, length, length)
        SearchWindow._RunSearch()
    }

    static _OnInputChange() {
        text := SearchWindow.Input.Value
        if RegExMatch(text, "[`r`n`t]") {                                   ; 粘贴了多行文字: 合并成一行, 搜索框始终只有一行
            SearchWindow.Input.Value := RegExReplace(text, "\s*[`r`n`t]+\s*", " ")
            len := StrLen(SearchWindow.Input.Value)
            Platform.SelectEdit(SearchWindow.Input, len, len)
        }
        SearchWindow.HistoryIndex := 0
        if (SearchWindow._searchTimer = "")
            SearchWindow._searchTimer := () => SearchWindow._RunSearch()
        SetTimer(SearchWindow._searchTimer, -1)                             ; 连续输入时只搜索最后一次
    }

    static _searchGen := 0
    static _RunSearch() {
        gen := ++SearchWindow._searchGen
        text := SearchWindow.Input.Value
        if (SearchWindow.Mode = "actions") {
            filtered := []
            for action in SearchWindow.AllActions
                if (Trim(text) = "" || FuzzyMatcher.Score(text, action.Title) > 0)
                    filtered.Push(action)
            return SearchWindow.SetResults(filtered)
        }
        browse := FileSearchProvider.BrowsePath(text)                       ; 浏览文件夹: 只按最后一段 (过滤的文字) 高亮, 路径里的词不算
        SearchWindow.HighlightText := IsObject(browse) ? browse.Filter : text
        results := SearchWindow.FileMode ? ProviderRegistry.SearchOnly(FileSearchProvider, text) : ProviderRegistry.Search(text)
        if (gen != SearchWindow._searchGen)                                 ; 搜索期间又输入了字: 用新的那次的结果
            return
        SearchWindow.SetResults(results)
    }

    static SetResults(results) {
        SearchWindow.Results := results
        SearchWindow.Selected := results.Length ? 1 : 0, SearchWindow.Offset := 0
        SearchWindow._Layout()
    }

    static _repaintLater := ""

    static _AfterResults() {
        SearchWindow._Layout()
    }

    static _recent := [], _blankLogged := false
    static _NoteResults(count) {
        SearchWindow._recent.Push(FormatTime(, "HH:mm:ss") "." Format("{:03}", A_MSec) " '" SubStr(SearchWindow.Input.Value, 1, 30) "' mode " SearchWindow.Mode
            . (SearchWindow.FileMode ? " (files)" : "") " results " count " gen " SearchWindow._searchGen " painted rows " SearchWindow.RowModel.Length)
        if (SearchWindow._recent.Length > 10)
            SearchWindow._recent.RemoveAt(1)
    }
    static _LogBlankRow(row, count) {
        if (SearchWindow._blankLogged || !Logger.Enabled)
            return
        SearchWindow._blankLogged := true
        Logger.Warn("SearchWindow: row " row " has no result (results " count ", offset " SearchWindow.Offset ", painted rows " SearchWindow.RowModel.Length
            . ", window rows " SearchWindow._shownRows ", mode " SearchWindow.Mode ", input '" SubStr(SearchWindow.Input.Value, 1, 30) "')")
        for entry in SearchWindow._recent
            Logger.Debug("  recent results: " entry)
    }

    static _VisibleCount() {
        return Min(SearchWindow.Results.Length, SearchWindow.VisibleRows)
    }

    static _WindowHeight(visibleCount) {
        return SearchWindow.ListTop + SearchWindow.Padding + visibleCount * SearchWindow.RowHeight + SearchWindow.FooterHeight
    }

    static _Layout() {
        count := SearchWindow._VisibleCount()
        SearchWindow.Hovered := 0
        SearchWindow.Canvas.Move(0, 0, SearchWindow.Width, SearchWindow._WindowHeight(count))
        if (SearchWindow.IsVisible() && SearchWindow._shownRows != count) {
            SearchWindow.Gui.Show("NA w" SearchWindow.Width " h" SearchWindow._WindowHeight(count))
            SearchWindow._shownRows := count
        }
        SearchWindow._Repaint()
    }

    static _Repaint() {
        if !IsObject(SearchWindow.Canvas)
            return
        if SearchWindow._painting {
            SearchWindow._paintAgain := true
            return
        }
        SearchWindow._painting := true
        try {
            rows := [], count := SearchWindow._VisibleCount(), pad := SearchWindow.Padding
            Loop count {
                index := SearchWindow.Offset + A_Index, item := SearchWindow.Results[index]
                selected := index = SearchWindow.Selected
                background := selected ? ThemeManager.Get("SelectedBackground") : A_Index = SearchWindow.Hovered
                    ? LauncherCanvas.Blend(ThemeManager.Get("Background"), ThemeManager.Get("Title"), 0.045) : ThemeManager.Get("Background")
                rows.Push({Index: index, Item: item, X: pad, Y: SearchWindow.ListTop + (A_Index - 1) * SearchWindow.RowHeight
                    , Width: SearchWindow.Width - pad * 2, Height: SearchWindow.RowHeight - 4, Title: item.Title, Subtitle: item.Subtitle
                    , Shortcut: "Ctrl+" A_Index, Background: background, Selected: selected})
            }
            IconCache.Scale := SearchWindow.Gui.PixelScale
            frameImage := LauncherCanvas.Render(SearchWindow.Width, SearchWindow._WindowHeight(count), SearchWindow.Gui.PixelScale, rows)
            try SearchWindow.Canvas.Value := "HBITMAP:" frameImage.ToBitmap()
            catch {
                frameImage.Dispose()
                throw
            }
            previousFrame := SearchWindow.Frame
            SearchWindow.Frame := frameImage, SearchWindow.RowModel := rows
            SearchWindow.Canvas.Move(0, 0, SearchWindow.Width, SearchWindow._WindowHeight(count))
            labels := []
            for row in rows
                labels.Push(row.Title (row.Subtitle != "" ? ": " row.Subtitle : ""))
            LauncherCanvas.AccessibleLabel(SearchWindow.Canvas, TextTools.JoinList(labels, "; "))
            if IsObject(previousFrame)
                previousFrame.Dispose()
        } finally {
            SearchWindow._painting := false
            if SearchWindow._paintAgain {
                SearchWindow._paintAgain := false
                SetTimer(() => SearchWindow._Repaint(), -1)
            }
        }
    }

    static RowAt(x, y) {
        for row in SearchWindow.RowModel
            if (x >= row.X && x < row.X + row.Width && y >= row.Y && y < row.Y + row.Height)
                return A_Index
        return 0
    }

    static _CanvasPoint(lParam) {
        x := (lParam << 48) >> 48, y := (lParam << 32) >> 48
        if Platform.IsWindows
            x /= SearchWindow.Gui.PixelScale, y /= SearchWindow.Gui.PixelScale
        return {X: x, Y: y}
    }

    static _CanvasMove(wParam, lParam) {
        point := SearchWindow._CanvasPoint(lParam)
        if (IsObject(SearchWindow._footerMenuOrigin) && (Abs(point.X - SearchWindow._footerMenuOrigin.X) > 4 || Abs(point.Y - SearchWindow._footerMenuOrigin.Y) > 4))
            SearchWindow._footerMenuOrigin := ""
        if IsObject(SearchWindow._drag) {
            if !(wParam & 1)
                return SearchWindow._CanvasUp()
            pointer := SearchWindow._ScreenPointer()
            SearchWindow.Gui.Show("NA x" (SearchWindow._drag.X + pointer.X - SearchWindow._drag.MouseX) " y" (SearchWindow._drag.Y + pointer.Y - SearchWindow._drag.MouseY))
            return 0
        }
        row := SearchWindow.RowAt(point.X, point.Y)
        if (row != SearchWindow.Hovered) {
            SearchWindow.Hovered := row
            SearchWindow._Repaint()
        }
    }

    static _CanvasDown(lParam) {
        point := SearchWindow._CanvasPoint(lParam), row := SearchWindow.RowAt(point.X, point.Y)
        if row
            SearchWindow._OnRowClick(row)
        else if (SearchWindow.FooterHeight && point.Y >= SearchWindow._WindowHeight(SearchWindow._VisibleCount()) - SearchWindow.FooterHeight) {
            if (point.X < SearchWindow.Padding + 150) {
                if (SearchWindow.Mode = "actions")
                    SearchWindow._CloseActions()
                else if Platform.IsLinux
                    SearchWindow._FooterMenu(point)
                else
                    SetTimer(() => SearchWindow._FooterMenu(), -1)
            } else if (point.X > SearchWindow.Width * 0.68 && SearchWindow.Mode = "results")
                SearchWindow._OpenActions()
        }
        else if (point.Y < SearchWindow.ListTop) {
            try {
                pointer := SearchWindow._ScreenPointer()
                WinGetPos(&x, &y, , , "ahk_id " SearchWindow.Gui.Hwnd)
                SearchWindow._drag := {X: x, Y: y, MouseX: pointer.X, MouseY: pointer.Y}
            }
#if WINDOWS
            if IsObject(SearchWindow._drag)
                DllCall("SetCapture", "Ptr", SearchWindow.Canvas.Hwnd, "Ptr")
#endif
        }
        return 0
    }

    static _FooterMenu(point := "") {
        if Platform.IsLinux {
            if (!SearchWindow.IsVisible() || SearchWindow.Mode = "actions")
                return
            ; Keep Linux menus inside the launcher: parentless GTK popups can break Wayland grabs.
            SearchWindow.SavedQuery := SearchWindow.Input.Value
            SearchWindow.ActionSource := ResultItem(App.Name)
            SearchWindow.AllActions := [
                ResultItem(I18n.T("Tray.Preferences"), "Ctrl+,", {OnRun: (*) => App.OpenPreferences()}),
                ResultItem(I18n.T("Menu.CheatSheet"), "?", {OnRun: (*) => SearchWindow._SetInput("?")}),
                ResultItem(I18n.T("Tray.RebuildIndex"), "", {OnRun: (*) => App.RebuildIndex()}),
                ResultItem(I18n.T("Tray.CheckUpdate"), "", {OnRun: (*) => UpdateChecker.Check()}),
                ResultItem(I18n.T("Tray.Reload"), "", {OnRun: (*) => App.Reload()}),
                ResultItem(I18n.T("Tray.Exit"), "", {OnRun: (*) => App.Quit()})
            ]
            SearchWindow._footerMenuActive := true, SearchWindow._footerMenuOrigin := point
            SearchWindow.Mode := "actions"
            SearchWindow.Input.SetCue(I18n.T("Search.ActionsFor", App.Name))
            SearchWindow._SetInput("")
            SearchWindow.Input.Focus()
            return
        }
        later := (fn) => (*) => (SearchWindow.Hide(), SetTimer(fn, -1))
        popup := Menu()
        popup.Add(I18n.T("Tray.Preferences") "`tCtrl+,", later(() => App.OpenPreferences()))
        popup.Add(I18n.T("Menu.CheatSheet") "`t?", (*) => SearchWindow._SetInput("?"))
        popup.Add()
        popup.Add(I18n.T("Tray.RebuildIndex"), later(() => App.RebuildIndex()))
        popup.Add(I18n.T("Tray.CheckUpdate"), later(() => UpdateChecker.Check()))
        popup.Add()
        popup.Add(I18n.T("Tray.Reload"), later(() => App.Reload()))
        popup.Add(I18n.T("Tray.Exit"), later(() => App.Quit()))
        WinGetPos(&x, &y, , , "ahk_id " SearchWindow.Gui.Hwnd)
        top := SearchWindow._WindowHeight(SearchWindow._VisibleCount()) - SearchWindow.FooterHeight
        previousMode := A_CoordModeMenu
        SearchWindow._keepOpen := true
        try {
            CoordMode("Menu", "Screen")
            scale := SearchWindow._ScreenScale()
            popup.Show(x + SearchWindow.Padding * scale, y + top * scale)
        } finally {
            CoordMode("Menu", previousMode)
            SearchWindow._keepOpen := false
        }
        if SearchWindow.IsVisible()
            SearchWindow.Input.Focus()
    }

    static _CanvasUp() {
        if IsObject(SearchWindow._drag) {
            SearchWindow._drag := ""
#if WINDOWS
            if (DllCall("GetCapture", "Ptr") = SearchWindow.Canvas.Hwnd)
                DllCall("ReleaseCapture")
#endif
            SearchWindow._OnMoved()
        }
        return 0
    }

    static _ScreenPointer() {
        previousMode := A_CoordModeMouse
        CoordMode("Mouse", "Screen")
        try {
            MouseGetPos(&x, &y)
            return {X: x, Y: y}
        } finally CoordMode("Mouse", previousMode)
    }

    static _CanvasDoubleClick(lParam) {
        ; A panel resize can put a menu command under the click that opened it.
        if (SearchWindow._footerMenuActive && IsObject(SearchWindow._footerMenuOrigin))
            return 0
        point := SearchWindow._CanvasPoint(lParam), row := SearchWindow.RowAt(point.X, point.Y)
        if row
            SearchWindow._OnRowDoubleClick(row)
        return 0
    }

    static _CanvasRightClick(lParam) {
        point := SearchWindow._CanvasPoint(lParam)
        SearchWindow.Hovered := SearchWindow.RowAt(point.X, point.Y)
        if SearchWindow.Hovered
            SearchWindow._OnRowClick(SearchWindow.Hovered)
    }

    static _CanvasLeave() {
        if SearchWindow.Hovered {
            SearchWindow.Hovered := 0
            SearchWindow._Repaint()
        }
    }

    static SelectedItem() {
        if (SearchWindow.Selected < 1 || SearchWindow.Selected > SearchWindow.Results.Length)
            return ""
        return SearchWindow.Results[SearchWindow.Selected]
    }

    static MoveSelection(step, wrap := false) {
        count := SearchWindow.Results.Length
        if !count
            return
        if (wrap && (SearchWindow.Selected + step > count || SearchWindow.Selected + step < 1))
            SearchWindow.Selected := step > 0 ? 1 : count
        else
            SearchWindow.Selected := Max(1, Min(count, SearchWindow.Selected + step))
        visible := SearchWindow.VisibleRows
        if (SearchWindow.Selected <= SearchWindow.Offset)
            SearchWindow.Offset := SearchWindow.Selected - 1
        else if (SearchWindow.Selected > SearchWindow.Offset + visible)
            SearchWindow.Offset := SearchWindow.Selected - visible
        SearchWindow._Repaint()
    }

    static _Execute(modifier := "") {
        item := SearchWindow.SelectedItem()
        if !IsObject(item)
            return

        if (SearchWindow.Mode = "actions") {
            if SearchWindow._footerMenuActive {
                cheatSheet := item = SearchWindow.AllActions[2]
                SearchWindow._CloseActions()
                if !cheatSheet
                    SearchWindow.Hide()
                SearchWindow._Later(() => SearchWindow._SafeRun(() => item.OnRun.Call()))
                return
            }
            source := SearchWindow.ActionSource
            Knowledge.Record(SearchWindow.SavedQuery, source.Uid)
            RecentProvider.Remember(source)
            Usage.CountItem(source)
            SearchWindow.Marked := SearchWindow._MarkedMap()
            SearchWindow.Hide()
            SearchWindow._SafeRun(() => item.OnRun.Call(source))
            return
        }

        if !item.Valid {
            if (item.AutoComplete != "")
                SearchWindow._SetInput(item.AutoComplete)
            return
        }
        Knowledge.Record(SearchWindow.Input.Value, item.Uid)
        RecentProvider.Remember(item)
        Usage.CountItem(item)
        SearchWindow.Hide()
        if (modifier = "")
            SearchWindow._SafeRun(() => ActionCatalog.RunDefault(item))
        else
            SearchWindow._SafeRun(() => ActionCatalog.RunModifier(item, modifier))
    }

    static _SafeRun(fn) {
        try {
            fn()
        } catch as e {
            Logger.Error("SearchWindow: action failed - " e.Message)
            MsgBox(e.Message, App.Name, 48)
        }
    }

    static _RunVisibleRow(row) {
        if (row > SearchWindow._VisibleCount())
            return
        SearchWindow.Selected := SearchWindow.Offset + row
        SearchWindow._Execute()
    }

    static ShowActions(item) {
        SearchWindow.Show("", false)
        if SearchWindow._OpenActionsFor(item)
            SearchWindow._actionsOnly := true
    }

    static _OpenActions() {
        return SearchWindow._OpenActionsFor(SearchWindow.SelectedItem())
    }

    static _OpenActionsFor(item) {
        if (!IsObject(item) || !item.Valid || SearchWindow.Mode = "actions")
            return false
        if SearchWindow.Marked.Count {                                      ; 有标记的文件: 对所有标记的一起操作
            paths := []
            for key, markedPath in SearchWindow.Marked
                paths.Push(markedPath)
            item := ResultItem(I18n.T("Search.MarkedItems", paths.Length), "", {Icon: "folder:"})
            actions := ResultActions.ListForMany(paths)
        } else
            actions := ResultActions.ListFor(item)
        if !actions.Length
            return false
        SearchWindow._footerMenuActive := false, SearchWindow._footerMenuOrigin := ""
        SearchWindow.SavedQuery := SearchWindow.Input.Value
        SearchWindow.ActionSource := item
        SearchWindow.AllActions := actions
        SearchWindow.Mode := "actions"
        SearchWindow.Input.SetCue(I18n.T("Search.ActionsFor", item.Title))
        SearchWindow._SetInput("")
        return true
    }

    static _CloseActions() {
        SearchWindow._footerMenuActive := false, SearchWindow._footerMenuOrigin := ""
        SearchWindow.Mode := "results"
        SearchWindow._UpdateCueBanner()
        SearchWindow._SetInput(SearchWindow.SavedQuery)
    }

    static _CanEnterFileMode() {
        return SearchWindow.Mode = "results" && !SearchWindow.FileMode && (SearchWindow.Input.Value = "" || SearchWindow._CaretAtStart())
            && AppSettings.Feature("FileSearch")["SpacePrefix"] && ProviderRegistry.IsEnabled(FileSearchProvider)
    }

    static _SetFileMode(enabled) {
        SearchWindow.FileMode := enabled
        SearchWindow._UpdateCueBanner()
        SearchWindow._RunSearch()
    }

    static _UpdateCueBanner() {
        if SearchWindow.FileMode
            text := I18n.T("Search.FilesPlaceholder")
        else
            text := (SearchWindow._tip != "") ? SearchWindow._tip : SearchWindow.Placeholder()
        SearchWindow.Input.SetCue(text)
    }

    static Placeholder() {
        text := AppSettings.Appearance.Get("Placeholder", "")
        return text = "" ? I18n.T("Search.Placeholder") : Trim(text)
    }

    static _TargetItem() {
        return (SearchWindow.Mode = "actions") ? SearchWindow.ActionSource : SearchWindow.SelectedItem()
    }

    static _CurrentQuery() {
        return (SearchWindow.Mode = "actions") ? SearchWindow.SavedQuery : SearchWindow.Input.Value
    }

    static _Later(fn) {
        SetTimer(fn, -1)
    }

    static _EditSelected() {
        item := SearchWindow._TargetItem()
        isFallback := IsObject(item) && item.Provider = ""                  ; 没有匹配时的兜底项 (网页搜索等)
        if (IsObject(item) && !isFallback && ResultActions.CanEdit(item))
            return SearchWindow._Later(() => SearchWindow.EditItem(item))
        query := Trim(SearchWindow._CurrentQuery())
        if (query != "" && (!IsObject(item) || isFallback))                 ; 没有结果: 用输入的文字新建一条命令
            return SearchWindow._Later(() => SearchWindow.NewCommand(query))
        App.Notify(I18n.T("Search.NotEditable"))
    }

    static EditItem(item) {
        query := SearchWindow._CurrentQuery()
        SearchWindow.Hide()
        SearchWindow._SafeRun(() => ResultActions.EditItem(item))
        SearchWindow._Reopen(query)
    }

    static NewCommand(title) {
        SearchWindow.Hide()
        SearchWindow._SafeRun(() => CustomCommandProvider.Edit("", Map("Title", title)))
        SearchWindow._Reopen(title)
    }

    static DeleteItem(item) {
        query := SearchWindow._CurrentQuery()
        wasVisible := SearchWindow.IsVisible()
        SearchWindow._keepOpen := true
        answer := MsgBox(ResultActions.DeletePrompt(item), App.Name, "YesNo Icon! Default2" (wasVisible ? " Owner" SearchWindow.Gui.Hwnd : ""))
        SearchWindow._keepOpen := false
        if (answer = "Yes")
            SearchWindow._SafeRun(() => ResultActions.DeleteItem(item))
        selected := SearchWindow.Selected
        SearchWindow._Reopen(query)
        if (answer = "Yes" && selected > 1)
            SearchWindow.MoveSelection(selected - 2)                        ; 选中被删除那一行的上一行 (MoveSelection 相对第 1 行)
    }

    static _Reopen(query) {
        previous := App.PreviousWindow
        SearchWindow.Show(query)
        App.PreviousWindow := previous
    }

    static _OnRowContextMenu(row, x, y) {
        if (row < 1 || SearchWindow.Offset + row > SearchWindow.Results.Length)
            return
        if (SearchWindow.Mode = "results") {
            SearchWindow.Selected := SearchWindow.Offset + row
            SearchWindow._Repaint()
        }
        item := SearchWindow._TargetItem()
        if (!IsObject(item) || !item.Valid && !ResultActions.CanEdit(item))
            return
        if (SearchWindow.Mode = "actions") {                                ; 操作面板里右键 = 执行这一项
            if !SearchWindow._footerMenuActive
                SearchWindow._Execute()
            return
        }
        if Platform.IsLinux {
            SearchWindow._OpenActionsFor(item)
            SearchWindow.Input.Focus()
            return
        }
        contextMenu := Menu()
        for action in ResultActions.ListFor(item) {
            label := StrReplace(action.Title, "&", "&&") (action.Subtitle != "" ? "`t" action.Subtitle : "")
            contextMenu.Add(label, SearchWindow._MenuHandler(action, item))
            if (A_Index = 1)
                contextMenu.Default := label
        }
        Critical("Off")
        SearchWindow._Repaint()
        SearchWindow._keepOpen := true
        contextMenu.Show(x, y)
        SearchWindow._keepOpen := false
        if (SearchWindow.IsVisible() && !SearchWindow.IsActive())
            try WinActivate("ahk_id " SearchWindow.Gui.Hwnd)
    }

    static _MenuHandler(action, item) {
        return (*) => SearchWindow._RunMenuAction(action, item)
    }

    static _RunMenuAction(action, item) {
        SearchWindow._keepOpen := false
        Knowledge.Record(SearchWindow.Input.Value, item.Uid)
        RecentProvider.Remember(item)
        Usage.CountItem(item)
        SearchWindow.SavedQuery := SearchWindow.Input.Value
        SearchWindow.Hide()
        SearchWindow._SafeRun(() => action.OnRun.Call(item))
    }

    static _IsOwnWindow(hwnd) {
        return IsObject(SearchWindow.Gui) && (hwnd = SearchWindow.Gui.Hwnd || hwnd = SearchWindow.Input.Hwnd || hwnd = SearchWindow.List.Hwnd)
    }

    static _OnKeyDown(wParam, lParam, msg, hwnd, modifiers := "") {
        if !SearchWindow._IsOwnWindow(hwnd)
            return
        vk := wParam
        ctrl  := modifiers = "" ? GetKeyState("Ctrl") : (modifiers & 1) != 0
        shift := modifiers = "" ? GetKeyState("Shift") : (modifiers & 2) != 0
        alt   := modifiers = "" ? (msg = 0x104) || GetKeyState("Alt") : (modifiers & 4) != 0
        actions := SearchWindow.Mode = "actions"

        switch vk {
            case 0x0D:                                                      ; Enter
                SearchWindow._Execute(ctrl ? "ctrl" : alt ? "alt" : "")
                return 0
            case 0x1B:                                                      ; Esc
                if (actions && SearchWindow._actionsOnly)
                    SearchWindow.Hide()
                else if actions
                    SearchWindow._CloseActions()
                else
                    SearchWindow.Hide()
                return 0
            case 0x20:                                                      ; 空格: 空的搜索框里 (或光标在最前面时) 进入文件搜索模式
                if (ctrl || alt)
                    return
                if (!shift && !actions && !SearchWindow.FileMode && SearchWindow._AllTextSelected()) {
                    SearchWindow._SetInput("")
                    if SearchWindow._CanEnterFileMode() {
                        SearchWindow._SetFileMode(true)
                        return 0
                    }
                    return
                }
                if (!shift && SearchWindow._CanEnterFileMode()) {
                    SearchWindow._SetFileMode(true)
                    return 0
                }
                if (!shift && AppSettings.General["SpaceToRun"] && SearchWindow.Input.Value != "" && IsObject(SearchWindow.SelectedItem())) {
                    SearchWindow._Execute()
                    return 0
                }
                return
            case 0x26:                                                      ; ↑ / Ctrl+↑ 上一条搜索记录
                if ctrl
                    SearchWindow.RecallHistory(1)
                else
                    SearchWindow.MoveSelection(-1)
                return 0
            case 0x28:                                                      ; ↓ / Ctrl+↓ 下一条搜索记录
                if ctrl
                    SearchWindow.RecallHistory(-1)
                else
                    SearchWindow.MoveSelection(1)
                return 0
            case 0x21:                                                      ; PgUp
                SearchWindow.MoveSelection(-SearchWindow.VisibleRows)
                return 0
            case 0x22:                                                      ; PgDn
                SearchWindow.MoveSelection(SearchWindow.VisibleRows)
                return 0
            case 0x2D:                                                      ; Insert: 标记 / 取消标记 (和 Total Commander 一样), 移到下一行
                if (!actions && !ctrl && !shift && !alt) {
                    SearchWindow.ToggleMark()
                    return 0
                }
                return
            case 0x09:                                                      ; Tab
                SearchWindow._TabKey(ctrl, shift)
                return 0
            case 0x27:                                                      ; →
                if (SearchWindow._CanOpenActions(lParam) && SearchWindow._OpenActions())
                    return 0
                return
            case 0x25:                                                      ; ←
                if (actions && SearchWindow.Input.Value = "") {
                    if SearchWindow._actionsOnly
                        SearchWindow.Hide()
                    else
                        SearchWindow._CloseActions()
                    return 0
                }
                return
            case 0x70:                                                      ; F1
                SearchWindow.Hide()
                App.About()
                return 0
            case 0x72:                                                      ; F3
                SearchWindow._EditSelected()
                return 0
            case 0x71:                                                      ; F2
                SearchWindow.Hide()
                App.OpenPreferences()
                return 0
            case 0x73:                                                      ; F4
                SearchWindow.Hide()
                App.EditSettingsFile()
                return 0
            case 0x2E:                                                      ; Ctrl+Del
                if (ctrl && SearchWindow._CaretAtEnd() && IsObject(item := SearchWindow._TargetItem()) && ResultActions.CanDelete(item)) {
                    SearchWindow._Later(() => SearchWindow.DeleteItem(item))
                    return 0
                }
                return
            case 0x08:                                                      ; Backspace
                if (actions && SearchWindow.Input.Value = "") {
                    if SearchWindow._actionsOnly
                        SearchWindow.Hide()
                    else
                        SearchWindow._CloseActions()
                    return 0
                }
                if (SearchWindow.FileMode && (SearchWindow.Input.Value = "" || !actions && SearchWindow._CaretAtStart())) {
                    SearchWindow._SetFileMode(false)
                    return 0
                }
                if ctrl {                                                   ; Ctrl+Backspace: 删除前一个词 (普通 Edit 控件不支持)
                    SearchWindow._DeletePreviousWord()
                    return 0
                }
                return
        }

        if !ctrl
            return
        switch vk {
            case 0x4E:                                                      ; Ctrl+N
                SearchWindow.MoveSelection(1)
                return 0
            case 0x50:                                                      ; Ctrl+P
                SearchWindow.MoveSelection(-1)
                return 0
            case 0x43:                                                      ; Ctrl+C
                if (shift || SearchWindow._HasTextSelection())
                    return
                SearchWindow._CopySelected()
                return 0
            case 0x4C:                                                      ; Ctrl+L
                if LargeType.Enabled()
                    SearchWindow._ShowLargeType()
                return 0
            case 0x45:
                SearchWindow._EditFileSelected()
                return 0
            case 0xBC:                                                      ; Ctrl+,
                SearchWindow.Hide()
                App.OpenPreferences()
                return 0
        }
        if (vk >= 0x31 && vk <= 0x39) {                                     ; Ctrl+1..9
            SearchWindow._RunVisibleRow(vk - 0x30)
            return 0
        }
    }

    static RecallHistory(step) {
        if (SearchWindow.Mode = "actions" || SearchWindow.FileMode)
            return
        history := Knowledge.History
        current := SearchWindow.Input.Value
        index := SearchWindow.HistoryIndex
        if (index = 0)
            SearchWindow._historyDraft := current
        Loop {
            index += step
            if (index < 0 || index > history.Length)
                return                                                      ; 已经是最早 / 最新的一条
            text := index ? history[index] : SearchWindow._historyDraft
            if (text != current || index = 0)
                break
        }
        SearchWindow._SetInput(text)
        SearchWindow.HistoryIndex := index                                  ; _SetInput 不经过 Change 事件, 这里保持历史位置
    }

    static ToggleMark() {
        item := SearchWindow.SelectedItem()
        if !(IsObject(item) && (item.Kind = "file" || item.Kind = "folder") && item.Arg != "")
            return false
        key := Platform.Identity(item.Arg)
        if SearchWindow.Marked.Has(key)
            SearchWindow.Marked.Delete(key)
        else
            SearchWindow.Marked[key] := item.Arg
        if (SearchWindow.Selected < SearchWindow.Results.Length)
            SearchWindow.MoveSelection(1)
        else
            SearchWindow._Repaint()
        return true
    }

    static IsMarked(item) {
        return SearchWindow.Marked.Count && IsObject(item) && (item.Kind = "file" || item.Kind = "folder") && SearchWindow.Marked.Has(Platform.Identity(item.Arg))
    }

    static _AutoComplete() {
        item := SearchWindow.SelectedItem()
        if (!IsObject(item) || SearchWindow.Mode = "actions")
            return
        text := item.AutoComplete != "" ? item.AutoComplete : item.Kind = "folder" ? RTrim(item.Arg, "\/") A_DirSeparator : item.Title
        SearchWindow._SetInput(text)
    }

    static _TabKey(ctrl := false, shift := false) {
        if (!ctrl && AppSettings.General["TabKey"] = "Next")
            SearchWindow.MoveSelection(shift ? -1 : 1, true)
        else
            SearchWindow._AutoComplete()
    }

    static _CanOpenActions(lParam := 0) => !(lParam & 0x40000000) && SearchWindow._CaretAtEnd() && !SearchWindow._HasTextSelection()

    static _EditFileSelected() {
        item := SearchWindow.SelectedItem()
        if !(IsObject(item) && item.Kind = "file" && IsObject(ActionCatalog.EditorFor(item.Arg)))
            return
        SearchWindow.Hide()
        SearchWindow._SafeRun(() => ActionCatalog.EditFile(item.Arg))
    }

    static _CopySelected() {
        item := SearchWindow.SelectedItem()
        if !IsObject(item)
            return
        SearchWindow.Hide()
        ActionCatalog.CopyText(item.CopyText())
    }

    static _ShowLargeType() {
        item := SearchWindow.SelectedItem()
        text := IsObject(item) ? item.DisplayText() : SearchWindow.Input.Value
        SearchWindow.Hide()
        LargeType.Show(text)
    }

    static _CaretAtStart() {
        selection := Platform.EditSelection(SearchWindow.Input)
        return selection.Start = 0 && selection.End = 0
    }

    static _CaretAtEnd() {
        return Platform.EditCaret(SearchWindow.Input) >= StrLen(SearchWindow.Input.Value)
    }

    static _AllTextSelected() {
        selection := Platform.EditSelection(SearchWindow.Input)
        length := StrLen(SearchWindow.Input.Value)
        return length && selection.Start = 0 && selection.End >= length
    }

    static _HasTextSelection() {
        selection := Platform.EditSelection(SearchWindow.Input)
        return selection.Start != selection.End
    }

    static _DeletePreviousWord() {
        text := SearchWindow.Input.Value
        caret := Platform.EditCaret(SearchWindow.Input)
        before := RegExReplace(SubStr(text, 1, caret), "\S*\s*$")
        SearchWindow.Input.Value := before SubStr(text, caret + 1)
        Platform.SelectEdit(SearchWindow.Input, StrLen(before), StrLen(before))
        SearchWindow._OnInputChange()
    }

    static _OnRowClick(row) {
        if (row >= 1 && SearchWindow.Offset + row <= SearchWindow.Results.Length) {
            SearchWindow.Selected := SearchWindow.Offset + row
            SearchWindow._Repaint()
        }
        SearchWindow.Input.Focus()
    }

    static _OnRowDoubleClick(row) {
        if (row >= 1 && SearchWindow.Offset + row <= SearchWindow.Results.Length) {
            SearchWindow.Selected := SearchWindow.Offset + row
            SearchWindow._Execute()
        }
    }

    static _OnMouseWheel(wParam, lParam, msg, hwnd) {
        if !SearchWindow._IsOwnWindow(hwnd)
            return
        delta := (wParam >> 16) & 0xFFFF
        SearchWindow.MoveSelection(delta >= 0x8000 ? 1 : -1)                ; 高位是有符号的滚动量
        return 0
    }

    static _HideIfInactive() {
        if (SearchWindow._keepOpen || !SearchWindow.IsVisible())
            return
        if SearchWindow.IsActive()
            SearchWindow._focusArmed := true
        else if SearchWindow._focusArmed
            SearchWindow.Hide()
    }
}

#if !WINDOWS
#CSharp
public static void ALTRunLauncherAttachDoubleClick(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapped,
    Keysharp.Builtins.KeysharpFunc callback)
{
    var control = (Eto.Forms.Control)wrapped.Native;
    control.MouseDoubleClick += (_, e) =>
    {
        if (e.Buttons != Eto.Forms.MouseButtons.Primary) return;
        long point = (ushort)(short)System.Math.Round(e.Location.X)
            | ((long)(ushort)(short)System.Math.Round(e.Location.Y) << 16);
        callback.Call(point);
        e.Handled = true;
    };
}

public static void ALTRunLauncherAttachKeys(Keysharp.Builtins.Ks.Clr.ManagedInstance window,
    Keysharp.Builtins.Ks.Clr.ManagedInstance input, Keysharp.Builtins.Ks.Clr.ManagedInstance canvas,
    Keysharp.Builtins.KeysharpFunc callback)
{
    Eto.Forms.Control[] controls = System.OperatingSystem.IsLinux()
        ? [(Eto.Forms.Control)window.Native, (Eto.Forms.Control)input.Native, (Eto.Forms.Control)canvas.Native]
        : [(Eto.Forms.Control)input.Native, (Eto.Forms.Control)canvas.Native];
    var pressed = new System.Collections.Generic.HashSet<Eto.Forms.Keys>();
    var recent = new System.Collections.Generic.Dictionary<(uint, Eto.Forms.Keys), bool>();
    var order = new System.Collections.Generic.Queue<(uint, Eto.Forms.Keys)>();
    foreach (var control in controls)
    {
        control.LostFocus += (_, _) => pressed.Clear();
        control.KeyUp += (_, e) => pressed.Remove(e.Key & Eto.Forms.Keys.KeyMask);
        control.KeyDown += (_, e) =>
        {
            var key = e.Key & Eto.Forms.Keys.KeyMask;
            long vk = ALTRunLauncherVirtualKey(key);
            if (vk == 0) return;
            // GTK can offer one native key to a toplevel twice. Preserve the first decision, including
            // suppression, while retaining separate timestamps for physical key repeats.
            uint stamp = System.OperatingSystem.IsLinux() ? ALTRunLauncherCurrentEventTime() : 0;
            var identity = (stamp, key);
            if (stamp != 0 && recent.TryGetValue(identity, out bool handled))
            {
                e.Handled |= handled;
                return;
            }
            if (stamp != 0)
            {
                // A callback may pump GTK again. Suppress a nested duplicate while it decides.
                recent[identity] = true;
                order.Enqueue(identity);
                if (order.Count > 32) recent.Remove(order.Dequeue());
            }
            if (e.Handled) return;
            long repeat = pressed.Add(key) ? 1 : 0x40000001;
            long modifiers = ((e.Modifiers & Eto.Forms.Keys.Control) != 0 ? 1 : 0)
                | ((e.Modifiers & Eto.Forms.Keys.Shift) != 0 ? 2 : 0)
                | ((e.Modifiers & Eto.Forms.Keys.Alt) != 0 ? 4 : 0);
            object result = callback.Call(vk, repeat, (modifiers & 4) != 0 ? 0x104L : 0x100L, modifiers);
            if (result != null && (result is not string text || text.Length != 0))
                e.Handled = true;
            if (stamp != 0) recent[identity] = e.Handled;
        };
    }
}

[System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_get_current_event_time")]
private static extern uint ALTRunLauncherCurrentEventTime();

private static long ALTRunLauncherVirtualKey(Eto.Forms.Keys key)
{
    if (key >= Eto.Forms.Keys.A && key <= Eto.Forms.Keys.Z)
        return 'A' + (key - Eto.Forms.Keys.A);
    if (key >= Eto.Forms.Keys.D0 && key <= Eto.Forms.Keys.D9)
        return '0' + (key - Eto.Forms.Keys.D0);
    if (key >= Eto.Forms.Keys.F1 && key <= Eto.Forms.Keys.F4)
        return 0x70 + (key - Eto.Forms.Keys.F1);
    return key switch
    {
        Eto.Forms.Keys.Backspace => 0x08,
        Eto.Forms.Keys.Tab => 0x09,
        Eto.Forms.Keys.Enter => 0x0D,
        Eto.Forms.Keys.Escape => 0x1B,
        Eto.Forms.Keys.Space => 0x20,
        Eto.Forms.Keys.PageUp => 0x21,
        Eto.Forms.Keys.PageDown => 0x22,
        Eto.Forms.Keys.Left => 0x25,
        Eto.Forms.Keys.Up => 0x26,
        Eto.Forms.Keys.Right => 0x27,
        Eto.Forms.Keys.Down => 0x28,
        Eto.Forms.Keys.Insert => 0x2D,
        Eto.Forms.Keys.Delete => 0x2E,
        Eto.Forms.Keys.Comma => 0xBC,
        _ => 0
    };
}
#EndCSharp
#endif

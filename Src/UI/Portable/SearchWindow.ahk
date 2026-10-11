; SearchWindow.ahk - Portable launcher UI with provider actions, history and keyboard navigation.

class SearchWindow {
    static _visible := false, _focusArmed := false, _imageList := 0
    static Gui := "", Input := "", List := "", Separator := ""
    static Results := [], Selected := 0, Offset := 0
    static Mode := "results"                        ; results = 搜索结果; actions = 操作面板
    static HighlightText := ""                      ; 搜索结果标题里高亮和它匹配的字 (Highlight 颜色)
    static FileMode := false                        ; 文件搜索模式: 空的搜索框里按空格进入, 只搜文件
    static ActionSource := "", SavedQuery := "", AllActions := []
    static _actionsOnly := false                                            ; 直接打开的操作面板 (选中内容的操作): Esc / ← 关掉窗口
    static HistoryIndex := 0                         ; 正在看第几条搜索记录 (Knowledge.History, 1 = 最近), 0 = 没有在翻
    static Marked := Map()                           ; Insert 标记的文件 / 文件夹: 平台路径标识 -> 路径
    static _historyDraft := ""                       ; 开始翻记录之前输入框里的文字, Ctrl+↓ 翻回来时恢复
    static Width := 0, Padding := 0, InputHeight := 0, RowHeight := 0, IconSize := 0, VisibleRows := 8
    static SelectedRadius := 0
    static _searchTimer := "", _hideTimer := ""
    static _shownRows := -1                                                 ; 窗口当前按几行结果的高度显示
    static _tip := ""                                                       ; 这次显示时的使用提示 (HelpProvider.NextTip)
    static LastArea := "", HiddenAt := 0                                    ; 上次隐藏时所在屏幕的工作区和时间 (Hud 用)
    static _last := ""                                                      ; 上次隐藏时的搜索 {Text, FileMode, Selected} (KeepLastQuery)
    static _keepOpen := false                        ; 右键菜单 / 删除确认期间不因失去焦点而隐藏

    static Create() {
        if IsObject(SearchWindow.Gui)
            SearchWindow.Gui.Destroy()
        SearchWindow.Width := Max(480, AppSettings.Appearance["Width"])
        SearchWindow.VisibleRows := Max(1, Min(9, AppSettings.Appearance["VisibleRows"]))
        SearchWindow.Padding := 12, SearchWindow.InputHeight := 42, SearchWindow.RowHeight := 30
        SearchWindow._visible := false, SearchWindow._focusArmed := false
        g := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox", App.Name)
        g.MarginX := 0, g.MarginY := 0
        g.SetFont("s12", ThemeManager.FontName())
        searchBox := g.AddEdit("x12 y12 w" (SearchWindow.Width - 24) " r1 -Multi -WantReturn")
        searchBox.SetCue(I18n.T("Search.Placeholder"))
        searchBox.OnEvent("Change", (*) => SearchWindow._OnInputChange())
        list := g.AddListView("x12 y58 w" (SearchWindow.Width - 24) " h" (SearchWindow.RowHeight + 4) " Hidden -Hdr -Multi Report", ["Result", "Details", "Key"])
        list.SetFont("s10")
        list.ModifyCol(1, Round((SearchWindow.Width - 92) * 0.48))
        list.ModifyCol(2, Round((SearchWindow.Width - 92) * 0.52))
        list.ModifyCol(3, 64)
        SearchWindow._imageList := IL_Create(16, 16)
        list.SetImageList(SearchWindow._imageList, 1)
        list.OnEvent("Click", (ctrl, row) => SearchWindow._OnRowClick(row))
        list.OnEvent("DoubleClick", (ctrl, row) => SearchWindow._OnRowDoubleClick(row))
        list.OnEvent("ContextMenu", (ctrl, row, right, x, y) => SearchWindow._OnRowContextMenu(row, x, y))
        g.OnEvent("Close", (*) => (SearchWindow.Hide(), true))
        g.OnEvent("Escape", (*) => SearchWindow.Hide())
        SearchWindow.Gui := g, SearchWindow.Input := searchBox, SearchWindow.List := list
        for control in [searchBox, list] {
            control.OnMessage(0x100, (ctrl, w, l, msg) => SearchWindow._OnKeyDown(w, l, msg, ctrl.Hwnd))
            control.OnMessage(0x104, (ctrl, w, l, msg) => SearchWindow._OnKeyDown(w, l, msg, ctrl.Hwnd))
            control.OnMessage(0x20A, (ctrl, w, l, msg) => SearchWindow._OnMouseWheel(w, l, msg, ctrl.Hwnd))
        }
        g.Show("Hide w" SearchWindow.Width " h" SearchWindow._WindowHeight(0))
        SearchWindow._hideTimer := () => SearchWindow._HideIfInactive()
    }

    static IsVisible() {
        return IsObject(SearchWindow.Gui) && SearchWindow._visible
    }

    static IsActive() {
        return IsObject(SearchWindow.Gui) && WinActive("ahk_id " SearchWindow.Gui.Hwnd) ? true : false
    }

    static _showing := false
    static Show(text := "", typeAhead := true) {
        if (!IsObject(SearchWindow.Gui) || SearchWindow._showing)
            return
        SearchWindow._showing := true
        try SearchWindow._Show(text)
        finally SearchWindow._showing := false
    }

    static _Show(text) {
        App.RememberActiveWindow()
        SearchWindow._actionsOnly := false, SearchWindow.Marked := Map()
        Usage.Count("Show")
        last := SearchWindow._last
        restore := text = "" && AppSettings.General["KeepLastQuery"] && IsObject(last) && last.Text != ""
        SearchWindow.Mode := "results", SearchWindow.FileMode := restore ? last.FileMode : false
        SearchWindow._tip := AppSettings.General["ShowTips"] ? HelpProvider.NextTip() : ""
        SearchWindow._UpdateCueBanner()
        SearchWindow.HistoryIndex := 0
        SearchWindow._SetInput(restore ? last.Text : text)
        if restore
            SearchWindow.MoveSelection(last.Selected - SearchWindow.Selected)
        appearance := AppSettings.Appearance
        pos := SearchWindow.Place(SearchWindow._ScreenArea(appearance["ShowOn"]), SearchWindow.Width
            , SearchWindow._WindowHeight(SearchWindow.VisibleRows), appearance["RememberPosition"] ? appearance["Position"] : "")
        SearchWindow.Gui.Show("x" pos.X " y" pos.Y " w" SearchWindow.Width " h" SearchWindow._WindowHeight(SearchWindow._VisibleCount()))
        SearchWindow._visible := true, SearchWindow._focusArmed := false
        SearchWindow._shownRows := SearchWindow._VisibleCount()
        SearchWindow.Input.Focus()
        length := StrLen(SearchWindow.Input.Value)
        Platform.SelectEdit(SearchWindow.Input, restore ? 0 : length, length)
        if AppSettings.General["HideOnDeactivate"]
            SetTimer(SearchWindow._hideTimer, 200)
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
        return Win.WorkAreaAtMouse()
    }

    static _OnMoved(*) {
        if (!SearchWindow.IsVisible() || !AppSettings.Appearance["RememberPosition"])
            return
        SearchWindow.Gui.GetPos(&x, &y)
        area := Win.WorkAreaAt(x + SearchWindow.Width // 2, y + SearchWindow.InputHeight // 2)
        AppSettings.Appearance["Position"] := SearchWindow.RelativePosition(area, SearchWindow.Width, x, y)
    }

    static Hide() {
        if IsObject(SearchWindow._hideTimer)
            SetTimer(SearchWindow._hideTimer, 0)
        if SearchWindow.IsVisible() {
            SearchWindow._OnMoved()
            SearchWindow.Gui.GetPos(&x, &y, &w, &h)
            SearchWindow.LastArea := Win.WorkAreaAt(x + w // 2, y + h // 2), SearchWindow.HiddenAt := A_TickCount
            SearchWindow._RememberQuery()
            SearchWindow._visible := false
            SearchWindow.Gui.Hide()
        }
        LargeType.Close()
    }

    static _RememberQuery() {
        actions := (SearchWindow.Mode = "actions")
        SearchWindow._last := {Text: actions ? SearchWindow.SavedQuery : SearchWindow.Input.Value
                             , FileMode: SearchWindow.FileMode, Selected: actions ? 1 : Max(1, SearchWindow.Selected)}
    }

    static Toggle() {
        if (SearchWindow.IsVisible() && WinActive("ahk_id " SearchWindow.Gui.Hwnd))
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
        results := SearchWindow.FileMode ? ProviderRegistry.SearchFiles(text) : ProviderRegistry.Search(text)
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
            . (SearchWindow.FileMode ? " (files)" : "") " results " count " gen " SearchWindow._searchGen " list rows before " SearchWindow.List.GetCount())
        if (SearchWindow._recent.Length > 10)
            SearchWindow._recent.RemoveAt(1)
    }
    static _LogBlankRow(row, count) {
        if (SearchWindow._blankLogged || !Logger.Enabled)
            return
        SearchWindow._blankLogged := true
        Logger.Warn("SearchWindow: row " row " has no result (results " count ", offset " SearchWindow.Offset ", list rows " SearchWindow.List.GetCount()
            . ", window rows " SearchWindow._shownRows ", mode " SearchWindow.Mode ", input '" SubStr(SearchWindow.Input.Value, 1, 30) "')")
        for entry in SearchWindow._recent
            Logger.Debug("  recent results: " entry)
    }

    static _VisibleCount() {
        return Min(SearchWindow.Results.Length, SearchWindow.VisibleRows)
    }

    static _WindowHeight(visibleCount) {
        return 70 + (visibleCount ? visibleCount * SearchWindow.RowHeight + 12 : 0)
    }

    static _Layout() {
        count := SearchWindow._VisibleCount()
        list := SearchWindow.List
        if (list.GetCount() != count) {
            list.Delete()
            Loop count
                list.Add("", "", "", "")
        }
        list.Move(, , , Max(SearchWindow.RowHeight + 4, count * SearchWindow.RowHeight))
        list.Visible := count > 0
        SearchWindow._Repaint()
        if (SearchWindow.IsVisible() && SearchWindow._shownRows != count) {
            SearchWindow.Gui.Show("NA w" SearchWindow.Width " h" SearchWindow._WindowHeight(count))
            SearchWindow._shownRows := count
        }
    }

    static _Repaint() {
        list := SearchWindow.List
        if !IsObject(list)
            return
        count := SearchWindow._VisibleCount()
        Loop count {
            index := SearchWindow.Offset + A_Index
            item := SearchWindow.Results[index]
            title := (SearchWindow.IsMarked(item) ? Chr(0x2713) " " : item.Pinned ? Chr(0x2022) " " : "") item.Title
            icon := IconCache.AddTo(SearchWindow._imageList, item.Icon)
            list.Modify(A_Index, "Icon" icon, title, item.Subtitle, "Ctrl+" A_Index)
        }
        list.Modify(0, "-Select -Focus")
        row := SearchWindow.Selected - SearchWindow.Offset
        if (row >= 1 && row <= count)
            list.Modify(row, "Select Focus Vis")
        list.Redraw()
    }

    static SelectedItem() {
        if (SearchWindow.Selected < 1 || SearchWindow.Selected > SearchWindow.Results.Length)
            return ""
        return SearchWindow.Results[SearchWindow.Selected]
    }

    static MoveSelection(step) {
        count := SearchWindow.Results.Length
        if !count
            return
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
            source := SearchWindow.ActionSource
            Knowledge.Record(SearchWindow.SavedQuery, source.Uid)
            RecentProvider.Remember(source)
            Usage.CountItem(source)
            SearchWindow.Marked := Map()
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
            actions := ActionCatalog.ListForMany(paths)
        } else
            actions := ActionCatalog.ListFor(item)
        if !actions.Length
            return false
        SearchWindow.SavedQuery := SearchWindow.Input.Value
        SearchWindow.ActionSource := item
        SearchWindow.AllActions := actions
        SearchWindow.Mode := "actions"
        SearchWindow.Input.SetCue(I18n.T("Search.ActionsFor", item.Title))
        SearchWindow._SetInput("")
        return true
    }

    static _CloseActions() {
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
            text := (SearchWindow._tip != "") ? SearchWindow._tip : I18n.T("Search.Placeholder")
        SearchWindow.Input.SetCue(text)
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
        if (IsObject(item) && !isFallback && ActionCatalog.CanEdit(item))
            return SearchWindow._Later(() => SearchWindow.EditItem(item))
        query := Trim(SearchWindow._CurrentQuery())
        if (query != "" && (!IsObject(item) || isFallback))                 ; 没有结果: 用输入的文字新建一条命令
            return SearchWindow._Later(() => SearchWindow.NewCommand(query))
        App.Notify(I18n.T("Search.NotEditable"))
    }

    static EditItem(item) {
        query := SearchWindow._CurrentQuery()
        SearchWindow.Hide()
        SearchWindow._SafeRun(() => ActionCatalog.EditItem(item))
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
        answer := MsgBox(ActionCatalog.DeletePrompt(item), App.Name, "YesNo Icon! Default2" (wasVisible ? " Owner" SearchWindow.Gui.Hwnd : ""))
        SearchWindow._keepOpen := false
        if (answer = "Yes")
            SearchWindow._SafeRun(() => ActionCatalog.DeleteItem(item))
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
        if (!IsObject(item) || !item.Valid && !ActionCatalog.CanEdit(item))
            return
        if (SearchWindow.Mode = "actions")                                  ; 操作面板里右键 = 执行这一项
            return SearchWindow._Execute()
        contextMenu := Menu()
        for action in ActionCatalog.ListFor(item) {
            label := StrReplace(action.Title, "&", "&&") (action.Subtitle != "" ? "`t" action.Subtitle : "")
            contextMenu.Add(label, SearchWindow._MenuHandler(action, item))
            if (A_Index = 1)
                contextMenu.Default := label
        }
        Critical("Off")
        SearchWindow.List.Modify(0, "-Select -Focus")
        SearchWindow._Repaint()
        SearchWindow.List.Redraw()
        SearchWindow._keepOpen := true
        contextMenu.Show(x, y)
        SearchWindow._keepOpen := false
        if (SearchWindow.IsVisible() && !WinActive("ahk_id " SearchWindow.Gui.Hwnd))
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

    static _OnKeyDown(wParam, lParam, msg, hwnd) {
        if !SearchWindow._IsOwnWindow(hwnd)
            return
        vk := wParam
        ctrl  := GetKeyState("Ctrl")
        shift := GetKeyState("Shift")
        alt   := (msg = 0x104) || GetKeyState("Alt")
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
                SearchWindow._AutoComplete()
                return 0
            case 0x27:                                                      ; →
                if (SearchWindow._CaretAtEnd() && SearchWindow._OpenActions())
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
                if (ctrl && SearchWindow._CaretAtEnd() && IsObject(item := SearchWindow._TargetItem()) && ActionCatalog.CanDelete(item)) {
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
                SearchWindow._ShowLargeType()
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

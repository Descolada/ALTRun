; PreferencesWindow.ahk - Portable settings and command editors using toolkit events.

class PreferencesWindow {
    static Gui := "", Working := "", Pages := [], Binds := [], PageList := ""
    static _lists := Map()                                                  ; 列表页的设置路径 (例如 "CustomCommands") -> 加入 / 编辑项目的方法
    static PageKeys := ["Prefs.Page.General", "Prefs.Page.Window", "Prefs.Page.Appearance", "Prefs.Page.Features", "Prefs.Page.Applications"
        , "Prefs.Page.FileSearch", "Prefs.Page.Commands", "Prefs.Page.Snippets", "Prefs.Page.Clipboard", "Prefs.Page.WebSearch", "Prefs.Page.Calculator"
        , "Prefs.Page.Scripts", "Prefs.Page.Hotkeys", "Prefs.Page.Advanced"]
    static _page := 0, _y := 0
    static _dirty := false, _ready := false, ApplyButton := ""
    static ContentX := 190, ContentW := 560, LabelW := 190
    static WidthS := 70, WidthM := 220, ButtonW := 200, ButtonH := 26       ; WidthL = 整个控件列 (_InputW)
    static WidthK := 150                                                    ; 热键框 ("K")
    static _pairX := 0, _pairFirstW := 0, _pairSecondW := 0, _pairSizes := ["", ""]
    static ButtonY := 619                                                   ; 底部按钮的位置; 页面内容要在它上面 (y < ButtonY - 10)
    static LabelMax := 250                                                  ; 左列最宽多少, 再长的标签换行
    static _positionReset := false
    static _pageKey := "", _wider := Map()                                  ; 正在建的页; 标签放不下的页 -> 需要的左列宽度
    static _labelWidths := Map()                                            ; "语言 页" -> 加宽后的左列宽度 (打开过一次就记住)

    static Show(pageIndex := 1, x := "", y := "") {
        if IsObject(PreferencesWindow.Gui) {
            if !IsInteger(pageIndex)
                pageIndex := PreferencesWindow._PageIndex(pageIndex)
            PreferencesWindow._SelectRow(Max(1, Min(pageIndex, PreferencesWindow.Pages.Length)))
            PreferencesWindow.Gui.Show()
            return
        }
        PreferencesWindow.Working := PreferencesWindow.DeepCopy(AppSettings.Data)
        PreferencesWindow.Pages := [], PreferencesWindow.Binds := [], PreferencesWindow._lists := Map()
        PreferencesWindow._dirty := false, PreferencesWindow._ready := false, PreferencesWindow._page := 0
        PreferencesWindow._positionReset := false
        g := Gui("-MinimizeBox", I18n.T("Prefs.Title"))
        g.SetFont("s9", ThemeManager.FontName())
        PreferencesWindow.Gui := g
        pageList := g.AddListView("x12 y12 w160 h" (PreferencesWindow.ButtonY - 24) " -Hdr -Multi Report", [""])
        PreferencesWindow.PageList := pageList
        PreferencesWindow._BuildPages()
        for page in PreferencesWindow.Pages
            pageList.Add("", page.Name)
        pageList.ModifyCol(1, 154)
        pageList.OnEvent("ItemSelect", (ctrl, row, selected) => selected ? PreferencesWindow.SelectPage(row) : "")
        pageList.OnEvent("Click", (ctrl, row) => row ? PreferencesWindow.SelectPage(row) : "")
        g.AddButton("x190 y" PreferencesWindow.ButtonY " w85", I18n.T("Prefs.Help")).OnEvent("Click", (*) => PreferencesWindow.Help())
        g.AddButton("x475 yp w85 Default", "OK").OnEvent("Click", (*) => PreferencesWindow.OK())
        g.AddButton("x570 yp w85", I18n.T("Prefs.Cancel")).OnEvent("Click", (*) => PreferencesWindow.Cancel())
        PreferencesWindow.ApplyButton := g.AddButton("x665 yp w85 Disabled", I18n.T("Prefs.Apply"))
        PreferencesWindow.ApplyButton.OnEvent("Click", (*) => PreferencesWindow.Apply())
        g.OnEvent("Close", (*) => PreferencesWindow.Cancel())
        g.OnEvent("Escape", (*) => PreferencesWindow.Cancel())
        if !IsInteger(pageIndex)
            pageIndex := PreferencesWindow._PageIndex(pageIndex)
        PreferencesWindow._SelectRow(Max(1, Min(pageIndex, PreferencesWindow.Pages.Length)))
        g.Show((IsInteger(x) && IsInteger(y) ? "x" x " y" y " " : "") "w765 h" (PreferencesWindow.ButtonY + 41))
        pageList.Focus()
        PreferencesWindow._ready := true
    }

    static _SelectRow(index) {
        PreferencesWindow.SelectPage(index)
        PreferencesWindow.PageList.Modify(index, "Select Focus Vis")
    }

    static _PageIndex(nameKey) {
        for index, page in PreferencesWindow.Pages
            if (page.Key = nameKey)
                return index
        return 1
    }

    static MarkDirty(force := false) {
        if ((!PreferencesWindow._ready && !force) || PreferencesWindow._dirty)
            return
        PreferencesWindow._dirty := true
        try PreferencesWindow.ApplyButton.Enabled := true
    }

    static SelectPage(pageIndex) {
        if (pageIndex < 1 || pageIndex > PreferencesWindow.Pages.Length)
            return
        PreferencesWindow._page := pageIndex
        for index, page in PreferencesWindow.Pages
            for ctrl in page.Controls
                ctrl.Visible := index = pageIndex
    }

    static Close() {
        HotkeyBox.CancelActive()                                            ; 正在录制热键时关窗口: 先结束录制, 恢复 ALTRun 的热键
        if IsObject(PreferencesWindow.Gui)
            PreferencesWindow.Gui.Destroy()
        PreferencesWindow.Gui := "", PreferencesWindow._lists := Map()
    }

    static AddCommands(paths) {
        PreferencesWindow.Show("Prefs.Page.Commands")
        list := PreferencesWindow._lists["CustomCommands"]
        if (paths.Length = 1) {
            existing := CustomCommandProvider.FindByTarget(paths[1], list.Items)
            if IsObject(existing) {
                App.Notify(I18n.T("Custom.Exists", existing["Title"]), 2500)
                list.Edit.Call(existing)
            } else {
                list.Insert.Call(CustomCommandProvider.FromPath(paths[1]))
            }
            return
        }
        added := 0, skipped := 0
        for target in paths {
            if IsObject(CustomCommandProvider.FindByTarget(target, list.Items)) {
                skipped += 1
                continue
            }
            list.Append.Call(CustomCommandProvider.FromPath(target))
            added += 1
        }
        App.Toast(I18n.T("Custom.AddedMany", added) (skipped ? " " I18n.T("Custom.SkippedExisting", skipped) : ""), 3000)
    }

    static OK() {
        if PreferencesWindow._dirty
            PreferencesWindow.Save(false)
        else
            PreferencesWindow.Close()
    }

    static Apply() {
        if PreferencesWindow._dirty
            PreferencesWindow.Save(true)
    }

    static Cancel() {
        if (PreferencesWindow._dirty && MsgBox(I18n.T("Prefs.DiscardChanges"), I18n.T("Prefs.Title"), "YesNo Icon? Default2 Owner" PreferencesWindow.Gui.Hwnd) != "Yes")
            return true
        PreferencesWindow.Close()
        return false
    }

    static Help() {
        page := PreferencesWindow.Pages[Max(1, PreferencesWindow._page)]
        ActionCatalog.OpenUrl(HelpProvider.WikiPage(page.Wiki))
    }

    static WikiPage(nameKey) {
        static pages := Map("Prefs.Page.Window", "Usage", "Prefs.Page.Appearance", "Themes", "Prefs.Page.Features", "Usage", "Prefs.Page.FileSearch", "File-Search"
                          , "Prefs.Page.Commands", "Commands-and-Snippets", "Prefs.Page.Snippets", "Commands-and-Snippets"
                          , "Prefs.Page.Clipboard", "Commands-and-Snippets", "Prefs.Page.WebSearch", "Usage", "Prefs.Page.Calculator", "Extensions", "Prefs.Page.Scripts", "Extensions"
                          , "Prefs.Page.Hotkeys", "Extensions", "Prefs.Page.QuickSwitch", "Extensions", "Prefs.Page.QSPanel", "Extensions", "Prefs.Page.DateStamp", "Extensions"
                          , "Prefs.Page.FileIndex", "File-Search", "Prefs.Page.Usage", "Usage")
        return pages.Has(nameKey) ? pages[nameKey] : "Configuration"
    }

    static ParseArgs(args) {
        value(i) => (args.Length >= i && IsInteger(args[i])) ? Integer(args[i]) : ""
        page := value(2)
        return {Page: (page = "") ? 1 : page, X: value(3), Y: value(4)}
    }

    static Save(reopen := true) {
        for bind in PreferencesWindow.Binds
            PreferencesWindow.SetPath(PreferencesWindow.Working, bind.Path, bind.Read.Call())
        general := PreferencesWindow.Working["General"]
        appearance := PreferencesWindow.Working["Appearance"]
        appearance["VisibleRows"] := Max(1, Min(appearance["VisibleRows"], 9))
        appearance["Width"] := Max(400, appearance["Width"])
        if (general["Hotkey"] = "")
            general["Hotkey"] := "!Space"
        clash := PreferencesWindow.DuplicateHotkey(PreferencesWindow._GlobalHotkeys(PreferencesWindow.Working))
        if (IsObject(clash) && MsgBox(I18n.T("Prefs.HotkeyClash", HotkeyBox.Label(clash.Key), clash.First, clash.Second)
                , I18n.T("Prefs.Title"), "YesNo Icon! Default2 Owner" PreferencesWindow.Gui.Hwnd) != "Yes")
            return
        if !PreferencesWindow._positionReset                                ; 打开偏好设置之后拖动过搜索窗口: 用新的位置
            appearance["Position"] := PreferencesWindow.DeepCopy(AppSettings.Appearance["Position"])

        AppSettings.Data := PreferencesWindow.Working
        if !AppSettings.Save()
            return
        page := PreferencesWindow._page
        PreferencesWindow.Gui.GetPos(&x, &y)
        PreferencesWindow.Close()
        App.Restart(reopen ? "-Preferences " page " " x " " y : "-Reloaded")
    }

    static _BuildPages() {
        PreferencesWindow._BuildGeneral()
        PreferencesWindow._BuildWindow()
        PreferencesWindow._BuildAppearance()
        PreferencesWindow._BuildFeatures()
        PreferencesWindow._BuildApplications()
        PreferencesWindow._BuildFileSearch()
        PreferencesWindow._BuildCommands()
        PreferencesWindow._BuildSnippets()
        PreferencesWindow._BuildClipboard()
        PreferencesWindow._BuildWebSearch()
        PreferencesWindow._BuildCalculator()
        PreferencesWindow._BuildScripts()
        PreferencesWindow._BuildHotkeys()
        PreferencesWindow._BuildAdvanced()
    }

    static _BuildGeneral() {
        PreferencesWindow._BeginPage("Prefs.Page.General", 140)
        PreferencesWindow._Field("General.Hotkey", "Prefs.Hotkey", "M", "hotkey")
        PreferencesWindow._Field("General.SecondaryHotkey", "Prefs.SecondaryHotkey", "M", "hotkey")
        PreferencesWindow._Choice("General.Language", "Prefs.Language", PreferencesWindow._LanguageValues(), PreferencesWindow._LanguageLabels())
        if (Platform.IsWindows || Platform.IsLinux)
            PreferencesWindow._Check("General.LaunchAtLogin", "Prefs.LaunchAtLogin")
        PreferencesWindow._Check("General.ShowTrayIcon", "Prefs.ShowTrayIcon")
        PreferencesWindow._Check("General.SaveLog", "Prefs.SaveLog")
        PreferencesWindow._Field("General.FileManager", "Prefs.FileManager", "L")
    }

    static _BuildWindow() {
        PreferencesWindow._BeginPage("Prefs.Page.Window", 140)
        PreferencesWindow._Check("General.HideOnDeactivate", "Prefs.HideOnDeactivate")
        PreferencesWindow._Check("General.KeepLastQuery", "Prefs.KeepLastQuery")
        PreferencesWindow._Check("General.SpaceToRun", "Prefs.SpaceToRun")
        PreferencesWindow._Choice("General.TabKey", "Prefs.TabKey", ["Complete", "Next"], [I18n.T("Prefs.TabKey.Complete"), I18n.T("Prefs.TabKey.Next")])
        PreferencesWindow._Check("General.ShowTips", "Prefs.ShowTips")
        PreferencesWindow._Field("Features.Recent.RecentCount", "Prefs.RecentCount", "S", "number")
        PreferencesWindow._Field("General.HistorySize", "Prefs.HistorySize", "S", "number")
    }

    static _BuildAppearance() {
        PreferencesWindow._BeginPage("Prefs.Page.Appearance", 140)
        themes := ThemeManager.Names(), labels := []
        for name in themes
            labels.Push(PreferencesWindow._ThemeLabel(name))
        PreferencesWindow._Choice("Appearance.Theme", "Prefs.Section.Theme", themes, labels)
        PreferencesWindow._Choice("Appearance.Density", "Prefs.Density", ThemeManager.Densities
            , [I18n.T("Prefs.Density.Comfortable"), I18n.T("Prefs.Density.Normal"), I18n.T("Prefs.Density.Compact")])
        PreferencesWindow._Field("Appearance.Placeholder", "Prefs.Placeholder", "M")
        PreferencesWindow._Field("Appearance.Width", "Prefs.Width", "S", "number")
        PreferencesWindow._Field("Appearance.VisibleRows", "Prefs.VisibleRows", "S", "number")
        PreferencesWindow._Choice("Appearance.ShowOn", "Prefs.ShowOn", ["Mouse", "Primary", "Active"]
            , [I18n.T("Prefs.ShowOn.Mouse"), I18n.T("Prefs.ShowOn.Primary"), I18n.T("Prefs.ShowOn.Active")])
        PreferencesWindow._Check("Appearance.RememberPosition", "Prefs.RememberPosition")
        PreferencesWindow._Button("Prefs.ResetPosition", (button, *) => PreferencesWindow._ResetPosition(button))
    }

    static _ResetPosition(button) {
        PreferencesWindow.Working["Appearance"]["Position"] := AppSettings.Defaults()["Appearance"]["Position"]
        PreferencesWindow._positionReset := true
        PreferencesWindow.MarkDirty()
        button.Enabled := false
    }

    static _LanguageValues() {
        values := ["auto"]
        for language in I18n.Languages()
            values.Push(language[1])
        return values
    }

    static _LanguageLabels() {
        labels := [I18n.T("Prefs.Language.auto")]
        for language in I18n.Languages()
            labels.Push(language[2])
        return labels
    }

    static _ThemeLabel(themeName) {
        label := I18n.T("Theme." themeName)
        return (label = "Theme." themeName) ? themeName : label
    }

    static _ThemeGallery(path, themes, height) {
        list := PreferencesWindow._Add("ListView", "w" PreferencesWindow.ContentW " h" height " Report -Multi -Hdr", ["Theme"])
        selected := 1
        for index, name in themes {
            list.Add("", PreferencesWindow._ThemeLabel(name))
            if (name = PreferencesWindow.GetPath(PreferencesWindow.Working, path))
                selected := index
        }
        list.Modify(selected, "Select Focus Vis")
        list.OnEvent("ItemSelect", (ctrl, row, chosen) => chosen ? PreferencesWindow.MarkDirty() : "")
        PreferencesWindow._Bind(path, () => themes[list.GetNext() || selected])
        return list
    }

    static _CopyTheme(gallery, themes) {
        source := themes[gallery.GetNext() || 1]
        theme := ThemeManager.Resolve(source)
        answer := InputBox(I18n.T("Prefs.CopyThemePrompt"), I18n.T("Prefs.CopyTheme"), "w340 h130", source " Custom")
        name := Trim(RegExReplace(answer.Value, '[\\/:*?"<>|]'))
        if (answer.Result != "OK" || name = "")
            return
        destination := Platform.Join(ThemeManager.UserDir, name ".json")
        if (FileExist(destination) && MsgBox(I18n.T("Prefs.ThemeExists", name), App.Name, "YesNo Default2") != "Yes")
            return
        DirCreate(ThemeManager.UserDir)
        JSON.WriteFile(destination, theme)
        Platform.Edit(destination)
    }

    static _BuildFeatures() {
        PreferencesWindow._BeginPage("Prefs.Page.Features", 140)
        features := ["Applications", "CustomCommands", "Snippets", "Calculator", "WebSearch", "Recent", "FileSearch", "Scripts", "Terminal", "System", "Help", "Clipboard", "Windows", "Bookmarks", "LargeType"]
        top := PreferencesWindow._y
        for index, feature in features
            PreferencesWindow._FeatureCheck(feature, PreferencesWindow.ContentX + Mod(index - 1, 2) * 280, top + ((index - 1) // 2) * 30)
        PreferencesWindow._y := top + Ceil(features.Length / 2) * 30 + 8
        PreferencesWindow._Check("Features.Windows.InDefaultResults", "Prefs.ShowInNormal", , , "Prefs.Feature.Windows")
        PreferencesWindow._Field("Features.Windows.Keyword", "Prefs.Feature.Windows", "M")
        PreferencesWindow._Check("Features.Bookmarks.InDefaultResults", "Prefs.ShowInNormal", , , "Prefs.Feature.Bookmarks")
        PreferencesWindow._Field("Features.Bookmarks.Keyword", "Prefs.Feature.Bookmarks", "M")
        PreferencesWindow._Field("Features.Terminal.Prefix", "Prefs.TerminalPrefix", "S")
        PreferencesWindow._Field("Features.Terminal.Shell", "Prefs.TerminalShell", "M")
    }

    static _FeatureCheck(feature, x, y) {
        PreferencesWindow._y := y
        path := "Features." feature ".Enabled"
        control := PreferencesWindow._Add("Checkbox", "x" x " w265", I18n.T("Prefs.Feature." feature))
        control.Value := PreferencesWindow.GetPath(PreferencesWindow.Working, path) ? 1 : 0
        PreferencesWindow._Bind(path, () => control.Value)
    }

    static _BuildApplications() {
        PreferencesWindow._BeginPage("Prefs.Page.Applications", 140)
        PreferencesWindow._Lines("Features.Applications.Folders", "Prefs.AppFolders", 4)
        PreferencesWindow._Csv("Features.Applications.FileTypes", "Prefs.AppFileTypes", "L")
        PreferencesWindow._Field("Features.Applications.Exclude", "Prefs.AppExclude", "L")
        PreferencesWindow._Field("Features.Applications.Depth", "Prefs.AppDepth", "S", "number")
        PreferencesWindow._Check("Features.Applications.MatchPinyin", "Prefs.MatchPinyin")
        PreferencesWindow._Button("Prefs.RebuildIndex", (*) => App.RebuildIndex())
    }

    static _BuildFileSearch() {
        PreferencesWindow._BeginPage("Prefs.Page.FileSearch", 140)
        PreferencesWindow._Lines("Features.FileSearch.ScopeFolders", "Prefs.ScopeFolders", 4)
        PreferencesWindow._Csv("Features.FileSearch.Keywords", "Prefs.FileKeywords", "M")
        PreferencesWindow._Field("Features.FileSearch.ScopeDepth", "Prefs.ScopeDepth", "S", "number")
        PreferencesWindow._Field("Features.FileSearch.MaxResults", "Prefs.FileMaxResults", "S", "number")
        PreferencesWindow._Check("Features.FileSearch.SpacePrefix", "Prefs.SpacePrefix")
        PreferencesWindow._Button("Prefs.RebuildIndex", (*) => App.RebuildIndex())
    }

    static _BuildCommands() {
        PreferencesWindow._BeginPage("Prefs.Page.Commands")
        PreferencesWindow._List("CustomCommands", 540
            , [["Prefs.Col.Title", "Title", 140], ["Prefs.Col.Type", "Type", 70], ["Prefs.Col.Target", "Target", 190], ["Prefs.Col.Keyword", "Keyword", 70], ["Prefs.Col.Status", "Status", 70]]
            , CustomCommandProvider.EditorFields(), () => CustomCommandProvider.NewCommand()
            , (item, roots) => CustomCommandProvider.CheckTarget(item, roots))
        PreferencesWindow._Note("Prefs.CommandsNote")
    }

    static _BuildSnippets() {
        PreferencesWindow._BeginPage("Prefs.Page.Snippets", 150)
        PreferencesWindow._List("Snippets", 220
            , [["Prefs.Col.Name", "Name", 150], ["Prefs.Col.Keyword", "Keyword", 90], ["Prefs.Col.Text", "Text", 300]]
            , SnippetProvider.EditorFields(), () => SnippetProvider.NewSnippet())
        PreferencesWindow._Section("Prefs.Section.Options")
        PreferencesWindow._Check("Features.Snippets.SearchText", "Prefs.SnippetSearchText", , , "Prefs.Group.Search")
        PreferencesWindow._Field("Features.Snippets.Keyword", "Prefs.SnippetKeyword", "M")
        PreferencesWindow._Check("Features.Snippets.AutoExpand", "Prefs.SnippetAutoExpand", , , "Prefs.Group.AutoExpand")
        PreferencesWindow._Field("Features.Snippets.ExpandPrefix", "Prefs.ExpandPrefix", "S")
        PreferencesWindow._Lines("Features.Snippets.ExpandExclude", "Prefs.ExpandExclude", 2)
        PreferencesWindow._Pair(["Features.Snippets.PasteMode", "Prefs.PasteMode", "M", "choice", ["Auto", "Clipboard", "Type"], [I18n.T("Prefs.PasteMode.Auto"), I18n.T("Prefs.PasteMode.Clipboard"), I18n.T("Prefs.PasteMode.Type")]]
            , ["Features.Snippets.PasteDelay", "Prefs.PasteDelay", "S", "number"])
    }

    static _BuildClipboard() {
        PreferencesWindow._BeginPage("Prefs.Page.Clipboard", 120)
        PreferencesWindow._Pair(["Features.Clipboard.Hotkey", "Prefs.ClipHotkey", "K", "hotkey"], ["Features.Clipboard.Keyword", "Prefs.ClipKeyword", "S"])
        PreferencesWindow._Pair(["Features.Clipboard.MaxItems", "Prefs.ClipMaxItems", "S", "number"], ["Features.Clipboard.MaxItemLength", "Prefs.ClipMaxLength", "S", "number"])
        PreferencesWindow._Check("Features.Clipboard.Persist", "Prefs.ClipPersist")
        PreferencesWindow._Check("Features.Clipboard.Images", "Prefs.ClipImages")
        PreferencesWindow._Field("Features.Clipboard.MaxImages", "Prefs.ClipMaxImages", "S", "number")
        PreferencesWindow._Choice("Features.Clipboard.LocalFiles", "Prefs.ClipStorage", [0, 1, 2]
            , [I18n.T("Prefs.ClipStorage.Data"), I18n.T("Prefs.ClipStorage.Files"), I18n.T("Prefs.ClipStorage.All")], "L")
        PreferencesWindow._Check("Features.Clipboard.MergeDoubleCopy", "Prefs.ClipMerge")
        PreferencesWindow._Lines("Features.Clipboard.IgnoreApps", "Prefs.ClipIgnoreApps", 2)
    }

    static _BuildWebSearch() {
        PreferencesWindow._BeginPage("Prefs.Page.WebSearch", 130)
        PreferencesWindow._List("Features.WebSearch.Engines", 320
            , [["Prefs.Col.Keyword", "Keyword", 70], ["Prefs.Col.Title", "Title", 130], ["Prefs.Col.Url", "Url", 340]]
            , WebSearchProvider.EditorFields(), () => WebSearchProvider.NewEngine())
        PreferencesWindow._Csv("Features.WebSearch.Fallbacks", "Prefs.Fallbacks", "L")
    }

    static _BuildCalculator() {
        base := "Features.Calculator."
        PreferencesWindow._BeginPage("Prefs.Page.Calculator", 180)
        PreferencesWindow._Section("Prefs.Section.Calculator")
        PreferencesWindow._Check(base "Currency", "Prefs.Currency")
        PreferencesWindow._Section("Prefs.Section.Structural")
        PreferencesWindow._Check(base "StructuralCalc", "Prefs.StructuralCalc")
        PreferencesWindow._Field(base "RebarCover", "Prefs.RebarCover", "S", "number")      ; 每项一行: 标签和输入框各自对齐
        PreferencesWindow._Field(base "MaxBarSpacing", "Prefs.MaxBarSpacing", "S", "number")
        PreferencesWindow._Csv(base "BarSizes", "Prefs.BarSizes", "M")
        PreferencesWindow._Field(base "BarPrefix", "Prefs.BarPrefix", "S")
    }

    static _BuildScripts() {
        PreferencesWindow._BeginPage("Prefs.Page.Scripts", 110)
        PreferencesWindow._Section("Prefs.Section.Scripts")
        PreferencesWindow._Info("Prefs.Group.ScriptsFolder", ScriptProvider.Dir, " cGray")
        PreferencesWindow._y += 4
        PreferencesWindow._Button("Prefs.ScriptsFolder", (*) => (ScriptProvider.OpenFolder(), PreferencesWindow._FillScripts()))
        PreferencesWindow._Section("Prefs.Section.ScriptList")
        listView := PreferencesWindow._Add("ListView", "w" PreferencesWindow.ContentW " h170 -Multi NoSort Grid ReadOnly"
            , [I18n.T("Prefs.Col.Name"), I18n.T("Prefs.Col.Keyword"), I18n.T("Prefs.Col.Argument"), I18n.T("Prefs.Col.Mode"), I18n.T("Prefs.Col.File")])
        for index, width in [145, 70, 95, 135, 100]
            listView.ModifyCol(index, width)
        listView.OnEvent("DoubleClick", (ctrl, row) => (row && row <= ScriptProvider.Scripts.Length) ? Platform.Edit(ScriptProvider.Scripts[row].Path) : "")
        PreferencesWindow._scriptList := listView
        PreferencesWindow._FillScripts()
        PreferencesWindow._Below(6, listView)
        PreferencesWindow._Note("Prefs.ScriptsNote")
    }

    static _scriptList := ""
    static _FillScripts() {
        static modes := Map("window", "Script.Mode.Window", "silent", "Script.Mode.Silent", "output", "Script.Mode.Output")
        listView := PreferencesWindow._scriptList
        if !IsObject(listView)
            return
        ScriptProvider.Load()
        listView.Delete()
        for script in ScriptProvider.Scripts
            listView.Add(, script.Title, script.Keyword, script.Argument, I18n.T(modes[script.Mode]), script.Name)
        if !ScriptProvider.Scripts.Length
            listView.Add(, I18n.T("Prefs.NoScripts"))
    }

    static _BuildHotkeys() {
        PreferencesWindow._BeginPage("Prefs.Page.Hotkeys", 100)
        actions := [["ToggleWindow", I18n.T("Tray.Show")]]
        for command in SystemProvider.Commands()
            actions.Push([command["Id"], command["Title"]])
        PreferencesWindow._List("Hotkeys", 430
            , [["Prefs.Col.Key", "Key", 160], ["Prefs.Col.Action", "Action", 150], ["Prefs.Col.WinTitle", "WinTitle", 230]]
            , [ItemEditor.Field("Key", "Prefs.Col.Key", "hotkey", true, "", I18n.T("Prefs.HotkeyHint"))
             , ItemEditor.Field("Action", "Prefs.Col.Action", "choice", false, actions)
             , ItemEditor.Field("WinTitle", "Prefs.Col.WinTitle", "text")]
            , () => Map("Key", "", "Action", "ToggleWindow", "WinTitle", ""))
    }

    static _BuildAdvanced() {
        PreferencesWindow._BeginPage("Prefs.Page.Advanced", 140)
        PreferencesWindow._Info("Prefs.Page.Advanced", I18n.T("Prefs.Version", App.Version))
        PreferencesWindow._Info("Prefs.Group.DataFolder", AppSettings.DataDir, "w500")
        PreferencesWindow._Button("Prefs.EditJson", (*) => Platform.Edit(AppSettings.File))
        PreferencesWindow._Button("Prefs.OpenDataFolder", (*) => Platform.Open(AppSettings.DataDir))
        PreferencesWindow._Button("Prefs.OpenThemes", (*) => Platform.Open(ThemeManager.UserDir))
        PreferencesWindow._Button("Prefs.ResetLearning", (*) => PreferencesWindow._ResetLearning())
    }

    static _usage := ""
    static _ResetLearning() {
        Knowledge.Picks := Knowledge._UidMap(), Knowledge.QueryPicks := Map(), Knowledge.History := [], Knowledge.Recent := []
        Knowledge.Save()
        MsgBox(I18n.T("Prefs.ResetDone"), App.Name, 64)
    }

    static _OpenFolder(folder) {
        DirCreate(folder)
        ActionCatalog.OpenFolder(folder)                                    ; 设置的文件管理器 (例如 Total Commander)
    }

    static _BeginPage(nameKey, labelW := 190) {
        PreferencesWindow.Pages.Push({Key: nameKey, Name: I18n.T(nameKey), Wiki: PreferencesWindow.WikiPage(nameKey), Controls: []})
        PreferencesWindow._y := 14
        PreferencesWindow._pageKey := nameKey
        PreferencesWindow._pairX := 0                                       ; 这一页成对设置的右列位置, 见 _Pair
        PreferencesWindow.LabelW := Max(labelW, PreferencesWindow._labelWidths.Get(I18n.Lang " " nameKey, 0))
    }

    static _FitLabel(ctrl, text) {
        ; The portable pages reserve a fixed label column and let long labels wrap.
    }

    static _Add(type, options, text := "") {
        pos := InStr(options, " x") || InStr(options, "x") = 1 ? "" : "x" PreferencesWindow.ContentX " "
        ctrl := PreferencesWindow.Gui.Add(type, pos "y" PreferencesWindow._y " " options " Hidden", text)
        PreferencesWindow.Pages[PreferencesWindow.Pages.Length].Controls.Push(ctrl)
        switch type, false {                                                ; 用户修改 -> "应用" 可用 (类型名不区分大小写)
            case "Edit", "DropDownList", "ComboBox": ctrl.OnEvent("Change", (*) => PreferencesWindow.MarkDirty())
            case "CheckBox", "Radio":                ctrl.OnEvent("Click", (*) => PreferencesWindow.MarkDirty())
        }
        return ctrl
    }

    static _Bind(path, readFn) {
        PreferencesWindow.Binds.Push({Path: path, Read: readFn})
    }

    static _Below(gap, controls*) {
        bottom := PreferencesWindow._y
        for ctrl in controls {
            ctrl.GetPos(, &top, , &height)
            bottom := Max(bottom, top + height)
        }
        PreferencesWindow._y := bottom + gap
    }

    static _Section(labelKey) {
        if (PreferencesWindow._y > 20)
            PreferencesWindow._y += 8
        PreferencesWindow.Gui.SetFont("bold")
        ctrl := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW, I18n.T(labelKey))
        PreferencesWindow.Gui.SetFont("norm")
        PreferencesWindow._Below(3, ctrl)
        line := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW " h1 0x10")   ; SS_ETCHEDHORZ
        PreferencesWindow._Below(PreferencesWindow._HasDesc(labelKey) ? 4 : 10, line)
        PreferencesWindow._Desc(labelKey, PreferencesWindow.ContentX)
    }

    static _HasDesc(labelKey) {
        return I18n.Strings.Has(labelKey ".Desc")
    }

    static _Desc(labelKey, x, text := "") {
        if (text = "") {
            if !PreferencesWindow._HasDesc(labelKey)
                return
            text := I18n.T(labelKey ".Desc")
        }
        PreferencesWindow.Gui.SetFont("s8")
        ctrl := PreferencesWindow._Add("Text", "x" x " w" (PreferencesWindow.ContentX + PreferencesWindow.ContentW - x) " cGray", text)
        PreferencesWindow.Gui.SetFont("s9")
        PreferencesWindow._Below(10, ctrl)
    }

    static _Note(textKey) {
        PreferencesWindow._Desc("", PreferencesWindow.ContentX, I18n.T(textKey))
    }

    static _Gap() {
        PreferencesWindow._y += 10
    }

    static _Label(labelKey) {
        PreferencesWindow._y += 3
        ctrl := PreferencesWindow._Add("Text", "w" (PreferencesWindow.LabelW - 12) " Right", I18n.T(labelKey))
        PreferencesWindow._y -= 3
        PreferencesWindow._FitLabel(ctrl, I18n.T(labelKey))
        return ctrl
    }

    static _InputX() {
        return PreferencesWindow.ContentX + PreferencesWindow.LabelW
    }

    static _InputW() {
        return PreferencesWindow.ContentW - PreferencesWindow.LabelW
    }

    static _Width(size, withBrowse := false) {
        switch size {
            case "S": return PreferencesWindow.WidthS
            case "M": return PreferencesWindow.WidthM
            case "K": return PreferencesWindow.WidthK
            case "B": return PreferencesWindow.ButtonW                      ; 和按钮一样宽 (外观页: 主题下拉框和下面的按钮对齐)
        }
        return PreferencesWindow._InputW() - (withBrowse ? 34 : 0)
    }

    static _Check(path, labelKey, x := 0, desc := "", group := "", width := 0) {
        x := x ? x : PreferencesWindow._InputX()
        if (group != "")
            PreferencesWindow._GroupLabel(group)
        ctrl := PreferencesWindow._Add("Checkbox", "x" x " w" (width ? width : PreferencesWindow.ContentX + PreferencesWindow.ContentW - x), I18n.T(labelKey))
        ctrl.Value := PreferencesWindow.GetPath(PreferencesWindow.Working, path) ? 1 : 0
        PreferencesWindow._Bind(path, () => ctrl.Value)
        hasDesc := (desc != "" || PreferencesWindow._HasDesc(labelKey))
        PreferencesWindow._Below(hasDesc ? 0 : 6, ctrl)
        PreferencesWindow._Desc(labelKey, x + 18, desc)                     ; 和复选框的文字对齐
        return ctrl
    }

    static _GroupLabel(labelKey, dy := 1) {
        PreferencesWindow._y += dy
        ctrl := PreferencesWindow._Add("Text", "x" PreferencesWindow.ContentX " w" (PreferencesWindow.LabelW - 12) " Right", I18n.T(labelKey))
        PreferencesWindow._y -= dy
        PreferencesWindow._FitLabel(ctrl, I18n.T(labelKey))
        return ctrl
    }

    static _Info(labelKey, text, options := "", type := "Text") {
        label := PreferencesWindow._GroupLabel(labelKey)
        ctrl := PreferencesWindow._Add(type, "x" PreferencesWindow._InputX() " w" PreferencesWindow._InputW() " " options, text)
        PreferencesWindow._Below(6, label, ctrl)
        return ctrl
    }

    static _InlineField(path, labelKey, size, kind := "text") {
        x := PreferencesWindow._InputX()
        PreferencesWindow._y += 3
        label := PreferencesWindow._Add("Text", "x" x, I18n.T(labelKey))
        PreferencesWindow._y -= 3
        label.GetPos(, , &labelW)
        value := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        ctrl := PreferencesWindow._Add("Edit", "x" (x + labelW + 8) " w" PreferencesWindow._Width(size) " r1 -Multi" (kind = "number" ? " Number" : ""), value)
        if (kind = "number")
            PreferencesWindow._Bind(path, () => IsInteger(ctrl.Value) ? Integer(ctrl.Value) : 0)
        else
            PreferencesWindow._Bind(path, () => ctrl.Value)
        PreferencesWindow._Below(PreferencesWindow._HasDesc(labelKey) ? 3 : 8, label, ctrl)
        PreferencesWindow._Desc(labelKey, x)
    }

    static _Field(path, labelKey, size, kind := "text") {
        label := PreferencesWindow._Label(labelKey)
        if (kind = "hotkey")
            return PreferencesWindow._BelowInput(labelKey, label, PreferencesWindow._HotkeyBox(PreferencesWindow._InputX(), path))
        value := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        browseKind := (kind = "file" || kind = "folder")
        ctrl := PreferencesWindow._Add("Edit", "x" PreferencesWindow._InputX() " w" PreferencesWindow._Width(size, browseKind) " r1 -Multi" (kind = "number" ? " Number" : ""), value)
        if browseKind {
            browse := PreferencesWindow._Add("Button", "x+4 yp-1 w30", I18n.T("Prefs.Browse"))
            browseFn := ItemEditor._Browser(ctrl, kind, PreferencesWindow.Gui)
            browse.OnEvent("Click", (p*) => (browseFn(p*), PreferencesWindow.MarkDirty()))
        }
        if (kind = "number")
            PreferencesWindow._Bind(path, () => IsInteger(ctrl.Value) ? Integer(ctrl.Value) : 0)
        else
            PreferencesWindow._Bind(path, () => ctrl.Value)
        PreferencesWindow._BelowInput(labelKey, label, ctrl)
    }

    static _BelowInput(labelKey, controls*) {
        hasDesc := PreferencesWindow._HasDesc(labelKey)
        PreferencesWindow._Below(hasDesc ? 3 : 8, controls*)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
    }

    static _Choice(path, labelKey, values, labels, size := "M") {
        label := PreferencesWindow._Label(labelKey)
        ctrl := PreferencesWindow._Add("DropDownList", "x" PreferencesWindow._InputX() " w" PreferencesWindow._Width(size), labels)
        current := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        ctrl.Value := 1
        for index, value in values
            if (value = current)
                ctrl.Value := index
        PreferencesWindow._Bind(path, () => values[ctrl.Value])
        PreferencesWindow._BelowInput(labelKey, label, ctrl)
        return ctrl
    }

    static _Lines(path, labelKey, rows) {
        label := PreferencesWindow._Label(labelKey)
        value := PreferencesWindow.JoinLines(PreferencesWindow.GetPath(PreferencesWindow.Working, path))
        ctrl := PreferencesWindow._Add("Edit", "x" PreferencesWindow._InputX() " w" PreferencesWindow._InputW() " r" rows " +Multi -Wrap +HScroll +VScroll", value)
        PreferencesWindow._Bind(path, () => PreferencesWindow.SplitLines(ctrl.Value))
        PreferencesWindow._Below(3, label, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
    }

    static _WinList(path, labelKey, rows, value := "") {
        label := PreferencesWindow._Label(labelKey)
        if (path != "")
            value := PreferencesWindow.SplitWindows(PreferencesWindow.GetPath(PreferencesWindow.Working, path))
        ctrl := PreferencesWindow._Add("Edit", "x" PreferencesWindow._InputX() " w" PreferencesWindow._InputW() " r" rows " +Multi -Wrap +HScroll +VScroll", PreferencesWindow.JoinLines(value))
        if (path != "")
            PreferencesWindow._Bind(path, () => PreferencesWindow.JoinWindows(PreferencesWindow.SplitLines(ctrl.Value)))
        PreferencesWindow._Below(3, label, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
        return ctrl
    }

    static _Csv(path, labelKey, size) {
        label := PreferencesWindow._Label(labelKey)
        value := PreferencesWindow.JoinCsv(PreferencesWindow.GetPath(PreferencesWindow.Working, path))
        ctrl := PreferencesWindow._Add("Edit", "x" PreferencesWindow._InputX() " w" PreferencesWindow._Width(size) " r1 -Multi", value)
        PreferencesWindow._Bind(path, () => PreferencesWindow.SplitCsv(ctrl.Value))
        PreferencesWindow._BelowInput(labelKey, label, ctrl)
    }

    static _Button(labelKey, fn, group := "") {
        if (group != "")
            PreferencesWindow._GroupLabel(group, 5)                         ; 和按钮上的文字对齐
        ctrl := PreferencesWindow._Add("Button", "x" PreferencesWindow._InputX() " w" PreferencesWindow.ButtonW " h" PreferencesWindow.ButtonH, I18n.T(labelKey))
        ctrl.OnEvent("Click", fn)
        PreferencesWindow._Below(PreferencesWindow._HasDesc(labelKey) ? 2 : 6, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
        return ctrl
    }

    static _Buttons(group, specs*) {
        if (group != "")
            PreferencesWindow._GroupLabel(group, 5)
        x := PreferencesWindow._InputX(), controls := []
        buttonW := Min(PreferencesWindow.ButtonW, (PreferencesWindow._InputW() - 10 * (specs.Length - 1)) // specs.Length)   ; 左列加宽后放不下时按钮窄一点
        for spec in specs {
            ctrl := PreferencesWindow._Add("Button", "x" x " w" buttonW " h" PreferencesWindow.ButtonH, I18n.T(spec[1]))
            ctrl.OnEvent("Click", spec[2])
            controls.Push(ctrl)
            x += buttonW + 10
        }
        PreferencesWindow._Below(PreferencesWindow._HasDesc(specs[1][1]) ? 2 : 6, controls*)
        PreferencesWindow._Desc(specs[1][1], PreferencesWindow._InputX())
    }

    static _Pair(left, right) {
        label := PreferencesWindow._Label(left[2])
        first := PreferencesWindow._Input(PreferencesWindow._InputX(), left*)
        first.GetPos(&x, , &w)
        sameAsFirstRow := PreferencesWindow._pairX && left[3] = PreferencesWindow._pairSizes[1] && right[3] = PreferencesWindow._pairSizes[2]
        if sameAsFirstRow {                                                 ; 和这一页第一行一样的输入框: 用同样的宽度, 右边对齐到同一列
            w := PreferencesWindow._pairFirstW
            first.Move(, , w)
        }
        PreferencesWindow._y += 3
        label2 := PreferencesWindow._Add("Text", "x" (x + w + 18), I18n.T(right[2]))
        PreferencesWindow._y -= 3
        label2.GetPos(&x2, , &w2)
        secondW := sameAsFirstRow ? PreferencesWindow._pairSecondW : 0
        overflow := x2 + w2 + 8 + (secondW ? secondW : PreferencesWindow._Width(right[3])) - (PreferencesWindow.ContentX + PreferencesWindow.ContentW)
        if (!sameAsFirstRow && overflow > 0 && left[3] = right[3] && w > PreferencesWindow.WidthS) {
            w := Max(PreferencesWindow.WidthS, (PreferencesWindow.ContentX + PreferencesWindow.ContentW - x - 18 - w2 - 8) // 2)
            first.Move(, , w)
            label2.Move(x + w + 18)
            label2.GetPos(&x2)
            secondW := w, overflow := x2 + w2 + 8 + w - (PreferencesWindow.ContentX + PreferencesWindow.ContentW)
        }
        if (overflow > 0 && w > PreferencesWindow.WidthS) {
            shrink := Min(overflow, w - PreferencesWindow.WidthS)
            w -= shrink, overflow -= shrink
            first.Move(, , w)
            label2.Move(x + w + 18)
            label2.GetPos(&x2)
        }
        if (overflow > 0) {                                                 ; 还是放不下: 右边这一项换到下一行
            first.GetPos(, &firstY, , &firstH)
            PreferencesWindow._y := firstY + firstH + 6
            label2.Move(PreferencesWindow._InputX(), PreferencesWindow._y + 3)
            label2.GetPos(&x2)
        }
        secondX := x2 + w2 + 8
        if (overflow <= 0) {
            target := PreferencesWindow._pairX
            if !target
                PreferencesWindow._pairX := secondX, PreferencesWindow._pairFirstW := w, PreferencesWindow._pairSizes := [left[3], right[3]]
                , PreferencesWindow._pairSecondW := secondW ? secondW : PreferencesWindow._Width(right[3])
            else if (w = PreferencesWindow._pairFirstW && target >= secondX && target + (secondW ? secondW : PreferencesWindow._Width(right[3])) <= PreferencesWindow.ContentX + PreferencesWindow.ContentW) {
                label2.Move(target - 8 - w2)
                secondX := target
            }
        }
        second := PreferencesWindow._Input(secondX, right*)
        if secondW
            second.Move(, , secondW)
        PreferencesWindow._BelowInput(left[2], label, first, label2, second)
    }

    static _Input(x, path, labelKey, size, kind := "text", values := "", labels := "") {
        current := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        if (kind = "hotkey")
            return PreferencesWindow._HotkeyBox(x, path)
        if (kind = "choice") {
            ctrl := PreferencesWindow._Add("DropDownList", "x" x " w" PreferencesWindow._Width(size), labels)
            ctrl.Value := 1
            for index, value in values
                if (value = current)
                    ctrl.Value := index
            PreferencesWindow._Bind(path, () => values[ctrl.Value])
            return ctrl
        }
        text := (kind = "csv") ? PreferencesWindow.JoinCsv(current) : current
        ctrl := PreferencesWindow._Add("Edit", "x" x " w" PreferencesWindow._Width(size) " r1 -Multi" (kind = "number" ? " Number" : ""), text)
        switch kind {
            case "number": PreferencesWindow._Bind(path, () => IsInteger(ctrl.Value) ? Integer(ctrl.Value) : 0)
            case "csv":    PreferencesWindow._Bind(path, () => PreferencesWindow.SplitCsv(ctrl.Value))
            default:       PreferencesWindow._Bind(path, () => ctrl.Value)
        }
        return ctrl
    }

    static _HotkeyBox(x, path) {
        ctrl := HotkeyBox.Add(PreferencesWindow.Gui, "x" x " y" PreferencesWindow._y " w" PreferencesWindow.WidthK " Hidden"
            , PreferencesWindow.GetPath(PreferencesWindow.Working, path), false, () => PreferencesWindow.MarkDirty())
        PreferencesWindow.Pages[PreferencesWindow.Pages.Length].Controls.Push(ctrl)
        PreferencesWindow._Bind(path, () => HotkeyBox.Value(ctrl))
        return ctrl
    }

    static _SideButton(rowY, labelKey, fn) {
        x := PreferencesWindow._InputX() + PreferencesWindow.WidthS + 12
        ctrl := PreferencesWindow._Add("Button", "x" x " y" (rowY - 2) " w" PreferencesWindow.ButtonW " h" PreferencesWindow.ButtonH, I18n.T(labelKey))
        ctrl.OnEvent("Click", fn)
        return ctrl
    }

    static _List(path, height, columns, fields, newItem, check := "") {
        items := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        headers := []
        for column in columns
            headers.Push(I18n.T(column[1]))
        listView := PreferencesWindow._Add("ListView", "w" PreferencesWindow.ContentW " h" (height - 40) " -Multi NoSort Grid", headers)
        for index, column in columns
            listView.ModifyCol(index, column[3])
        pageName := PreferencesWindow.Pages[PreferencesWindow.Pages.Length].Name
        statuses := Map()                                                   ; Platform.ObjectId(item) -> 检查结果, 检查过才有
        shown := []                                                         ; 每一行对应 items 里的第几项 (筛选时只显示一部分)
        filterBox := ""

        Refresh(selectRow := 0) {
            listView.Opt("-Redraw")
            listView.Delete()
            shown.Length := 0
            filter := IsObject(filterBox) ? filterBox.Value : ""
            for index, item in items {
                cells := []
                for column in columns
                    cells.Push((column[2] = "Status") ? StatusText(item) : PreferencesWindow._Cell(item, column[2]))
                if !PreferencesWindow.FilterMatch(filter, cells)
                    continue
                listView.Add("", cells*)
                shown.Push(index)
            }
            if (selectRow && shown.Length)
                listView.Modify(Min(selectRow, shown.Length), "Select Focus Vis")
            listView.Opt("+Redraw")
        }
        RowOf(index) {                                                      ; items 里的第 index 项在第几行, 没有显示时 0
            for row, shownIndex in shown
                if (shownIndex = index)
                    return row
            return 0
        }
        StatusText(item) {
            key := Platform.ObjectId(item)
            return statuses.Has(key) ? I18n.T("Prefs.Status." statuses[key]) : ""
        }
        Recheck(item) {                                                     ; 检查过之后, 新增 / 修改的项目也马上检查
            if statuses.Count
                statuses[Platform.ObjectId(item)] := check(item, Map())
        }
        AddItem(*) => Insert(newItem())
        Insert(item) {                                                      ; 打开编辑框 (item 是预先填好的内容), 确定后加进列表
            edited := ItemEditor.Edit(PreferencesWindow.Gui, pageName, fields, item)
            if IsObject(edited)
                Append(edited)
        }
        Append(item) {
            items.Push(item)
            PreferencesWindow.MarkDirty(true)
            Recheck(item)
            if IsObject(filterBox)
                filterBox.Value := ""                                       ; 清掉筛选, 新加的一项一定看得到
            Refresh(items.Length)
        }
        EditExisting(item) {                                                ; 选中列表里的这一项并打开编辑框
            for index, existing in items {
                if (existing = item) {
                    if IsObject(filterBox)
                        filterBox.Value := ""
                    Refresh(index)
                    return EditItem()
                }
            }
        }
        EditItem(*) {
            row := listView.GetNext()
            if !row
                return
            index := shown[row]
            edited := ItemEditor.Edit(PreferencesWindow.Gui, pageName, fields, ItemEditor.WithDefaults(items[index], newItem()))
            if IsObject(edited) {
                if statuses.Has(Platform.ObjectId(items[index]))
                    statuses.Delete(Platform.ObjectId(items[index]))
                items[index] := edited
                PreferencesWindow.MarkDirty()
                Recheck(edited)
                Refresh(row)
            }
        }
        CheckItems(button, *) {
            button.Enabled := false
            statuses.Clear()
            roots := Map()
            counts := Map("OK", 0, "Missing", 0, "Unavailable", 0, "Skipped", 0)
            firstProblem := 0
            for index, item in items {
                result := check(item, roots)
                statuses[Platform.ObjectId(item)] := result
                counts[result] += 1
                if (!firstProblem && (result = "Missing" || result = "Unavailable"))
                    firstProblem := index
            }
            Refresh(RowOf(firstProblem))
            button.Enabled := true
            if !firstProblem
                message := I18n.T("Prefs.CheckAllOk", counts["OK"])
            else
                message := I18n.T("Prefs.CheckResult", counts["Missing"], counts["Unavailable"])
            if counts["Skipped"]
                message .= "`n`n" I18n.T("Prefs.CheckSkipped", counts["Skipped"])
            MsgBox(message, pageName, (firstProblem ? "Icon!" : "Iconi") " Owner" PreferencesWindow.Gui.Hwnd)
        }
        DeleteItem(*) {
            row := listView.GetNext()
            if !row
                return
            if (MsgBox(I18n.T("Prefs.ConfirmDelete", listView.GetText(row, 1)), pageName, "YesNo Icon? Owner" PreferencesWindow.Gui.Hwnd) != "Yes")
                return
            items.RemoveAt(shown[row])
            PreferencesWindow.MarkDirty()
            Refresh(row)
        }

        listView.OnEvent("DoubleClick", EditItem)
        Refresh()
        PreferencesWindow._lists[path] := {Items: items, Insert: Insert, Append: Append, Edit: EditExisting}   ; 外面加进来的项目 (AddCommands)
        PreferencesWindow._y += height - 34
        PreferencesWindow._Add("Button", "w80", I18n.T("Prefs.Add")).OnEvent("Click", AddItem)
        PreferencesWindow._Add("Button", "x+8 yp w80", I18n.T("Prefs.Edit")).OnEvent("Click", EditItem)
        PreferencesWindow._Add("Button", "x+8 yp w80", I18n.T("Prefs.Delete")).OnEvent("Click", DeleteItem)
        if IsObject(check)
            PreferencesWindow._Add("Button", "x+24 yp w100", I18n.T("Prefs.CheckTargets")).OnEvent("Click", CheckItems)
        listView.GetPos(&listX, , &listW)
        filterBox := PreferencesWindow.Gui.Add("Edit", "x" (listX + listW - 160) " yp+1 w160 r1 -Multi Hidden")   ; 不用 _Add: 筛选不算修改设置
        PreferencesWindow.Pages[PreferencesWindow.Pages.Length].Controls.Push(filterBox)
        filterBox.SetCue(I18n.T("Prefs.Filter"))
        filterBox.OnEvent("Change", (*) => Refresh())
        PreferencesWindow._y += 38
    }

    static FilterMatch(filter, cells) {
        filter := Trim(filter)
        if (filter = "")
            return true
        text := ""
        for cell in cells
            text .= cell "`n"
        for word in StrSplit(filter, " ")
            if (word != "" && !InStr(text, word))
                return false
        return true
    }

    static _Cell(item, key) {
        if !(item is Map) || !item.Has(key)
            return ""
        if (key = "Target" && item.Has("Arguments") && Trim(item["Arguments"]) != "")   ; 自定义命令: 目标后面接着显示参数
            return RegExReplace(item["Target"] " " item["Arguments"], "\s+", " ")
        if (key = "Key")                                                    ; 自定义热键: 显示 Ctrl+Alt+P、鼠标中键
            return HotkeyBox.Label(item[key])
        if (key = "Type") {                                                 ; 自定义命令的类型显示翻译后的名称
            label := I18n.T("Prefs.TypeShort." item[key])
            if (label != "Prefs.TypeShort." item[key])
                return label
        }
        return RegExReplace(item[key] "", "\s+", " ")
    }

    static _GlobalHotkeys(data) {
        list := []
        add(key, label) => (Trim(key) != "") ? list.Push({Key: key, Label: label}) : ""
        general := data["General"]
        add(general["Hotkey"], I18n.T("Prefs.Hotkey"))
        add(general["SecondaryHotkey"], I18n.T("Prefs.SecondaryHotkey"))
        add(general.Has("SelectionHotkey") ? general["SelectionHotkey"] : "", I18n.T("Prefs.SelectionHotkey"))
        clipboardOptions := PreferencesWindow.GetPath(data, "Features.Clipboard")
        if (clipboardOptions is Map && clipboardOptions.Has("Enabled") && clipboardOptions["Enabled"] && clipboardOptions.Has("Hotkey"))
            add(clipboardOptions["Hotkey"], I18n.T("Prefs.Page.Clipboard"))
        if (data.Has("Hotkeys") && data["Hotkeys"] is Array)
            for entry in data["Hotkeys"]
                if (entry is Map && entry.Has("Key") && (!entry.Has("WinTitle") || Trim(entry["WinTitle"]) = ""))
                    add(entry["Key"], I18n.T("Prefs.Page.Hotkeys") " (" (entry.Has("Action") ? entry["Action"] : "") ")")
        return list
    }

    static DuplicateHotkey(list) {
        seen := Map()
        for entry in list {
            key := StrLower(RegExReplace(Trim(entry.Key), "^[~*$]+"))
            if RegExMatch(key, "^([\^!+#]+)(.+)$", &m)                     ; 修饰符的顺序不同也是同一个键 (!^c = ^!c)
                key := StrReplace(Sort(RegExReplace(m[1], "(.)", "$1`n")), "`n") m[2]
            if seen.Has(key)
                return {Key: entry.Key, First: seen[key], Second: entry.Label}
            seen[key] := entry.Label
        }
        return ""
    }

    static DeepCopy(value) {
        return JSON.Parse(JSON.Stringify(value))
    }

    static GetPath(data, path) {
        node := data
        for key in StrSplit(path, ".") {
            if !(node is Map) || !node.Has(key)
                return ""
            node := node[key]
        }
        return node
    }

    static SetPath(data, path, value) {
        keys := StrSplit(path, ".")
        node := data
        Loop keys.Length - 1 {
            key := keys[A_Index]
            if !(node.Has(key) && node[key] is Map)
                node[key] := Map()
            node := node[key]
        }
        node[keys[keys.Length]] := value
    }

    static SplitLines(text) {
        items := []
        for line in StrSplit(text, "`n", "`r")
            if (Trim(line) != "")
                items.Push(Trim(line))
        return items
    }

    static JoinLines(items) {
        return (items is Array) ? TextTools.Join(items) : items
    }

    static SplitCsv(text) {
        items := []
        for part in StrSplit(text, ",")
            if (Trim(part) != "")
                items.Push(Trim(part))
        return items
    }

    static SplitWindows(text) {
        return PreferencesWindow.SplitCsv(text)
    }

    static JoinWindows(lists*) {
        all := [], seen := Map()
        seen.CaseSense := false
        for list in lists
            for window in list
                if (Trim(window) != "" && !seen.Has(Trim(window)))
                    seen[Trim(window)] := true, all.Push(Trim(window))
        return PreferencesWindow.JoinCsv(all)
    }

    static JoinCsv(items) {
        if !(items is Array)
            return items
        out := ""
        for index, item in items
            out .= (index = 1 ? "" : ", ") item
        return out
    }
}

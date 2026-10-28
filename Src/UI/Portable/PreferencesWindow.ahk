; PreferencesWindow.ahk - Themed portable settings with native fields and a painted window frame.
#Import Ks { RequestCapabilities }

class PreferencesWindow {
    static Gui := "", Working := "", Pages := [], Binds := [], PageList := ""
    static _lists := Map()                                                  ; 列表页的设置路径 (例如 "CustomCommands") -> 加入 / 编辑项目的方法
    static PageKeys := PreferencesWindow._PageKeys()
    static _page := 0, _y := 0
    static _dirty := false, _ready := false, ApplyButton := ""
    static ContentX := 190, ContentW := 560, LabelW := 190
    static WidthS := 70, WidthM := 220, ButtonW := 200, ButtonH := 26       ; WidthL = 整个控件列 (_InputW)
    static WidthK := 150                                                    ; 热键框 ("K")
    static ButtonY := 619                                                   ; 底部按钮的位置; 页面内容要在它上面 (y < ButtonY - 10)
    static _positionReset := false
    static Chrome := "", Palette := Map(), UiFont := 10, HintFont := 9
    static WindowW := 980, WindowH := 700, _viewHeight := 700
    static SidebarW := 224, HeaderH := 92, RowGap := 10
    static Footer := []

    static _PageKeys() {
        keys := ["Prefs.Page.General", "Prefs.Page.Window", "Prefs.Page.Keyboard", "Prefs.Page.Appearance", "Prefs.Page.Features", "Prefs.Page.Applications"
            , "Prefs.Page.FileSearch", "Prefs.Page.FileIndex", "Prefs.Page.Commands", "Prefs.Page.Snippets", "Prefs.Page.Clipboard", "Prefs.Page.WebSearch", "Prefs.Page.Calculator"
            , "Prefs.Page.Scripts", "Prefs.Page.Hotkeys", "Prefs.Page.QuickSwitch", "Prefs.Page.QSPanel", "Prefs.Page.DateStamp", "Prefs.Page.Usage", "Prefs.Page.Advanced"]
        if Platform.IsLinux {
            Loop 3
                keys.RemoveAt(16)
        }
        return keys
    }

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
        PreferencesWindow.Palette := PreferencesWindow.Colors()
        PreferencesWindow.UiFont := ThemeManager.Density = "Compact" ? 9.5 : ThemeManager.Density = "Comfortable" ? 10.5 : 10
        PreferencesWindow.HintFont := Max(8.5, PreferencesWindow.UiFont - 1)
        PreferencesWindow.RowGap := ThemeManager.Density = "Compact" ? 8 : 10
        g := Gui("-MinimizeBox +Resize +MinSize640x420 +AutoScroll", I18n.T("Prefs.Title"))
        g.BackColor := PreferencesWindow.Palette["Background"]
        g.MarginX := 0, g.MarginY := 0
        g.SetFont("s" PreferencesWindow.UiFont " c" PreferencesWindow.Palette["Text"], ThemeManager.FontName())
        PreferencesWindow.Gui := g
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        screenScale := LauncherCanvas.ScreenScale(g)
        PreferencesWindow.WindowW := Max(740, Min(980, Floor((right - left) / screenScale) - 64))
        PreferencesWindow._viewHeight := Max(500, Min(900, Floor((bottom - top) / screenScale) - 74))
        PreferencesWindow.ContentX := PreferencesWindow.SidebarW + 28
        PreferencesWindow.ContentW := PreferencesWindow.WindowW - PreferencesWindow.ContentX - 30
        PreferencesWindow.ButtonH := ThemeManager.Density = "Compact" ? 30 : 34
        PreferencesWindow.Chrome := g.AddPicture("x0 y0 w" PreferencesWindow.WindowW " h100")
        pageList := g.AddListView("x16 y108 w" (PreferencesWindow.SidebarW - 30) " h460 -Hdr -Multi Report -E0x200 c" PreferencesWindow.Palette["Text"] " Background" PreferencesWindow.Palette["Sidebar"], [""])
        navigationColors := PreferencesWindow.Palette.Clone()
        navigationColors["Surface"] := navigationColors["Sidebar"]
        PreferencesWindow.StyleNative(pageList, "Navigation", navigationColors)
        try pageList.ToClr().RowHeight := ThemeManager.Density = "Compact" ? 29 : 33
        PreferencesWindow.PageList := pageList
        PreferencesWindow._BuildPages()
        contentBottom := PreferencesWindow.HeaderH
        for page in PreferencesWindow.Pages {
            page.Bottom := PreferencesWindow.HeaderH
            for control in page.Controls {
                control.GetPos(, &controlY, , &controlH)
                contentBottom := Max(contentBottom, controlY + controlH)
                page.Bottom := Max(page.Bottom, controlY + controlH)
            }
        }
        PreferencesWindow.ButtonY := Max(620, contentBottom + 24)
        PreferencesWindow.WindowH := PreferencesWindow.ButtonY + 60
        PreferencesWindow.Chrome.Move(, , , PreferencesWindow.WindowH)
        pageList.Move(, , , Min(PreferencesWindow.Pages.Length * 34 + 12, PreferencesWindow.ButtonY - 122))
        for page in PreferencesWindow.Pages
            pageList.Add("", page.Name)
        pageList.ModifyCol(1, PreferencesWindow.SidebarW - 38)
        pageList.OnEvent("ItemSelect", (ctrl, row, selected) => selected ? PreferencesWindow.SelectPage(row) : "")
        pageList.OnEvent("Click", (ctrl, row) => row ? PreferencesWindow.SelectPage(row) : "")
        buttonColors := " Background" PreferencesWindow.Palette["Surface"] " c" PreferencesWindow.Palette["Text"]
        help := g.AddButton("x" PreferencesWindow.ContentX " y" PreferencesWindow.ButtonY " w90 h" PreferencesWindow.ButtonH buttonColors, I18n.T("Prefs.Help"))
        help.OnEvent("Click", (*) => PreferencesWindow.Help())
        okay := g.AddButton("x" (PreferencesWindow.WindowW - 330) " yp w90 h" PreferencesWindow.ButtonH " Default" buttonColors, "OK")
        okay.OnEvent("Click", (*) => PreferencesWindow.OK())
        cancel := g.AddButton("x+10 yp w90 h" PreferencesWindow.ButtonH buttonColors, I18n.T("Prefs.Cancel"))
        cancel.OnEvent("Click", (*) => PreferencesWindow.Cancel())
        PreferencesWindow.ApplyButton := g.AddButton("x+10 yp w100 h" PreferencesWindow.ButtonH " Disabled Background" PreferencesWindow.Palette["Selected"] " c" PreferencesWindow.Palette["SelectedText"], I18n.T("Prefs.Apply"))
        PreferencesWindow.Footer := [help, okay, cancel, PreferencesWindow.ApplyButton]
        for button in PreferencesWindow.Footer
            PreferencesWindow.StyleNative(button, button = PreferencesWindow.ApplyButton ? "PrimaryButton" : "Button", PreferencesWindow.Palette)
        PreferencesWindow.ApplyButton.OnEvent("Click", (*) => PreferencesWindow.Apply())
        g.OnEvent("Close", (*) => PreferencesWindow.Cancel())
        g.OnEvent("Escape", (*) => PreferencesWindow.Cancel())
        g.OnEvent("DpiChanged", (*) => PreferencesWindow._PaintChrome())
        if !IsInteger(pageIndex)
            pageIndex := PreferencesWindow._PageIndex(pageIndex)
        PreferencesWindow._SelectRow(Max(1, Min(pageIndex, PreferencesWindow.Pages.Length)))
        PreferencesWindow._PaintChrome()
        g.Show((IsInteger(x) && IsInteger(y) ? "x" x " y" y " " : "") "w" (PreferencesWindow.WindowW + 18) " h" Min(PreferencesWindow.WindowH, PreferencesWindow._viewHeight))
        pageList.Focus()
        PreferencesWindow._ready := true
    }

    static _SelectRow(index) {
        PreferencesWindow.SelectPage(index)
        PreferencesWindow.PageList.Modify(index, "Select Focus Vis")
    }

    static Colors() {
        background := PreferencesWindow._Color("Background", "F6F7FA")
        border := PreferencesWindow._Color("Border", "D9DEE8")
        return Map("Background", background, "Sidebar", PreferencesWindow._Mix(background, border, 0.18)
            , "Surface", PreferencesWindow._Mix(background, border, ThemeManager.IsDarkColor(background) ? 0.3 : 0.1), "Border", border
            , "Text", PreferencesWindow._Color("Title", "202530"), "InputText", PreferencesWindow._Color("InputText", "202530")
            , "Muted", PreferencesWindow._Color("Subtitle", "667085"), "Accent", PreferencesWindow._Color("Highlight", "2563EB")
            , "Selected", PreferencesWindow._Color("SelectedBackground", "E7EDFA"), "SelectedText", PreferencesWindow._Color("SelectedTitle", "202530"))
    }

    static _Color(key, fallback) {
        value := ThemeManager.Get(key)
        return RegExMatch(value, "i)^[0-9a-f]{6}$") ? value : fallback
    }

    static _Mix(first, second, amount) {
        first := Integer("0x" first), second := Integer("0x" second), result := ""
        for shift in [16, 8, 0]
            result .= Format("{:02X}", Round(((first >> shift) & 255) * (1 - amount) + ((second >> shift) & 255) * amount))
        return result
    }

    static _PaintChrome() {
        if !IsObject(PreferencesWindow.Chrome) || !IsObject(PreferencesWindow.Gui)
            return
        colors := PreferencesWindow.Palette
        width := PreferencesWindow.WindowW, height := PreferencesWindow.WindowH
        canvas := Image.Create(width, height, , PreferencesWindow.Gui.PixelScale)
        try {
            canvas.FillRoundRect(0, 0, width, height, 0, "0xFF" colors["Background"])
            canvas.FillRoundRect(0, 0, PreferencesWindow.SidebarW, height, 0, "0xFF" colors["Sidebar"])
            canvas.DrawLine(PreferencesWindow.SidebarW, 0, PreferencesWindow.SidebarW, height, "0xFF" colors["Border"], 1)
            font := ThemeManager.FontName()
            try canvas.DrawImage(App.IconFile, 22, 22, 28, 28)
            canvas.DrawText(App.Name, 61, 24, "0xFF" colors["Text"], "s14 bold", font)
            canvas.DrawText(I18n.T("Prefs.Title"), 22, 67, "0xFF" colors["Muted"], "s" PreferencesWindow.HintFont, font)
            title := PreferencesWindow._page ? PreferencesWindow.Pages[PreferencesWindow._page].Name : I18n.T("Prefs.Title")
            canvas.FillRoundRect(PreferencesWindow.SidebarW + 12, 25, 3, 32, 1, "0xFF" colors["Accent"])
            canvas.DrawText(title, PreferencesWindow.ContentX, 22, "0xFF" colors["Text"], "s19 bold", font)
            canvas.DrawLine(PreferencesWindow.ContentX, 73, width - 30, 73, "0xFF" colors["Border"], 1)
            canvas.DrawLine(PreferencesWindow.ContentX, PreferencesWindow.ButtonY - 16, width - 30, PreferencesWindow.ButtonY - 16, "0xFF" colors["Border"], 1)
            canvas.DrawText(I18n.T("Prefs.Version", App.Version), 22, height - 42, "0xFF" colors["Muted"], "s" PreferencesWindow.HintFont, font)
            PreferencesWindow.Chrome.Value := "HBITMAP:" canvas.ToBitmap()
        } finally {
            canvas.Dispose()
        }
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
        if (pageIndex < 1 || pageIndex > PreferencesWindow.Pages.Length || pageIndex = PreferencesWindow._page)
            return
        PreferencesWindow._page := pageIndex
        for index, page in PreferencesWindow.Pages
            for ctrl in page.Controls
                ctrl.Visible := index = pageIndex
        PreferencesWindow._LayoutPage()
        PreferencesWindow._PaintChrome()
    }

    static _LayoutPage() {
        if !PreferencesWindow._page || !PreferencesWindow.Footer.Length
            return
        PreferencesWindow.ButtonY := Max(620, PreferencesWindow.Pages[PreferencesWindow._page].Bottom + 28)
        PreferencesWindow.WindowH := PreferencesWindow.ButtonY + 60
        PreferencesWindow.Chrome.Move(, , , PreferencesWindow.WindowH)
        PreferencesWindow.PageList.Move(, , , Min(PreferencesWindow.Pages.Length * 34 + 12, PreferencesWindow.ButtonY - 122))
        for button in PreferencesWindow.Footer
            button.Move(, PreferencesWindow.ButtonY)
    }

    static StyleNative(control, kind, colors) {
#if WINDOWS
        ALTRunStylePreferenceControl(control.ToClr(), kind, colors["Surface"], colors["InputText"], colors["Border"], colors["Selected"], colors["SelectedText"], colors["Background"], colors["Text"], colors["Muted"])
#elif LINUX
        ALTRunStyleGtkPreferenceControl(control.ToClr(), kind, colors["Surface"], colors["InputText"], colors["Border"], colors["Selected"], colors["SelectedText"], colors["Background"], colors["Text"], colors["Muted"])
#endif
    }

    static FitText(control) {
#if WINDOWS || LINUX || OSX
        control.GetPos(, , &width, &height)
        preferred := ALTRunPreferenceTextHeight(control.ToClr(), width)
        if preferred > height
            control.Move(, , , preferred)
#endif
    }

    static Close() {
        HotkeyBox.CancelActive()                                            ; 正在录制热键时关窗口: 先结束录制, 恢复 ALTRun 的热键
        if IsObject(PreferencesWindow.Gui)
            PreferencesWindow.Gui.Destroy()
        PreferencesWindow.Gui := "", PreferencesWindow.Chrome := "", PreferencesWindow.Footer := [], PreferencesWindow._lists := Map()
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
        for key in PreferencesWindow.PageKeys {
            builder := "_Build" SubStr(key, 12)
            PreferencesWindow.%builder%()
        }
    }

    static _BuildGeneral() {
        PreferencesWindow._BeginPage("Prefs.Page.General", 140)
        PreferencesWindow._Field("General.Hotkey", "Prefs.Hotkey", "M", "hotkey")
        PreferencesWindow._Field("General.SecondaryHotkey", "Prefs.SecondaryHotkey", "M", "hotkey")
        PreferencesWindow._Field("General.SelectionHotkey", "Prefs.SelectionHotkey", "M", "hotkey")
        PreferencesWindow._Choice("General.DoubleTap", "Prefs.DoubleTap", ["", "Ctrl", "Shift"], [I18n.T("Prefs.DoubleTap.None"), I18n.T("Prefs.DoubleTap.Ctrl"), I18n.T("Prefs.DoubleTap.Shift")])
        PreferencesWindow._Choice("General.Language", "Prefs.Language", PreferencesWindow._LanguageValues(), PreferencesWindow._LanguageLabels())
        if (Platform.IsWindows || Platform.IsLinux || Platform.IsMac)
            PreferencesWindow._Check("General.LaunchAtLogin", "Prefs.LaunchAtLogin")
        PreferencesWindow._Check("General.ShowTrayIcon", "Prefs.ShowTrayIcon")
        PreferencesWindow._Check("General.CheckForUpdates", "Prefs.CheckUpdates")
        if Platform.IsMac
            PreferencesWindow._Field("General.UpdateRepository", "Mac.UpdateRepository", "M")
        PreferencesWindow._Check("General.SaveLog", "Prefs.SaveLog")
        PreferencesWindow._Field("General.FileManager", "Prefs.FileManager", "L")
    }

    static _BuildWindow() {
        PreferencesWindow._BeginPage("Prefs.Page.Window", 140)
        PreferencesWindow._Check("General.HideOnDeactivate", "Prefs.HideOnDeactivate")
        PreferencesWindow._Check("General.KeepLastQuery", "Prefs.KeepLastQuery")
        PreferencesWindow._Check("Appearance.StatusBar", "Prefs.StatusBar")
        PreferencesWindow._Check("General.ShowTips", "Prefs.ShowTips")
        PreferencesWindow._Field("Features.Recent.RecentCount", "Prefs.RecentCount", "S", "number")
    }

    static _BuildKeyboard() {
        PreferencesWindow._BeginPage("Prefs.Page.Keyboard", 170)
        if (Platform.IsMac || Platform.IsWindows) {
            PreferencesWindow._Choice("General.SwitchToEnglishInput", "Prefs.EnglishInput", Platform.IsMac ? [0, 1] : [0, 1, 2]
                , Platform.IsMac ? [I18n.T("Prefs.EnglishInput.Off"), I18n.T("Prefs.EnglishInput.Keyboard")] : [I18n.T("Prefs.EnglishInput.Off"), I18n.T("Prefs.EnglishInput.Keyboard"), I18n.T("Prefs.EnglishInput.Mode")])
            PreferencesWindow._Check("General.RestoreInput", "Prefs.RestoreInput")
            if Platform.IsMac {
                values := [""], labels := [I18n.T("Prefs.Language.auto")]
                try {
                    for source in MacInputIntegration.Sources() {
                        values.Push(source.Id)
                        labels.Push(source.Label)
                    }
                }
                configured := PreferencesWindow.GetPath(PreferencesWindow.Working, "General.MacInputSource")
                if (configured != "" && !values.Contains(configured)) {
                    values.Push(configured)
                    labels.Push(configured)
                }
                PreferencesWindow._Choice("General.MacInputSource", "Mac.InputSource", values, labels)
            }
            PreferencesWindow._Choice("General.CapsLock", "Prefs.CapsLock", Platform.IsMac ? ["", "Layout"] : ["", "Layout", "Mode"]
                , Platform.IsMac ? [I18n.T("Prefs.CapsLock.Off"), I18n.T("Prefs.CapsLock.Layout")] : [I18n.T("Prefs.CapsLock.Off"), I18n.T("Prefs.CapsLock.Layout"), I18n.T("Prefs.CapsLock.Mode")])
            PreferencesWindow._Check("General.CapsLockNotify", "Prefs.CapsLockNotify")
        }
        PreferencesWindow._Check("General.SpaceToRun", "Prefs.SpaceToRun")
        PreferencesWindow._Choice("General.TabKey", "Prefs.TabKey", ["Complete", "Next"], [I18n.T("Prefs.TabKey.Complete"), I18n.T("Prefs.TabKey.Next")])
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
        if (Platform.IsMac || Platform.IsWindows)
            PreferencesWindow._Check("Appearance.Fade", "Prefs.Fade")
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

    static _BuildFeatures() {
        PreferencesWindow._BeginPage("Prefs.Page.Features", 140)
        features := ["Applications", "CustomCommands", "Snippets", "Calculator", "WebSearch", "Recent", "FileSearch", "Scripts", "Terminal", "System", "Help", "Clipboard", "Windows", "Bookmarks", "LargeType"]
        top := PreferencesWindow._y
        for index, feature in features
            PreferencesWindow._FeatureCheck(feature, PreferencesWindow.ContentX + Mod(index - 1, 2) * (PreferencesWindow.ContentW // 2), top + ((index - 1) // 2) * 34)
        PreferencesWindow._y := top + Ceil(features.Length / 2) * 34 + 12
        PreferencesWindow._Check("Features.Windows.InDefaultResults", "Prefs.ShowInNormal", , , "Prefs.Feature.Windows")
        PreferencesWindow._Field("Features.Windows.Keyword", "Prefs.Feature.Windows", "M")
        PreferencesWindow._Check("Features.Bookmarks.InDefaultResults", "Prefs.ShowInNormal", , , "Prefs.Feature.Bookmarks")
        PreferencesWindow._Field("Features.Bookmarks.Keyword", "Prefs.Feature.Bookmarks", "M")
        PreferencesWindow._Field("Features.Terminal.Prefix", "Prefs.TerminalPrefix", "S")
        PreferencesWindow._Field("Features.Terminal.Shell", "Prefs.TerminalShell", "M")
        if Platform.IsMac
            PreferencesWindow._Choice("Features.Terminal.Terminal", "Mac.Terminal", ["Terminal", "iTerm"], ["Terminal", "iTerm"])
        PreferencesWindow._Lines("Features.System.Hidden", "Prefs.SysHidden", 3)
        PreferencesWindow._Check("Features.System.ConfirmActions", "Prefs.ConfirmActions")
        if Platform.IsWindows || Platform.IsMac
            PreferencesWindow._Check("Features.System.SettingsPages", Platform.IsMac ? "Mac.Settings.Enabled" : "Prefs.SettingsPages")
        if (Platform.IsMac && PreferencesWindow.GetPath(PreferencesWindow.Working, "Features.Shortcuts") is Map) {
            PreferencesWindow._Check("Features.Shortcuts.Enabled", "Mac.Shortcuts.Enabled")
            PreferencesWindow._Field("Features.Shortcuts.Keyword", "Mac.Shortcuts.Keyword", "M")
        }
        if Platform.IsMac {
            PreferencesWindow._Check("Features.Bookmarks.Safari", "Mac.Safari.Enabled")
            PreferencesWindow._Lines("Features.Bookmarks.Imports", "Mac.Bookmarks.Imports", 3)
        }
    }

    static _FeatureCheck(feature, x, y) {
        PreferencesWindow._y := y
        path := "Features." feature ".Enabled"
        control := PreferencesWindow._Add("Checkbox", "x" x " w" (PreferencesWindow.ContentW // 2 - 12), I18n.T("Prefs.Feature." feature))
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
        PreferencesWindow._Lines("Features.Applications.Hidden", "Prefs.AppHidden", 3)
        PreferencesWindow._Button("Prefs.RebuildIndex", (*) => App.RebuildIndex())
    }

    static _BuildFileSearch() {
        PreferencesWindow._BeginPage("Prefs.Page.FileSearch", 140)
        PreferencesWindow._Csv("Features.FileSearch.Keywords", "Prefs.FileKeywords", "M")
        PreferencesWindow._Csv("Features.FileSearch.FolderKeywords", "Prefs.FolderKeywords", "M")
        PreferencesWindow._Csv("Features.FileSearch.RecentKeywords", "Prefs.RecentKeywords", "M")
        PreferencesWindow._Lines("Features.FileSearch.TypeFilters", "Prefs.TypeFilters", 4)
        PreferencesWindow._Field("Features.FileSearch.MaxResults", "Prefs.FileMaxResults", "S", "number")
        PreferencesWindow._Check("Features.FileSearch.SpacePrefix", "Prefs.SpacePrefix")
        PreferencesWindow._Check("Features.FileSearch.QuotePrefix", "Prefs.QuotePrefix")
        PreferencesWindow._Check("Features.FileSearch.InDefaultResults", "Prefs.FileInDefault")
        PreferencesWindow._Field("Features.FileSearch.DefaultResultsLimit", "Prefs.FileDefaultLimit", "S", "number")
        PreferencesWindow._Field("Features.FileSearch.MinQueryLength", "Prefs.FileMinLength", "S", "number")
    }

    static _BuildFileIndex() {
        PreferencesWindow._BeginPage("Prefs.Page.FileIndex", 160)
        if Platform.IsWindows {
            PreferencesWindow._Check("Features.FileSearch.UseEverything", "Prefs.UseEverything")
            PreferencesWindow._Field("Features.FileSearch.EverythingFilter", "Prefs.EverythingFilter", "L")
            PreferencesWindow._Field("Features.FileSearch.EverythingPath", "Prefs.EverythingPath", "L", "folder")
        }
        if (Platform.IsMac && PreferencesWindow.Working["Features"]["FileSearch"].Has("Spotlight")) {
            PreferencesWindow._Check("Features.FileSearch.Spotlight", "Mac.Spotlight.Enabled")
            PreferencesWindow._Check("Features.FileSearch.SpotlightContent", "Mac.Spotlight.Content")
        }
        PreferencesWindow._Lines("Features.FileSearch.ScopeFolders", "Prefs.ScopeFolders", 4)
        PreferencesWindow._Field("Features.FileSearch.ScopeDepth", "Prefs.ScopeDepth", "S", "number")
        PreferencesWindow._Field("Features.FileSearch.ScopeExclude", "Prefs.ScopeExclude", "L")
        PreferencesWindow._Field("Features.FileSearch.MaxEntries", "Prefs.MaxEntries", "S", "number")
        PreferencesWindow._Field("Features.FileSearch.RefreshMinutes", "Prefs.RefreshMinutes", "S", "number")
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
        PreferencesWindow._Button("Snippet.Import", (*) => PreferencesWindow._ImportSnippets())
        PreferencesWindow._Button("Snippet.Export", (*) => PreferencesWindow._ExportSnippets())
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
        PreferencesWindow._Button("Prefs.ClipClear", (*) => ClipboardProvider.Clear())
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
        PreferencesWindow._Info("Prefs.Group.DataFolder", AppSettings.DataDir)
        PreferencesWindow._Button("Prefs.EditJson", (*) => Platform.Edit(AppSettings.File))
        PreferencesWindow._Button("Prefs.OpenDataFolder", (*) => Platform.Open(AppSettings.DataDir))
        PreferencesWindow._Button("Prefs.OpenThemes", (*) => Platform.Open(ThemeManager.UserDir))
        PreferencesWindow._Button("Prefs.ChangeDataFolder", (*) => PreferencesWindow._ChangeDataFolder())
        PreferencesWindow._Button("Prefs.OpenLog", (*) => App.OpenLog())
        PreferencesWindow._Button("Prefs.CopySystemInfo", (*) => PreferencesWindow._CopyDiagnostics())
        PreferencesWindow._Button("Tray.CheckUpdate", (*) => UpdateChecker.Check())
        PreferencesWindow._Button("Prefs.ResetLearning", (*) => PreferencesWindow._ResetLearning())
        PreferencesWindow._Button("Prefs.RestoreDefaults", (*) => PreferencesWindow._RestoreDefaults())
        if Platform.IsMac
            PreferencesWindow._Button("Mac.Permissions.Status", (*) => PreferencesWindow._ShowPermissions())
    }

    static _ResetLearning() {
        Knowledge.Picks := Knowledge._UidMap(), Knowledge.QueryPicks := Map(), Knowledge.History := [], Knowledge.Recent := []
        Knowledge.Save()
        MsgBox(I18n.T("Prefs.ResetDone"), App.Name, 64)
    }

    static _BuildQuickSwitch() {
        base := "Extensions.QuickSwitch."
        PreferencesWindow._BeginPage("Prefs.Page.QuickSwitch", 160)
        PreferencesWindow._Check(base "Enabled", "Prefs.EnableExtension")
        PreferencesWindow._Field(base "Hotkey", "Prefs.QSHotkey", "K", "hotkey")
        PreferencesWindow._Check(base "AutoSwitch", "Prefs.QSAuto")
        if Platform.IsWindows {
            PreferencesWindow._Check(base "StandardDialogs", "Prefs.QSStandard")
            PreferencesWindow._Check(base "BrowseDialogs", "Prefs.QSBrowse")
            PreferencesWindow._Lines(base "DialogWindows", "Prefs.QSOtherDialogs", 3)
        }
        PreferencesWindow._Lines(base "ExcludeWindows", "Prefs.QSExclude", 3)
        PreferencesWindow._Lines(base "AutoSwitchExclude", "Prefs.QSAutoExclude", 3)
    }

    static _BuildQSPanel() {
        base := "Extensions.QuickSwitch."
        PreferencesWindow._BeginPage("Prefs.Page.QSPanel", 160)
        PreferencesWindow._Check(base "ShowPanel", "Prefs.QSPanel")
        PreferencesWindow._Choice(base "PanelSearch", "Prefs.QSPanelSearch", ["folders", "all"], [I18n.T("Prefs.QSPanelSearch.Folders"), I18n.T("Prefs.QSPanelSearch.All")])
        PreferencesWindow._Field(base "RecentFolders", "Prefs.QSRecent", "S", "number")
        PreferencesWindow._Field(base "MenuHotkey", "Prefs.QSMenu", "K", "hotkey")
    }

    static _BuildDateStamp() {
        base := "Extensions.AutoDate."
        PreferencesWindow._BeginPage("Prefs.Page.DateStamp", 160)
        PreferencesWindow._Check(base "Enabled", "Prefs.EnableExtension")
        PreferencesWindow._Field(base "Hotkey", "Prefs.RenameHotkey", "K", "hotkey")
        PreferencesWindow._Field(base "DateFormat", "Prefs.DateFormat", "M")
        if !Platform.IsMac {
            PreferencesWindow._Lines(base "RenameWindows", "Prefs.RenameWindows", 3)
            PreferencesWindow._Lines(base "AppendWindows", "Prefs.AppendWindows", 3)
        }
    }

    static DraftValue(path) {
        for bind in PreferencesWindow.Binds
            if (bind.Path = path)
                return bind.Read.Call()
        return PreferencesWindow.GetPath(PreferencesWindow.Working, path)
    }

    static ImportSnippetText(text) {
        list := PreferencesWindow._lists["Snippets"]
        result := SnippetProvider.ImportRows(DelimitedText.Parse(text), list.Items, PreferencesWindow.DraftValue("Features.Snippets.ExpandPrefix"))
        if (result.Added || result.Updated) {
            PreferencesWindow.MarkDirty(true)
            list.Reload.Call()
        }
        return result
    }

    static ExportSnippetText() => DelimitedText.ToCsv(SnippetProvider.ExportRows(PreferencesWindow._lists["Snippets"].Items))

    static _ImportSnippets() {
        owner := PreferencesWindow.Gui, title := I18n.T("Snippet.Import.Title")
        colors := PreferencesWindow.Palette
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox +Resize +MinSize480x340", title)
        g.BackColor := colors["Background"]
        g.SetFont("s10 c" colors["Text"], ThemeManager.FontName())
        g.AddText("xm w560", I18n.T("Snippet.Import.Help"))
        g.AddText("xm y+6 w560", I18n.T("Snippet.Import.Columns"))
        box := g.AddEdit("xm y+8 w560 r12 +Multi +WantTab Background" colors["Surface"] " c" colors["InputText"])
        g.AddButton("xm y+12 w110", I18n.T("Snippet.Import.File")).OnEvent("Click", ChooseFile)
        g.AddButton("x+12 yp w110 Default", I18n.T("Snippet.Import.Ok")).OnEvent("Click", DoImport)
        g.AddButton("x+12 yp w110", I18n.T("Prefs.Cancel")).OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        owner.Opt("+Disabled")
        try {
            g.Show()
            WinWaitClose(g.Hwnd)
        } finally {
            owner.Opt("-Disabled")
            try owner.Show()
        }

        ChooseFile(*) {
            g.Opt("+OwnDialogs")
            selected := FileSelect(1, , title, I18n.T("Snippet.Import.Filter"))
            if (selected = "")
                return
            try box.Value := DelimitedText.ReadFile(selected)
            catch as e
                MsgBox(e.Message, title, "Icon! Owner" g.Hwnd)
        }
        DoImport(*) {
            result := PreferencesWindow.ImportSnippetText(box.Value)
            if !(result.Added || result.Updated)
                return MsgBox(I18n.T("Snippet.Import.None"), title, "Icon! Owner" g.Hwnd)
            MsgBox(I18n.T("Snippet.Import.Done", result.Added, result.Updated)
                . (result.Skipped ? "`n" I18n.T("Snippet.Import.Skipped", result.Skipped) : ""), title, "Iconi Owner" g.Hwnd)
            g.Destroy()
        }
    }

    static _ExportSnippets() {
        owner := PreferencesWindow.Gui, title := I18n.T("Snippet.Export")
        owner.Opt("+OwnDialogs")
        target := FileSelect("S16", "Snippets.csv", title, I18n.T("Snippet.Export.Filter"))
        if (target = "")
            return
        if !RegExMatch(target, "i)\.(csv|txt)$")
            target .= ".csv"
        try {
            output := FileOpen(target, "w", "UTF-8")
            try output.Write(PreferencesWindow.ExportSnippetText())
            finally output.Close()
        } catch as e {
            return MsgBox(e.Message, title, "Icon! Owner" owner.Hwnd)
        }
        MsgBox(I18n.T("Snippet.Export.Done", PreferencesWindow._lists["Snippets"].Items.Length, target), title, "Iconi Owner" owner.Hwnd)
    }

    static _usage := ""
    static _BuildUsage() {
        PreferencesWindow._BeginPage("Prefs.Page.Usage", 140)
        totals := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW " r2")
        PreferencesWindow._Below(8, totals)
        since := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW)
        PreferencesWindow._Below(12, since)
        chart := PreferencesWindow._Add("Picture", "w" PreferencesWindow.ContentW " h100")
        PreferencesWindow._Below(4, chart)
        chartLabel := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW " cGray")
        PreferencesWindow._Below(12, chartLabel)
        headers := []
        for key in ["Feature", "Today", "Week", "Month", "All", "Share"]
            headers.Push(I18n.T("Usage.Col." key))
        list := PreferencesWindow._Add("ListView", "w" PreferencesWindow.ContentW " h280 -Multi NoSort", headers)
        for index, width in [180, 65, 65, 65, 70, 70]
            list.ModifyCol(index, width)
        PreferencesWindow._Below(12, list)
        PreferencesWindow._Button("Usage.Clear", (*) => PreferencesWindow._ClearUsage())
        PreferencesWindow._usage := {Totals: totals, Since: since, Chart: chart, ChartLabel: chartLabel, List: list}
        PreferencesWindow._RefreshUsage()
    }

    static UsageRows() {
        periods := [Usage.Summary(1), Usage.Summary(7), Usage.Summary(30), Usage.Summary(0)], rows := []
        total := Usage.Total(periods[4])
        for feature in Usage.Features {
            counts := []
            for period in periods
                counts.Push(period.Has(feature) ? period[feature] : 0)
            rows.Push({Id: feature, Counts: counts, Share: total ? Format("{:.1f}%", counts[4] * 100 / total) : "0%"})
        }
        Loop rows.Length - 1 {
            i := A_Index + 1, entry := rows[i], j := i - 1
            while (j >= 1 && rows[j].Counts[4] < entry.Counts[4])
                rows[j + 1] := rows[j], j -= 1
            rows[j + 1] := entry
        }
        counts := []
        for period in periods
            counts.Push(period.Has("Show") ? period["Show"] : 0)
        rows.Push({Id: "Show", Counts: counts, Share: "-"})
        return rows
    }

    static _RefreshUsage() {
        ui := PreferencesWindow._usage
        ui.Totals.Value := I18n.T("Usage.Totals", Usage.Total(Usage.Summary(1)), Usage.Total(Usage.Summary(7)), Usage.Total(Usage.Summary(30)), Usage.Total(Usage.Summary(0)))
        all := Usage.Summary()
        ui.Since.Value := I18n.T("Usage.Since", Usage.Since != "" ? Usage.Since : FormatTime(, "yyyy-MM-dd"), all.Has("Show") ? all["Show"] : 0)
        ui.List.Delete()
        for row in PreferencesWindow.UsageRows() {
            cells := [I18n.T("Usage.F." row.Id)]
            for count in row.Counts
                cells.Push(count)
            cells.Push(row.Share)
            ui.List.Add("", cells*)
        }
        daily := Usage.Daily(30), most := 1, width := PreferencesWindow.ContentW
        for day in daily
            most := Max(most, day[2])
        ui.ChartLabel.Value := SubStr(daily[1][1], 6) " — " I18n.T("Usage.Today") "   " I18n.T("Usage.Chart", most)
        descriptions := []
        for day in daily
            descriptions.Push(day[1] ": " day[2])
        LauncherCanvas.AccessibleLabel(ui.Chart, TextTools.JoinList(descriptions, "; "))
        canvas := Image.Create(width, 100, , PreferencesWindow.Gui.PixelScale)
        canvas.FillRect(0, 0, width, 100, PreferencesWindow.Palette["Surface"])
        for index, day in daily {
            barHeight := Round(day[2] * 82 / most)
            if barHeight
                canvas.FillRect((index - 1) * width / 30 + 2, 88 - barHeight, width / 30 - 4, barHeight, PreferencesWindow.Palette["Accent"])
        }
        ui.Chart.Value := "HBITMAP:" canvas.ToBitmap()
        canvas.Dispose()
    }

    static _ClearUsage() {
        if (MsgBox(I18n.T("Usage.ClearConfirm"), App.Name, "YesNo Icon? Default2 Owner" PreferencesWindow.Gui.Hwnd) != "Yes")
            return
        Usage.Clear()
        PreferencesWindow._RefreshUsage()
    }

    static DataFoldersOverlap(first, second) {
        first := Platform.Identity(Path.Full(first)), second := Platform.Identity(Path.Full(second))
        if Platform.IsWindows
            first := StrReplace(first, "\", "/"), second := StrReplace(second, "\", "/")
        first := RTrim(first, "/") "/", second := RTrim(second, "/") "/"
        return SubStr(first, 1, StrLen(second)) == second || SubStr(second, 1, StrLen(first)) == first
    }

    static _ChangeDataFolder() {
        current := AppSettings.DataDir
        folder := DirSelect(current, 3, I18n.T("Prefs.DataFolderPrompt"))
        if (folder = "" || AppSettings._SameLocation(folder, current))
            return
        if PreferencesWindow.DataFoldersOverlap(current, folder)
            return MsgBox(I18n.T("Prefs.DataFolderNested"), App.Name, "Icon! Owner" PreferencesWindow.Gui.Hwnd)
        useExisting := false
        if FileExist(Platform.Join(folder, "ALTRun.json")) {
            answer := MsgBox(I18n.T("Prefs.DataFolderExisting", folder), App.Name, "YesNoCancel Icon? Owner" PreferencesWindow.Gui.Hwnd)
            if (answer = "Cancel")
                return
            useExisting := answer = "Yes"
        } else if (MsgBox(I18n.T("Prefs.DataFolderCopy", folder), App.Name, "OKCancel Icon? Owner" PreferencesWindow.Gui.Hwnd) != "OK")
            return
        if PreferencesWindow.Cancel()
            return
        try {
            if !useExisting {
                AppSettings.Save(), Knowledge.Save(), Usage.Save(), ClipboardProvider.Save()
                DirCopy(current, folder, true)
            }
            AppSettings.SetDataLocation(folder)
        } catch as e {
            return MsgBox(I18n.T("Prefs.DataFolderFailed", folder, e.Message), App.Name, "Icon!")
        }
        App.Reload()
    }

    static _RestoreDefaults() {
        if (MsgBox(I18n.T("Prefs.RestoreDefaultsConfirm"), App.Name, "YesNo Icon! Default2 Owner" PreferencesWindow.Gui.Hwnd) != "Yes")
            return
        try {
            if FileExist(AppSettings.File)
                FileCopy(AppSettings.File, AppSettings.File ".bak", true)
        } catch as e {
            return MsgBox(I18n.T("Settings.SaveError", e.Message), App.Name, "Icon! Owner" PreferencesWindow.Gui.Hwnd)
        }
        AppSettings.Data := AppSettings.ResetData(AppSettings.Data)
        if AppSettings.Save()
            App.Reload()
    }

    static PermissionReport() {
        capabilities := RequestCapabilities()                              ; No arguments queries status without prompting.
        text := ""
        for name in ["InputMonitoring", "InputControl", "WindowMonitoring", "WindowControl", "ScreenCapture", "ClipboardMonitoring"]
            text .= (text = "" ? "" : "`n") name ": " capabilities.%name%
        return text
    }

    static _ShowPermissions() => MsgBox(PreferencesWindow.PermissionReport(), I18n.T("Mac.Permissions.Status"), "Iconi Owner" PreferencesWindow.Gui.Hwnd)

    static _CopyDiagnostics() {
        A_Clipboard := App.SystemInfo() (Platform.IsMac ? "`n`n" PreferencesWindow.PermissionReport() : "")
        App.Notify(I18n.T("Prefs.SystemInfoCopied"))
    }

    static _BeginPage(nameKey, labelW := 190) {
        PreferencesWindow.Pages.Push({Key: nameKey, Name: I18n.T(nameKey), Wiki: PreferencesWindow.WikiPage(nameKey), Controls: []})
        PreferencesWindow._y := PreferencesWindow.HeaderH
        PreferencesWindow.LabelW := Max(180, labelW)
    }

    static _Add(type, options, text := "") {
        if ((type = "Edit" || type = "Text") && !IsObject(text))
            text := text ""
        options := RegExReplace(options, "i)(^|\s)cGray\b", "$1c" PreferencesWindow.Palette["Muted"])
        if !RegExMatch(options, "i)(^|\s)c[0-9a-f]{6}\b")
            options .= " c" PreferencesWindow.Palette[(type = "Edit" || type = "DropDownList" || type = "ComboBox") ? "InputText" : "Text"]
        switch type, false {
            case "Edit", "DropDownList", "ComboBox", "ListView", "Button":
                options .= " Background" PreferencesWindow.Palette["Surface"]
                if (type = "Edit" && InStr(options, "-Multi") && !RegExMatch(options, "i)(^|\s)h\d"))
                    options .= " h" PreferencesWindow.ButtonH
            case "Text", "Checkbox", "Radio":
                options .= " Background" PreferencesWindow.Palette["Background"]
        }
        pos := InStr(options, " x") || InStr(options, "x") = 1 ? "" : "x" PreferencesWindow.ContentX " "
        ctrl := PreferencesWindow.Gui.Add(type, pos "y" PreferencesWindow._y " " options " Hidden", text)
        PreferencesWindow.StyleNative(ctrl, type, PreferencesWindow.Palette)
        if (type = "Text" && text != "")
            PreferencesWindow.FitText(ctrl)
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
        PreferencesWindow.Gui.SetFont("s" (PreferencesWindow.UiFont + 1) " bold")
        ctrl := PreferencesWindow._Add("Text", "w" PreferencesWindow.ContentW " c" PreferencesWindow.Palette["Accent"], I18n.T(labelKey))
        PreferencesWindow.Gui.SetFont("s" PreferencesWindow.UiFont " norm")
        PreferencesWindow._Below(PreferencesWindow._HasDesc(labelKey) ? 6 : 14, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow.ContentX)
    }

    static _HasDesc(labelKey) {
        return I18n.Strings.Has(PreferencesWindow._DescriptionKey(labelKey))
    }

    static _DescriptionKey(labelKey) {
        if !Platform.IsWindows {
            if (labelKey = "Prefs.FileManager")
                return labelKey (Platform.IsMac ? ".Mac.Desc" : ".Linux.Desc")
            if (Platform.IsMac && (labelKey = "Prefs.Hotkey" || labelKey = "Prefs.SecondaryHotkey"))
                return labelKey ".Desc"
            if I18n.Strings.Has(labelKey ".Portable.Desc")
                return labelKey ".Portable.Desc"
        }
        return labelKey ".Desc"
    }

    static _Desc(labelKey, x, text := "") {
        if (text = "") {
            if !PreferencesWindow._HasDesc(labelKey)
                return
            key := PreferencesWindow._DescriptionKey(labelKey)
            text := key = "Prefs.SaveLog.Portable.Desc" ? I18n.T(key, Logger.File) : I18n.T(key)
            if (key = "Prefs.SelectionHotkey.Desc")
                text := RegExReplace(text, "i)\s*<a\b[^>]*>.*?</a>", "")
        }
        PreferencesWindow.Gui.SetFont("s" PreferencesWindow.HintFont)
        ctrl := PreferencesWindow._Add("Text", "x" x " w" (PreferencesWindow.ContentX + PreferencesWindow.ContentW - x) " c" PreferencesWindow.Palette["Muted"], text)
        PreferencesWindow.Gui.SetFont("s" PreferencesWindow.UiFont)
        PreferencesWindow._Below(12, ctrl)
    }

    static _Note(textKey) {
        if (!Platform.IsWindows && I18n.Strings.Has(textKey ".Portable"))
            textKey .= ".Portable"
        PreferencesWindow._Desc("", PreferencesWindow.ContentX, I18n.T(textKey))
    }

    static _Label(labelKey) {
        PreferencesWindow._y += 3
        ctrl := PreferencesWindow._Add("Text", "w" (PreferencesWindow.LabelW - 20), I18n.T(labelKey))
        PreferencesWindow._y -= 3
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
        groupControl := (group != "") ? PreferencesWindow._GroupLabel(group) : ""
        ctrl := PreferencesWindow._Add("Checkbox", "x" x " w" (width ? width : PreferencesWindow.ContentX + PreferencesWindow.ContentW - x), I18n.T(labelKey))
        ctrl.Value := PreferencesWindow.GetPath(PreferencesWindow.Working, path) ? 1 : 0
        PreferencesWindow._Bind(path, () => ctrl.Value)
        hasDesc := (desc != "" || PreferencesWindow._HasDesc(labelKey))
        if IsObject(groupControl)
            PreferencesWindow._Below(hasDesc ? 2 : PreferencesWindow.RowGap, ctrl, groupControl)
        else
            PreferencesWindow._Below(hasDesc ? 2 : PreferencesWindow.RowGap, ctrl)
        PreferencesWindow._Desc(labelKey, x + 18, desc)                     ; 和复选框的文字对齐
        return ctrl
    }

    static _GroupLabel(labelKey, dy := 1) {
        PreferencesWindow._y += dy
        ctrl := PreferencesWindow._Add("Text", "x" PreferencesWindow.ContentX " w" (PreferencesWindow.LabelW - 20), I18n.T(labelKey))
        PreferencesWindow._y -= dy
        return ctrl
    }

    static _Info(labelKey, text, options := "", type := "Text") {
        label := PreferencesWindow._GroupLabel(labelKey)
        ctrl := PreferencesWindow._Add(type, "x" PreferencesWindow._InputX() " w" PreferencesWindow._InputW() " " options, text)
        PreferencesWindow._Below(6, label, ctrl)
        return ctrl
    }

    static _Field(path, labelKey, size, kind := "text", values := "", labels := "") {
        label := PreferencesWindow._Label(labelKey)
        ctrl := PreferencesWindow._Input(PreferencesWindow._InputX(), path, labelKey, size, kind, values, labels)
        PreferencesWindow._BelowInput(labelKey, label, ctrl)
        return ctrl
    }

    static _BelowInput(labelKey, controls*) {
        hasDesc := PreferencesWindow._HasDesc(labelKey)
        PreferencesWindow._Below(hasDesc ? 5 : PreferencesWindow.RowGap, controls*)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
    }

    static _Choice(path, labelKey, values, labels, size := "M")
        => PreferencesWindow._Field(path, labelKey, size, "choice", values, labels)

    static _Lines(path, labelKey, rows) {
        label := PreferencesWindow._Label(labelKey)
        value := PreferencesWindow.JoinLines(PreferencesWindow.GetPath(PreferencesWindow.Working, path))
        ctrl := PreferencesWindow._Add("Edit", "x" PreferencesWindow._InputX() " w" PreferencesWindow._InputW() " r" rows " +Multi -Wrap +HScroll +VScroll", value)
        PreferencesWindow._Bind(path, () => PreferencesWindow.SplitLines(ctrl.Value))
        PreferencesWindow._Below(3, label, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
    }

    static _Csv(path, labelKey, size) => PreferencesWindow._Field(path, labelKey, size, "csv")

    static _Button(labelKey, fn, group := "") {
        if (group != "")
            PreferencesWindow._GroupLabel(group, 5)                         ; 和按钮上的文字对齐
        ctrl := PreferencesWindow._Add("Button", "x" PreferencesWindow._InputX() " w" PreferencesWindow.ButtonW " h" PreferencesWindow.ButtonH, I18n.T(labelKey))
        ctrl.OnEvent("Click", fn)
        PreferencesWindow._Below(PreferencesWindow._HasDesc(labelKey) ? 2 : 6, ctrl)
        PreferencesWindow._Desc(labelKey, PreferencesWindow._InputX())
        return ctrl
    }

    static _Pair(left, right) {
        label := PreferencesWindow._Label(left[2])
        first := PreferencesWindow._Input(PreferencesWindow._InputX(), left*)
        first.GetPos(&x, , &w)
        PreferencesWindow._y += 3
        label2 := PreferencesWindow._Add("Text", "x" (x + w + 18), I18n.T(right[2]))
        PreferencesWindow._y -= 3
        label2.GetPos(&x2, , &w2)
        secondW := 0
        overflow := x2 + w2 + 8 + (secondW ? secondW : PreferencesWindow._Width(right[3])) - (PreferencesWindow.ContentX + PreferencesWindow.ContentW)
        if (overflow > 0 && left[3] = right[3] && w > PreferencesWindow.WidthS) {
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
        browseKind := (kind = "file" || kind = "folder")
        ctrl := PreferencesWindow._Add("Edit", "x" x " w" PreferencesWindow._Width(size, browseKind) " r1 -Multi" (kind = "number" ? " Number" : ""), text)
        if browseKind {
            browse := PreferencesWindow._Add("Button", "x+4 yp-1 w30", I18n.T("Prefs.Browse"))
            browseFn := ItemEditor._Browser(ctrl, kind, PreferencesWindow.Gui)
            browse.OnEvent("Click", (p*) => (browseFn(p*), PreferencesWindow.MarkDirty()))
        }
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
        ctrl.Opt("Background" PreferencesWindow.Palette["Surface"] " c" PreferencesWindow.Palette["InputText"])
        PreferencesWindow.StyleNative(ctrl, "Edit", PreferencesWindow.Palette)
        PreferencesWindow.Pages[PreferencesWindow.Pages.Length].Controls.Push(ctrl)
        PreferencesWindow._Bind(path, () => HotkeyBox.Value(ctrl))
        return ctrl
    }

    static _List(path, height, columns, fields, newItem, check := "") {
        height := Min(height, Max(220, PreferencesWindow._viewHeight - PreferencesWindow.HeaderH - 155))
        items := PreferencesWindow.GetPath(PreferencesWindow.Working, path)
        headers := []
        for column in columns
            headers.Push(I18n.T(column[1]))
        listView := PreferencesWindow._Add("ListView", "w" PreferencesWindow.ContentW " h" (height - 40) " -Multi NoSort", headers)
        try listView.ToClr().RowHeight := ThemeManager.Density = "Compact" ? 27 : 31
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
        PreferencesWindow._lists[path] := {Items: items, Insert: Insert, Append: Append, Edit: EditExisting, Reload: Refresh}   ; Draft lists are independent of saved settings.
        PreferencesWindow._y += height - 34
        PreferencesWindow._Add("Button", "w80", I18n.T("Prefs.Add")).OnEvent("Click", AddItem)
        PreferencesWindow._Add("Button", "x+8 yp w80", I18n.T("Prefs.Edit")).OnEvent("Click", EditItem)
        PreferencesWindow._Add("Button", "x+8 yp w80", I18n.T("Prefs.Delete")).OnEvent("Click", DeleteItem)
        if IsObject(check)
            PreferencesWindow._Add("Button", "x+24 yp w100", I18n.T("Prefs.CheckTargets")).OnEvent("Click", CheckItems)
        listView.GetPos(&listX, , &listW)
        filterBox := PreferencesWindow.Gui.Add("Edit", "x" (listX + listW - 160) " yp+1 w160 r1 -Multi Hidden")   ; 不用 _Add: 筛选不算修改设置
        filterBox.Opt("Background" PreferencesWindow.Palette["Surface"] " c" PreferencesWindow.Palette["InputText"])
        PreferencesWindow.StyleNative(filterBox, "Edit", PreferencesWindow.Palette)
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

    static JoinCsv(items) {
        if !(items is Array)
            return items
        out := ""
        for index, item in items
            out .= (index = 1 ? "" : ", ") item
        return out
    }
}

#if WINDOWS
#CSharp
public static long ALTRunPreferenceTextHeight(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapped, double Width)
{
    if (Wrapped.Native is not System.Windows.Forms.Label label) return 0;
    double scale = label.DeviceDpi / 96d;
    return (long)System.Math.Ceiling(label.GetPreferredSize(new System.Drawing.Size((int)System.Math.Ceiling(Width * scale), 0)).Height / scale) + 2;
}

public static object ALTRunStylePreferenceControl(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapped, string Kind,
    string Background, string Foreground, string Border, string Selected, string SelectedText, string Backdrop, string BodyText, string Muted)
{
    System.Drawing.Color Color(string value) => System.Drawing.Color.FromArgb(unchecked((int)0xFF000000) | System.Convert.ToInt32(value, 16));
    var background = Color(Background);
    var foreground = Color(Foreground);
    var border = Color(Border);
    var selected = Color(Selected);
    var selectedText = Color(SelectedText);
    var muted = Color(Muted);
    var bodyText = Color(BodyText);
    if (Wrapped.Native is System.Windows.Forms.ComboBox combo)
    {
        combo.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
        combo.BackColor = background;
        combo.ForeColor = foreground;
        combo.DrawMode = System.Windows.Forms.DrawMode.OwnerDrawFixed;
        combo.ItemHeight = System.Math.Max(20, combo.Font.Height + 8);
        combo.DrawItem += (_, e) =>
        {
            bool chosen = (e.State & System.Windows.Forms.DrawItemState.Selected) != 0 && combo.DroppedDown;
            using var brush = new System.Drawing.SolidBrush(chosen ? selected : background);
            e.Graphics.FillRectangle(brush, e.Bounds);
            string label = e.Index >= 0 && e.Index < combo.Items.Count ? combo.GetItemText(combo.Items[e.Index]) : combo.Text;
            var bounds = System.Drawing.Rectangle.Inflate(e.Bounds, -6, 0);
            System.Windows.Forms.TextRenderer.DrawText(e.Graphics, label, combo.Font, bounds, !combo.Enabled ? muted : chosen ? selectedText : foreground,
                System.Windows.Forms.TextFormatFlags.Left | System.Windows.Forms.TextFormatFlags.VerticalCenter
                | System.Windows.Forms.TextFormatFlags.EndEllipsis | System.Windows.Forms.TextFormatFlags.NoPrefix);
        };
    }
    else if (Wrapped.Native is System.Windows.Forms.TextBox edit)
    {
        edit.BorderStyle = System.Windows.Forms.BorderStyle.None;
        edit.BackColor = background;
        edit.ForeColor = foreground;
    }
    else if (Wrapped.Native is System.Windows.Forms.Button button)
    {
        button.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
        button.UseVisualStyleBackColor = false;
        var normalBackground = button.BackColor.ToArgb() == selected.ToArgb() ? selected : background;
        var normalText = normalBackground.ToArgb() == selected.ToArgb() ? selectedText : bodyText;
        button.BackColor = normalBackground;
        button.ForeColor = button.Enabled ? normalText : muted;
        button.FlatAppearance.BorderColor = border;
        button.FlatAppearance.BorderSize = 1;
        button.FlatAppearance.MouseOverBackColor = selected;
        button.FlatAppearance.MouseDownBackColor = selected;
        button.MouseEnter += (_, _) => { if (button.Enabled) button.ForeColor = selectedText; };
        button.MouseLeave += (_, _) => button.ForeColor = button.Enabled ? normalText : muted;
        button.EnabledChanged += (_, _) => button.ForeColor = button.Enabled ? normalText : muted;
        button.Paint += (_, e) =>
        {
            if (button.Enabled) return;
            using var brush = new System.Drawing.SolidBrush(normalBackground);
            using var pen = new System.Drawing.Pen(border);
            e.Graphics.FillRectangle(brush, button.ClientRectangle);
            var bounds = button.ClientRectangle;
            bounds.Width -= 1;
            bounds.Height -= 1;
            e.Graphics.DrawRectangle(pen, bounds);
            System.Windows.Forms.TextRenderer.DrawText(e.Graphics, button.Text, button.Font, button.ClientRectangle, muted,
                System.Windows.Forms.TextFormatFlags.HorizontalCenter | System.Windows.Forms.TextFormatFlags.VerticalCenter
                | System.Windows.Forms.TextFormatFlags.EndEllipsis | System.Windows.Forms.TextFormatFlags.NoPrefix);
        };
    }
    else if (Wrapped.Native is System.Windows.Forms.CheckBox checkbox)
    {
        checkbox.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
        checkbox.UseVisualStyleBackColor = false;
        checkbox.BackColor = Color(Backdrop);
        checkbox.ForeColor = bodyText;
        checkbox.FlatAppearance.BorderColor = border;
        checkbox.FlatAppearance.CheckedBackColor = selected;
    }
    else if (Wrapped.Native is System.Windows.Forms.ListView list)
    {
        list.BorderStyle = System.Windows.Forms.BorderStyle.None;
        list.BackColor = background;
        list.ForeColor = bodyText;
        list.OwnerDraw = true;
        if (Kind == "Navigation")
        {
            int height = System.Math.Max((int)System.Math.Ceiling(32d * list.DeviceDpi / 96d), list.Font.Height + 12);
            var spacing = new System.Windows.Forms.ImageList { ImageSize = new System.Drawing.Size(1, height), ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit };
            var blank = new System.Drawing.Bitmap(1, height);
            spacing.Images.Add(blank);
            list.SmallImageList = spacing;
            list.Disposed += (_, _) => { spacing.Dispose(); blank.Dispose(); };
        }
        list.DrawColumnHeader += (_, e) =>
        {
            using var brush = new System.Drawing.SolidBrush(background);
            e.Graphics.FillRectangle(brush, e.Bounds);
            var bounds = System.Drawing.Rectangle.Inflate(e.Bounds, -6, 0);
            System.Windows.Forms.TextRenderer.DrawText(e.Graphics, e.Header.Text, list.Font, bounds, muted,
                System.Windows.Forms.TextFormatFlags.Left | System.Windows.Forms.TextFormatFlags.VerticalCenter
                | System.Windows.Forms.TextFormatFlags.EndEllipsis | System.Windows.Forms.TextFormatFlags.NoPrefix);
        };
        list.DrawItem += (_, e) =>
        {
            using var brush = new System.Drawing.SolidBrush(e.Item.Selected ? selected : background);
            e.Graphics.FillRectangle(brush, e.Bounds);
        };
        list.DrawSubItem += (_, e) =>
        {
            bool chosen = e.Item.Selected;
            using var brush = new System.Drawing.SolidBrush(chosen ? selected : background);
            e.Graphics.FillRectangle(brush, e.Bounds);
            var bounds = System.Drawing.Rectangle.Inflate(e.Bounds, -6, 0);
            System.Windows.Forms.TextRenderer.DrawText(e.Graphics, e.SubItem.Text, list.Font, bounds, !list.Enabled ? muted : chosen ? selectedText : bodyText,
                System.Windows.Forms.TextFormatFlags.Left | System.Windows.Forms.TextFormatFlags.VerticalCenter
                | System.Windows.Forms.TextFormatFlags.EndEllipsis | System.Windows.Forms.TextFormatFlags.NoPrefix);
        };
    }
    return null;
}
#EndCSharp
#endif

#if OSX
#CSharp
public static long ALTRunPreferenceTextHeight(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapped, double width)
{
    var control = (Eto.Forms.Control)wrapped.Native;
    return (long)System.Math.Ceiling(control.GetPreferredSize(new Eto.Drawing.SizeF((float)width, float.PositiveInfinity)).Height);
}
#EndCSharp
#endif

#if LINUX
#CSharp
public static long ALTRunPreferenceTextHeight(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapped, double Width)
{
    if (Wrapped.Native is not Eto.Forms.Label label) return 0;
    return ALTRunGtkPreferenceStyle.MeasureTextHeight(label.NativeHandle, Width);
}

public static object ALTRunStyleGtkPreferenceControl(Keysharp.Builtins.Ks.Clr.ManagedInstance Wrapped, string Kind,
    string Background, string Foreground, string Border, string Selected, string SelectedText, string Backdrop, string BodyText, string Muted)
{
    if (Wrapped.Native is not Eto.Forms.Control control || control is Eto.Forms.Label) return null;
    var palette = new ALTRunGtkPreferenceStyle.Palette(Background, Foreground, Border, Selected, SelectedText, Backdrop, BodyText, Muted);
    ALTRunGtkPreferenceStyle.Apply(control.NativeHandle, Kind, palette);
    if (control is Eto.Forms.ComboBox)
        ALTRunGtkPreferenceStyle.WatchPopup(control.NativeHandle);
    if (control is Eto.Forms.GridView grid)
    {
        Eto.Drawing.Color Color(string value)
        {
            int rgb = System.Convert.ToInt32(value, 16);
            return Eto.Drawing.Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255);
        }
        var background = Color(Background);
        var foreground = Color(BodyText);
        var selected = Color(Selected);
        var selectedText = Color(SelectedText);
        grid.CellFormatting += (_, e) =>
        {
            bool chosen = System.Linq.Enumerable.Contains(grid.SelectedRows, e.Row);
            e.ForegroundColor = chosen ? selectedText : foreground;
            e.BackgroundColor = chosen ? selected : background;
        };
    }
    return null;
}

private static class ALTRunGtkPreferenceStyle
{
    internal sealed record Palette(string Surface, string Input, string Border, string Selected, string SelectedText, string Background, string Text, string Muted);
    private sealed record Binding(System.IntPtr Screen, System.IntPtr Provider, Palette Colors);
    private static readonly System.Collections.Generic.Dictionary<System.IntPtr, Binding> Bindings = new();
    private static long next;
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private delegate void Destroyed(System.IntPtr widget, System.IntPtr data);
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private delegate void Notified(System.IntPtr widget, System.IntPtr parameter, System.IntPtr data);
    private static readonly Destroyed DestroyCallback = Release;
    private static readonly Notified PopupCallback = StylePopup;

    internal static long MeasureTextHeight(System.IntPtr widget, double width)
    {
        var original = GetLabelLayout(widget);
        if (original == System.IntPtr.Zero) return 0;
        var layout = CopyLayout(original);
        try
        {
            // GTK's preferred size can retain the label's explicit one-line height request.
            SetLayoutWidth(layout, (int)System.Math.Max(1, System.Math.Floor(width) - 4) * 1024);
            SetLayoutWrap(layout, 2);
            SetLayoutEllipsize(layout, 0);
            SetSingleParagraph(layout, 0);
            GetLayoutPixelSize(layout, out _, out var height);
            return height + 4L;
        }
        finally { Unref(layout); }
    }

    internal static void Apply(System.IntPtr widget, string kind, Palette colors)
    {
        if (widget == System.IntPtr.Zero) return;
        Release(widget, System.IntPtr.Zero);
        string name = "altrun-prefs-" + System.Threading.Interlocked.Increment(ref next);
        SetName(widget, name);
        string root = "#" + name;
        bool plain = kind is "Text" or "Checkbox" or "Radio" or "check" or "CheckBox";
        bool primary = kind == "PrimaryButton";
        string background = primary ? colors.Selected : plain ? colors.Background : colors.Surface;
        string foreground = primary ? colors.SelectedText : plain || kind is "Button" or "Navigation" or "ListView" ? colors.Text : colors.Input;
        string css = root + ", " + root + " * { background-image: none; background-color: #" + background
            + "; color: #" + foreground + "; border-color: #" + colors.Border + "; box-shadow: none; text-shadow: none; }\n"
            + root + " button:hover, " + root + " button:hover *, " + root + " menuitem:hover, " + root + " menuitem:hover *, "
            + root + ":selected, " + root + " *:selected, " + root + " selection { background-color: #" + colors.Selected
            + "; color: #" + colors.SelectedText + "; }\n"
            + root + ":disabled, " + root + " *:disabled { background-image: none; background-color: #" + background + "; color: #" + colors.Muted + "; }\n"
            + root + " check, " + root + " radio { background-color: #" + colors.Surface + "; border-color: #" + colors.Border + "; }\n"
            + root + " check:checked, " + root + " radio:checked { background-color: #" + colors.Selected + "; color: #" + colors.SelectedText + "; }\n"
            + root + ":focus { outline-color: #" + colors.Selected + "; outline-style: solid; outline-width: 1px; outline-offset: 1px; }\n";
        if (kind is "Button" or "PrimaryButton")
            css += root + ":hover, " + root + ":hover *, " + root + ":active, " + root + ":active * { background-color: #" + colors.Selected + "; color: #" + colors.SelectedText + "; }\n";
        var provider = NewProvider();
        if (Load(provider, css, new System.IntPtr(-1), out var error) == 0)
        {
            string message = error == System.IntPtr.Zero ? "Unknown GTK CSS error." : System.Runtime.InteropServices.Marshal.PtrToStringUTF8(System.Runtime.InteropServices.Marshal.ReadIntPtr(error, 8));
            if (error != System.IntPtr.Zero) FreeError(error);
            Unref(provider);
            throw new System.InvalidOperationException(message);
        }
        var screen = GetScreen(widget);
        AddProvider(screen, provider, 801);
        Bindings[widget] = new Binding(screen, provider, colors);
        ConnectDestroy(widget, "destroy", DestroyCallback, System.IntPtr.Zero, System.IntPtr.Zero, 0);
    }

    internal static void WatchPopup(System.IntPtr widget) => ConnectNotify(widget, "notify::popup-shown", PopupCallback, System.IntPtr.Zero, System.IntPtr.Zero, 0);

    private static void StylePopup(System.IntPtr widget, System.IntPtr parameter, System.IntPtr data)
    {
        try
        {
            if (!Bindings.TryGetValue(widget, out var binding)) return;
            var accessible = GetPopupAccessible(widget);
            if (accessible == System.IntPtr.Zero) return;
            var popup = GetAccessibleWidget(accessible);
            if (popup != System.IntPtr.Zero && popup != widget && !Bindings.ContainsKey(popup))
                Apply(popup, "Popup", binding.Colors);
        }
        catch (System.Exception error) { System.Diagnostics.Debug.WriteLine(error); }
    }

    private static void Release(System.IntPtr widget, System.IntPtr data)
    {
        if (!Bindings.Remove(widget, out var binding)) return;
        RemoveProvider(binding.Screen, binding.Provider);
        Unref(binding.Provider);
    }

    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_set_name", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void SetName(System.IntPtr widget, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string name);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_widget_get_screen", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr GetScreen(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_css_provider_new", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr NewProvider();
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_css_provider_load_from_data", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern int Load(System.IntPtr provider, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string css, System.IntPtr length, out System.IntPtr error);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_style_context_add_provider_for_screen", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void AddProvider(System.IntPtr screen, System.IntPtr provider, uint priority);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_style_context_remove_provider_for_screen", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void RemoveProvider(System.IntPtr screen, System.IntPtr provider);
    [System.Runtime.InteropServices.DllImport("libgobject-2.0.so.0", EntryPoint = "g_object_unref", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void Unref(System.IntPtr value);
    [System.Runtime.InteropServices.DllImport("libglib-2.0.so.0", EntryPoint = "g_error_free", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void FreeError(System.IntPtr error);
    [System.Runtime.InteropServices.DllImport("libgobject-2.0.so.0", EntryPoint = "g_signal_connect_data", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern ulong ConnectDestroy(System.IntPtr widget, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string signal, Destroyed callback, System.IntPtr data, System.IntPtr destroy, int flags);
    [System.Runtime.InteropServices.DllImport("libgobject-2.0.so.0", EntryPoint = "g_signal_connect_data", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern ulong ConnectNotify(System.IntPtr widget, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string signal, Notified callback, System.IntPtr data, System.IntPtr destroy, int flags);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_combo_box_get_popup_accessible", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr GetPopupAccessible(System.IntPtr combo);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_accessible_get_widget", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr GetAccessibleWidget(System.IntPtr accessible);
    [System.Runtime.InteropServices.DllImport("libgtk-3.so.0", EntryPoint = "gtk_label_get_layout", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr GetLabelLayout(System.IntPtr widget);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_copy", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern System.IntPtr CopyLayout(System.IntPtr layout);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_set_width", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void SetLayoutWidth(System.IntPtr layout, int width);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_set_wrap", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void SetLayoutWrap(System.IntPtr layout, int wrap);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_set_ellipsize", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void SetLayoutEllipsize(System.IntPtr layout, int ellipsize);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_set_single_paragraph_mode", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void SetSingleParagraph(System.IntPtr layout, int singleParagraph);
    [System.Runtime.InteropServices.DllImport("libpango-1.0.so.0", EntryPoint = "pango_layout_get_pixel_size", CallingConvention = System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private static extern void GetLayoutPixelSize(System.IntPtr layout, out int width, out int height);
}
#EndCSharp
#endif

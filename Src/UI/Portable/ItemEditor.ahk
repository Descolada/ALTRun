; ItemEditor.ahk - Themed native field editors for commands, snippets and search engines.

class ItemEditor {
    static Gui := "", _activeState := ""

    static Edit(owner, title, fields, item) {
        state := {Result: "", Open: true}                                               ; 嵌套函数 OnOk 通过它把结果交回来
        colors := PreferencesWindow.Colors()
        fontSize := ThemeManager.Density = "Compact" ? 9.5 : ThemeManager.Density = "Comfortable" ? 10.5 : 10
        rowHeight := ThemeManager.Density = "Compact" ? 30 : 34
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox +AutoScroll", title)
        ItemEditor.Gui := g, ItemEditor._activeState := state
        g.BackColor := colors["Background"]
        g.SetFont("s" fontSize " c" colors["Text"], ThemeManager.FontName())
        g.MarginX := 0, g.MarginY := 0
        controls := Map(), passBoxes := Map()
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        screenScale := LauncherCanvas.ScreenScale(g)
        windowW := Max(660, Min(860, Floor((right - left) / screenScale) - 74))
        maxHeight := Max(460, Floor((bottom - top) / screenScale) - 90)
        labelW := 160, inputX := labelW + 44, inputW := windowW - inputX - 28
        header := g.AddPicture("x0 y0 w" windowW " h76")
        ItemEditor._PaintHeader(header, g, windowW, title, colors)
        g.OnEvent("DpiChanged", (*) => ItemEditor._PaintHeader(header, g, windowW, title, colors))
        rowY := 92
        inputColors := " c" colors["InputText"] " Background" colors["Surface"]
        buttonColors := " c" colors["Text"] " Background" colors["Surface"]

        for field in fields {
            label := g.AddText("x26 y" (rowY + 5) " w" labelW " Background" colors["Background"], (field.Type = "check") ? "" : field.Label)
            PreferencesWindow.FitText(label)
            value := item.Has(field.Key) ? item[field.Key] : ""
            if !IsObject(value)
                value := value ""
            position := "x" inputX " y" rowY " "
            rowBottom := rowY + rowHeight
            switch field.Type {
                case "multiline":
                    ctrl := g.AddEdit(position "w" inputW " r8 +Multi +WantTab" inputColors, value)
                case "check":
                    ctrl := g.AddCheckbox(position "w" inputW " h" rowHeight " Background" colors["Background"], field.Label)
                    ctrl.Value := value ? 1 : 0
                case "choice":
                    labels := []
                    for choice in field.Choices
                        labels.Push(choice[2])
                    ctrl := g.AddDropDownList(position "w" inputW inputColors, labels)
                    ctrl.Value := Max(1, ItemEditor._ChoiceIndex(field.Choices, value))
                case "file", "folder":
                    extraW := field.HasOwnProp("Button") ? 174 : 0
                    ctrl := g.AddEdit(position "w" (inputW - 42 - extraW) " r1 -Multi h" rowHeight inputColors, value)
                    browse := g.AddButton("x+6 yp w36 h" rowHeight buttonColors, I18n.T("Prefs.Browse"))
                    PreferencesWindow.StyleNative(browse, "Button", colors)
                    kind := field.HasOwnProp("FolderWhen") ? ItemEditor._KindGetter(field.FolderWhen, fields, controls) : field.Type
                    browse.OnEvent("Click", ItemEditor._Browser(ctrl, kind, g))
                    if extraW {
                        extraButton := g.AddButton("x+6 yp w" (extraW - 6) " h" rowHeight buttonColors, field.Button.Label)
                        PreferencesWindow.StyleNative(extraButton, "Button", colors)
                        extraButton.OnEvent("Click", ItemEditor._FieldButton(field.Button, controls, g))
                    }
                case "number":
                    ctrl := g.AddEdit(position "w110 r1 -Multi Number h" rowHeight inputColors, value)
                case "hotkey":
                    ctrl := HotkeyBox.Add(g, position "w200 h" rowHeight, LTrim(value, "~"), true)
                    ctrl.Opt(inputColors)
                    passBoxes[field.Key] := g.AddCheckbox("x" (inputX + 216) " y" (rowY + 3) " w" (inputW - 216) " Background" colors["Background"] " c" colors["Text"], I18n.T("Hotkey.PassThrough"))
                    PreferencesWindow.StyleNative(passBoxes[field.Key], "CheckBox", colors)
                    passBoxes[field.Key].Value := (SubStr(value, 1, 1) = "~") ? 1 : 0
                default:
                    ctrl := g.AddEdit(position "w" inputW " r1 -Multi h" rowHeight inputColors, value)
            }
            PreferencesWindow.StyleNative(ctrl, field.Type, colors)
            ctrl.GetPos(, &controlY, , &controlH)
            label.GetPos(, &labelY, , &labelH)
            rowBottom := Max(rowBottom, controlY + controlH, labelY + labelH)
            if field.HasOwnProp("Hint") {
                indent := (field.Type = "check") ? 20 : 0
                g.SetFont("s" Max(8.5, fontSize - 1))
                hint := g.AddText("x" (inputX + indent) " y" (rowBottom + 6) " w" (inputW - indent) " c" colors["Muted"] " Background" colors["Background"], field.Hint)
                PreferencesWindow.FitText(hint)
                g.SetFont("s" fontSize)
                hint.GetPos(, &hintY, , &hintH)
                rowBottom := hintY + hintH
            }
            controls[field.Key] := ctrl
            rowY := rowBottom + 18
        }

        g.AddText("x26 y" rowY " w" (windowW - 54) " h1 Background" colors["Border"])
        okay := g.AddButton("x" (windowW - 226) " y" (rowY + 18) " w90 h" rowHeight " Default Background" colors["Selected"] " c" colors["SelectedText"], "OK")
        PreferencesWindow.StyleNative(okay, "PrimaryButton", colors)
        okay.OnEvent("Click", OnOk)
        cancel := g.AddButton("x+10 yp w100 h" rowHeight buttonColors, I18n.T("Prefs.Cancel"))
        PreferencesWindow.StyleNative(cancel, "Button", colors)
        cancel.OnEvent("Click", (*) => ItemEditor.Cancel())
        g.OnEvent("Escape", (*) => ItemEditor.Cancel())
        g.OnEvent("Close", (*) => ItemEditor.Cancel())

        owner.Opt("+Disabled")
        try {
            g.Show("w" (windowW + 18) " h" Min(rowY + rowHeight + 40, maxHeight))
            if fields.Length
                controls[fields[1].Key].Focus()
            while state.Open
                Sleep(20)
        } finally {
            HotkeyBox.CancelActive()
            owner.Opt("-Disabled")
            try g.Destroy()
            ItemEditor.Gui := "", ItemEditor._activeState := ""
        }
        if IsObject(PreferencesWindow.Gui)
            PreferencesWindow.Gui.Show()
        return state.Result

        OnOk(*) {
            g.Opt("+OwnDialogs")                                            ; 提示框挡住编辑窗口, 关掉提示框之前不能操作
            edited := item.Clone()
            for spec in fields {
                input := controls[spec.Key]
                switch spec.Type {
                    case "check" : newValue := input.Value
                    case "choice": newValue := spec.Choices[input.Value][1]
                    case "number": newValue := IsInteger(input.Value) ? Integer(input.Value) : 0
                    case "hotkey":
                        newValue := HotkeyBox.Value(input)
                        if (newValue != "" && passBoxes[spec.Key].Value && SubStr(newValue, 1, 1) != "~")
                            newValue := "~" newValue
                        else if !passBoxes[spec.Key].Value
                            newValue := LTrim(newValue, "~")
                    default      : newValue := input.Value
                }
                if (spec.HasOwnProp("Required") && spec.Required && Trim(newValue) = "") {
                    MsgBox(I18n.T("Prefs.Required", spec.Label), title, 48)
                    input.Focus()
                    return
                }
                edited[spec.Key] := newValue
            }
            for spec in fields {                                            ; Check: 全部字段读完后再检查, 可以看其它字段 (返回提示文字 = 有问题)
                if !spec.HasOwnProp("Check") || (warning := spec.Check.Call(edited[spec.Key], edited)) = ""
                    continue
                if (MsgBox(warning "`n`n" I18n.T("Editor.SaveAnyway"), title, "YesNo Icon! Default2") != "Yes") {
                    controls[spec.Key].Focus()
                    return
                }
            }
            state.Result := edited
            (state.Open := false, g.Destroy())
        }
    }

    static Cancel() {
        if IsObject(ItemEditor._activeState)
            ItemEditor._activeState.Open := false
        if IsObject(ItemEditor.Gui)
            try ItemEditor.Gui.Destroy()
    }

    static _PaintHeader(picture, window, width, title, colors) {
        canvas := Image.Create(width, 76, , window.PixelScale)
        try {
            canvas.FillRoundRect(0, 0, width, 76, 0, "0xFF" colors["Background"])
            canvas.FillRoundRect(26, 22, 3, 28, 1, "0xFF" colors["Accent"])
            canvas.DrawText(title, 42, 19, "0xFF" colors["Text"], "s17 bold", ThemeManager.FontName())
            canvas.DrawLine(26, 72, width - 28, 72, "0xFF" colors["Border"], 1)
            picture.Value := "HBITMAP:" canvas.ToBitmap()
        } finally {
            canvas.Dispose()
        }
    }

    static _FieldButton(button, controls, g) {
        return (*) => button.OnClick.Call(controls, g)
    }

    static WithDefaults(item, defaults) {
        filled := item.Clone()
        for key, value in defaults
            if !filled.Has(key)
                filled[key] := value
        return filled
    }

    static Field(key, labelKey, type := "text", required := false, choices := "", hint := "") {
        spec := {Key: key, Label: I18n.T(labelKey), Type: type, Required: required}
        if IsObject(choices)
            spec.Choices := choices
        if (hint != "")
            spec.Hint := hint
        return spec
    }

    static Owner() {
        static hiddenOwner := ""
        if IsObject(PreferencesWindow.Gui)
            return PreferencesWindow.Gui
        if !IsObject(hiddenOwner)
            hiddenOwner := Gui("+ToolWindow -Caption", App.Name)
        return hiddenOwner
    }

    static _ChoiceIndex(choices, value) {
        for index, choice in choices
            if (choice[1] = value)
                return index
        return 0
    }

    static _Browser(ctrl, kind, owner) {
        return (*) => ItemEditor._Browse(ctrl, kind, owner)
    }

    static _KindGetter(when, fields, controls) {
        return () => ItemEditor.KindFor(when, fields, controls)
    }

    static KindFor(when, fields, controls) {
        for spec in fields {
            if (spec.Key = when[1] && controls.Has(spec.Key) && spec.HasOwnProp("Choices")) {
                index := controls[spec.Key].Value
                return (index >= 1 && index <= spec.Choices.Length && spec.Choices[index][1] = when[2]) ? "folder" : "file"
            }
        }
        return "file"
    }

    static _Browse(ctrl, kind, owner) {
        if HasMethod(kind)
            kind := kind()
        owner.Opt("+OwnDialogs")
        current := Path.Resolve(ctrl.Value)
        selected := (kind = "folder") ? DirSelect(current, 3) : FileSelect(3, current)
        if (selected != "")
            ctrl.Value := selected
    }
}

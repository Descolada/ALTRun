; ItemEditor.ahk - Portable field-based editors for commands, snippets and search engines.

class ItemEditor {

    static Edit(owner, title, fields, item) {
        state := {Result: "", Open: true}                                               ; 嵌套函数 OnOk 通过它把结果交回来
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", title)
        g.SetFont("s9", ThemeManager.FontName())
        g.MarginX := 14, g.MarginY := 12
        controls := Map(), passBoxes := Map()
        labelW := 110, inputW := 540                                        ; 宽一些, 长路径和命令行参数才看得全

        for field in fields {
            g.AddText("xm w" labelW " y+10 Section", (field.Type = "check") ? "" : field.Label)   ; 复选框的文字写在框后面
            value := item.Has(field.Key) ? item[field.Key] : ""
            switch field.Type {
                case "multiline":
                    ctrl := g.AddEdit("x+8 ys-3 w" inputW " r8 +Multi +WantTab", value)
                case "check":
                    ctrl := g.AddCheckbox("x+8 ys w" inputW, field.Label)
                    ctrl.Value := value ? 1 : 0
                case "choice":
                    labels := []
                    for choice in field.Choices
                        labels.Push(choice[2])
                    ctrl := g.AddDropDownList("x+8 ys-3 w" inputW, labels)
                    ctrl.Value := Max(1, ItemEditor._ChoiceIndex(field.Choices, value))
                case "file", "folder":
                    extraW := field.HasOwnProp("Button") ? 154 : 0           ; 字段自己的按钮 (例如 "下载网站图标")
                    ctrl := g.AddEdit("x+8 ys-3 w" (inputW - 34 - extraW) " r1 -Multi", value)
                    browse := g.AddButton("x+4 yp-1 w30", I18n.T("Prefs.Browse"))
                    kind := field.HasOwnProp("FolderWhen") ? ItemEditor._KindGetter(field.FolderWhen, fields, controls) : field.Type
                    browse.OnEvent("Click", ItemEditor._Browser(ctrl, kind, g))
                    if extraW
                        g.AddButton("x+4 yp w" (extraW - 4), field.Button.Label).OnEvent("Click", ItemEditor._FieldButton(field.Button, controls, g))
                case "number":
                    ctrl := g.AddEdit("x+8 ys-3 w100 r1 -Multi Number", value)
                case "hotkey":
                    ctrl := HotkeyBox.Add(g, "x+8 ys-3 w200", LTrim(value, "~"), true)
                    passBoxes[field.Key] := g.AddCheckbox("x+14 yp+3", I18n.T("Hotkey.PassThrough"))
                    passBoxes[field.Key].Value := (SubStr(value, 1, 1) = "~") ? 1 : 0
                default:
                    ctrl := g.AddEdit("x+8 ys-3 w" inputW " r1 -Multi", value)
            }
            if field.HasOwnProp("Hint") {                                   ; 灰色小字说明, 和偏好设置里的一样
                indent := (field.Type = "check") ? 18 : 0                   ; 复选框: 和框后面的文字对齐
                g.SetFont("s8")
                g.AddText("xs+" (labelW + 8 + indent) " y+3 w" (inputW - indent) " cGray", field.Hint)
                g.SetFont("s9")
            }
            controls[field.Key] := ctrl
        }

        g.AddButton("xm+" (labelW + inputW - 170) " y+18 w80 Default", "OK").OnEvent("Click", OnOk)
        g.AddButton("x+10 yp w80", I18n.T("Prefs.Cancel")).OnEvent("Click", (*) => (state.Open := false, g.Destroy()))
        g.OnEvent("Escape", (*) => (state.Open := false, g.Destroy()))
        g.OnEvent("Close", (*) => (state.Open := false, g.Destroy()))

        owner.Opt("+Disabled")
        try {
            g.Show()
            while state.Open
                Sleep(20)
        } finally {
            HotkeyBox.CancelActive()
            owner.Opt("-Disabled")
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

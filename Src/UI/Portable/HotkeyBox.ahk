; HotkeyBox.ahk - Portable hotkey fields accept the same AutoHotkey syntax saved in settings.
class HotkeyBox {
    static Boxes := Map()

    static Add(g, options, value, mouse := false, onChange := "") {
        ctrl := g.AddEdit(options " r1 -Multi", value)
        ctrl.SetCue("!Space / ^!r / F8")
        if IsObject(onChange)
            ctrl.OnEvent("Change", (*) => onChange.Call())
        return ctrl
    }

    static Value(ctrl) {
        return Trim(ctrl.Value)
    }

    static Label(hk) {
        return Win.HotkeyLabel(hk, HotkeyBox.Names())
    }

    static Names() {
        return Map("MButton", I18n.T("Hotkey.MButton"), "XButton1", I18n.T("Hotkey.XButton1"), "XButton2", I18n.T("Hotkey.XButton2")
            , "LButton", I18n.T("Hotkey.LButton"), "RButton", I18n.T("Hotkey.RButton"))
    }

    static Compose(mods, key) {
        ordered := ""
        for modifier in ["^", "!", "+", "#"]
            if InStr(mods, modifier)
                ordered .= modifier
        return ordered (StrLen(key) = 1 ? StrLower(key) : key)
    }

    static IsAllowed(hk) {
        if !RegExMatch(hk, "^([\^!+#]*)(.+)$", &match)
            return false
        return RegExMatch(match[1], "[\^!#]") || !(StrLen(match[2]) = 1 || RegExMatch(match[2], "i)^(Space|Enter|Tab|Backspace|Delete|Escape|Numpad.*)$"))
    }

    static CancelActive() {
        ; Editable fields do not install an input hook or suspend application hotkeys.
    }

    static Prune() {
        HotkeyBox.Boxes.Clear()
    }

    static IsAlive(state) {
        try return state.Ctrl.Hwnd = state.Hwnd
        return false
    }
}

; Native macOS shortcut recording; other portable desktops retain editable hotkey syntax.
class HotkeyBox {
    static _active := "", _wasSuspended := false

    static Add(g, options, value, mouse := false, onChange := "") {
#if OSX
        ctrl := g.AddEdit(options " r1 -Multi", HotkeyBox.Label(value))
        ALTRunMacHotkeyBind(ctrl.ToClr(), value, mouse, (kind) => HotkeyBox._Changed(ctrl, g, onChange, kind))
        return ctrl
#else
        ctrl := g.AddEdit(options " r1 -Multi", value)
        ctrl.SetCue("!Space / ^!r / F8")
        if IsObject(onChange)
            ctrl.OnEvent("Change", (*) => onChange.Call())
        return ctrl
#endif
    }

    static Value(ctrl) {
#if OSX
        return ALTRunMacHotkeyValue(ctrl.ToClr())
#else
        return Trim(ctrl.Value)
#endif
    }

    static Start(ctrl) {
        HotkeyBox.CancelActive()
        HotkeyBox._active := ctrl
        HotkeyBox._wasSuspended := A_IsSuspended
        Suspend(true)
    }

    static Stop(ctrl) {
        if (IsObject(HotkeyBox._active) && HotkeyBox._active = ctrl)
            HotkeyBox.CancelActive()
    }

    static _Changed(ctrl, owner, onChange, kind) {
        if (kind = "focus")
            return HotkeyBox.Start(ctrl)
        if (kind = "blur")
            return HotkeyBox.Stop(ctrl)
        ctrl.Value := HotkeyBox.Label(HotkeyBox.Value(ctrl))
        if (kind = "change" && IsObject(onChange))
            onChange.Call()
        HotkeyBox.Stop(ctrl)
        found := false
        for control in owner {
            if (found && control.Visible && control.Enabled && control.Type = "Button") {
                try {
                    control.Focus()
                    return
                }
            }
            if (control = ctrl)
                found := true
        }
    }

    static Label(hk) {
        return Win.HotkeyLabel(hk, HotkeyBox.Names())
    }

    static Names() {
        return Map("MButton", I18n.T("Hotkey.MButton"), "XButton1", I18n.T("Hotkey.XButton1"), "XButton2", I18n.T("Hotkey.XButton2")
            , "LButton", I18n.T("Hotkey.LButton"), "RButton", I18n.T("Hotkey.RButton"))
    }

    static CancelActive() {
        if !IsObject(HotkeyBox._active)
            return
        HotkeyBox._active := ""
        Suspend(HotkeyBox._wasSuspended)
    }

}

#if OSX
#CSharp
private sealed class ALTRunMacHotkeyState
{
    internal string Value, Before;
}
private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<Eto.Forms.Control, ALTRunMacHotkeyState> ALTRunMacHotkeys = new();

private static string ALTRunMacHotkeyCompose(string name, long modifiers)
{
    string key = name switch { "Escape" => "Esc", "PageUp" => "PgUp", "PageDown" => "PgDn", "Comma" => ",", "Period" => ".", "Slash" => "/", "Backslash" => "\\", "BackSpace" => "Backspace", "Minus" => "-", "Plus" => "=", "Semicolon" => ";", "Quote" => "'", "Grave" => "`", "LeftBracket" => "[", "RightBracket" => "]", _ => name };
    if (key.Length == 2 && key[0] == 'D' && char.IsDigit(key[1])) key = key[1..];
    if (key.StartsWith("Keypad", System.StringComparison.Ordinal)) key = "Numpad" + key[6..];
    if (key.Length == 1 && char.IsLetter(key[0])) key = key.ToLowerInvariant();
    var flags = (Eto.Forms.Keys)modifiers;
    return (flags.HasFlag(Eto.Forms.Keys.Control) ? "^" : "") + (flags.HasFlag(Eto.Forms.Keys.Alt) ? "!" : "")
        + (flags.HasFlag(Eto.Forms.Keys.Shift) ? "+" : "") + (flags.HasFlag(Eto.Forms.Keys.Application) ? "#" : "") + key;
}

public static void ALTRunMacHotkeyBind(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, string initial, bool mouse, Keysharp.Builtins.KeysharpFunc callback)
{
    var control = (Eto.Forms.TextBox)wrapper.Native;
    var state = new ALTRunMacHotkeyState { Value = initial, Before = initial };
    ALTRunMacHotkeys.Add(control, state);
    // Eto's public opt-in key, also used by Keysharp's native hotkey control.
    control.Properties.Set("Eto.Mac.MacFieldEditor.CaptureKeyEquivalents", true);
    control.GotFocus += (_, _) => { state.Before = state.Value; callback.Call("focus"); };
    control.LostFocus += (_, _) => callback.Call("blur");
    if (mouse) control.MouseDown += (_, e) =>
    {
        string name = e.Buttons == Eto.Forms.MouseButtons.Middle ? "MButton" : e.Buttons.ToString() switch
            { "Auxiliary1" or "XButton1" => "XButton1", "Auxiliary2" or "XButton2" => "XButton2", _ => "" };
        if (name == "") return;
        e.Handled = true;
        state.Value = ALTRunMacHotkeyCompose(name, (long)e.Modifiers);
        callback.Call("change");
    };
    control.KeyDown += (_, e) =>
    {
        e.Handled = true;
        string name = e.Key.ToString();
        if (e.Key == Eto.Forms.Keys.Escape || e.Key == Eto.Forms.Keys.Tab)
        {
            state.Value = state.Before;
            callback.Call("cancel");
            return;
        }
        if (e.Key == Eto.Forms.Keys.None || name.Contains("Control") || name.Contains("Shift") || name.Contains("Alt") || name.Contains("Application"))
            return;
        if ((e.Key == Eto.Forms.Keys.Backspace || e.Key == Eto.Forms.Keys.Delete) && e.Modifiers == Eto.Forms.Keys.None)
            state.Value = "";
        else
        {
            // A bare typing key would make ordinary text entry launch an action globally.
            string bare = ALTRunMacHotkeyCompose(name, 0);
            if ((e.Modifiers & (Eto.Forms.Keys.Control | Eto.Forms.Keys.Alt | Eto.Forms.Keys.Application)) == Eto.Forms.Keys.None
                && (bare.Length == 1 || System.Text.RegularExpressions.Regex.IsMatch(bare, @"^(?:Space|Enter|Tab|Backspace|Delete|Esc|Numpad.*)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)))
                return;
            state.Value = ALTRunMacHotkeyCompose(name, (long)e.Modifiers);
        }
        callback.Call("change");
    };
}

public static string ALTRunMacHotkeyValue(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper)
    => ALTRunMacHotkeys.GetValue((Eto.Forms.Control)wrapper.Native, _ => throw new System.InvalidOperationException("The shortcut recorder was not initialized.")).Value;
#EndCSharp
#endif

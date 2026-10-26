; Isolated settings repair and native recorder handle-recreation regression; no window is shown or keys sent.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => HotkeyPersistence.OnError(err, mode))
OnExit((*) => HotkeyPersistence.CleanUp())
SetTimer(() => HotkeyPersistence.Fail("Timed out after 20 seconds."), -20000)
HotkeyPersistence.Run()

MsgBox(args*) {
    throw Error("Unexpected settings dialog.")
}

class HotkeyPersistence {
    static Folder := "", Gui := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        Logger.Enabled := false
        HotkeyPersistence.Labels()
        HotkeyPersistence.Settings()
#if WINDOWS
        HotkeyPersistence.NativeRecorder()
#endif
        FileAppend("PASS HOTKEY_PERSISTENCE labels, settings roundtrip and native recorder state`n", "*")
        ExitApp(0)
    }

    static Labels() {
        for pair in [["Alt+Space", "!Space"], ["Alt+R", "!r"], ["Ctrl+Alt+C", "^!c"]
            , ["Win+Shift+F12", "+#F12"], ["alt+ctrl+K", "^!k"], ["Ctrl++", "^+"]
            , ["Ctrl+NumpadAdd", "^NumpadAdd"], ["Ctrl+F1 Up", "^F1 up"]] {
            normalized := Win.NormalizeHotkeyLabel(pair[1])
            HotkeyPersistence.Assert(normalized == pair[2], "Wrong label normalization: " pair[1])
            HotkeyPersistence.Assert(Win.NormalizeHotkeyLabel(normalized) == normalized, "Normalization is not idempotent.")
        }
        for key in ["!Space", "~*$<^>!a", "CapsLock & j", "~MButton", "+", "^+", "NumpadAdd", "F1 up", "Ctrl+UnknownKey", "CapsLock+J", ""]
            HotkeyPersistence.Assert(Win.NormalizeHotkeyLabel(key) == key, "Existing syntax or unknown key was changed: " key)
        for key in ["!Space", "!r", "^!c", "#e", "^+F12", "^+", "^NumpadAdd"]
            HotkeyPersistence.Assert(Win.NormalizeHotkeyLabel(Win.HotkeyLabel(key)) == key, "Hotkey label did not roundtrip: " key)
    }

    static Settings() {
        HotkeyPersistence.Folder := Platform.Join(A_Temp, "ALTRun-HotkeyPersistence-" Platform.NewUuid())
        DirCreate(HotkeyPersistence.Folder)
        AppSettings.DataDir := HotkeyPersistence.Folder
        AppSettings.File := Platform.Join(HotkeyPersistence.Folder, "ALTRun.json")
        AppSettings.LegacyFile := Platform.Join(HotkeyPersistence.Folder, "Legacy.json")
        stored := AppSettings.Defaults()
        stored["General"]["Hotkey"] := "Alt+Space"
        stored["General"]["SecondaryHotkey"] := "Alt+R"
        stored["Features"]["Clipboard"]["Hotkey"] := "Ctrl+Alt+C"
        stored["Extensions"]["QuickSwitch"]["Hotkey"] := "Ctrl+G"
        stored["Extensions"]["QuickSwitch"]["MenuHotkey"] := "Ctrl+Shift+G"
        stored["Extensions"]["AutoDate"]["Hotkey"] := "Ctrl+D"
        stored["Hotkeys"] := [Map("Key", "Ctrl+F12", "Action", "Lock", "WinTitle", "")
            , Map("Key", "CapsLock & j", "Action", "Lock", "WinTitle", "")]
        stored["CustomCommands"] := [Map("Title", "Untouched", "Type", "text", "Target", "Ctrl+Alt+C")]
        JSON.WriteFile(AppSettings.File, stored)
        AppSettings.Load()
        repaired := JSON.Parse(FileRead(AppSettings.File, "UTF-8"))
        HotkeyPersistence.Assert(repaired["General"]["Hotkey"] == "!Space", "Primary hotkey was not repaired on disk.")
        HotkeyPersistence.Assert(repaired["General"]["SecondaryHotkey"] == "!r", "Secondary hotkey was not repaired.")
        HotkeyPersistence.Assert(repaired["Features"]["Clipboard"]["Hotkey"] == "^!c", "Clipboard hotkey was not repaired.")
        HotkeyPersistence.Assert(repaired["Extensions"]["QuickSwitch"]["Hotkey"] == "^g"
            && repaired["Extensions"]["QuickSwitch"]["MenuHotkey"] == "^+g", "QuickSwitch hotkeys were not repaired.")
        HotkeyPersistence.Assert(repaired["Extensions"]["AutoDate"]["Hotkey"] == "^d", "AutoDate hotkey was not repaired.")
        HotkeyPersistence.Assert(repaired["Hotkeys"][1]["Key"] == "^F12" && repaired["Hotkeys"][2]["Key"] == "CapsLock & j", "Custom hotkey syntax changed.")
        HotkeyPersistence.Assert(repaired["CustomCommands"][1]["Target"] == "Ctrl+Alt+C", "Non-hotkey content changed.")
        HotkeyPersistence.Assert(!AppSettings._NormalizeHotkeys(repaired), "Repaired settings changed on a second normalization.")
        before := FileRead(AppSettings.File, "UTF-8")
        AppSettings.Load()
        HotkeyPersistence.Assert(FileRead(AppSettings.File, "UTF-8") == before, "Second load rewrote repaired settings.")
    }

#if WINDOWS
    static NativeRecorder() {
        g := Gui()
        HotkeyPersistence.Gui := g
        colors := Map("Surface", "252932", "InputText", "F1F3F6", "Border", "444A56", "Selected", "334A70"
            , "SelectedText", "FFFFFF", "Background", "181B21", "Text", "F1F3F6", "Muted", "9299A8")
        fields := []
        for key in ["!Space", "!r", "^!c"] {
            ctrl := HotkeyBox.Add(g, "w180", key)
            previous := ctrl.Hwnd
            PreferencesWindow.StyleNative(ctrl, "Edit", colors)
            HotkeyPersistence.Assert(ctrl.Hwnd != previous, "Theme styling did not recreate the native edit handle.")
            HotkeyPersistence.Assert(HotkeyBox.Value(ctrl) == key, "Styling replaced recorded syntax with its display label.")
            fields.Push({Control: ctrl, Key: key})
        }
        for field in fields {
            HotkeyPersistence.Assert(HotkeyBox.Value(field.Control) == field.Key, "Creating another recorder discarded existing state.")
            HotkeyPersistence.Assert(HotkeyBox.Boxes.Has(field.Control.Hwnd), "Recorder is not indexed by its current handle.")
        }
        first := fields[1].Control
        first.ToClr().BorderStyle := Clr.System.Windows.Forms.BorderStyle.FixedSingle
        HotkeyBox.Prune()
        HotkeyPersistence.Assert(HotkeyBox.Value(first) == "!Space", "Another native handle recreation discarded the recorded hotkey.")
        g.Destroy()
        HotkeyPersistence.Gui := ""
        HotkeyBox.Prune()
        HotkeyPersistence.Assert(HotkeyBox.Boxes.Count = 0, "Disposed recorders were retained.")
    }
#endif

    static CleanUp() {
        if IsObject(HotkeyPersistence.Gui)
            try HotkeyPersistence.Gui.Destroy()
        if (HotkeyPersistence.Folder != "") {
            fixtureFolder := Platform.FullPath(HotkeyPersistence.Folder)
            allowedPrefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-HotkeyPersistence-"))
            if (InStr(Platform.Identity(fixtureFolder), Platform.Identity(allowedPrefix), true) = 1 && DirExist(fixtureFolder))
                try DirDelete(fixtureFolder, true)
        }
    }

    static Fail(message) {
        FileAppend("FAIL HOTKEY_PERSISTENCE " message "`n", "**")
        ExitApp(1)
    }

    static OnError(err, mode) {
        HotkeyPersistence.Fail(err.Message "`n" err.Stack)
        return true
    }
}

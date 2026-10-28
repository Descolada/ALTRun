; Native clipboard, expansion and secure-focus acceptance. All generated input is restricted to fixture-owned windows.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Import Ks { RequestCapabilities }
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacInteraction.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacInteraction.CleanUp())
SetTimer(() => MacInteraction.Fail("Timed out after 35 seconds."), -35000)
MacInteraction.Run()

MsgBox(args*) {
    throw Error("Unexpected interaction fixture dialog.")
}

class MacInteraction {
    static Folder := "", Gui := "", Text := "", Secret := "", SavedClipboard := "", ExpectedClipboard := "", OwnsClipboard := false
    static Previous := 0, Expanded := false, Abbreviation := "", BeforeSource := ""
    static TargetJob := 0, TargetWindow := 0, TargetPid := 0, TargetFolder := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            MacInteraction.Assert(A_TickCount - started < 3500, message)
            Sleep(15)
        }
    }

    static OwnFocus() => IsObject(MacInteraction.Gui) && MacInteraction.Gui.ToClr().HasFocus

    static Keys(keys) {
        MacInteraction.Assert(MacInteraction.OwnFocus(), "Refusing to type outside the owned interaction window.")
        SendEvent(keys)
        Sleep(100)
    }

    static ClipboardWritten() {
        MacInteraction.ExpectedClipboard := Crypt.Hash(ClipboardAll())
        MacInteraction.OwnsClipboard := true
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_INTERACTION macOS-only fixture.`n", "*")
            ExitApp(0)
        }
        capabilities := RequestCapabilities()
        for capability in ["InputMonitoring", "InputControl", "WindowMonitoring", "WindowControl"]
            if (capabilities.%capability% != "Granted") {
                FileAppend("SKIP MAC_INTERACTION existing input/window permissions required; no prompt requested.`n", "*")
                ExitApp(0)
            }
        MacInteraction.Previous := WinExist("A")
        MacInteraction.SavedClipboard := ClipboardAll()
        MacInteraction.BeforeSource := MacInputIntegration.CurrentSource()
        MacInteraction.Folder := Platform.Join(A_Temp, "ALTRun-MacInteraction-" Platform.NewUuid())
        DirCreate(MacInteraction.Folder)
        AppSettings.DataDir := MacInteraction.Folder
        AppSettings.File := Platform.Join(MacInteraction.Folder, "ALTRun.json")
        AppSettings.Data := AppSettings.Defaults()
        AppSettings.General["RestoreInput"] := 0
        AppSettings.General["SwitchToEnglishInput"] := 0
        AppSettings.Feature("Snippets")["PasteDelay"] := 120
        AppSettings.Feature("Clipboard")["LocalFiles"] := 0
        AppSettings.Feature("Clipboard")["IgnoreApps"] := []
        AppSettings.Feature("Clipboard")["Persist"] := 1
        ClipboardProvider.File := Platform.Join(MacInteraction.Folder, "ClipboardHistory.json")
        ClipboardProvider.Folder := Platform.Join(MacInteraction.Folder, "Clipboard")
        ClipboardProvider.LocalDir := MacInteraction.Folder
        Knowledge.File := Platform.Join(MacInteraction.Folder, "Knowledge.json")
        Usage.File := Platform.Join(MacInteraction.Folder, "Usage.json")
        Logger.Enabled := false
        I18n.LangDir := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "Lang")
        ThemeManager.BuiltinDir := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "Themes")
        ThemeManager.UserDir := MacInteraction.Folder
        I18n.Init("en"), ThemeManager.Load("Dark", "Compact"), Usage.Load()
        ClipboardProvider.Init()
        g := Gui("+AlwaysOnTop", "ALTRun native interaction fixture " Platform.NewUuid())
        MacInteraction.Gui := g
        g.SetFont("s12")
        MacInteraction.Text := g.AddEdit("w500 r3", "Fixture text")
        MacInteraction.Secret := g.AddEdit("w500 r1 Password", "fixture-secret")
        g.Show()
        MacInteraction.Text.Focus()
        MacInteraction.WaitFor(() => MacInteraction.OwnFocus(), "The owned fixture did not receive focus.")
        Sleep(150)
        MacInteraction.Assert(!MacInputIntegration.IsSecureField(), "A normal owned text field was classified as secure.")
        MacInteraction.Secret.Focus()
        Sleep(150)
        MacInteraction.Assert(MacInputIntegration.IsSecureField(), "The native secure field was not identified.")
        MacInteraction.Assert(!SnippetExpander.ShouldExpand(), "Snippet expansion was allowed in a native password field.")
        MacInteraction.Assert(!IsObject(SelectionActions.Capture()), "Selection capture was allowed in a native password field.")
        MacInteraction.Text.Focus()
        Sleep(150)
        FileAppend("PASS MAC_INTERACTION native secure-field expansion/capture safeguards`n", "*")

        sources := MacInputIntegration.Sources(), current := MacInputIntegration.CurrentSource()
        MacInteraction.Assert(sources.Length && current != "", "Native enabled input sources were unavailable.")
        MacInteraction.Assert(MacInputIntegration.SelectSource(current), "Selecting the already-current source failed.")
        MacInteraction.Assert(!MacInputIntegration.SelectSource("org.altrun.fixture.nonexistent"), "A nonexistent input source was accepted.")
        FileAppend("PASS MAC_INTERACTION native source discovery and safe selection`n", "*")

        ClipboardData.BorrowedUntil := 0
        A_Clipboard := "ALTRun fixture clipboard text " Platform.NewUuid()
        token := A_Clipboard
        MacInteraction.ClipboardWritten()
        MacInteraction.WaitFor(() => ClipboardProvider.Entries.Length && ClipboardProvider.Entries[1]["Text"] = token, "Native text clipboard changes were not recorded.")
        before := ClipboardProvider.Entries.Length
        Clipboard.Set(Map("Text", "ALTRun concealed fixture", "org.nspasteboard.ConcealedType", Buffer(1)))
        MacInteraction.ClipboardWritten()
        Sleep(350)
        MacInteraction.Assert(ClipboardProvider.IsPrivate() && ClipboardProvider.Entries.Length = before, "Concealed clipboard data was recorded.")
        FileAppend("PASS MAC_INTERACTION clipboard changes and concealed-data exclusion`n", "*")

        sample := Platform.Join(MacInteraction.Folder, "file with ünicode.txt")
        FileAppend("Owned fixture only", sample, "UTF-8")
        ClipboardData.BorrowedUntil := 0
        MacInteraction.Assert(ClipboardData.SetFiles([sample]), "Publishing native file clipboard data failed.")
        MacInteraction.ClipboardWritten()
        MacInteraction.Assert(ClipboardData.HasFiles() && ClipboardData.Files()[1] == sample, "Native file clipboard data did not round trip.")
        MacInteraction.WaitFor(() => ClipboardProvider.Entries.Length && ClipboardProvider.TypeOf(ClipboardProvider.Entries[1]) = "files", "Native file clipboard changes were not recorded.")
        imageFile := Platform.Join(MacInteraction.Folder, "fixture.png")
        drawing := Image.Create(16, 8, "0xFF123456")
        drawing.Save(imageFile), drawing.Dispose()
        ClipboardData.BorrowedUntil := 0
        MacInteraction.Assert(ClipboardData.SetImage(imageFile), "Publishing native image clipboard data failed.")
        MacInteraction.ClipboardWritten()
        MacInteraction.WaitFor(() => ClipboardProvider.Entries.Length && ClipboardProvider.TypeOf(ClipboardProvider.Entries[1]) = "image", "Native image clipboard changes were not recorded.")
        savedImage := Platform.Join(MacInteraction.Folder, "roundtrip.png")
        size := ClipboardData.SaveImage(savedImage)
        MacInteraction.Assert(IsObject(size) && size.Width = 16 && size.Height = 8, "Native image size did not round trip.")
        FileAppend("PASS MAC_INTERACTION file/image clipboard history and native round trips`n", "*")

        A_Clipboard := "ALTRun restore sentinel " Platform.NewUuid()
        MacInteraction.ClipboardWritten()
        sentinel := A_Clipboard
        MacInteraction.Text.Value := ""
        MacInteraction.Text.Focus()
        MacInteraction.Assert(MacInteraction.OwnFocus(), "Lost owned focus before paste.")
        AppSettings.Feature("Snippets")["PasteMode"] := "Clipboard"
        ActionCatalog.PasteText("owned multiline`nwith unicode ü", false)
        MacInteraction.WaitFor(() => InStr(MacInteraction.Text.Value, "with unicode ü"), "Native paste did not reach the owned target.")
        MacInteraction.Assert(A_Clipboard = sentinel, "Paste failed to restore the clipboard.")
        MacInteraction.Text.Value := "owned selection for actions"
        MacInteraction.Text.Focus()
        Platform.SelectEdit(MacInteraction.Text, 0, -1)
        selection := SelectionActions.Capture()
        MacInteraction.Assert(IsObject(selection) && selection.HasOwnProp("Text") && selection.Text = "owned selection for actions", "Native selection capture failed.")
        MacInteraction.Assert(A_Clipboard = sentinel, "Selection capture failed to restore the clipboard.")
        MacInteraction.ClipboardWritten()
        FileAppend("PASS MAC_INTERACTION native paste/selection and clipboard restoration`n", "*")

        MacInteraction.Abbreviation := ";altrunfixture" SubStr(StrReplace(Platform.NewUuid(), "-"), 1, 8)
        AppSettings.Data["Snippets"] := [Map("Name", "Fixture", "Keyword", SubStr(MacInteraction.Abbreviation, 2), "Text", "EXPANDED-FIXTURE")]
        AppSettings.Feature("Snippets")["AutoExpand"] := 1
        AppSettings.Feature("Snippets")["ExpandExclude"] := []
        MacInteraction.Text.Value := ""
        MacInteraction.Text.Focus()
        SnippetExpander.Refresh()
        MacInteraction.Assert(SnippetExpander.Count = 1, "The fixture hotstring was not registered.")
        SetKeyDelay(35, 35)
        SendLevel(1)
        try MacInteraction.Keys("{Text}" MacInteraction.Abbreviation)
        finally SendLevel(0)
        MacInteraction.WaitFor(() => MacInteraction.Text.Value = "EXPANDED-FIXTURE", "Native hotstring did not replace its abbreviation.")
        MacInteraction.ClipboardWritten()
        FileAppend("PASS MAC_INTERACTION native hotstring expansion into the owned target`n", "*")

        MacInteraction.ExternalTarget(sample, imageFile)

        AppSettings.Feature("Snippets")["AutoExpand"] := 0
        SnippetExpander.Refresh()
        PTToolsWindow.Load(AppSettings.Extension("PTTools"))
        PTToolsWindow.Show()
        MacInteraction.Assert(IsObject(PTToolsWindow.G) && IsNumber(PTToolsWindow.G["RebarTotalArea"].Value), "Portable PT Tools failed to open or calculate.")
        PTToolsWindow.OnClose(PTToolsWindow.G)
        PTToolsWindow.ShowSpf2m()
        MacInteraction.Assert(IsObject(PTToolsWindow.LastResult) && PTToolsWindow.LastResult.Error = ""
            , "Portable SPF2M failed to calculate: " (IsObject(PTToolsWindow.LastResult) ? PTToolsWindow.LastResult.Error : "No result") " / " JSON.Stringify(PTToolsWindow.ProfileInput()))
        PTToolsWindow.OnCloseSpf2m(PTToolsWindow.SpfG)
        FileAppend("PASS MAC_INTERACTION portable PT Tools and SPF2M native windows`n", "*")
        ExitApp(0)
    }

    static ExternalTarget(sample, imageFile) {
        MacInteraction.TargetFolder := Platform.Join(MacInteraction.Folder, "Target")
        DirCreate(MacInteraction.TargetFolder)
        host := ProcessRunner.ScriptHost(Platform.Join(A_ScriptDir, "Fixtures", "MacInteractionTarget.ahk"), [MacInteraction.TargetFolder])
        MacInteraction.TargetJob := ProcessRunner.Start(host.Executable, host.Arguments, "", true)
        MacInteraction.WaitFor(() => FileExist(Platform.Join(MacInteraction.TargetFolder, "ready")), "The separate owned receiver did not start.")
        MacInteraction.TargetPid := Integer(FileRead(Platform.Join(MacInteraction.TargetFolder, "ready"), "UTF-8"))
        criteria := "ALTRun isolated native interaction target ahk_pid " MacInteraction.TargetPid
        MacInteraction.WaitFor(() => WinExist(criteria), "The separate owned receiver did not expose its native target window.")
        MacInteraction.TargetWindow := WinExist(criteria)
        MacInteraction.TargetCommand("activate")
        MacInteraction.WaitFor(() => ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid, "The separate owned receiver did not acquire native application focus.")
        MacInteraction.Assert(!MacInputIntegration.IsSecureField(), "The receiver's normal external field was treated as secure.")
        sentinel := A_Clipboard
        MacInteraction.TargetKeys("{Text}External selection ü")
        MacInteraction.TargetKeys("#a")
        selection := SelectionActions.Capture()
        MacInteraction.Assert(IsObject(selection) && selection.Text = "External selection ü", "Selection capture failed in the separate process.")
        MacInteraction.Assert(A_Clipboard = sentinel, "External selection capture did not restore the clipboard.")
        MacInteraction.TargetCommand("clear")
        MacInteraction.Assert(ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid, "Lost the receiver before clipboard paste.")
        ActionCatalog.PasteText("Separate process paste ü", false)
        MacInteraction.WaitFor(() => MacInteraction.TargetText() = "Separate process paste ü", "Clipboard paste failed in the separate process.")
        MacInteraction.Assert(A_Clipboard = sentinel, "External clipboard paste did not restore the clipboard.")
        App.PreviousWindow := MacInteraction.TargetWindow
        MacInteraction.Assert(ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid, "Lost the receiver before file paste.")
        SendLevel(1)
        try ClipboardProvider._PasteWith(() => ClipboardData.SetFiles([sample]))
        finally SendLevel(0)
        MacInteraction.WaitFor(() => MacInteraction.TargetPasteKind() = "files", "The separate process did not receive the file clipboard offer.")
        MacInteraction.Assert(A_Clipboard = sentinel, "External file paste did not restore the clipboard.")
        MacInteraction.Assert(ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid, "Lost the receiver before image paste.")
        SendLevel(1)
        try ClipboardProvider._PasteWith(() => ClipboardData.SetImage(imageFile))
        finally SendLevel(0)
        MacInteraction.WaitFor(() => MacInteraction.TargetPasteKind() = "image", "The separate process did not receive the image clipboard offer.")
        MacInteraction.Assert(A_Clipboard = sentinel, "External image paste did not restore the clipboard.")
        MacInteraction.TargetCommand("clear")
        SetKeyDelay(35, 35)
        SendLevel(1)
        try MacInteraction.TargetKeys("{Text}" MacInteraction.Abbreviation)
        finally SendLevel(0)
        MacInteraction.WaitFor(() => MacInteraction.TargetText() = "EXPANDED-FIXTURE", "The hotstring failed in the separate native process.")
        MacInteraction.ClipboardWritten()
        MacInteraction.RapidTyping()
        MacInteraction.TargetCommand("stop")
        MacInteraction.WaitFor(() => ProcessRunner.IsFinished(MacInteraction.TargetJob), "The owned receiver did not stop.")
        result := ProcessRunner.Result(MacInteraction.TargetJob)
        MacInteraction.TargetJob := 0
        MacInteraction.Assert(result["ExitCode"] = 0, "The receiver exited with an error: " result["Error"])
        MacInteraction.Gui.Show(), MacInteraction.Text.Focus()
        FileAppend("PASS MAC_INTERACTION separate-process selection, text/files/image paste, restore and hotstrings`n", "*")
    }

    static RapidTyping() {
        MacInteraction.TargetCommand("clear")
        AppSettings.General["HideOnDeactivate"] := 0
        AppSettings.General["ShowTips"] := 0
        AppSettings.General["KeepLastQuery"] := 0
        SearchWindow.Create()
        original := SearchWindow.GetOwnPropDesc("_Show").Call
        ; Exercise a busy first show while native events continue reaching the former foreground app.
        SearchWindow.DefineProp("_Show", {Call: (self, text) => (Sleep(150), original.Call(self, text))})
        Hotkey("^!F19", (*) => (SetTimer(() => MacInteraction.RapidKeys(), -15), SearchWindow.Show("", true)))
        SetKeyDelay(30, 30)
        SendLevel(1)
        try MacInteraction.TargetKeys("^!{F19}")
        finally SendLevel(0)
        MacInteraction.WaitFor(() => SearchWindow.IsVisible() && SearchWindow.Gui.ToClr().HasFocus, "The launcher did not receive focus after its real hotkey.")
        Sleep(250)
        Hotkey("^!F19", "Off")
        SearchWindow.DefineProp("_Show", {Call: original})
        MacInteraction.Assert(SearchWindow.Input.Value = "rapidfixture" && MacInteraction.TargetText() = ""
            , "Characters typed while the launcher opened were lost or leaked into the previous application.")
        SearchWindow.Hide()
        MacInteraction.TargetCommand("activate")
        FileAppend("PASS MAC_INTERACTION rapid typing during hotkey-driven launcher activation`n", "*")
    }

    static RapidKeys() {
        MacInteraction.Assert(ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid
            || (SearchWindow.IsVisible() && SearchWindow.Gui.ToClr().HasFocus), "Refusing rapid typing outside the owned receiver/launcher.")
        SetKeyDelay(0, 0)
        SendLevel(1)
        try SendEvent("{Text}rapidfixture")
        finally SendLevel(0)
    }

    static TargetText() {
        file := Platform.Join(MacInteraction.TargetFolder, "text")
        return FileExist(file) ? FileRead(file, "UTF-8") : ""
    }

    static TargetPasteKind() {
        file := Platform.Join(MacInteraction.TargetFolder, "paste")
        return FileExist(file) ? FileRead(file, "UTF-8") : ""
    }

    static TargetKeys(keys) {
        MacInteraction.Assert(MacInteraction.TargetPid && ALTRunMacFixtureFrontmostPid() = MacInteraction.TargetPid
            , "Refusing to type outside the separate owned receiver.")
        SendEvent(keys)
        Sleep(100)
    }

    static TargetCommand(command) {
        ack := Platform.Join(MacInteraction.TargetFolder, "ack")
        try FileDelete(ack)
        staging := Platform.Join(MacInteraction.TargetFolder, "next-command")
        FileAppend(command, staging, "UTF-8")
        FileMove(staging, Platform.Join(MacInteraction.TargetFolder, "command"), 1)
        if (command != "stop")
            MacInteraction.WaitFor(() => FileExist(ack), "The owned receiver did not acknowledge a fixture command.")
    }

    static CleanUp() {
        try Hotkey("^!F19", "Off")
        if IsObject(SearchWindow.Gui)
            try SearchWindow.Gui.Destroy()
        if MacInteraction.TargetJob
            try ProcessRunner.Finish(MacInteraction.TargetJob, true)
        if MacInteraction.Abbreviation != "" {
            try AppSettings.Feature("Snippets")["AutoExpand"] := 0
            try SnippetExpander.Refresh()
        }
        for window in [PTToolsWindow.G, PTToolsWindow.SpfG, MacInteraction.Gui]
            if IsObject(window)
                try window.Destroy()
        if (MacInteraction.OwnsClipboard && Crypt.Hash(ClipboardAll()) = MacInteraction.ExpectedClipboard) {
            ClipboardData.Borrow(2000)
            try A_Clipboard := MacInteraction.SavedClipboard
        }
        if (MacInteraction.BeforeSource != "" && MacInputIntegration.CurrentSource() != MacInteraction.BeforeSource)
            try MacInputIntegration.SelectSource(MacInteraction.BeforeSource)
        if (MacInteraction.Previous && WinExist("ahk_id " MacInteraction.Previous))
            try WinActivate("ahk_id " MacInteraction.Previous)
        if (MacInteraction.Folder != "" && InStr(Platform.FullPath(MacInteraction.Folder), Platform.FullPath(Platform.Join(A_Temp, "ALTRun-MacInteraction-")), true) = 1)
            try DirDelete(MacInteraction.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL MAC_INTERACTION " message "`n", "*")
        ExitApp(1)
    }
}

#if OSX
#CSharp
public static long ALTRunMacFixtureFrontmostPid()
{
    var workspace = ALTRunMacObjC.Send(ALTRunMacObjC.Class("NSWorkspace"), ALTRunMacObjC.Selector("sharedWorkspace"));
    var app = ALTRunMacObjC.Send(workspace, ALTRunMacObjC.Selector("frontmostApplication"));
    return ALTRunMacObjC.Send(app, ALTRunMacObjC.Selector("processIdentifier")).ToInt64();
}
#EndCSharp
#endif

; Finder/action contracts use owned temporary fixtures; UI automation is opt-in.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacFinderActions.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacFinderActions.CleanUp())
SetTimer(() => MacFinderActions.Fail("Timed out after 40 seconds."), -40000)
MacFinderActions.Run()

MsgBox(args*) => MacFinderActions.Answer

class MacFinderActions {
    static Folder := "", Calls := [], Answer := "Cancel", SavedApple := "", SavedStart := "", SavedRead := "", Searches := []
    static NativeDestination := "", NativePassed := false, NativeError := ""
    static NativeOwner := ""

    static Check(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_FINDER_ACTIONS requires macOS`n", "*")
            ExitApp(0)
        }
        MacFinderActions.Folder := Platform.Join(A_Temp, "ALTRun-MacFinder-" Platform.NewUuid())
        DirCreate(MacFinderActions.Folder)
        source := Platform.Join(MacFinderActions.Folder, "source '漢字")
        destination := Platform.Join(MacFinderActions.Folder, "destination")
        DirCreate(source), DirCreate(destination), DirCreate(Platform.Join(source, "child"))
        file := Platform.Join(source, 'report "quoted"`nline.txt')
        FileAppend("fixture content", file, "UTF-8-RAW")
        AppSettings.DataDir := MacFinderActions.Folder
        AppSettings.Data := AppSettings.Defaults()
        root := Platform.FullPath("..", A_ScriptDir)
        I18n.LangDir := Platform.Join(root, "Resources", "Lang")
        Pinyin.DataFile := Platform.Join(root, "Resources", "Pinyin.txt")
        ThemeManager.BuiltinDir := Platform.Join(root, "Resources", "Themes")
        ThemeManager.UserDir := MacFinderActions.Folder
        App.IconFile := Platform.Join(root, "Resources", "ALTRun.ico")
        Logger.Enabled := false
        I18n.Init("en"), ThemeManager.Load("Dark", "Compact")
        MacFinderActions.Check(ALTRunMacTransferAllowed(file, destination), "A valid file copy was rejected.")
        MacFinderActions.Check(!ALTRunMacTransferAllowed(source, Platform.Join(source, "child")), "Copying a directory into its descendant must be rejected.")
        MacFinderActions.Check(!ALTRunMacTransferAllowed(file, source), "Copying a file into its current directory must be rejected.")
        MacFinderActions.Check(!ALTRunMacTransferAllowed("/", destination), "The filesystem root must not be copied or moved.")
        alias := Platform.Join(MacFinderActions.Folder, "alias")
        Clr.System.IO.Directory.CreateSymbolicLink(alias, source)
        MacFinderActions.Check(!ALTRunMacTransferAllowed(source, Platform.Join(alias, "child")), "A symlinked descendant must not bypass recursion protection.")
        FileAppend("PASS MAC_FINDER_ACTIONS transfer recursion and symlink safety`n", "*")

        term := 'report "quotes" * ? 漢字'
        search := ALTRunMacSavedSearchQuery(MacSpotlight.Expression(term)["Query"], destination)
        MacFinderActions.Searches.Push(search)
        xml := FileRead(search)
        MacFinderActions.Check(InStr(xml, "RawQuery") && InStr(xml, "FXScopeArrayOfPaths") && InStr(xml, destination), "Finder search must retain the requested scope.")
        MacFinderActions.Check(InStr(xml, "漢字") && InStr(xml, "\*") && InStr(xml, "\?"), "Finder search must preserve Unicode and quote wildcard literals.")
        MacFinderActions.Check(ALTRunMacFinderFixtureMode(search) = 384, "Saved searches must have private permissions.")
        FileAppend("PASS MAC_FINDER_ACTIONS Finder search query, scope and private file`n", "*")
        if A_Args.Length && A_Args[1] = "--native-dialog" {
            MacFinderActions.NativeDialog(source, destination)
            ExitApp(0)
        }
        if A_Args.Length && A_Args[1] = "--native-finder" {
            MacFinderActions.NativeFinder(file, destination)
            ExitApp(0)
        }
        if A_Args.Length && A_Args[1] = "--native-actions" {
            MacFinderActions.NativeActions(file, destination)
            ExitApp(0)
        }

        MacFinderActions.SavedApple := MacDesktop.GetOwnPropDesc("AppleScript")
        MacFinderActions.SavedStart := ProcessRunner.GetOwnPropDesc("StartApplication")
        MacFinderActions.SavedRead := MacDesktop.GetOwnPropDesc("Snapshot")
        MacDesktop.DefineProp("AppleScript", {Call: (self, script, title := "") => (MacFinderActions.Calls.Push({Script: script, Title: title}), true)})
        ProcessRunner.DefineProp("StartApplication", {Call: (self, executable, arguments := [], workingDirectory := "", capture := false)
            => MacFinderActions.Calls.Push({Executable: executable, Arguments: arguments})})
        MacDesktop.DefineProp("Snapshot", {Call: (self, refresh := false) => Map("Folder", destination, "Selection", [file], "Folders", [destination], "Error", "", "Pending", false)})

        MacFinderActions.Check(MacDesktop.CopyMove([file], destination), "Copy must dispatch to Finder.")
        copy := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(InStr(copy.Script, "duplicate {") && InStr(copy.Script, "without replacing") && InStr(copy.Script, ProcessRunner.QuoteAppleScript(file)), "Copy must preserve literal paths and avoid replacement.")
        MacFinderActions.Check(MacDesktop.CopyMove([file], destination, true), "Move must dispatch to Finder.")
        move := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(InStr(move.Script, "move {") && !InStr(move.Script, "duplicate"), "Move must not become a copy.")
        FileAppend("existing", Platform.Join(destination, Path.Leaf(file)), "UTF-8-RAW")
        MacFinderActions.Check(!MacDesktop.CopyMove([file], destination), "Cancelling conflicts must leave files alone.")
        MacFinderActions.Answer := "No"
        MacFinderActions.Check(!MacDesktop.CopyMove([file], destination), "Skipping all conflicts must do nothing.")
        MacFinderActions.Answer := "Yes"
        MacFinderActions.Check(MacDesktop.CopyMove([file], destination), "Explicit conflict replacement must dispatch.")
        MacFinderActions.Check(InStr(MacFinderActions.Calls.Pop().Script, "with replacing"), "Replacement must require an explicit affirmative choice.")
        MacDesktop.GetInfo(file)
        MacFinderActions.Check(InStr(MacFinderActions.Calls.Pop().Script, "open information window"), "Get Info must use Finder information windows.")
        MacDesktop.QuickLook([file])
        call := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(call.Executable == "/usr/bin/qlmanage" && call.Arguments[1] == "-p" && call.Arguments[2] == file, "Quick Look must preserve literal file arguments.")
        MacDesktop.Search('tag:"work thing"', destination, true)
        call := MacFinderActions.Calls.Pop()
        searchXml := FileRead(call.Arguments[1])
        MacFinderActions.Check(InStr(searchXml, "kMDItemUserTags") && InStr(searchXml, "public.folder") && InStr(searchXml, destination), "Finder fallback must preserve metadata syntax, folder filters and scope.")
        AppSettings.General["FileManager"] := "/Applications/Fixture File Manager.app"
        ActionCatalog.OpenFolder(destination)
        call := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(call.Executable == "/usr/bin/open" && JSON.Stringify(call.Arguments) == JSON.Stringify(["-a", "/Applications/Fixture File Manager.app", destination]), "The selected file manager must receive the folder literally.")
        ActionCatalog.Reveal(file)
        call := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(call.Arguments[3] == source, "Alternative file managers must receive the containing folder for reveal.")
        AppSettings.General["FileManager"] := ""
        TerminalProvider.OpenAtCurrentFolder()
        call := MacFinderActions.Calls.Pop()
        MacFinderActions.Check(call.Executable == "/usr/bin/osascript", "Terminal Here must use the Finder folder launch path.")
        ; The wrapper is created by the real terminal builder even though terminal execution is intercepted.
        match := ""
        if RegExMatch(call.Arguments[2], "ALTRun-terminal-[0-9a-f]+\.sh", &match) {
            Loop Files, Platform.Join(A_Temp, match[0]), "F"
                FileDelete(A_LoopFileFullPath)
        }
        FileAppend("PASS MAC_FINDER_ACTIONS safe Finder copy/move, conflicts, Get Info, Quick Look and Terminal Here dispatch`n", "*")

        item := ResultItem("fixture", "", {Kind: "file", Arg: file})
        actions := Map()
        for action in ResultActions.ListFor(item)
            actions[action.Title] := true
        for key in ["Action.GetInfo", "Action.OpenWith", "Action.QuickLook", "Action.Share", "Action.CopyToFolder", "Action.MoveToFolder", "Action.CopyToFinder", "Action.MoveToFinder"]
            MacFinderActions.Check(actions.Has(I18n.T(key)), "Missing native action: " key)
        choices := [ResultItem("Owned choice", "", {OnRun: (*) => true})]
        MacFinderActions.Check(ResultActions.ListFor(ResultItem("Choose", "", {Kind: "actions", Actions: choices})) == choices, "An actions-only chooser must not acquire a no-op Run row.")
        MacFinderActions.Check(!ALTRunMacDialogMatches(-1), "An unknown dialog token must not authorize keyboard input.")
        MacFinderActions.Check(!ALTRunMacSetGoToFolder(-1, destination), "An unknown dialog token must not authorize text replacement.")
        MacFinderActions.Check(!ALTRunMacApplicationAction(ProcessExist(), "Quit"), "Application actions must not terminate the launcher process.")
        FileAppend("PASS MAC_FINDER_ACTIONS action availability and stale-dialog guards`n", "*")
        ExitApp(0)
    }

    static NativeDialog(source, destination) {
        MacFinderActions.NativeDestination := destination
        MacFinderActions.NativeOwner := Gui("", "ALTRun Owned Finder Fixture")
        MacFinderActions.NativeOwner.AddText("w300", "Owned file dialog test")
        MacFinderActions.NativeOwner.Show()
        WinActivate("ahk_id " MacFinderActions.NativeOwner.Hwnd)
        Sleep(150)
        SetTimer(() => MacFinderActions.ProbeNativeDialog(), -800)
        selected := FileSelect("S", Platform.Join(source, "preserve-name.txt"), "ALTRun Owned Finder Fixture", "Text (*.txt)")
        MacFinderActions.Check(MacFinderActions.NativeError = "", MacFinderActions.NativeError)
        MacFinderActions.Check(MacFinderActions.NativePassed, "The owned native file panel was not recognized or navigated.")
        FileAppend("PASS MAC_FINDER_ACTIONS owned native Save panel folder navigation and filename preservation`n", "*")
    }

    static NativeActions(file, destination) {
        MacFinderActions.Check(MacDesktop.Share([file]), "Share did not open its owned picker window.")
        Sleep(200)
        MacFinderActions.Check(ALTRunMacFinderFixtureShare(), "The native sharing-service picker was not constructed.")
        MacDesktop.Stop()
        FileAppend("PASS MAC_FINDER_ACTIONS native Share picker construction without sharing data`n", "*")
        originalFolders := MacDesktop.GetOwnPropDesc("Folders")
        MacDesktop.DefineProp("Folders", {Call: (self) => [{Path: destination, Group: "open", Tag: "Finder"}]})
        try {
            QuickSwitch.Options := AppSettings.Extension("QuickSwitch")
            MacQuickSwitch.BuildPanel()
            MacQuickSwitch.Input.Value := "destination"
            MacQuickSwitch.Filter()
            MacFinderActions.Check(MacQuickSwitch.Rows.Length = 1 && MacQuickSwitch.Rows[1].Path == destination, "The native folder panel did not filter its Finder rows.")
            MacQuickSwitch.Key("Down")
            MacQuickSwitch.HidePanel()
        } finally {
            MacDesktop.DefineProp("Folders", originalFolders)
        }
        FileAppend("PASS MAC_FINDER_ACTIONS native searchable folder-panel controls and cleanup`n", "*")
        MacFinderActions.NativeOwner := Gui("", "ALTRun Owned Open With Fixture")
        MacFinderActions.NativeOwner.AddText("w300", "Owned application chooser test")
        MacFinderActions.NativeOwner.Show()
        WinActivate("ahk_id " MacFinderActions.NativeOwner.Hwnd)
        Sleep(100)
        SetTimer(() => MacFinderActions.ProbeOpenWith(), -500)
        result := MacDesktop.OpenWith(file)
        MacFinderActions.Check(!result && MacFinderActions.NativePassed, "The application chooser did not cancel without opening a file.")
        MacFinderActions.Check(MacFinderActions.NativeError = "", MacFinderActions.NativeError)
        FileAppend("PASS MAC_FINDER_ACTIONS native Open With application chooser and safe cancellation`n", "*")
    }

    static ProbeOpenWith() {
        try {
            MacFinderActions.Check(ALTRunMacFrontPid() = ProcessExist(), "The owned application chooser lost focus.")
            MacFinderActions.Check(MacDesktop.FileDialog()["Valid"], "The native application chooser was not recognized.")
            MacFinderActions.NativePassed := true
        } catch as error {
            MacFinderActions.NativeError := error.Message
        } finally {
            ALTRunMacFinderFixtureCancel()
        }
    }

    static NativeFinder(file, destination) {
        MacDesktop.Refresh()
        started := A_TickCount
        while MacDesktop.Snapshot()["Pending"] && A_TickCount - started < 3000
            Sleep(25)
        snapshot := MacDesktop.Snapshot()
        if snapshot["Error"] != "" {
            FileAppend("SKIP MAC_FINDER_NATIVE Finder automation permission must already be granted.`n", "*")
            return
        }
        MacFinderActions.Check(snapshot["Folder"] != "", "A granted Finder read must return its current folder.")
        copied := Platform.Join(destination, Path.Leaf(file))
        MacFinderActions.Check(MacDesktop.CopyMove([file], destination), "Native Finder copy was not started.")
        MacFinderActions.WaitFor(() => FileExist(copied) && !MacDesktop._jobs.Length, "Native Finder copy did not complete.")
        MacFinderActions.Check(FileRead(copied) == "fixture content" && FileExist(file), "Finder copy changed source or content.")
        movedFolder := Platform.Join(MacFinderActions.Folder, "moved")
        DirCreate(movedFolder)
        MacFinderActions.Check(MacDesktop.CopyMove([copied], movedFolder, true), "Native Finder move was not started.")
        moved := Platform.Join(movedFolder, Path.Leaf(file))
        MacFinderActions.WaitFor(() => FileExist(moved) && !FileExist(copied) && !MacDesktop._jobs.Length, "Native Finder move did not complete.")
        MacFinderActions.Check(FileRead(moved) == "fixture content", "Finder move changed file content.")
        FileAppend("PASS MAC_FINDER_ACTIONS native Finder snapshot, literal Unicode/newline copy and move`n", "*")
    }

    static WaitFor(predicate, message) {
        started := A_TickCount
        while !predicate.Call() {
            MacFinderActions.Check(A_TickCount - started < 5000, message)
            Sleep(25)
        }
    }

    static ProbeNativeDialog() {
        try {
            MacFinderActions.Check(ALTRunMacFrontPid() = ProcessExist(), "The owned file panel lost focus; no keys were sent (expected " ProcessExist() ", actual " ALTRunMacFrontPid() ").")
            dialog := MacDesktop.FileDialog()
            if !dialog["Valid"]
                FileAppend("DIAGNOSTIC MAC_FINDER_DIALOG " ALTRunMacFinderFixtureAX() "`n", "*")
            MacFinderActions.Check(dialog["Valid"], "The owned Save panel was not recognized.")
            before := ALTRunMacFinderFixtureName()
            MacFinderActions.Check(MacDesktop.JumpFolder(MacFinderActions.NativeDestination, dialog), "Navigation did not reach the Go to Folder sheet.")
            Sleep(350)
            after := ALTRunMacFinderFixtureName()
            MacFinderActions.Check(before = after && InStr(after, "preserve-name"), "Folder navigation changed the Save filename.")
            MacFinderActions.Check(ALTRunMacFinderFixtureSamePath(ALTRunMacFinderFixtureFolder(), MacFinderActions.NativeDestination), "The native Save panel did not enter the requested directory: " ALTRunMacFinderFixtureFolder())
            MacFinderActions.NativePassed := true
        } catch as error {
            MacFinderActions.NativeError := error.Message
            FileAppend("DIAGNOSTIC MAC_FINDER_NAV " ALTRunMacFinderFixtureAX() "`n", "*")
        } finally {
            ALTRunMacFinderFixtureCancel()
        }
    }

    static CleanUp() {
        if IsObject(MacFinderActions.NativeOwner)
            try MacFinderActions.NativeOwner.Destroy()
        if IsObject(MacFinderActions.SavedApple)
            MacDesktop.DefineProp("AppleScript", MacFinderActions.SavedApple)
        if IsObject(MacFinderActions.SavedStart)
            ProcessRunner.DefineProp("StartApplication", MacFinderActions.SavedStart)
        if IsObject(MacFinderActions.SavedRead)
            MacDesktop.DefineProp("Snapshot", MacFinderActions.SavedRead)
        MacDesktop.Stop()
        for search in MacFinderActions.Searches
            try FileDelete(search)
        if MacFinderActions.Folder != ""
            try DirDelete(MacFinderActions.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL MAC_FINDER_ACTIONS " message "`n", "*")
        ExitApp(1)
    }
}

#if OSX
#CSharp
[System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",EntryPoint="AXUIElementCopyActionNames")]
private static extern int ALTRunMacFinderFixtureActions(nint element,out nint names);
public static long ALTRunMacFinderFixtureMode(string path) => (long)System.IO.File.GetUnixFileMode(path);
public static bool ALTRunMacFinderFixtureShare() => ALTRunMacSharePicker!=0;
public static string ALTRunMacFinderFixtureAX()
{
    if(ALTRunMacDesktopNative.FrontPid()!=System.Environment.ProcessId)return "not-owned";
    var app=ALTRunMacDesktopNative.AXUIElementCreateApplication(System.Environment.ProcessId);
    var window=ALTRunMacDesktopNative.Get(app,"AXFocusedWindow"); if(window==0)return "no-window";
    var nodes=ALTRunMacAXNodes(window); var result=new System.Text.StringBuilder();
    foreach(var node in nodes) {
        result.Append(ALTRunMacDesktopNative.Attribute(node,"AXRole")).Append('/').Append(ALTRunMacDesktopNative.Attribute(node,"AXSubrole")).Append(':').Append(ALTRunMacDesktopNative.Attribute(node,"AXIdentifier"));
        if(ALTRunMacFinderFixtureActions(node,out var actions)==0 && actions!=0) {
            for(long i=0;i<(long)ALTRunMacDesktopNative.CFArrayGetCount(actions);i++)result.Append(',').Append(ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.CFArrayGetValueAtIndex(actions,(nint)i)));
            ALTRunMacDesktopNative.CFRelease(actions);
        }
        result.Append('|'); ALTRunMacDesktopNative.CFRelease(node);
    }
    ALTRunMacDesktopNative.CFRelease(window); ALTRunMacDesktopNative.CFRelease(app); return result.ToString();
}
public static string ALTRunMacFinderFixtureName()
{
    var panel=ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSApplication"),ALTRunMacDesktopNative.Sel("sharedApplication")),ALTRunMacDesktopNative.Sel("modalWindow"));
    if(panel==0)return "";
    return ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Send(panel,ALTRunMacDesktopNative.Sel("nameFieldStringValue")));
}
public static void ALTRunMacFinderFixtureCancel()
{
    var panel=ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSApplication"),ALTRunMacDesktopNative.Sel("sharedApplication")),ALTRunMacDesktopNative.Sel("modalWindow"));
    if(panel!=0)ALTRunMacDesktopNative.Arg(panel,ALTRunMacDesktopNative.Sel("cancel:"),0);
}
public static string ALTRunMacFinderFixtureFolder()
{
    var panel=ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSApplication"),ALTRunMacDesktopNative.Sel("sharedApplication")),ALTRunMacDesktopNative.Sel("modalWindow"));
    if(panel==0)return "";
    var url=ALTRunMacDesktopNative.Send(panel,ALTRunMacDesktopNative.Sel("directoryURL"));
    return ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Send(url,ALTRunMacDesktopNative.Sel("path")));
}
public static bool ALTRunMacFinderFixtureSamePath(string a,string b)
{
    string Resolve(string value) { var pointer=ALTRunMacDesktopNative.RealPath(value,0); if(pointer==0)return value; try{return System.Runtime.InteropServices.Marshal.PtrToStringUTF8(pointer) ?? value;}finally{ALTRunMacDesktopNative.Free(pointer);} }
    return Resolve(a)==Resolve(b);
}
#EndCSharp
#endif

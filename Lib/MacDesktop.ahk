; macOS desktop actions. Finder reads are cached and refreshed off the input thread.
class MacDesktop {
    static _timer := "", _jobs := [], _poll := "", _shareGui := "", _searches := []

    static Init() {
        if !Platform.IsMac
            return
        MacDesktop.Refresh()
        MacDesktop._timer := (*) => BackgroundWork.CanRun() ? MacDesktop.Refresh() : ""
        SetTimer(MacDesktop._timer, 5000)
    }

    static Stop() {
        if IsObject(MacDesktop._timer)
            SetTimer(MacDesktop._timer, 0)
        if IsObject(MacDesktop._poll)
            SetTimer(MacDesktop._poll, 0)
        for job in MacDesktop._jobs
            try ProcessRunner.Finish(job.Process, true)
        MacDesktop._jobs := []
        if IsObject(MacDesktop._shareGui)
            try MacDesktop._shareGui.Destroy()
        for search in MacDesktop._searches
            try FileDelete(search)
        MacDesktop._searches := []
#if OSX
        ALTRunMacDesktopStop()
#endif
    }

    static Refresh(requestPermission := false) {
#if OSX
        ALTRunMacFinderRefresh(requestPermission)
#endif
    }

    ; Only explicit commands wait for a fresh Finder read; menus use the last cached snapshot.
    static Snapshot(refresh := false) {
#if OSX
        if refresh {
            MacDesktop.Refresh(true)
            started := A_TickCount
            while (ALTRunMacFinderPending() && A_TickCount - started < 2000)
                Sleep(15)
        }
        snapshot := JSON.Parse(ALTRunMacFinderSnapshot())
        if refresh && (snapshot["Pending"] || snapshot["Error"] != "")
            snapshot["Folder"] := "", snapshot["Selection"] := [], snapshot["Folders"] := []
        return snapshot
#else
        return Map("Folder", "", "Selection", [], "Folders", [], "Error", "", "Pending", false)
#endif
    }

    static CurrentFolder(refresh := true) => MacDesktop.Snapshot(refresh)["Folder"]
    static Selection(refresh := true) => MacDesktop.Snapshot(refresh)["Selection"]

    static Folders() {
        folders := [], seen := Map()
        add(folder, group, tag) {
            if (folder != "" && !seen.Has(folder) && DirExist(folder)) {
                seen[folder] := true
                folders.Push({Path: folder, Group: group, Tag: tag})
            }
        }
        for folder in MacDesktop.Snapshot()["Folders"]
            add(folder, "open", "Finder")
        for folder in QuickSwitch.RecentFolders(QuickSwitch.Options.Has("RecentFolders") ? QuickSwitch.Options["RecentFolders"] : 10)
            add(folder, "recent", I18n.T("QuickSwitch.TagRecent"))
        return folders
    }

    static _Aliases(paths) {
        values := []
        for itemPath in paths
            values.Push("(POSIX file " ProcessRunner.QuoteAppleScript(Platform.FullPath(itemPath)) " as alias)")
        return "{" TextTools.JoinList(values, ", ") "}"
    }

    static AppleScript(script, title := "Finder") {
        process := ProcessRunner.StartApplication("/usr/bin/osascript", ["-e", "with timeout of 120 seconds`n" script "`nend timeout"], "", true)
        MacDesktop._jobs.Push({Process: process, Title: title, Started: A_TickCount})
        if !IsObject(MacDesktop._poll)
            MacDesktop._poll := (*) => MacDesktop._PollJobs()
        SetTimer(MacDesktop._poll, 100)
        return true
    }

    static _PollJobs() {
        index := MacDesktop._jobs.Length
        while index > 0 {
            job := MacDesktop._jobs[index]
            if ((finished := ProcessRunner.IsFinished(job.Process)) || A_TickCount - job.Started > 125000) {
                MacDesktop._jobs.RemoveAt(index)
                try {
                    output := ProcessRunner.Finish(job.Process, !finished)
                    if (Trim(output) != "")
                        App.Notify(job.Title ": " Trim(output), 5000)
                } catch as e {
                    Logger.Error(job.Title ": " e.Message)
                    App.Notify(job.Title ": " e.Message, 5000)
                }
                MacDesktop.Refresh()
            }
            index--
        }
        if !MacDesktop._jobs.Length
            SetTimer(MacDesktop._poll, 0)
    }

    static GetInfo(itemPath) {
        return MacDesktop.AppleScript('tell application "Finder" to open information window of (POSIX file ' ProcessRunner.QuoteAppleScript(Platform.FullPath(itemPath)) ' as alias)', I18n.T("Action.GetInfo"))
    }

    static OpenWith(itemPath) {
#if OSX
        application := ALTRunMacChooseApplication()
        if (application != "")
            return ProcessRunner.StartApplication("/usr/bin/open", ["-a", application, Platform.FullPath(itemPath)])
#endif
        return false
    }

    static QuickLook(paths) {
        arguments := ["-p"]
        for itemPath in paths
            if FileExist(itemPath)
                arguments.Push(Platform.FullPath(itemPath))
        if arguments.Length = 1
            return false
        return ProcessRunner.StartApplication("/usr/bin/qlmanage", arguments)
    }

    static Share(items) {
#if OSX
        if !items.Length
            return false
        if IsObject(MacDesktop._shareGui)
            try MacDesktop._shareGui.Destroy()
        windowGui := Gui("+ToolWindow +AlwaysOnTop", I18n.T("Action.Share"))
        windowGui.BackColor := ThemeManager.Get("Background")
        windowGui.SetFont("s12 c" ThemeManager.Get("Title"))
        windowGui.AddText("w360", I18n.T("Mac.ShareHint"))
        button := windowGui.AddButton("w180 Default", I18n.T("Action.Share"))
        button.OnEvent("Click", (*) => ALTRunMacShare(windowGui.ToClr(), JSON.Stringify(items)))
        windowGui.OnEvent("Escape", (*) => windowGui.Destroy())
        windowGui.Show("w400 h110")
        MacDesktop._shareGui := windowGui
        ALTRunMacShare(windowGui.ToClr(), JSON.Stringify(items))
        return true
#else
        return false
#endif
    }

    ; Finder performs the transfer; conflicts are an explicit choice before any operation starts.
    static CopyMove(paths, destination := "", move := false) {
        if (destination = "")
            destination := DirSelect("", 0, I18n.T(move ? "Action.MoveToFolder" : "Action.CopyToFolder"))
        if (destination = "" || !DirExist(destination))
            return false
        valid := [], conflicts := [], replacing := false
        destination := Platform.FullPath(destination)
        for itemPath in paths {
            itemPath := Platform.FullPath(itemPath)
            if !FileExist(itemPath)
                continue
#if OSX
            if !ALTRunMacTransferAllowed(itemPath, destination)
                continue
#endif
            target := Platform.Join(destination, Path.Leaf(RTrim(itemPath, "/")))
            if FileExist(target)
                conflicts.Push(itemPath)
            else
                valid.Push(itemPath)
        }
        if conflicts.Length {
            choice := MsgBox(I18n.T("Mac.TransferConflicts", conflicts.Length, destination), App.Name, "YesNoCancel Icon? Default3")
            if (choice = "Cancel")
                return false
            if (choice = "Yes") {
                replacing := true
                for itemPath in conflicts
                    valid.Push(itemPath)
            }
        }
        if !valid.Length
            return false
        command := move ? "move " : "duplicate "
        script := 'tell application "Finder"`n' command MacDesktop._Aliases(valid) " to (POSIX file " ProcessRunner.QuoteAppleScript(destination) " as alias)"
            . (replacing ? " with replacing" : " without replacing") '`nend tell'
        App.Notify(I18n.T(move ? "Action.MovingMany" : "Action.CopyingMany", valid.Length, destination), 2000)
        return MacDesktop.AppleScript(script, I18n.T(move ? "Action.MoveToFolder" : "Action.CopyToFolder"))
    }

    static DateStamp() {
#if OSX
        try {
            if !ALTRunMacFinderActive()
                return false
            paths := MacDesktop.Selection()
            if !paths.Length
                return false
            changes := []
            for itemPath in paths {
                name := AutoDate.AddDateToName(Path.Leaf(RTrim(itemPath, "/")))
                if (InStr(name, "/") || InStr(name, ":") || name = "" || name = "." || name = "..")
                    throw Error(I18n.T("Mac.InvalidDateName"))
                if (name == Path.Leaf(RTrim(itemPath, "/")))
                    continue
                if FileExist(Platform.Join(ActionCatalog.ParentDir(itemPath), name))
                    throw Error(I18n.T("Mac.DateConflict", name))
                changes.Push("set name of (POSIX file " ProcessRunner.QuoteAppleScript(itemPath) " as alias) to " ProcessRunner.QuoteAppleScript(name))
            }
            if !changes.Length
                return false
            Usage.Count("AutoDate")
            return MacDesktop.AppleScript('tell application "Finder"`n' TextTools.JoinList(changes, "`n") '`nend tell', I18n.T("Mac.DateStamp"))
        } catch as e {
            App.Notify(e.Message, 5000)
        }
#endif
        return false
    }

    ; A saved search opens in Finder without typing into an unrelated application's controls.
    static Search(term, folder := "", scope := false) {
#if OSX
        expression := MacSpotlight.Expression(term, scope)
        file := ALTRunMacSavedSearchQuery(expression["Query"], folder)
        MacDesktop._searches.Push(file)
        return ProcessRunner.StartApplication("/usr/bin/open", [file])
#else
        return false
#endif
    }

    static FileDialog() {
#if OSX
        return JSON.Parse(ALTRunMacFileDialog())
#else
        return Map("Valid", false)
#endif
    }

    static JumpFolder(folder, dialog := "") {
#if OSX
        if !DirExist(folder)
            return false
        if !IsObject(dialog)
            dialog := MacDesktop.FileDialog()
        if !dialog["Valid"] || !ALTRunMacDialogMatches(dialog["Token"])
            return false
        Win.WaitModifiersUp()
        SendEvent("#+g")
        started := A_TickCount
        while (A_TickCount - started < 1500) {
            if ALTRunMacSetGoToFolder(dialog["Token"], Platform.FullPath(folder)) {
                Sleep(150)
                ; Cocoa's path completion can take one Return to accept the completion and
                ; another to enter it. Each Return is restricted to that same Go to Folder sheet.
                Loop 2 {
                    if !ALTRunMacGoToReady(dialog["Token"])
                        break
                    SendEvent("{Enter}")
                    Sleep(150)
                }
                if ALTRunMacDialogMatches(dialog["Token"]) {
                    Usage.Count("QuickSwitch")
                    return true
                }
                return false
            }
            Sleep(25)
        }
#endif
        return false
    }

    static WindowActions(hwnd) {
        actions := [], pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if !pid
            return actions
        for entry in [["Center", "Mac.WindowCenter"], ["Left", "Mac.WindowLeft"], ["Right", "Mac.WindowRight"], ["Maximize", "Mac.WindowMaximize"], ["Hide", "Mac.AppHide"], ["Quit", "Mac.AppQuit"]] {
            operation := entry[1]
            actions.Push(ResultItem(I18n.T(entry[2]), "", {Icon: App.IconFile, OnRun: MacDesktop._WindowHandler(hwnd, pid, operation)}))
        }
        return actions
    }

    static _WindowHandler(hwnd, pid, operation) => (*) => MacDesktop.WindowAction(hwnd, pid, operation)

    static Unhide(pid) {
#if OSX
        return ALTRunMacApplicationAction(pid, "Show")
#else
        return false
#endif
    }

    static WindowAction(hwnd, pid, operation) {
        if !(operation ~= "^(Center|Left|Right|Maximize|Hide|Quit)$")
            return false
        if !WinExist("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != pid
            return App.Notify(I18n.T("Win.Gone"))
#if OSX
        if (operation = "Hide" || operation = "Quit") {
            accepted := ALTRunMacApplicationAction(pid, operation)
            if !accepted
                App.Notify(I18n.T("Mac.AppActionFailed", I18n.T(operation = "Hide" ? "Mac.AppHide" : "Mac.AppQuit")), 4000)
            return accepted
        }
#endif
        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
        area := Win.WorkAreaAt(x + width / 2, y + height / 2)
        availableW := area.Right - area.Left, availableH := area.Bottom - area.Top
        switch operation {
            case "Center":
                width := Min(width, availableW), height := Min(height, availableH)
                WinMove(area.Left + (availableW - width) / 2, area.Top + (availableH - height) / 2, width, height, "ahk_id " hwnd)
            case "Left", "Right":
                half := Floor(availableW / 2)
                WinMove(area.Left + (operation = "Right" ? half : 0), area.Top, operation = "Right" ? availableW - half : half, availableH, "ahk_id " hwnd)
            case "Maximize":
                WinMove(area.Left, area.Top, availableW, availableH, "ahk_id " hwnd)
        }
        WinActivate("ahk_id " hwnd)
        return true
    }
}

#if OSX
#CSharp
private static class ALTRunMacDesktopNative
{
    internal const string ObjC = "/usr/lib/libobjc.A.dylib";
    internal const string CF = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    internal const string AX = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_getClass")] internal static extern nint Class(string name);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="sel_registerName")] internal static extern nint Sel(string name);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern nint Send(nint target, nint selector);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern nint Arg(nint target, nint selector, nint value);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern nint Two(nint target, nint selector, nint first, nint second);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern nint StringArg(nint target, nint selector, [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string value);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern void Bool(nint target, nint selector, byte value);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern nint Array(nint target, nint selector, nint[] values, nuint count);
    [System.Runtime.InteropServices.DllImport(ObjC, EntryPoint="objc_msgSend")] internal static extern void Picker(nint target, nint selector, ALTRunMacRect rect, nint view, long edge);
    [System.Runtime.InteropServices.DllImport(CF)] internal static extern void CFRelease(nint value);
    [System.Runtime.InteropServices.DllImport(CF)] internal static extern nint CFRetain(nint value);
    [System.Runtime.InteropServices.DllImport(CF)] [return:System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)] internal static extern bool CFEqual(nint a,nint b);
    [System.Runtime.InteropServices.DllImport(CF)] internal static extern nint CFArrayGetCount(nint array);
    [System.Runtime.InteropServices.DllImport(CF)] internal static extern nint CFArrayGetValueAtIndex(nint array,nint index);
    [System.Runtime.InteropServices.DllImport(AX)] internal static extern nint AXUIElementCreateApplication(int pid);
    [System.Runtime.InteropServices.DllImport(AX)] internal static extern int AXUIElementCopyAttributeValue(nint element,nint attribute,out nint value);
    [System.Runtime.InteropServices.DllImport(AX)] internal static extern int AXUIElementSetAttributeValue(nint element,nint attribute,nint value);
    [System.Runtime.InteropServices.DllImport(AX)] internal static extern int AXUIElementSetMessagingTimeout(nint element,float seconds);
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")] internal static extern int AECreateDesc(uint type,byte[] data,nint size,out ALTRunMacAEDesc descriptor);
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")] internal static extern int AEDisposeDesc(ref ALTRunMacAEDesc descriptor);
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")] internal static extern int AEDeterminePermissionToAutomateTarget(ref ALTRunMacAEDesc descriptor,uint eventClass,uint eventId,byte ask);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libSystem.B.dylib",EntryPoint="realpath")] internal static extern nint RealPath([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string path,nint resolved);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libSystem.B.dylib",EntryPoint="free")] internal static extern void Free(nint value);
    internal static nint Text(string value) => StringArg(Class("NSString"),Sel("stringWithUTF8String:"),value);
    internal static nint Send(nint target,string selector) => Send(target,Sel(selector));
    internal static nint Arg(nint target,string selector,nint value) => Arg(target,Sel(selector),value);
    internal static string String(nint value) => value == 0 ? "" : System.Runtime.InteropServices.Marshal.PtrToStringUTF8(Send(value,Sel("UTF8String"))) ?? "";
    internal static nint Get(nint element,string name) => AXUIElementCopyAttributeValue(element,Text(name),out var value)==0 ? value : 0;
    internal static string Attribute(nint element,string name) { var value=Get(element,name); if(value==0)return ""; try{return String(value);}finally{CFRelease(value);} }
    internal static int FrontPid() { var workspace=Send(Class("NSWorkspace"),Sel("sharedWorkspace")); var app=Send(workspace,Sel("frontmostApplication")); return (int)Send(app,Sel("processIdentifier")); }
    internal static bool FinderActive() { var workspace=Send(Class("NSWorkspace"),Sel("sharedWorkspace")); return String(Send(Send(workspace,Sel("frontmostApplication")),Sel("bundleIdentifier")))=="com.apple.finder"; }
    internal static string Run(string script,int timeout=1800)
    {
        var info=new System.Diagnostics.ProcessStartInfo("/usr/bin/osascript") { UseShellExecute=false,RedirectStandardOutput=true,RedirectStandardError=true };
        info.ArgumentList.Add("-e"); info.ArgumentList.Add(script);
        using var process=System.Diagnostics.Process.Start(info) ?? throw new System.InvalidOperationException("Could not start Finder automation.");
        var output=process.StandardOutput.ReadToEndAsync(); var error=process.StandardError.ReadToEndAsync();
        if(!process.WaitForExit(timeout)) { process.Kill(true); throw new System.TimeoutException("Finder did not respond in time."); }
        string result=output.GetAwaiter().GetResult(); string failure=error.GetAwaiter().GetResult();
        if(process.ExitCode!=0) throw new System.InvalidOperationException(failure.Trim());
        return result;
    }
}
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
private struct ALTRunMacRect { internal double X,Y,Width,Height; }
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
private struct ALTRunMacAEDesc { internal uint Type; internal nint Handle; }
private sealed record ALTRunMacFinderState(string Folder,string[] Selection,string[] Folders,string Error,bool Pending);
private static readonly object ALTRunMacFinderLock=new();
private static ALTRunMacFinderState ALTRunMacFinder=new("",[],[],"",false);
public static void ALTRunMacFinderRefresh(bool requestPermission)
{
    lock(ALTRunMacFinderLock) if(ALTRunMacFinder.Pending)return;
    if(!requestPermission) {
        byte[] target=System.Text.Encoding.UTF8.GetBytes("com.apple.finder");
        if(ALTRunMacDesktopNative.AECreateDesc(0x62756e64,target,target.Length,out var address)!=0)return;
        int permission;
        try { permission=ALTRunMacDesktopNative.AEDeterminePermissionToAutomateTarget(ref address,0x636f7265,0x67657464,0); }
        finally { ALTRunMacDesktopNative.AEDisposeDesc(ref address); }
        if(permission!=0) { lock(ALTRunMacFinderLock) ALTRunMacFinder=ALTRunMacFinder with { Error="Finder Automation permission is required.", Pending=false }; return; }
    }
    lock(ALTRunMacFinderLock) { if(ALTRunMacFinder.Pending)return; ALTRunMacFinder=ALTRunMacFinder with { Pending=true }; }
    _=System.Threading.Tasks.Task.Run(() => {
        try {
            const string script="use framework \"Foundation\"\nuse scripting additions\non encoded(value)\nreturn (((current application's NSString's stringWithString:value)'s dataUsingEncoding:4)'s base64EncodedStringWithOptions:0) as text\nend encoded\nset currentFolder to \"\"\nset selectedPaths to {}\nset folderPaths to {}\nwith timeout of 1 seconds\ntell application \"Finder\"\nif (count of Finder windows) > 0 then\ntry\nset currentFolder to POSIX path of (target of front Finder window as alias)\nend try\nrepeat with aWindow in Finder windows\ntry\nset end of folderPaths to POSIX path of (target of aWindow as alias)\nend try\nend repeat\nelse\nset currentFolder to POSIX path of (desktop as alias)\nend if\nrepeat with anItem in (get selection)\ntry\nset end of selectedPaths to POSIX path of (anItem as alias)\nend try\nend repeat\nend tell\nend timeout\nset resultText to \"C\" & (my encoded(currentFolder)) & linefeed\nrepeat with aPath in selectedPaths\nset resultText to resultText & \"S\" & (my encoded(aPath as text)) & linefeed\nend repeat\nrepeat with aPath in folderPaths\nset resultText to resultText & \"F\" & (my encoded(aPath as text)) & linefeed\nend repeat\nreturn resultText";
            string folder=""; var selection=new System.Collections.Generic.List<string>(); var folders=new System.Collections.Generic.List<string>();
            foreach(string line in ALTRunMacDesktopNative.Run(script).Split('\n')) {
                string text=line.TrimEnd('\r'); if(text.Length<2)continue;
                string path=System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(text[1..]));
                if(text[0]=='C')folder=path; else if(text[0]=='S')selection.Add(path); else if(text[0]=='F')folders.Add(path);
            }
            lock(ALTRunMacFinderLock) ALTRunMacFinder=new(folder,selection.ToArray(),folders.ToArray(),"",false);
        } catch(System.Exception error) { lock(ALTRunMacFinderLock) ALTRunMacFinder=ALTRunMacFinder with { Error=error.Message,Pending=false }; }
    });
}
public static string ALTRunMacFinderSnapshot() { lock(ALTRunMacFinderLock)return System.Text.Json.JsonSerializer.Serialize(ALTRunMacFinder); }
public static bool ALTRunMacFinderPending() { lock(ALTRunMacFinderLock)return ALTRunMacFinder.Pending; }
public static bool ALTRunMacFinderActive() => ALTRunMacDesktopNative.FinderActive();
public static long ALTRunMacFrontPid() => ALTRunMacDesktopNative.FrontPid();
public static bool ALTRunMacTransferAllowed(string source,string destination)
{
    string Canonical(string path) {
        string full=System.IO.Path.GetFullPath(path).TrimEnd('/');
        nint real=ALTRunMacDesktopNative.RealPath(full,0);
        if(real!=0) { try { full=System.Runtime.InteropServices.Marshal.PtrToStringUTF8(real)?.TrimEnd('/') ?? full; } finally { ALTRunMacDesktopNative.Free(real); } }
        return full;
    }
    source=Canonical(source); destination=Canonical(destination);
    return source.Length>0 && destination!=source && !destination.StartsWith(source+"/",System.StringComparison.Ordinal)
        && System.IO.Path.GetDirectoryName(source)!=destination;
}
public static bool ALTRunMacApplicationAction(long pid,string action)
{
    if(pid<=0 || pid==System.Environment.ProcessId)return false;
    bool result=false;
    Eto.Forms.Application.Instance.Invoke(() => result=ALTRunMacApplicationActionOnUi(pid,action));
    return result;
}
private static bool ALTRunMacApplicationActionOnUi(long pid,string action)
{
    nint app=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSRunningApplication"),"runningApplicationWithProcessIdentifier:",(nint)pid);
    if(action is not ("Hide" or "Show" or "Quit"))return false;
    string selector=action=="Hide"?"hide":action=="Show"?"unhide":"terminate";
    if(app!=0 && ALTRunMacDesktopNative.Send(app,selector)!=0)return true;
    if(action=="Quit")return false;
    nint accessible=ALTRunMacDesktopNative.AXUIElementCreateApplication((int)pid);
    if(accessible==0)return false;
    try {
        ALTRunMacDesktopNative.AXUIElementSetMessagingTimeout(accessible,0.15f);
        nint hidden=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSNumber"),"numberWithBool:",action=="Hide"?1:0);
        return ALTRunMacDesktopNative.AXUIElementSetAttributeValue(accessible,ALTRunMacDesktopNative.Text("AXHidden"),hidden)==0;
    } finally { ALTRunMacDesktopNative.CFRelease(accessible); }
}
public static string ALTRunMacChooseApplication()
{
    string result="";
    Eto.Forms.Application.Instance.Invoke(() => result=ALTRunMacChooseApplicationOnUi());
    return result;
}
private static string ALTRunMacChooseApplicationOnUi()
{
    var panel=ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSOpenPanel"),"openPanel");
    ALTRunMacDesktopNative.Bool(panel,ALTRunMacDesktopNative.Sel("setCanChooseFiles:"),1);
    ALTRunMacDesktopNative.Bool(panel,ALTRunMacDesktopNative.Sel("setCanChooseDirectories:"),0);
    ALTRunMacDesktopNative.Bool(panel,ALTRunMacDesktopNative.Sel("setAllowsMultipleSelection:"),0);
    var types=ALTRunMacDesktopNative.Array(ALTRunMacDesktopNative.Class("NSArray"),ALTRunMacDesktopNative.Sel("arrayWithObjects:count:"),[ALTRunMacDesktopNative.Text("app")],1);
    ALTRunMacDesktopNative.Arg(panel,"setAllowedFileTypes:",types);
    var url=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSURL"),"fileURLWithPath:",ALTRunMacDesktopNative.Text("/Applications"));
    ALTRunMacDesktopNative.Arg(panel,"setDirectoryURL:",url);
    if(ALTRunMacDesktopNative.Send(panel,"runModal")!=1)return "";
    return ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(panel,"URL"),ALTRunMacDesktopNative.Sel("path")));
}
private static nint ALTRunMacSharePicker;
public static void ALTRunMacShare(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper,string json)
    => Eto.Forms.Application.Instance.Invoke(() => ALTRunMacShareOnUi(wrapper,json));
private static void ALTRunMacShareOnUi(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper,string json)
{
    var form=(Eto.Forms.Form)wrapper.Native;
    if(form.ControlObject?.GetType().GetProperty("Handle")?.GetValue(form.ControlObject) is not nint window)return;
    var values=new System.Collections.Generic.List<nint>();
    foreach(string item in System.Text.Json.JsonSerializer.Deserialize<string[]>(json) ?? []) {
        nint value=ALTRunMacDesktopNative.Text(item);
        if(System.IO.Path.IsPathRooted(item) && (System.IO.File.Exists(item)||System.IO.Directory.Exists(item)))value=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSURL"),"fileURLWithPath:",value);
        else if(System.Uri.TryCreate(item,System.UriKind.Absolute,out var uri) && uri.Scheme is "http" or "https")value=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSURL"),"URLWithString:",value);
        values.Add(value);
    }
    var array=ALTRunMacDesktopNative.Array(ALTRunMacDesktopNative.Class("NSArray"),ALTRunMacDesktopNative.Sel("arrayWithObjects:count:"),values.ToArray(),(nuint)values.Count);
    if(ALTRunMacSharePicker!=0)ALTRunMacDesktopNative.Send(ALTRunMacSharePicker,"release");
    ALTRunMacSharePicker=ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSSharingServicePicker"),"alloc"),ALTRunMacDesktopNative.Sel("initWithItems:"),array);
    var view=ALTRunMacDesktopNative.Send(window,"contentView");
    ALTRunMacDesktopNative.Picker(ALTRunMacSharePicker,ALTRunMacDesktopNative.Sel("showRelativeToRect:ofView:preferredEdge:"),new ALTRunMacRect { X=20,Y=20,Width=180,Height=30 },view,1);
}
public static string ALTRunMacSavedSearchQuery(string query,string folder)
{
    string home=System.Environment.GetFolderPath(System.Environment.SpecialFolder.UserProfile);
    string scope=System.IO.Directory.Exists(folder)?System.IO.Path.GetFullPath(folder):home;
    var doc=new System.Xml.Linq.XDocument(new System.Xml.Linq.XDeclaration("1.0","UTF-8",null),new System.Xml.Linq.XElement("plist",new System.Xml.Linq.XAttribute("version","1.0"),new System.Xml.Linq.XElement("dict",
        new System.Xml.Linq.XElement("key","RawQuery"),new System.Xml.Linq.XElement("string",query),new System.Xml.Linq.XElement("key","SearchCriteria"),new System.Xml.Linq.XElement("dict",new System.Xml.Linq.XElement("key","FXScopeArrayOfPaths"),new System.Xml.Linq.XElement("array",new System.Xml.Linq.XElement("string",scope))))));
    string path=System.IO.Path.Combine(System.IO.Path.GetTempPath(),"ALTRun-"+System.Guid.NewGuid().ToString("N")+".savedSearch");
    System.IO.File.WriteAllText(path,doc.ToString(),new System.Text.UTF8Encoding(false));
    System.IO.File.SetUnixFileMode(path,System.IO.UnixFileMode.UserRead|System.IO.UnixFileMode.UserWrite);
    return path;
}
private sealed class ALTRunMacDialogState { internal int Pid; internal nint Window,Dialog,Focus; internal long Token; }
private static ALTRunMacDialogState ALTRunMacDialog;
private static long ALTRunMacDialogToken;
public static void ALTRunMacDesktopStop()
{
    if(ALTRunMacSharePicker!=0) { ALTRunMacDesktopNative.Send(ALTRunMacSharePicker,"release"); ALTRunMacSharePicker=0; }
    if(ALTRunMacDialog is {} state) { ALTRunMacDesktopNative.CFRelease(state.Window); ALTRunMacDesktopNative.CFRelease(state.Dialog); if(state.Focus!=0)ALTRunMacDesktopNative.CFRelease(state.Focus); ALTRunMacDialog=null; }
}
private static System.Collections.Generic.List<nint> ALTRunMacAXNodes(nint root)
{
    var result=new System.Collections.Generic.List<nint>(); var pending=new System.Collections.Generic.Queue<(nint,int)>();
    pending.Enqueue((ALTRunMacDesktopNative.CFRetain(root),0));
    while(pending.Count>0 && result.Count<400) {
        var (item,depth)=pending.Dequeue(); result.Add(item); if(depth>=12)continue;
        nint children=ALTRunMacDesktopNative.Get(item,"AXChildren"); if(children==0)continue;
        try { long count=(long)ALTRunMacDesktopNative.CFArrayGetCount(children); for(long i=0;i<System.Math.Min(count,80);i++)pending.Enqueue((ALTRunMacDesktopNative.CFRetain(ALTRunMacDesktopNative.CFArrayGetValueAtIndex(children,(nint)i)),depth+1)); }
        finally { ALTRunMacDesktopNative.CFRelease(children); }
    }
    while(pending.Count>0)ALTRunMacDesktopNative.CFRelease(pending.Dequeue().Item1);
    return result;
}
private static bool ALTRunMacIsFileDialog(nint node)
{
    string role=ALTRunMacDesktopNative.Attribute(node,"AXRole"),subrole=ALTRunMacDesktopNative.Attribute(node,"AXSubrole");
    if(role!="AXSheet" && role!="AXDialog" && subrole!="AXDialog")return false;
    string identifier=ALTRunMacDesktopNative.Attribute(node,"AXIdentifier");
    if(identifier is "save-panel" or "open-panel")return true;
    var nodes=ALTRunMacAXNodes(node);
    try {
        bool browser=false,path=false,confirm=false;
        foreach(nint child in nodes) {
            string childRole=ALTRunMacDesktopNative.Attribute(child,"AXRole");
            string childIdentifier=ALTRunMacDesktopNative.Attribute(child,"AXIdentifier");
            browser |= childRole is "AXBrowser" or "AXOutline" or "AXTable";
            path |= childRole=="AXPathControl" || childIdentifier.Contains("Path",System.StringComparison.OrdinalIgnoreCase) || childIdentifier.Contains("saveAsName",System.StringComparison.OrdinalIgnoreCase);
            confirm |= childRole=="AXButton";
        }
        return browser && path && confirm;
    } finally { foreach(var child in nodes)ALTRunMacDesktopNative.CFRelease(child); }
}
public static string ALTRunMacFileDialog()
{
    int pid=ALTRunMacDesktopNative.FrontPid(); if(pid<=0)return "{\"Valid\":false}";
    nint app=ALTRunMacDesktopNative.AXUIElementCreateApplication(pid);
    ALTRunMacDesktopNative.AXUIElementSetMessagingTimeout(app,0.12f);
    nint window=ALTRunMacDesktopNative.Get(app,"AXFocusedWindow");
    if(window==0) { ALTRunMacDesktopNative.CFRelease(app); return "{\"Valid\":false}"; }
    nint dialog=0; var nodes=ALTRunMacAXNodes(window);
    foreach(var node in nodes) if(ALTRunMacIsFileDialog(node)) { dialog=ALTRunMacDesktopNative.CFRetain(node); break; }
    foreach(var node in nodes)ALTRunMacDesktopNative.CFRelease(node);
    if(dialog==0) { ALTRunMacDesktopNative.CFRelease(window); ALTRunMacDesktopNative.CFRelease(app); return "{\"Valid\":false}"; }
    if(ALTRunMacDialog is {} existing && existing.Pid==pid && ALTRunMacDesktopNative.CFEqual(existing.Window,window) && ALTRunMacDesktopNative.CFEqual(existing.Dialog,dialog)) {
        ALTRunMacDesktopNative.CFRelease(window); ALTRunMacDesktopNative.CFRelease(dialog);
    } else {
        if(ALTRunMacDialog is {} old) { ALTRunMacDesktopNative.CFRelease(old.Window); ALTRunMacDesktopNative.CFRelease(old.Dialog); if(old.Focus!=0)ALTRunMacDesktopNative.CFRelease(old.Focus); }
        ALTRunMacDialog=new ALTRunMacDialogState { Pid=pid,Window=window,Dialog=dialog,Token=++ALTRunMacDialogToken,Focus=ALTRunMacDesktopNative.Get(app,"AXFocusedUIElement") };
    }
    ALTRunMacDesktopNative.CFRelease(app);
    return System.Text.Json.JsonSerializer.Serialize(new { Valid=true,Pid=pid,Token=ALTRunMacDialog.Token });
}
public static bool ALTRunMacDialogMatches(long token)
{
    if(ALTRunMacDialog is not {} state || state.Token!=token || ALTRunMacDesktopNative.FrontPid()!=state.Pid)return false;
    nint app=ALTRunMacDesktopNative.AXUIElementCreateApplication(state.Pid),window=ALTRunMacDesktopNative.Get(app,"AXFocusedWindow");
    try { return window!=0 && ALTRunMacDesktopNative.CFEqual(window,state.Window) && ALTRunMacIsFileDialog(state.Dialog); }
    finally { if(window!=0)ALTRunMacDesktopNative.CFRelease(window); ALTRunMacDesktopNative.CFRelease(app); }
}
// Both writing and confirming a path require the same token, app, native sheet and focused field.
private static bool ALTRunMacWithGoToFocus(long token,System.Func<nint,bool> action)
{
    if(ALTRunMacDialog is not {} state || state.Token!=token || ALTRunMacDesktopNative.FrontPid()!=state.Pid)return false;
    nint app=ALTRunMacDesktopNative.AXUIElementCreateApplication(state.Pid),window=ALTRunMacDesktopNative.Get(app,"AXFocusedWindow"),focus=ALTRunMacDesktopNative.Get(app,"AXFocusedUIElement"),parent=0;
    try {
        if(window==0 || focus==0 || ALTRunMacDesktopNative.CFEqual(window,state.Dialog)
            || state.Focus!=0 && ALTRunMacDesktopNative.CFEqual(focus,state.Focus))return false;
        if(ALTRunMacDesktopNative.Attribute(window,"AXIdentifier")!="GoToWindow"
            || ALTRunMacDesktopNative.Attribute(focus,"AXIdentifier")!="PathTextField")return false;
        string role=ALTRunMacDesktopNative.Attribute(focus,"AXRole");
        if(role is not ("AXTextField" or "AXComboBox"))return false;
        parent=ALTRunMacDesktopNative.Get(focus,"AXParent");
        for(int depth=0;parent!=0 && depth<8;depth++) {
            if(ALTRunMacDesktopNative.CFEqual(parent,window))return action(focus);
            nint next=ALTRunMacDesktopNative.Get(parent,"AXParent");
            ALTRunMacDesktopNative.CFRelease(parent); parent=next;
        }
        return false;
    } finally {
        if(parent!=0)ALTRunMacDesktopNative.CFRelease(parent);
        if(focus!=0)ALTRunMacDesktopNative.CFRelease(focus);
        if(window!=0)ALTRunMacDesktopNative.CFRelease(window);
        ALTRunMacDesktopNative.CFRelease(app);
    }
}
public static bool ALTRunMacSetGoToFolder(long token,string path) => ALTRunMacWithGoToFocus(token,
    focus => ALTRunMacDesktopNative.AXUIElementSetAttributeValue(focus,ALTRunMacDesktopNative.Text("AXValue"),ALTRunMacDesktopNative.Text(path))==0);
public static bool ALTRunMacGoToReady(long token) => ALTRunMacWithGoToFocus(token,_ => true);
#EndCSharp
#endif

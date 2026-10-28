; Native application identity and Services for a packaged Keysharp-hosted ALTRun.
#CSharp
public static string ALTRunFileAddress(string Filename) => new System.Uri(System.IO.Path.GetFullPath(Filename)).AbsoluteUri;
public static string ALTRunMacArchitecture() => System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x64";
public static string ALTRunOwnAppBundle(string Script)
{
    if (!System.OperatingSystem.IsMacOS()) return "";
    var directory = new System.IO.DirectoryInfo(System.IO.Path.GetDirectoryName(System.Environment.ProcessPath ?? "") ?? "/");
    while (directory != null)
    {
        if (directory.Name.EndsWith(".app", System.StringComparison.OrdinalIgnoreCase))
        {
            string root = System.IO.Path.Combine(directory.FullName, "Contents", "Resources", "ALTRun") + System.IO.Path.DirectorySeparatorChar;
            return System.IO.Path.GetFullPath(Script).StartsWith(root, System.StringComparison.Ordinal) ? directory.FullName : "";
        }
        directory = directory.Parent;
    }
    return "";
}

#EndCSharp
#if OSX
#CSharp
private static class ALTRunServicesNative
{
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    internal delegate void Service(nint self, nint command, nint pasteboard, nint userData, nint error);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] internal static extern nint objc_allocateClassPair(nint superclass,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string name, nuint extraBytes);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] internal static extern void objc_registerClassPair(nint value);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)]
    internal static extern bool class_addMethod(nint cls, nint selector, nint implementation,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string types);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")] internal static extern nint Two(nint target, nint selector, nint first, nint second);
    internal static readonly Service Add = (self, command, pasteboard, data, error) => Receive(pasteboard, true);
    internal static readonly Service Actions = (self, command, pasteboard, data, error) => Receive(pasteboard, false);
    internal static nint Provider;
    internal static readonly System.Collections.Concurrent.ConcurrentQueue<string> Requests = new();

    internal static void Receive(nint pasteboard, bool add)
    {
        try
        {
            nint Sel(string name) => ALTRunMacDesktopNative.Sel(name);
            nint Send(nint target, string name) => ALTRunMacDesktopNative.Send(target, Sel(name));
            var paths = new System.Collections.Generic.List<string>();
            nint classes = ALTRunMacDesktopNative.Array(ALTRunMacDesktopNative.Class("NSArray"), Sel("arrayWithObjects:count:"), new[] { ALTRunMacDesktopNative.Class("NSURL") }, 1);
            nint urls = Two(pasteboard, Sel("readObjectsForClasses:options:"), classes, 0);
            long count = (long)Send(urls, "count");
            for (long index = 0; index < System.Math.Min(count, 1000); index++)
            {
                nint url = ALTRunMacDesktopNative.Arg(urls, Sel("objectAtIndex:"), (nint)index);
                if ((long)Send(url, "isFileURL") == 0) continue;
                string path = ALTRunMacDesktopNative.String(Send(url, "path"));
                if (path.Length > 0) paths.Add(path);
            }
            if (paths.Count == 0)
            {
                nint legacy = ALTRunMacDesktopNative.Arg(pasteboard, Sel("propertyListForType:"), ALTRunMacDesktopNative.Text("NSFilenamesPboardType"));
                if (legacy != 0 && (long)ALTRunMacDesktopNative.Arg(legacy, Sel("isKindOfClass:"), ALTRunMacDesktopNative.Class("NSArray")) != 0)
                    for (long index = 0; index < System.Math.Min((long)Send(legacy, "count"), 1000); index++)
                    {
                        string path = ALTRunMacDesktopNative.String(ALTRunMacDesktopNative.Arg(legacy, Sel("objectAtIndex:"), (nint)index));
                        if (path.StartsWith('/')) paths.Add(path);
                    }
            }
            string text = "";
            if (!add && paths.Count == 0)
            {
                nint value = ALTRunMacDesktopNative.Arg(pasteboard, Sel("stringForType:"), ALTRunMacDesktopNative.Text("public.utf8-plain-text"));
                text = ALTRunMacDesktopNative.String(value);
                if (text.Length > 1_000_000) text = text[..1_000_000];
            }
            if (paths.Count > 0 || text.Length > 0)
                Requests.Enqueue(System.Text.Json.JsonSerializer.Serialize(new { Add = add, Files = paths, Text = text }));
        }
        catch (System.Exception) { }
    }
}

public static object ALTRunMacServicesInstall()
{
    void Install()
    {
    if (ALTRunServicesNative.Provider != 0) return;
    nint cls = ALTRunServicesNative.objc_allocateClassPair(ALTRunMacDesktopNative.Class("NSObject"), "ALTRunServicesProvider", 0);
    if (cls == 0) return;
    ALTRunServicesNative.class_addMethod(cls, ALTRunMacDesktopNative.Sel("addToALTRun:userData:error:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(ALTRunServicesNative.Add), "v@:@@^@");
    ALTRunServicesNative.class_addMethod(cls, ALTRunMacDesktopNative.Sel("actionsInALTRun:userData:error:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(ALTRunServicesNative.Actions), "v@:@@^@");
    ALTRunServicesNative.objc_registerClassPair(cls);
    ALTRunServicesNative.Provider = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(cls, ALTRunMacDesktopNative.Sel("alloc")), ALTRunMacDesktopNative.Sel("init"));
    nint application = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSApplication"), ALTRunMacDesktopNative.Sel("sharedApplication"));
    ALTRunMacDesktopNative.Arg(application, ALTRunMacDesktopNative.Sel("setServicesProvider:"), ALTRunServicesNative.Provider);
    }
    Eto.Forms.Application.Instance.Invoke(Install);
    return null;
}
public static string ALTRunMacServiceNext() => ALTRunServicesNative.Requests.TryDequeue(out var request) ? request : "";

private static class ALTRunMacQuitBridge
{
    private static bool installed, stopping;
    private static int pending;
    private static readonly System.EventHandler<System.ComponentModel.CancelEventArgs> Handler = (_, args) => {
        if (stopping) { args.Cancel = false; return; }
        args.Cancel = true;
        System.Threading.Interlocked.Exchange(ref pending, 1);
    };
    internal static void Install()
    {
        if (installed) return;
        installed = true;
        stopping = false;
        Eto.Forms.Application.Instance.Terminating += Handler;
    }
    internal static bool Poll() => System.Threading.Interlocked.Exchange(ref pending, 0) != 0;
    internal static void Stop() { stopping = true; System.Threading.Interlocked.Exchange(ref pending, 0); }
}
public static object ALTRunMacInstallQuitBridge() { Eto.Forms.Application.Instance.Invoke(ALTRunMacQuitBridge.Install); return null; }
public static bool ALTRunMacQuitRequested() => ALTRunMacQuitBridge.Poll();
public static object ALTRunMacStopQuitBridge() { Eto.Forms.Application.Instance.Invoke(ALTRunMacQuitBridge.Stop); return null; }

private static class ALTRunDesktopObserver
{
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private delegate void Observer(nint self, nint selector, nint notification);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern void Observe(nint center, nint command, nint observer, nint selector, nint name, nint obj);
    private static readonly Observer Callback = (self, selector, notification) => System.Threading.Interlocked.Exchange(ref pending, 1);
    private static nint observer, defaultCenter, workspaceCenter;
    private static int pending;
    internal static void Start()
    {
        if (observer != 0) return;
        nint Sel(string name) => ALTRunMacDesktopNative.Sel(name);
        nint cls = ALTRunServicesNative.objc_allocateClassPair(ALTRunMacDesktopNative.Class("NSObject"), "ALTRunDesktopObserver", 0);
        if (cls == 0) cls = ALTRunMacDesktopNative.Class("ALTRunDesktopObserver");
        else
        {
            ALTRunServicesNative.class_addMethod(cls, Sel("desktopChanged:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(Callback), "v@:@");
            ALTRunServicesNative.objc_registerClassPair(cls);
        }
        observer = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(cls, Sel("alloc")), Sel("init"));
        defaultCenter = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSNotificationCenter"), Sel("defaultCenter"));
        nint workspace = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSWorkspace"), Sel("sharedWorkspace"));
        workspaceCenter = ALTRunMacDesktopNative.Send(workspace, Sel("notificationCenter"));
        Observe(defaultCenter, Sel("addObserver:selector:name:object:"), observer, Sel("desktopChanged:"), ALTRunMacDesktopNative.Text("NSApplicationDidChangeScreenParametersNotification"), 0);
        foreach (var name in new[] { "NSWorkspaceDidWakeNotification", "NSWorkspaceActiveSpaceDidChangeNotification", "NSWorkspaceSessionDidBecomeActiveNotification" })
            Observe(workspaceCenter, Sel("addObserver:selector:name:object:"), observer, Sel("desktopChanged:"), ALTRunMacDesktopNative.Text(name), 0);
    }
    internal static bool Poll() => System.Threading.Interlocked.Exchange(ref pending, 0) != 0;
    internal static void Stop()
    {
        if (observer == 0) return;
        ALTRunMacDesktopNative.Arg(defaultCenter, ALTRunMacDesktopNative.Sel("removeObserver:"), observer);
        ALTRunMacDesktopNative.Arg(workspaceCenter, ALTRunMacDesktopNative.Sel("removeObserver:"), observer);
        ALTRunMacDesktopNative.Send(observer, ALTRunMacDesktopNative.Sel("release"));
        observer = 0;
        System.Threading.Interlocked.Exchange(ref pending, 0);
    }
}
public static object ALTRunMacObserveDesktop() { Eto.Forms.Application.Instance.Invoke(ALTRunDesktopObserver.Start); return null; }
public static bool ALTRunMacDesktopChanged() => ALTRunDesktopObserver.Poll();
public static object ALTRunMacStopObserving() { Eto.Forms.Application.Instance.Invoke(ALTRunDesktopObserver.Stop); return null; }
#EndCSharp
#endif

class MacApp {
    static Init() {
#if OSX
        if Platform.IsMac && Platform.AppBundle != ""
            ALTRunMacServicesInstall()
        if Platform.IsMac
            MacUpdate.Init()
        if Platform.IsMac
            ALTRunMacObserveDesktop()
        ALTRunMacInstallQuitBridge()
#endif
    }

    static PollServices() {
#if OSX
        if !Platform.IsMac
            return
        if ALTRunMacQuitRequested() {
            App.Quit()
            return
        }
        if ALTRunMacDesktopChanged() {
            try {
            WindowProvider._listTime := 0
            MacDesktop.Refresh()
            MacSpotlight.Stop()
            MacSpotlight.Cache := Map()
            if SearchWindow.IsVisible() {
                area := SearchWindow._ScreenArea(AppSettings.Appearance["ShowOn"])
                SearchWindow._shownArea := area
                SearchWindow.Gui.GetPos(&x, &y, &width, &height)
                x := Max(area.Left, Min(x, area.Right - width))
                y := Max(area.Top, Min(y, area.Bottom - height))
                SearchWindow.Gui.Move(x, y)
                SearchWindow.RefreshResults()
            }
            } catch as error
                Logger.Debug("macOS desktop refresh: " error.Message)
        }
        while (text := ALTRunMacServiceNext()) != "" {
            request := JSON.Parse(text)
            if request["Add"]
                CustomCommandProvider.AddFromPaths(request["Files"])
            else if request["Files"].Length
                SearchWindow.ShowActions(SelectionActions.ItemFor({Files: request["Files"]}))
            else if request["Text"] != ""
                SearchWindow.ShowActions(SelectionActions.ItemFor({Text: request["Text"]}))
        }
#endif
    }

    static Stop() {
#if OSX
        if Platform.IsMac
            ALTRunMacStopObserving()
        ALTRunMacStopQuitBridge()
#endif
    }
}

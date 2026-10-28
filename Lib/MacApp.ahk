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
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private delegate void Observer(nint self, nint selector, nint notification);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] private static extern nint objc_allocateClassPair(nint superclass,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string name, nuint extraBytes);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] private static extern void objc_registerClassPair(nint value);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)]
    private static extern bool class_addMethod(nint cls, nint selector, nint implementation,
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string types);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    private static extern void Observe(nint center, nint command, nint observer, nint selector, nint name, nint obj);
    private static readonly Service Add = (self, command, pasteboard, data, error) => Receive(pasteboard, true);
    private static readonly Service Actions = (self, command, pasteboard, data, error) => Receive(pasteboard, false);
    private static readonly Observer Changed = (self, selector, notification) => System.Threading.Interlocked.Or(ref events, 2);
    private static readonly System.EventHandler<System.ComponentModel.CancelEventArgs> Quitting = (_, args) => {
        args.Cancel = !stopping;
        if (!stopping) System.Threading.Interlocked.Or(ref events, 1);
    };
    internal static readonly System.Collections.Concurrent.ConcurrentQueue<string> Requests = new();
    private static nint provider, defaultCenter, workspaceCenter;
    private static int events;
    private static bool installed, stopping;

    internal static void Start(bool services)
    {
        if (provider != 0) return;
        nint Sel(string name) => ALTRunMacDesktopNative.Sel(name);
        nint Send(nint target, string name) => ALTRunMacDesktopNative.Send(target, Sel(name));
        nint cls = objc_allocateClassPair(ALTRunMacDesktopNative.Class("NSObject"), "ALTRunServicesProvider", 0);
        if (cls == 0) cls = ALTRunMacDesktopNative.Class("ALTRunServicesProvider");
        else
        {
            class_addMethod(cls, Sel("addToALTRun:userData:error:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(Add), "v@:@@^@");
            class_addMethod(cls, Sel("actionsInALTRun:userData:error:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(Actions), "v@:@@^@");
            class_addMethod(cls, Sel("desktopChanged:"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(Changed), "v@:@");
            objc_registerClassPair(cls);
        }
        provider = Send(Send(cls, "alloc"), "init");
        if (services)
            ALTRunMacDesktopNative.Arg(Send(ALTRunMacDesktopNative.Class("NSApplication"), "sharedApplication"), Sel("setServicesProvider:"), provider);
        defaultCenter = Send(ALTRunMacDesktopNative.Class("NSNotificationCenter"), "defaultCenter");
        workspaceCenter = Send(Send(ALTRunMacDesktopNative.Class("NSWorkspace"), "sharedWorkspace"), "notificationCenter");
        Observe(defaultCenter, Sel("addObserver:selector:name:object:"), provider, Sel("desktopChanged:"), ALTRunMacDesktopNative.Text("NSApplicationDidChangeScreenParametersNotification"), 0);
        foreach (var name in new[] { "NSWorkspaceDidWakeNotification", "NSWorkspaceActiveSpaceDidChangeNotification", "NSWorkspaceSessionDidBecomeActiveNotification" })
            Observe(workspaceCenter, Sel("addObserver:selector:name:object:"), provider, Sel("desktopChanged:"), ALTRunMacDesktopNative.Text(name), 0);
        stopping = false;
        if (!installed) Eto.Forms.Application.Instance.Terminating += Quitting;
        installed = true;
    }

    internal static int Poll() => System.Threading.Interlocked.Exchange(ref events, 0);
    internal static void Stop()
    {
        stopping = true;
        if (provider == 0) return;
        ALTRunMacDesktopNative.Arg(defaultCenter, ALTRunMacDesktopNative.Sel("removeObserver:"), provider);
        ALTRunMacDesktopNative.Arg(workspaceCenter, ALTRunMacDesktopNative.Sel("removeObserver:"), provider);
        nint application = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSApplication"), ALTRunMacDesktopNative.Sel("sharedApplication"));
        ALTRunMacDesktopNative.Arg(application, ALTRunMacDesktopNative.Sel("setServicesProvider:"), 0);
        ALTRunMacDesktopNative.Send(provider, ALTRunMacDesktopNative.Sel("release"));
        provider = 0;
        System.Threading.Interlocked.Exchange(ref events, 0);
    }

    internal static void Receive(nint pasteboard, bool add)
    {
        try
        {
            nint Sel(string name) => ALTRunMacDesktopNative.Sel(name);
            nint Send(nint target, string name) => ALTRunMacDesktopNative.Send(target, Sel(name));
            var paths = new System.Collections.Generic.List<string>();
            nint classes = ALTRunMacDesktopNative.Array(ALTRunMacDesktopNative.Class("NSArray"), Sel("arrayWithObjects:count:"), new[] { ALTRunMacDesktopNative.Class("NSURL") }, 1);
            nint urls = ALTRunMacDesktopNative.Two(pasteboard, Sel("readObjectsForClasses:options:"), classes, 0);
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

public static object ALTRunMacAppStart(bool Services) { Eto.Forms.Application.Instance.Invoke(() => ALTRunServicesNative.Start(Services)); return null; }
public static object ALTRunMacAppStop() { Eto.Forms.Application.Instance.Invoke(ALTRunServicesNative.Stop); return null; }
public static int ALTRunMacAppEvents() => ALTRunServicesNative.Poll();
public static string ALTRunMacServiceNext() => ALTRunServicesNative.Requests.TryDequeue(out var request) ? request : "";
#EndCSharp
#endif

class MacApp {
    static Init() {
#if OSX
        ALTRunMacAppStart(Platform.AppBundle != "")
        MacUpdate.Init()
#endif
    }

    static PollServices() {
#if OSX
        events := ALTRunMacAppEvents()
        if (events & 1) {
            App.Quit()
            return
        }
        if (events & 2) {
            try {
                WindowProvider._listTime := 0
                MacDesktop.Refresh()
                MacSpotlight.Stop()
                MacSpotlight.Cache := Map()
                if SearchWindow.IsVisible() {
                    area := SearchWindow._ScreenArea(AppSettings.Appearance["ShowOn"])
                    SearchWindow._shownArea := area
                    SearchWindow.Gui.GetPos(&x, &y, &width, &height)
                    SearchWindow.Gui.Move(Max(area.Left, Min(x, area.Right - width)), Max(area.Top, Min(y, area.Bottom - height)))
                    SearchWindow.RefreshResults()
                }
            } catch as error
                Logger.Debug("macOS desktop refresh: " error.Message)
        }
        while (text := ALTRunMacServiceNext()) != "" {
            request := JSON.Parse(text)
            if request["Add"]
                CustomCommandProvider.AddFromPaths(request["Files"])
            else
                SearchWindow.ShowActions(SelectionActions.ItemFor(request["Files"].Length ? {Files: request["Files"]} : {Text: request["Text"]}))
        }
#endif
    }

    static Stop() {
#if OSX
        ALTRunMacAppStop()
#endif
    }
}

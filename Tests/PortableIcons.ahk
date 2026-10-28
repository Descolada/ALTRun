; PortableIcons - Density-aware bitmap and Windows shell icon decoding without opening windows.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PortableIcons.OnError(err, mode))
OnExit((*) => PortableIcons.CleanUp())
PortableIcons.Run()

class PortableIcons {
    static Folder := "", OriginalSize := 32, OriginalScale := 1, OriginalMax := 1500

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        Logger.Enabled := false
        PortableIcons.OriginalSize := IconCache.Size
        PortableIcons.OriginalScale := IconCache.Scale
        PortableIcons.OriginalMax := IconCache.MaxIcons
        PortableIcons.Folder := Platform.Join(A_Temp, "ALTRun-Icons-" Platform.NewUuid())
        DirCreate(PortableIcons.Folder)
        file := Platform.Join(PortableIcons.Folder, "fixture.png")
        fixture := Image.Create(96, 96, "0xFF2864B4")
        try fixture.Save(file)
        finally fixture.Dispose()
        IconCache.Clear()
        IconCache.Size := 32, IconCache.Scale := 1
        first := IconCache.Get(file)
        PortableIcons.Assert(IsObject(first) && first.Width = 32 && first.Height = 32, "The 1x source was not decoded at the requested pixel size.")
        PortableIcons.Assert(IconCache.Get("thumb:" file) = first, "A thumbnail source did not share its decoded file cache.")
        IconCache.Scale := 2
        second := IconCache.Get(file)
        PortableIcons.Assert(IsObject(second) && second.Width = 64 && second.Height = 64 && second != first, "The 2x display reused a low-resolution icon.")
        PortableIcons.Assert(IconCache._images.Count = 2, "Different display densities must retain separate cached images.")
        canvas := Image.Create(32, 32, , 2)
        try {
            canvas.DrawImage(second, 0, 0, 32, 32)
            IconCache.Clear()
            PortableIcons.Assert((canvas.GetPixel(16, 16) & 0xFFFFFF) = 0x2864B4, "Clearing the icon cache invalidated a pending canvas draw.")
        } finally canvas.Dispose()
        PortableIcons.Assert(IconCache.Get("\\ALTRun-unreachable.invalid\share\icon.png") = "", "A remote icon was allowed to probe the network.")
        PortableIcons.Assert(IconCache.Get("thumb:\\ALTRun-unreachable.invalid\share\icon.png") = "", "A remote thumbnail bypassed the network guard.")
        PortableIcons.Assert(IconCache.Get("res:\\ALTRun-unreachable.invalid\share\icons.dll,-1") = "", "A remote resource bypassed the network guard.")
#if LINUX
        appIcon := Platform.Join(Platform.FullPath("..", A_ScriptDir), "Resources", "ALTRun.ico")
        PortableIcons.Assert(ALTRunGtkIconMatchesFrames(appIcon), "GDK's tray/file-preview icon differs from its decoded ICO frame.")
#endif
#if WINDOWS
        PortableIcons.Windows()
#elif OSX
        PortableIcons.Mac()
#endif
        PortableIcons.Deferred(file)
        IconCache.Clear()
        IconCache.MaxIcons := 2
        for density in [1, 1.5, 2] {
            IconCache.Scale := density
            PortableIcons.Assert(IsObject(IconCache.Get(file)), "The cache did not reload a source after reaching its bound.")
            PortableIcons.Assert(IconCache._images.Count <= 2, "The icon cache exceeded its configured bound.")
        }
        FileAppend("PASS PORTABLE_ICONS native specifications, density, remote guards and bitmap ownership`n", "*")
        ExitApp(0)
    }

    static Deferred(file) {
        decode := IconCache.GetOwnPropDesc("_Decode").Call
        ready := IconCache.CanLoadVisible, queueReady := IconCache.CanQueueVisible, onLoaded := IconCache.OnLoaded
        originalTheme := ThemeManager.Current, originalScale := IconCache.Scale
        layout := Map()
        for name in ["Padding", "InputHeight", "ListTop", "IconSize", "FooterHeight"]
            layout[name] := SearchWindow.%name%
        state := {Decodes: 0, Changes: 0}
        IconCache.Clear()
        try {
            IconCache.DefineProp("_Decode", {Call: (self, spec, pixels) => (state.Decodes += 1, decode.Call(self, spec, pixels))})
            IconCache.CanLoadVisible := () => false
            IconCache.CanQueueVisible := () => true
            IconCache.OnLoaded := () => state.Changes += 1
            ThemeManager.Current := ThemeManager.Defaults()
            SearchWindow.Padding := 10, SearchWindow.InputHeight := 34, SearchWindow.ListTop := 64
            SearchWindow.IconSize := 32, SearchWindow.FooterHeight := 0
            item := ResultItem("Cold icon fixture", "Synthetic result", {Icon: file})
            row := {Index: 1, Item: item, X: 10, Y: 64, Width: 620, Height: 48, Title: item.Title, Subtitle: item.Subtitle
                , Shortcut: "Ctrl+1", Background: "DDE7F6", Selected: true}
            rendered := LauncherCanvas.Render(640, 124, 1, [row])
            try PortableIcons.Assert(state.Decodes = 0 && IconCache._visible.Length = 1, "Rendering synchronously decoded a cold icon.")
            finally rendered.Dispose()
            IconCache._LoadVisible()
            PortableIcons.Assert(state.Decodes = 0, "Visible icon decoding interrupted a busy input field.")
            IconCache.BeginFrame()
            IconCache.Peek("thumb:" file), IconCache.Peek(file)
            PortableIcons.Assert(IconCache._visible.Length = 1, "Visible icon requests were not deduplicated for the current frame.")
            secondFile := Platform.Join(PortableIcons.Folder, "second.png")
            FileCopy(file, secondFile, true)
            IconCache.Peek(secondFile)
            IconCache.CanLoadVisible := () => true
            IconCache._LoadVisible()
            PortableIcons.Assert(state.Decodes = 1 && state.Changes = 1 && IsObject(IconCache.Peek(file))
                , "A deferred icon did not populate the cache and request a repaint.")
            PortableIcons.Assert(IconCache._visible.Length = 1, "One timer tick decoded more than one queued icon.")
            IconCache.Peek(file)
            PortableIcons.Assert(state.Decodes = 1, "A warm paint decoded its icon again.")
            IconCache._LoadVisible()
            PortableIcons.Assert(state.Decodes = 2 && !IconCache._visible.Length, "The remaining deferred icon was not decoded on the next tick.")
            IconCache.Clear()
            IconCache.Scale := 1
            IconCache.Peek(file)
            IconCache.Scale := 2
            IconCache._LoadVisible()
            PortableIcons.Assert(state.Decodes = 2 && !IconCache._images.Count, "An old-density request was decoded for a different display.")
            IconCache.Peek(file), IconCache._LoadVisible()
            PortableIcons.Assert(IconCache.Peek(file).Width = IconCache.Size * 2, "The deferred icon used the old display density.")
            IconCache.Clear()
            IconCache.DefineProp("_Decode", {Call: (self, spec, pixels) => (state.Decodes += 1, "")})
            IconCache.Peek(file), IconCache._LoadVisible()
            IconCache.BeginFrame()
            IconCache.Peek(file)
            PortableIcons.Assert(state.Decodes = 4 && !IconCache._visible.Length, "A failed icon was repeatedly decoded while painting.")
            IconCache.Clear()
            IconCache.CanQueueVisible := () => false
            IconCache.Peek(file)
            PortableIcons.Assert(!IconCache._visible.Length, "Preparing a hidden frame queued recurring icon work.")
            FileAppend("PASS PORTABLE_ICONS deferred render misses, busy-input gate, one load per tick, clear, density and failed-icon backoff`n", "*")
        } finally {
            IconCache.DefineProp("_Decode", {Call: decode})
            IconCache.CanLoadVisible := ready, IconCache.CanQueueVisible := queueReady, IconCache.OnLoaded := onLoaded
            ThemeManager.Current := originalTheme, IconCache.Scale := originalScale
            for name, value in layout
                SearchWindow.%name% := value
            IconCache.Clear()
        }
    }

#if WINDOWS
    static Windows() {
        executable := Platform.Join(A_WinDir, "explorer.exe")
        shortcut := Platform.Join(PortableIcons.Folder, "explorer.lnk")
        FileCreateShortcut(executable, shortcut)
        for spec in [executable, shortcut, "res:shell32.dll,-32", "res:shell32.dll,0", "ext:.txt", "folder:", "url:"
            , "shell:AppsFolder", PortableIcons.Folder] {
            decoded := IconCache.Get(spec)
            PortableIcons.Assert(IsObject(decoded) && decoded.Width = 64 && decoded.Height = 64, "Windows icon specification failed: " spec)
            PortableIcons.Assert(IconCache._sources[IconCache._Key(spec, 64)] == spec, "The icon source was replaced by a generic ALTRun bitmap: " spec)
        }
        PortableIcons.Assert(IconCache.Get(shortcut) = IconCache.Get(shortcut), "A shortcut icon was decoded again instead of cached.")
    }
#endif

#if OSX
    static Mac() {
        note := Platform.Join(PortableIcons.Folder, "note.txt")
        FileAppend("Synthetic native icon fixture.", note)
        for spec in ["/System/Applications/Utilities/Terminal.app", note, PortableIcons.Folder, "ext:.txt", "folder:", "url:"
            , "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"] {
            decoded := IconCache.Get(spec)
            PortableIcons.Assert(IsObject(decoded) && decoded.Width = 64 && decoded.Height = 64, "macOS native icon failed: " spec)
            PortableIcons.Assert(IconCache._sources[IconCache._Key(spec, 64)] == spec, "The native icon lost its source specification: " spec)
            PortableIcons.Assert(IconCache.Get(spec) = decoded, "A native icon was decoded again instead of cached.")
        }
        FileAppend("PASS PORTABLE_ICONS macOS application, document, folder and type icons`n", "*")
    }
#endif

    static CleanUp() {
        IconCache.Clear()
        IconCache.Size := PortableIcons.OriginalSize
        IconCache.Scale := PortableIcons.OriginalScale
        IconCache.MaxIcons := PortableIcons.OriginalMax
        if (PortableIcons.Folder = "")
            return
        fixtureFolder := Platform.FullPath(PortableIcons.Folder)
        allowedPrefix := Platform.FullPath(Platform.Join(A_Temp, "ALTRun-Icons-"))
        if (InStr(Platform.Identity(fixtureFolder), Platform.Identity(allowedPrefix), true) = 1 && DirExist(fixtureFolder))
            DirDelete(fixtureFolder, true)
    }

    static OnError(err, mode) {
        FileAppend("FAIL PORTABLE_ICONS " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }
}

#if LINUX
#CSharp
public static bool ALTRunGtkIconMatchesFrames(string path)
{
    using var icon = new Eto.Drawing.Icon(path);
    // The tray and file manager use GDK's primary image, whereas the launcher
    // decodes individual frames. Both must produce the same original pixels.
    var actual = icon.Handler.GetType().GetProperty("Pixbuf").GetValue(icon.Handler);
    int width = (int)actual.GetType().GetProperty("Width").GetValue(actual);
    int height = (int)actual.GetType().GetProperty("Height").GetValue(actual);
    Eto.Drawing.IconFrame matching = null;
    foreach (var frame in icon.Frames)
        if (frame.PixelSize.Width == width && frame.PixelSize.Height == height)
            matching = frame;
    if (matching == null) return false;
    var expected = matching.Bitmap.Handler.GetType().GetProperty("Pixbuf").GetValue(matching.Bitmap.Handler);
    var type = actual.GetType();
    int channels = (int)type.GetProperty("NChannels").GetValue(actual);
    if (channels != (int)type.GetProperty("NChannels").GetValue(expected)) return false;
    int actualStride = (int)type.GetProperty("Rowstride").GetValue(actual);
    int expectedStride = (int)type.GetProperty("Rowstride").GetValue(expected);
    var actualPixels = (System.IntPtr)type.GetProperty("Pixels").GetValue(actual);
    var expectedPixels = (System.IntPtr)type.GetProperty("Pixels").GetValue(expected);
    for (int y = 0; y < height; y++)
        for (int x = 0; x < width * channels; x++)
            if (System.Runtime.InteropServices.Marshal.ReadByte(actualPixels, y * actualStride + x)
                != System.Runtime.InteropServices.Marshal.ReadByte(expectedPixels, y * expectedStride + x))
                return false;
    return true;
}
#EndCSharp
#endif

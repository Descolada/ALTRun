; IconCache.ahk - Decoded result images, including Windows shell icons, at the display's pixel density.
#Import Ks { Image }

class IconCache {
    static Size := 32, Scale := 1, OnLoaded := "", MaxIcons := 1500
    static _images := IconCache._FileMap(), _sources := IconCache._FileMap()
    static PrefetchMax := 300, PrefetchGapMs := 30, _prefetch := [], _prefetchTimer := "", _prefetchBusy := false
    static CanLoadVisible := "", CanQueueVisible := ""
    static _visible := [], _visibleKeys := IconCache._FileMap(), _visibleTimer := "", _visibleBusy := false
    static _failed := IconCache._FileMap()

    static _FileMap() {
        files := Map()
        files.CaseSense := "On"
        return files
    }

    static Own(name, fallback := "") {
        SplitPath(App.IconFile, , &resources)
        file := Platform.Join(resources, "Icons", name ".ico")
        return FileExist(file) ? file : Platform.IsWindows && fallback != "" ? fallback : App.IconFile
    }

    static File(spec) {
        if (spec = "" || IconCache.IsRemote(spec))
            return ""
        if (SubStr(spec, 1, 6) = "thumb:")
            spec := SubStr(spec, 7)
        if (Platform.IsWindows && RegExMatch(spec, "i)^(res:|ext:|url:|folder:|shell:|::\{)"))
            return spec
        if (Platform.IsMac && RegExMatch(spec, "i)^(ext:|url:|folder:)"))
            return spec
        if FileExist(spec) {
            SplitPath(spec, , , &ext)
            if (Platform.IsWindows || Platform.IsMac || RegExMatch(ext, "i)^(ico|png|jpg|jpeg|gif|bmp|tif|tiff|svg|webp)$"))
                return spec
        }
        return ""
    }

    static Get(spec) {
        ; Cached images need no filesystem or shell lookup during typing and mouse navigation.
        normalized := IconCache._Normalize(spec), pixels := IconCache._Pixels(), key := IconCache._Key(normalized, pixels)
        if IconCache._images.Has(key)
            return IconCache._images[key]
        file := IconCache.File(spec)
        if (file = "")
            return ""
        key := IconCache._Key(file, pixels)
        if !IconCache._images.Has(key) {
            if (IconCache._images.Count >= IconCache.MaxIcons)
                IconCache.Clear()
            try decoded := IconCache._Decode(file, pixels)
            catch
                return ""
            if !IsObject(decoded)
                return ""
            IconCache._images[key] := decoded
            IconCache._sources[key] := file
        }
        return IconCache._images[key]
    }

    static _Normalize(spec) => SubStr(spec, 1, 6) = "thumb:" ? SubStr(spec, 7) : spec

    ; A paint must never invoke an image decoder or a native shell service.
    static Peek(spec) {
        spec := IconCache._Normalize(spec)
        if (spec = "")
            return ""
        key := IconCache._Key(spec, IconCache._Pixels())
        if IconCache._images.Has(key)
            return IconCache._images[key]
        if (IsObject(IconCache.CanQueueVisible) && !IconCache.CanQueueVisible.Call())
            return ""
        if (IconCache._failed.Has(key) && A_TickCount - IconCache._failed[key] < 30000)
            return ""
        if (!IconCache._visibleKeys.Has(key) && IconCache._visible.Length < IconCache.PrefetchMax) {
            IconCache._visibleKeys[key] := true
            IconCache._visible.Push({Spec: spec, Key: key})
            if (IconCache._visibleTimer = "")
                IconCache._visibleTimer := Logger.Watch("visible icon load", () => IconCache._LoadVisible())
            SetTimer(IconCache._visibleTimer, IconCache.PrefetchGapMs)
        }
        return ""
    }

    static BeginFrame() {
        ; Drop misses from the previous query before queuing the currently visible rows.
        IconCache._visible := [], IconCache._visibleKeys.Clear()
        if (IconCache._visibleTimer != "")
            SetTimer(IconCache._visibleTimer, 0)
    }

    static _LoadVisible() {
        if (IconCache._visibleBusy || !IconCache._visible.Length
            || (IsObject(IconCache.CanLoadVisible) && !IconCache.CanLoadVisible.Call()))
            return
        IconCache._visibleBusy := true
        try {
            request := IconCache._visible.RemoveAt(1)
            if (request.Key != IconCache._Key(request.Spec, IconCache._Pixels()))
                return
            loaded := IconCache.Get(request.Spec)
            if !IsObject(loaded) {
                if (IconCache._failed.Count >= IconCache.MaxIcons)
                    IconCache._failed.Clear()
                IconCache._failed[request.Key] := A_TickCount
            }
            if (IsObject(loaded) && IsObject(IconCache.OnLoaded))
                IconCache.OnLoaded.Call()
        } finally {
            if (!IconCache._visible.Length && IconCache._visibleTimer != "")
                SetTimer(IconCache._visibleTimer, 0)
            IconCache._visibleBusy := false
        }
    }

    static _Pixels() => Max(1, Round(IconCache.Size * IconCache.Scale))
    static _Key(spec, pixels) => pixels "|" Platform.Identity(spec)

    static _Decode(spec, pixels) {
#if WINDOWS
        if (SubStr(spec, 1, 4) = "res:") {
            resource := SubStr(spec, 5), index := 0
            if RegExMatch(resource, "^(.*),\s*(-?\d+)\s*$", &match)
                resource := Trim(match[1]), index := Integer(match[2])
            resource := Path.Resolve(resource)
            if IconCache.IsRemote(resource)
                return ""
            return Image.FromFile(resource, pixels, pixels, index >= 0 ? index + 1 : index)
        }
        if RegExMatch(spec, "i)^(ext:|url:|folder:|shell:|::\{)")
            return IconCache._ShellImage(spec, pixels)
        SplitPath(spec, , , &extension)
        if !RegExMatch(extension, "i)^(ico|png|jpg|jpeg|gif|bmp|tif|tiff|svg|webp|exe|dll|icl|cpl|scr)$")
            return IconCache._ShellImage(spec, pixels)
#endif
#if OSX
        SplitPath(spec, , , &extension)
        if !RegExMatch(extension, "i)^(ico|icns|png|jpg|jpeg|gif|bmp|tif|tiff|svg|webp)$")
            return ALTRunMacFileIcon(spec, pixels)
#endif
        return Image.FromFile(spec, pixels, pixels)
    }

#if WINDOWS
    static _ShellImage(spec, pixels) {
        attributes := 0, flags := 0x4000, pidl := 0
        switch {
            case SubStr(spec, 1, 4) = "ext:": target := SubStr(spec, 5), attributes := 0x80, flags |= 0x10
            case spec = "url:": target := ".html", attributes := 0x80, flags |= 0x10
            case spec = "folder:": target := "folder", attributes := 0x10, flags |= 0x10
            default: target := spec
        }
        if RegExMatch(target, "i)^(shell:|::\{)") {
            if DllCall("shell32\SHParseDisplayName", "WStr", target, "Ptr", 0, "Ptr*", &pidl, "UInt", 0, "Ptr", 0, "Int") != 0
                return ""
            flags |= 0x8
        }
        info := Buffer(A_PtrSize + 688, 0)
        try {
            if pidl
                found := DllCall("shell32\SHGetFileInfoW", "Ptr", pidl, "UInt", attributes, "Ptr", info, "UInt", info.Size, "UInt", flags, "UPtr")
            else
                found := DllCall("shell32\SHGetFileInfoW", "WStr", target, "UInt", attributes, "Ptr", info, "UInt", info.Size, "UInt", flags, "UPtr")
        } finally {
            if pidl
                DllCall("ole32\CoTaskMemFree", "Ptr", pidl)
        }
        if !found
            return ""
        icon := IconCache._SystemIcon(NumGet(info, A_PtrSize, "Int"), pixels)
        if !icon
            return ""
        ; The decoder copies a borrowed icon; ALTRun releases the shell's owned handle even on failure.
        try return Image.FromFile("HICON:*" icon, pixels, pixels)
        finally DllCall("DestroyIcon", "Ptr", icon)
    }

    static _SystemIcon(index, pixels) {
        iid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{46EB5926-582E-4017-9FDF-E8998DAA0950}", "Ptr", iid)
        for listType in [1, 0, 2, 4] {
            list := 0, width := 0, height := 0
            if DllCall("shell32\SHGetImageList", "Int", listType, "Ptr", iid, "Ptr*", &list, "Int") != 0 || !list
                continue
            try {
                DllCall("comctl32\ImageList_GetIconSize", "Ptr", list, "Int*", &width, "Int*", &height)
                if (width >= pixels || listType = 4)
                    return DllCall("comctl32\ImageList_GetIcon", "Ptr", list, "Int", index, "UInt", 1, "Ptr")
            } finally ObjRelease(list)
        }
        return 0
    }
#endif

    static GetNow(spec) {
        return IconCache.Get(spec)
    }

    static Clear() {
        if (IconCache._prefetchTimer != "")
            SetTimer(IconCache._prefetchTimer, 0)
        IconCache._prefetch := []
        IconCache.BeginFrame()
        IconCache._failed.Clear()
        for file, img in IconCache._images
            img.Dispose()
        IconCache._images.Clear()
        IconCache._sources.Clear()
    }

    static Prefetch(specs) {
        pending := [], seen := IconCache._FileMap()
        for spec in specs {
            if (spec = "" || IconCache.IsRemote(spec) || pending.Length >= IconCache.PrefetchMax)
                continue
            file := IconCache.File(spec), key := IconCache._Key(file, IconCache._Pixels())
            if (file = "" || seen.Has(key) || IconCache._images.Has(key))
                continue
            seen[key] := true
            pending.Push(file)
        }
        if (IconCache._prefetchTimer = "")
            IconCache._prefetchTimer := Logger.Watch("portable icon prefetch", () => IconCache._PrefetchStep())
        previousCritical := A_IsCritical
        Critical("On")
        try {
            IconCache._prefetch := pending
            SetTimer(IconCache._prefetchTimer, pending.Length ? IconCache.PrefetchGapMs : 0)
        } finally Critical(previousCritical)
    }

    static PrefetchPending => IconCache._prefetch.Length

    static _PrefetchStep() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if (IconCache._prefetchBusy || !IconCache._prefetch.Length)
                return
            IconCache._prefetchBusy := true
        } finally Critical(previousCritical)
        try {
            if !BackgroundWork.CanRun()
                return
            started := A_TickCount
            while ((spec := IconCache._TakePrefetch()) != "") {
                IconCache.Get(spec)
                if A_TickCount - started >= 10
                    break
            }
        } finally {
            previousCritical := A_IsCritical
            Critical("On")
            try {
                if !IconCache._prefetch.Length
                    SetTimer(IconCache._prefetchTimer, 0)
                IconCache._prefetchBusy := false
            } finally Critical(previousCritical)
        }
    }

    static _TakePrefetch() {
        ; Dequeue atomically; image decoding stays interruptible so typing can continue.
        previousCritical := A_IsCritical
        Critical("On")
        try return IconCache._prefetch.Length ? IconCache._prefetch.RemoveAt(1) : ""
        finally Critical(previousCritical)
    }

    ; Remember source specifications to warm the decoder on the next launch.
    static DiskFile() => Platform.Join(AppSettings.DataDir, "IconCache", "Icons-" IconCache.Size ".json")

    static LoadDisk(file := "") {
        file := file = "" ? IconCache.DiskFile() : file
        if !FileExist(file)
            return 0
        try {
            data := JSON.Parse(FileRead(file, "UTF-8"))
            if (!(data is Map) || data.Get("Size", 0) != IconCache.Size || !(data.Get("Files", "") is Array))
                return 0
            IconCache.Prefetch(data["Files"])
            return IconCache.PrefetchPending
        } catch as e {
            Logger.Debug("IconCache: portable cache ignored - " e.Message)
            return 0
        }
    }

    static SaveDisk(file := "") {
        file := file = "" ? IconCache.DiskFile() : file
        if !IconCache._sources.Count
            return false
        try {
            files := [], seen := IconCache._FileMap()
            for key, source in IconCache._sources
                if (files.Length < IconCache.PrefetchMax && !seen.Has(source) && IconCache.File(source) != "")
                    files.Push(source), seen[source] := true
            SplitPath(file, , &folder)
            DirCreate(folder)
            JSON.WriteFile(file, Map("Size", IconCache.Size, "Files", files))
            return true
        } catch as e {
            Logger.Debug("IconCache: portable cache could not be saved - " e.Message)
            return false
        }
    }

    static FolderIcon(folder, probeNow := false) {
        return "folder:"
    }

    static IsRemote(target) {
        if (SubStr(target, 1, 6) = "thumb:")
            target := SubStr(target, 7)
        if (SubStr(target, 1, 4) = "res:")
            target := SubStr(target, 5)
        return RegExMatch(target, "i)^(\\\\|//|smb:|nfs:)") != 0 || Path.IsRemote(target)
    }

}

#if OSX
#CSharp
public static object ALTRunMacFileIcon(string specification, long pixels)
{
    string kind = specification.ToLowerInvariant();
    bool type = kind is "folder:" or "url:" || kind.StartsWith("ext:", System.StringComparison.Ordinal);
    string value = kind == "folder:" ? "public.folder" : kind == "url:" ? "public.url"
        : type ? specification[4..].TrimStart('.') : System.IO.Path.GetFullPath(specification);
    var workspace = ALTRunMacObjC.Send(ALTRunMacObjC.Class("NSWorkspace"), ALTRunMacObjC.Selector("sharedWorkspace"));
    var icon = ALTRunMacObjC.SendArgument(workspace, ALTRunMacObjC.Selector(type ? "iconForFileType:" : "iconForFile:"), ALTRunMacObjC.String(value));
    if (icon == System.IntPtr.Zero) return "";
    // Draw the native icon directly at the requested size. TIFFRepresentation expands every
    // representation (including 1024px frames) and can stall a search for seconds.
    var copied = ALTRunMacObjC.Send(icon, ALTRunMacObjC.Selector("copy"));
    var runtime = System.Type.GetType("MonoMac.ObjCRuntime.Runtime, MonoMac", true);
    var wrap = System.Array.Find(runtime.GetMethods(), method => method.Name == "GetNSObject"
        && !method.IsGenericMethod && method.GetParameters().Length == 2);
    var native = wrap.Invoke(null, [copied, true]);
    var handlerType = System.Type.GetType("Eto.Mac.Drawing.BitmapHandler, Eto.Mac64", true);
    var handler = (Eto.Drawing.Bitmap.IHandler)System.Activator.CreateInstance(handlerType, native);
    using var bitmap = new Eto.Drawing.Bitmap(handler);
    using var sized = new Eto.Drawing.Bitmap(bitmap, (int)pixels, (int)pixels);
    return Keysharp.Builtins.Ks.KeysharpImage.FromBitmap(null, sized);
}
#EndCSharp
#endif

; IconCache.ahk - Portable result images use bundled icons and ordinary image files.
#Import Ks { Image }

class IconCache {
    static Size := 32, OnLoaded := "", MaxIcons := 1500
    static _images := IconCache._FileMap(), _sources := IconCache._FileMap(), _indices := IconCache._FileMap()
    static PrefetchMax := 300, PrefetchGapMs := 30, _prefetch := [], _prefetchTimer := "", _prefetchBusy := false

    static _FileMap() {
        files := Map()
        files.CaseSense := "On"
        return files
    }

    static Own(name, fallback := "") {
        SplitPath(App.IconFile, , &resources)
        file := Platform.Join(resources, "Icons", name ".ico")
        return FileExist(file) ? file : App.IconFile
    }

    static File(spec) {
        if (spec = "")
            return ""
        if (SubStr(spec, 1, 6) = "thumb:")
            spec := SubStr(spec, 7)
        if FileExist(spec) {
            SplitPath(spec, , , &ext)
            if RegExMatch(ext, "i)^(ico|png|jpg|jpeg|gif|bmp|tif|tiff)$")
                return spec
        }
        return App.IconFile
    }

    static Get(spec) {
        file := IconCache.File(spec)
        if (file = "" || !FileExist(file))
            return ""
        key := Platform.Identity(file)
        if !IconCache._images.Has(key) {
            if (IconCache._images.Count >= IconCache.MaxIcons)
                IconCache.Clear()
            try IconCache._images[key] := Image.FromFile(file, IconCache.Size, IconCache.Size)
            catch
                return ""
            IconCache._sources[key] := file
        }
        return IconCache._images[key]
    }

    static GetNow(spec) {
        return IconCache.Get(spec)
    }

    static AddTo(imageList, spec) {
        file := IconCache.File(spec)
        if (file = "" || !FileExist(file))
            return 0
        key := imageList "|" Platform.Identity(file)
        if !IconCache._indices.Has(key) {
            image := IconCache.Get(file)
            if !IsObject(image)
                return 0
            ; IL_Add consumes this bitmap copy; the decoded image stays cached for other lists.
            try IconCache._indices[key] := IL_Add(imageList, "HBITMAP:" image.ToBitmap(), 0xFF00FF, true)
            catch
                return 0
        }
        return IconCache._indices[key]
    }

    static Clear() {
        if (IconCache._prefetchTimer != "")
            SetTimer(IconCache._prefetchTimer, 0)
        IconCache._prefetch := []
        for file, img in IconCache._images
            img.Dispose()
        IconCache._images.Clear()
        IconCache._sources.Clear()
        IconCache._indices.Clear()
    }

    static Prefetch(specs) {
        pending := [], seen := IconCache._FileMap()
        for spec in specs {
            if (spec = "" || IconCache.IsRemote(spec) || pending.Length >= IconCache.PrefetchMax)
                continue
            file := IconCache.File(spec), key := Platform.Identity(file)
            if (file = "" || !FileExist(file) || seen.Has(key) || IconCache._images.Has(key))
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

    ; Portable icons already live in image files; keep their paths to warm the decoder on the next launch.
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
            files := []
            for key, source in IconCache._sources
                if (files.Length < IconCache.PrefetchMax && FileExist(source))
                    files.Push(source)
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
        return RegExMatch(target, "^(\\\\|//|smb:|nfs:)") != 0
    }

    static _Extension(target) {
        SplitPath(RTrim(target, "\/"), , , &ext)
        return (RegExMatch(ext, "^(?=.*[A-Za-z])[A-Za-z0-9]{1,6}$") || ext = "appref-ms") ? ext : ""
    }
}

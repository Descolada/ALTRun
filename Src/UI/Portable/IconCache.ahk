; IconCache.ahk - Portable result images use bundled icons and ordinary image files.
#Import Ks { Image }

class IconCache {
    static Size := 32, OnLoaded := "", MaxIcons := 1500
    static _images := Map(), _indices := Map()

    static Own(name, fallback := "") {
        file := Platform.Join(A_ScriptDir, "Resources", "Icons", name ".ico")
        return FileExist(file) ? file : Platform.Join(A_ScriptDir, "Resources", "ALTRun.ico")
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
        return Platform.Join(A_ScriptDir, "Resources", "ALTRun.ico")
    }

    static Get(spec) {
        file := IconCache.File(spec)
        if (file = "" || !FileExist(file))
            return ""
        if !IconCache._images.Has(file) {
            if (IconCache._images.Count >= IconCache.MaxIcons)
                IconCache.Clear()
            try IconCache._images[file] := Image.FromFile(file, IconCache.Size, IconCache.Size)
            catch
                return ""
        }
        return IconCache._images[file]
    }

    static GetNow(spec) {
        return IconCache.Get(spec)
    }

    static AddTo(imageList, spec) {
        file := IconCache.File(spec)
        if (file = "" || !FileExist(file))
            return 0
        key := imageList "|" file
        if !IconCache._indices.Has(key) {
            try IconCache._indices[key] := IL_Add(imageList, file)
            catch
                return 0
        }
        return IconCache._indices[key]
    }

    static Clear() {
        for file, img in IconCache._images
            img.Dispose()
        IconCache._images.Clear()
        IconCache._indices.Clear()
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

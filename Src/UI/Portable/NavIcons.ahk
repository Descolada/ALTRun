; NavIcons.ahk - Portable preferences use bundled images instead of system icon fonts.
class NavIcons {
    static ImageList(keys) {
        imageList := IL_Create(keys.Length, keys.Length)
        for key in keys
            IL_Add(imageList, IconCache.Own("Help"))
        return imageList
    }

    static FontName() {
        return ThemeManager.FontName()
    }
}

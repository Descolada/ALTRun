; ThemePreview.ahk - Portable theme previews are rendered through Keysharp Image.
class ThemePreview {
    static Bitmap(theme, width, height) {
        img := Image.Create(width, height, "0xFF" theme["Background"])
        pad := Max(3, Round(width * 0.06))
        img.FillRoundRect(pad, pad, width - 2 * pad, height * 0.25, 3, "0xFF" theme["InputText"])
        rowTop := Round(height * 0.4), rowHeight := Round(height * 0.2)
        img.FillRoundRect(pad, rowTop, width - 2 * pad, rowHeight, 3, "0xFF" theme["SelectedBackground"])
        for index in [0, 1] {
            top := rowTop + index * (rowHeight + 4)
            img.FillRect(pad + 5, top + 5, width * 0.5, 3, "0xFF" theme[index ? "Title" : "SelectedTitle"])
            img.FillRect(pad + 5, top + 12, width * 0.35, 2, "0xFF" theme[index ? "Subtitle" : "SelectedSubtitle"])
        }
        return img
    }

    static ForName(name, width, height) {
        theme := ThemeManager.Resolve(name = "System" ? "Light" : name)
        return ThemePreview.Bitmap(IsObject(theme) ? theme : ThemeManager.Defaults(), width, height)
    }

    static ImageList(names, width, height) {
        imageList := IL_Create(names.Length, names.Length, true)
        for name in names
            ThemePreview.AddTo(imageList, name, width, height)
        return imageList
    }

    static AddTo(imageList, name, width, height) {
        preview := ThemePreview.ForName(name, width, height)
        filename := Platform.Join(A_Temp, "ALTRun-ThemePreview-" Platform.NewUuid() ".png")
        try {
            preview.Save(filename)
            return IL_Add(imageList, filename, 0xFFFFFF, true) - 1
        } finally {
            preview.Dispose()
            if FileExist(filename)
                FileDelete(filename)
        }
    }
}

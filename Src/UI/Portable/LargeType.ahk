; LargeType.ahk - Portable large text window closed by a key or click.

class LargeType {
    static Gui := ""
    static _handlersReady := false

    static Show(text) {
        LargeType.Close()
        if (Trim(text) = "")
            return
        LargeType._EnsureHandlers()

        area := Win.WorkAreaAtMouse()
        areaW := area.Right - area.Left, areaH := area.Bottom - area.Top
        len := StrLen(text)
        fontSize := (len <= 12) ? 96 : (len <= 30) ? 64 : (len <= 80) ? 40 : (len <= 300) ? 28 : 18
        pad := Win.Scale(40)

        g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale", "ALTRun Large Type")
        g.BackColor := "141414"
        g.MarginX := pad, g.MarginY := pad
        g.SetFont("s" fontSize " cFFFFFF", ThemeManager.FontName())
        maxW := Round(areaW * 0.85) - 2 * pad
        label := g.AddText("Center", text)
        label.GetPos(, , &textW)
        if (textW > maxW) {                                                 ; 太宽就按最大宽度自动换行 (控件不能单独删除, 先藏起来)
            label.Visible := false
            label := g.AddText("xm ym Center w" maxW, text)
        }
        label.OnEvent("Click", (*) => LargeType.Close())
        g.OnEvent("Escape", (*) => LargeType.Close())
        g.OnEvent("Close", (*) => (LargeType.Close(), true))
        g.Show("Hide AutoSize")
        g.GetPos(, , &winW, &winH)
        winH := Min(winH, areaH)
        g.Show("x" (area.Left + (areaW - winW) // 2) " y" (area.Top + (areaH - winH) // 2) " h" winH)


        LargeType.Gui := g
    }

    static Close() {
        if IsObject(LargeType.Gui) {
            try LargeType.Gui.Destroy()
            LargeType.Gui := ""
        }
    }

    static _EnsureHandlers() {
        if LargeType._handlersReady
            return
        LargeType._handlersReady := true
        OnMessage(0x100, (p*) => LargeType._OnKey(p*))                      ; WM_KEYDOWN
        OnMessage(0x104, (p*) => LargeType._OnKey(p*))                      ; WM_SYSKEYDOWN
    }

    static _IsOwn(hwnd) {
        if !IsObject(LargeType.Gui)
            return false
        if (hwnd = LargeType.Gui.Hwnd)
            return true
        for control in LargeType.Gui
            if (control.Hwnd = hwnd)
                return true
        return false
    }

    static _OnKey(wParam, lParam, msg, hwnd) {
        if !LargeType._IsOwn(hwnd)
            return
        LargeType.Close()
        return 0
    }

}

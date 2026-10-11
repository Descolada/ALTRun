; Hud.ahk - Portable timed notification window; Show and Hide preserve the app contract.

class Hud {
    static Gui := ""
    static MaxWidth := 520                  ; 超过这个宽度 (96 DPI 下的像素) 自动换行
    static Alpha := 240
    static _alpha := 0
    static _timer := ""
    static _fadingOut := false

    static Show(text, duration := 1500) {
        Hud.Hide()
        if (Trim(text) = "")
            return
        g := Gui("+AlwaysOnTop +ToolWindow -Caption", App.Name)
        g.SetFont("s11", ThemeManager.FontName())
        g.MarginX := 20, g.MarginY := 12
        label := g.AddText("Center w" Hud.MaxWidth, text)
        label.OnEvent("Click", (*) => Hud.Hide())
        g.Show("Hide AutoSize")
        g.GetPos(, , &width, &height)
        pos := Hud.Position(width, height, Hud._Anchor())
        Hud.Gui := g
        g.Show("NA x" pos.X " y" pos.Y)
        SetTimer(() => Hud._Expire(g), -Max(duration, 300))
    }

    static _Expire(g) {
        if (Hud.Gui = g)
            Hud.Hide()
    }

    static Hide() {
        if IsObject(Hud._timer)
            SetTimer(Hud._timer, 0)
        Hud._timer := ""
        if IsObject(Hud.Gui) {
            try Hud.Gui.Destroy()
            Hud.Gui := ""
        }
    }

    static Position(w, h, anchor) {
        area := anchor.Area, gap := Win.Scale(12)
        if IsObject(anchor.Window) {
            box := anchor.Window
            x := box.X + (box.W - w) // 2
            y := box.Y + box.H + gap
            if (y + h > area.Bottom)
                y := box.Y - gap - h
        } else {
            x := area.Left + (area.Right - area.Left - w) // 2
            y := area.Top + Round((area.Bottom - area.Top) * 2 / 3) - h // 2
        }
        x := Max(area.Left, Min(x, area.Right - w))
        y := Max(area.Top, Min(y, area.Bottom - h))
        return {X: x, Y: y}
    }

    static RecentWindowMs := 3000

    static _Anchor() {
        if SearchWindow.IsVisible() {
            try {
                SearchWindow.Gui.GetPos(&x, &y, &w, &h)
                return {Window: {X: x, Y: y, W: w, H: h}, Area: Win.WorkAreaAt(x + w // 2, y + h // 2)}
            }
        }
        if (IsObject(SearchWindow.LastArea) && A_TickCount - SearchWindow.HiddenAt < Hud.RecentWindowMs)
            return {Window: "", Area: SearchWindow.LastArea}
        return {Window: "", Area: Hud.ScreenArea(AppSettings.Appearance["ShowOn"])}
    }

    static ScreenArea(showOn) {
        switch showOn, false {
            case "Primary": return Win.WorkArea(MonitorGetPrimary())
            case "Active":
                area := ""
                try area := Win.WorkAreaOfWindow(WinExist("A"))
                if IsObject(area)
                    return area
        }
        return Win.WorkAreaAtMouse()
    }

    static _Color(key, fallback) {
        color := ThemeManager.Get(key)
        return (color != "") ? color : fallback
    }

}

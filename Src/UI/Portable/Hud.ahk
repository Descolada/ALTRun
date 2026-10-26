; Hud.ahk - Themed bitmap notices with native positioning and a single expiry timer.

class Hud {
    static Gui := "", Picture := ""
    static MaxWidth := 520, MaxLines := 3
    static _timer := ""
    static _lines := [], _width := 0, _height := 0, _lineHeight := 0, _family := ""
    static _options := "s11", _textColor := "", _background := "", _scale := 0

    static Show(text, duration := 1500) {
        Hud.Hide()
        if (Trim(text, " `t`r`n") = "")
            return
        g := Gui("+AlwaysOnTop +ToolWindow -Caption", App.Name)
        g.BackColor := "0x00010203"
        g.MarginX := 0, g.MarginY := 0
        Hud._family := ThemeManager.FontName()
        Hud._background := Hud._Color("Background", "FAFAFA")
        Hud._textColor := Hud._Color("Title", "1F1F1F")
        backgroundLight := Hud._Luminance(Hud._background), textLight := Hud._Luminance(Hud._textColor)
        if ((Max(backgroundLight, textLight) + 0.05) / (Min(backgroundLight, textLight) + 0.05) < 4.5)
            Hud._textColor := backgroundLight > 0.179 ? "000000" : "FFFFFF"
        measure := Image.Create(1, 1)
        try {
            Hud._lineHeight := Ceil(measure.MeasureText("Ag", Hud._options, Hud._family).Height) + 3
            Hud._lines := Hud._Wrap(measure, text, Hud.MaxWidth - 70)
            contentWidth := 0
            for line in Hud._lines
                contentWidth := Max(contentWidth, measure.MeasureText(line, Hud._options, Hud._family).Width)
            Hud._width := Min(Hud.MaxWidth, Max(190, Ceil(contentWidth) + 70))
            Hud._height := Hud._lines.Length * Hud._lineHeight + 30
        } finally measure.Dispose()
        picture := g.AddPicture("x0 y0 w" Hud._width " h" Hud._height)
        picture.OnEvent("Click", (*) => Hud.Hide())
        LauncherCanvas.AccessibleLabel(picture, text)
        g.OnEvent("Close", (*) => (Hud.Hide(), true))
        g.OnEvent("Escape", (*) => Hud.Hide())
        g.OnEvent("DpiChanged", (*) => Hud._Render(g))
        Hud.Gui := g, Hud.Picture := picture
        Hud._Render(g)
        g.Show("Hide w" Hud._width " h" Hud._height)
        g.GetPos(, , &width, &height)
        screenScale := LauncherCanvas.ScreenScale(g)
        width := Round(width * screenScale), height := Round(height * screenScale)
        pos := Hud.Position(width, height, Hud._Anchor())
        g.Show("NA x" pos.X " y" pos.Y)
        if (Hud._scale != g.PixelScale)
            Hud._Render(g)
        Hud._timer := () => Hud._Expire(g)
        SetTimer(Hud._timer, -Min(60000, Max(duration, 300)))
    }

    static _Wrap(canvas, text, width) {
        remaining := Trim(StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n"))
        remaining := RegExReplace(remaining, "[ `t]+", " ")
        lines := []
        while (remaining != "" && lines.Length < Hud.MaxLines) {
            if (lines.Length = Hud.MaxLines - 1) {
                lines.Push(LauncherCanvas.Fit(canvas, RegExReplace(remaining, "\s+", " "), width, Hud._options, Hud._family))
                break
            }
            nextLine := InStr(remaining, "`n")
            paragraph := nextLine ? SubStr(remaining, 1, nextLine - 1) : remaining
            rest := nextLine ? SubStr(remaining, nextLine + 1) : ""
            if (paragraph = "") {
                remaining := rest
                continue
            }
            fitted := LauncherCanvas.Fit(canvas, paragraph, width, Hud._options, Hud._family)
            if (fitted == paragraph) {
                lines.Push(paragraph)
                remaining := rest
                continue
            }
            prefix := SubStr(fitted, -1) = Chr(0x2026) ? SubStr(fitted, 1, -1) : fitted
            consumed := StrLen(prefix), space := InStr(prefix, " ", , -1)
            if (space > consumed / 2)
                prefix := SubStr(prefix, 1, space - 1), consumed := space
            if (consumed = 0) {
                lines.Push(fitted)
                break
            }
            lines.Push(RTrim(prefix))
            remaining := LTrim(SubStr(paragraph, consumed + 1)) (rest != "" ? "`n" rest : "")
        }
        return lines
    }

    static _Render(g) {
        if (Hud.Gui != g || !IsObject(Hud.Picture))
            return
        Hud._scale := g.PixelScale
        noticeImage := Image.Create(Hud._width, Hud._height, , Hud._scale)
        try {
            noticeImage.FillRoundRect(1, 1, Hud._width - 2, Hud._height - 2, 12, "0xFF" Hud._background)
            edge := LauncherCanvas.Blend(Hud._background, Hud._textColor, 0.18)
            noticeImage.DrawRoundRect(1, 1, Hud._width - 2, Hud._height - 2, 12, "0xFF" edge, 1)
            accent := "0xFF" Hud._Color("Highlight", Hud._textColor)
            centerY := Hud._height / 2
            noticeImage.FillEllipse(18, centerY - 9, 18, 18, accent)
            noticeImage.FillEllipse(26, centerY - 6, 2, 2, "0xFF" Hud._background)
            noticeImage.DrawLine(27, centerY - 1, 27, centerY + 5, "0xFF" Hud._background, 1.7)
            for index, line in Hud._lines
                noticeImage.DrawText(line, 49, 15 + (index - 1) * Hud._lineHeight, "0xFF" Hud._textColor, Hud._options, Hud._family)
            Hud.Picture.Value := "HBITMAP:" noticeImage.ToBitmap()
        } finally noticeImage.Dispose()
    }

    static _Luminance(color) {
        rgb := Integer("0x" color), result := 0
        for index, weight in [0.2126, 0.7152, 0.0722] {
            shift := (3 - index) * 8
            channel := ((rgb >> shift) & 255) / 255
            channel := channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
            result += channel * weight
        }
        return result
    }

    static _Expire(g) {
        if (Hud.Gui = g)
            Hud.Hide()
    }

    static Hide() {
        if IsObject(Hud._timer)
            SetTimer(Hud._timer, 0)
        Hud._timer := ""
        if IsObject(Hud.Picture)
            try Hud.Picture.Value := ""
        Hud.Picture := ""
        if IsObject(Hud.Gui) {
            try Hud.Gui.Destroy()
            Hud.Gui := ""
        }
        Hud._lines := []
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
                WinGetPos(&x, &y, &w, &h, "ahk_id " SearchWindow.Gui.Hwnd)
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

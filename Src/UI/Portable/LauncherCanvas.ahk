; Shared bitmap drawing for the portable launcher; geometry stays in logical GUI units.
class LauncherCanvas {
    static _fits := LauncherCanvas._TextMap()
    static _metrics := LauncherCanvas._TextMap()

    static _TextMap() {
        values := Map()
        values.CaseSense := "On"
        return values
    }

    static Color(name) => "0xFF" ThemeManager.Get(name)

    static ScreenScale(windowGui) => Platform.IsWindows || (Platform.IsLinux && !Platform.IsWayland) ? windowGui.PixelScale : 1

    static AccessibleLabel(control, text) {
        if Platform.IsWindows {
            try control.ToClr().AccessibleName := text
        } else if Platform.IsLinux {
            try control.ToClr().ControlObject.Accessible.Name := text
        }
    }

    static Metrics(canvas, options, family) {
        key := options "|" family "|" canvas.ScaleX
        if !LauncherCanvas._metrics.Has(key)
            LauncherCanvas._metrics[key] := canvas.MeasureText("Ag", options, family)
        return LauncherCanvas._metrics[key]
    }

    static Blend(first, second, amount) {
        left := Integer("0x" first), right := Integer("0x" second), result := 0
        for shift in [16, 8, 0]
            result |= Round(((left >> shift) & 255) * (1 - amount) + ((right >> shift) & 255) * amount) << shift
        return Format("{:06X}", result)
    }

    static Fit(canvas, text, width, options, family) {
        text := RegExReplace(text, "[\r\n\t]+", " ")
        if (width <= 0 || text = "")
            return ""
        key := width "|" options "|" family "|" text
        if LauncherCanvas._fits.Has(key)
            return LauncherCanvas._fits[key]
        fitted := text
        if (canvas.MeasureText(text, options, family).Width > width) {
            low := 0, high := ALTRunLauncherTextLength(text)
            while (low < high) {
                middle := Ceil((low + high) / 2)
                candidate := ALTRunLauncherPrefix(text, middle) Chr(0x2026)
                if (canvas.MeasureText(candidate, options, family).Width <= width)
                    low := middle
                else
                    high := middle - 1
            }
            fitted := low ? ALTRunLauncherPrefix(text, low) Chr(0x2026) : ""
        }
        if (LauncherCanvas._fits.Count >= 1000)
            LauncherCanvas._fits.Clear()
        return LauncherCanvas._fits[key] := fitted
    }

    static Text(canvas, text, x, y, width, color, options, family, query := "", highlight := "") {
        fitted := LauncherCanvas.Fit(canvas, text, width, options, family)
        state := canvas.SaveState()
        try {
            canvas.Clip(Image.Path().AddRect(x, y, width, LauncherCanvas.Metrics(canvas, options, family).Height + 4))
            canvas.DrawText(fitted, x, y, color, options, family)
            if (query = "" || highlight = "")
                return fitted
            for range in FuzzyMatcher.MatchRanges(query, fitted) {
                before := SubStr(fitted, 1, range[1] - 1), matched := SubStr(fitted, range[1], range[2])
                offset := before != "" ? canvas.MeasureText(before, options, family).Width : 0
                spanWidth := canvas.MeasureText(matched, options, family).Width
                clipped := canvas.SaveState()
                try {
                    canvas.Clip(Image.Path().AddRect(x + offset, y, spanWidth, LauncherCanvas.Metrics(canvas, options, family).Height + 4))
                    canvas.DrawText(fitted, x, y, highlight, options, family)
                } finally canvas.RestoreState(clipped)
            }
            return fitted
        } finally canvas.RestoreState(state)
    }

    static Render(width, height, scale, rows) {
        canvas := Image.Create(width, height, , scale)
        canvas.FillRect(0, 0, width, height, LauncherCanvas.Color("Background"))
        family := ThemeManager.FontName(), pad := SearchWindow.Padding
        canvas.DrawRoundRect(0.5, 0.5, width - 1, height - 1, 10, LauncherCanvas.Color("Border"), 1)
        surface := LauncherCanvas.Blend(ThemeManager.Get("Background"), ThemeManager.Get("InputText"), 0.035)
        canvas.FillRoundRect(pad, pad, width - pad * 2, SearchWindow.InputHeight + 12, 8, "0xFF" surface)
        middle := pad + (SearchWindow.InputHeight + 12) / 2
        canvas.DrawEllipse(pad + 14, middle - 8, 12, 12, LauncherCanvas.Color("Subtitle"), 1.8)
        canvas.DrawLine(pad + 24, middle + 2, pad + 29, middle + 7, LauncherCanvas.Color("Subtitle"), 1.8)
        canvas.DrawLine(pad, SearchWindow.ListTop - 4, width - pad, SearchWindow.ListTop - 4, LauncherCanvas.Color("Separator"), 1)
        for row in rows
            LauncherCanvas.Row(canvas, row, family)
        if SearchWindow.FooterHeight
            LauncherCanvas.Footer(canvas, width, height, family)
        return canvas
    }

    static Row(canvas, row, family) {
        item := row.Item
        canvas.FillRoundRect(row.X, row.Y, row.Width, row.Height, 8, "0xFF" row.Background)
        titleColor := LauncherCanvas.Color(row.Selected ? "SelectedTitle" : "Title")
        subtitleColor := LauncherCanvas.Color(row.Selected ? "SelectedSubtitle" : "Subtitle")
        badgeColor := LauncherCanvas.Color(row.Selected ? "SelectedShortcut" : "Shortcut")
        iconSize := SearchWindow.IconSize, iconX := row.X + 12, iconY := row.Y + (row.Height - iconSize) / 2
        LauncherCanvas.Icon(canvas, item, iconX, iconY, iconSize, row.Background, row.Selected)
        titleX := iconX + iconSize + 14
        shortcutOptions := "s" ThemeManager.Get("ShortcutFontSize")
        badgeWidth := Max(42, canvas.MeasureText(row.Shortcut, shortcutOptions, family).Width + 14)
        badgeX := row.X + row.Width - badgeWidth - 12
        badgeHeight := Max(21, canvas.MeasureText(row.Shortcut, shortcutOptions, family).Height + 7)
        badgeY := row.Y + (row.Height - badgeHeight) / 2
        badgeBackground := LauncherCanvas.Blend(row.Background, ThemeManager.Get(row.Selected ? "SelectedTitle" : "Title"), 0.065)
        canvas.FillRoundRect(badgeX, badgeY, badgeWidth, badgeHeight, 5, "0xFF" badgeBackground)
        canvas.DrawText(row.Shortcut, badgeX + 7, badgeY + 3, badgeColor, shortcutOptions, family)
        textWidth := Max(0, badgeX - titleX - 14)
        titleOptions := "s" ThemeManager.Get("TitleFontSize")
        subtitleOptions := "s" ThemeManager.Get("SubtitleFontSize")
        titleHeight := LauncherCanvas.Metrics(canvas, titleOptions, family).Height
        subtitleHeight := row.Subtitle != "" ? LauncherCanvas.Metrics(canvas, subtitleOptions, family).Height : 0
        textTop := row.Y + Max(3, (row.Height - titleHeight - subtitleHeight - (subtitleHeight ? 3 : 0)) / 2)
        row.Title := LauncherCanvas.Text(canvas, row.Title, titleX, textTop, textWidth, titleColor, titleOptions, family
            , Trim(SearchWindow.HighlightText), LauncherCanvas.Color(row.Selected ? "SelectedHighlight" : "Highlight"))
        if (row.Subtitle != "")
            row.Subtitle := LauncherCanvas.Text(canvas, row.Subtitle, titleX, textTop + titleHeight + 3, textWidth, subtitleColor, subtitleOptions, family)
        if SearchWindow.IsMarked(item)
            canvas.FillEllipse(iconX - 3, iconY + iconSize - 7, 10, 10, LauncherCanvas.Color("SelectedHighlight"))
        else if item.Pinned
            canvas.FillEllipse(iconX - 2, iconY + iconSize - 5, 6, 6, LauncherCanvas.Color("Highlight"))
    }

    static Icon(canvas, item, x, y, size, background, selected) {
        iconImage := IconCache.Get(item.Icon)
        if IsObject(iconImage) {
            canvas.DrawImage(iconImage, x, y, size, size)
            return
        }
        accent := ThemeManager.Get(selected ? "SelectedHighlight" : "Highlight")
        soft := "0xFF" LauncherCanvas.Blend(background, accent, 0.16), ink := "0xFF" accent
        switch item.Kind {
            case "folder":
                canvas.FillRoundRect(x + 1, y + size * 0.18, size * 0.46, size * 0.3, 3, ink)
                canvas.FillRoundRect(x, y + size * 0.32, size, size * 0.57, 4, soft)
                canvas.DrawRoundRect(x + 0.5, y + size * 0.32, size - 1, size * 0.57, 4, ink, 1)
            case "url":
                canvas.FillRoundRect(x, y, size, size, 7, soft)
                canvas.DrawEllipse(x + 6, y + 6, size - 12, size - 12, ink, 1.5)
                canvas.DrawEllipse(x + size * 0.38, y + 6, size * 0.24, size - 12, ink, 1)
                canvas.DrawLine(x + 6, y + size / 2, x + size - 6, y + size / 2, ink, 1)
            case "file":
                canvas.FillRoundRect(x + 4, y + 2, size - 8, size - 4, 4, soft)
                canvas.DrawRoundRect(x + 4, y + 2, size - 8, size - 4, 4, ink, 1)
                for offset in [0.38, 0.55, 0.72]
                    canvas.DrawLine(x + 10, y + size * offset, x + size - 10, y + size * offset, ink, 1)
            default:
                canvas.FillRoundRect(x, y, size, size, 7, soft)
                glyph := item.Kind = "text" ? "=" : Chr(0x203A)
                options := "s" Round(size * 0.53), family := ThemeManager.FontName()
                measured := canvas.MeasureText(glyph, options, family)
                canvas.DrawText(glyph, x + (size - measured.Width) / 2, y + (size - measured.Height) / 2, ink, options, family)
        }
    }

    static Footer(canvas, width, height, family) {
        top := height - SearchWindow.FooterHeight, pad := SearchWindow.Padding
        canvas.DrawLine(pad, top, width - pad, top, LauncherCanvas.Color("Separator"), 1)
        options := "s9", color := LauncherCanvas.Color("Subtitle")
        actions := SearchWindow.Mode = "actions"
        if !actions
            Loop 3
                canvas.DrawLine(pad + 2, top + 13 + (A_Index - 1) * 4, pad + 14, top + 13 + (A_Index - 1) * 4, color, 1.5)
        left := actions ? Chr(0x2190) "  " I18n.T("Status.Back") : SearchWindow.FileMode ? I18n.T("Status.FileMode") : App.Name
        left := LauncherCanvas.Fit(canvas, left, width * 0.46, options, family)
        canvas.DrawText(left, pad + (actions ? 2 : 26), top + 10, color, options, family)
        item := SearchWindow.SelectedItem()
        label := !IsObject(item) ? "" : !item.Valid ? I18n.T("Status.Complete")
            : SearchWindow.Mode = "actions" ? I18n.T("Status.Run") : item.Kind = "text" ? I18n.T("Status.Copy") : I18n.T("Status.Open")
        hint := label != "" ? "Enter  " label "     " : ""
        hint .= SearchWindow.Mode = "actions" ? "" : I18n.T("Status.Actions") "  " Chr(0x2192)
        hint := LauncherCanvas.Fit(canvas, hint, width * 0.49 - pad, options, family)
        measured := canvas.MeasureText(hint, options, family)
        canvas.DrawText(hint, width - pad - measured.Width, top + 10, color, options, family)
    }
}

#CSharp
public static long ALTRunLauncherTextLength(string text) => System.Globalization.StringInfo.ParseCombiningCharacters(text).Length;
public static string ALTRunLauncherPrefix(string text, long length)
{
    if (length <= 0) return "";
    int[] starts = System.Globalization.StringInfo.ParseCombiningCharacters(text);
    return length >= starts.Length ? text : text[..starts[(int)length]];
}
#EndCSharp

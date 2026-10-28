; Shared bitmap drawing for the portable launcher; geometry stays in logical GUI units.
class LauncherCanvas {
    static _fits := LauncherCanvas._TextMap()
    static _measurements := LauncherCanvas._TextMap()

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
        } else if Platform.IsMac {
#if OSX
            ALTRunMacAccessibleLabel(control.ToClr(), text)
#endif
        }
    }

    static AccessibleResults(control, rows) {
#if OSX
        data := []
        for row in rows {
            item := row.Item
            identity := item.Identity()
            data.Push(Map("Index", row.Index, "Identity", identity, "Label", row.Title
                . (row.Subtitle != "" ? ". " row.Subtitle : "") ". " row.Shortcut
                , "X", row.X, "Y", row.Y, "W", row.Width, "H", row.Height, "Selected", row.Selected))
        }
        ALTRunMacAccessibleResults(control.ToClr(), JSON.Stringify(data)
            , (index, identity) => SearchWindow.AccessibleActivate(index, identity))
#endif
    }

    static Metrics(canvas, options, family) => LauncherCanvas.Measure(canvas, "Ag", options, family)

    static Measure(canvas, text, options, family) {
        key := options "|" family "|" canvas.ScaleX "|" text
        if !LauncherCanvas._measurements.Has(key) {
            if (LauncherCanvas._measurements.Count >= 2000)
                LauncherCanvas._measurements.Clear()
            LauncherCanvas._measurements[key] := canvas.MeasureText(text, options, family)
        }
        return LauncherCanvas._measurements[key]
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
        if (LauncherCanvas.Measure(canvas, text, options, family).Width > width) {
            low := 0, high := ALTRunLauncherTextLength(text)
            while (low < high) {
                middle := Ceil((low + high) / 2)
                candidate := ALTRunLauncherPrefix(text, middle) Chr(0x2026)
                if (LauncherCanvas.Measure(canvas, candidate, options, family).Width <= width)
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
                offset := before != "" ? LauncherCanvas.Measure(canvas, before, options, family).Width : 0
                spanWidth := LauncherCanvas.Measure(canvas, matched, options, family).Width
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
        IconCache.BeginFrame()
        canvas := Image.Create(width, height, , scale)
        if Platform.IsMac
            canvas.FillRoundRect(0, 0, width, height, 10, LauncherCanvas.Color("Background"))
        else
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
        badgeSize := LauncherCanvas.Measure(canvas, row.Shortcut, shortcutOptions, family)
        badgeWidth := Max(42, badgeSize.Width + 14)
        badgeX := row.X + row.Width - badgeWidth - 12
        badgeHeight := Max(21, badgeSize.Height + 7)
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
        iconImage := IconCache.Peek(item.Icon)
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
                measured := LauncherCanvas.Measure(canvas, glyph, options, family)
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
        measured := LauncherCanvas.Measure(canvas, hint, options, family)
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

#if OSX
#CSharp
public static void ALTRunMacAccessibleLabel(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, string text)
{
    var control = (Eto.Forms.Control)wrapper.Native;
    var handle = ALTRunMacObjC.Handle(control);
    if (handle == System.IntPtr.Zero) return;
    var selector = ALTRunMacDesktopNative.Sel("setAccessibilityLabel:");
    if (ALTRunMacObjC.Responds(handle, ALTRunMacDesktopNative.Sel("respondsToSelector:"), selector) == 0) return;
    ALTRunMacDesktopNative.Arg(handle, selector, ALTRunMacDesktopNative.Text(text));
}

public static void ALTRunMacRoundWindow(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, double radius)
{
    var form = (Eto.Forms.Form)wrapper.Native;
    var window = ALTRunMacObjC.Handle(form);
    if (window == System.IntPtr.Zero)
        throw new System.InvalidOperationException("The macOS launcher window is unavailable.");
    var view = ALTRunMacDesktopNative.Send(window, "contentView");
    // Auxiliary launcher windows follow the active Space and can appear above full-screen apps.
    ALTRunMacDesktopNative.Arg(window, "setCollectionBehavior:", 1 | 8 | 64 | 256);
    ALTRunMacDesktopNative.Bool(window, ALTRunMacDesktopNative.Sel("setOpaque:"), 0);
    ALTRunMacDesktopNative.Arg(window, "setBackgroundColor:",
        ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSColor"), "clearColor"));
    ALTRunMacDesktopNative.Bool(view, ALTRunMacDesktopNative.Sel("setWantsLayer:"), 1);
    var layer = ALTRunMacDesktopNative.Send(view, "layer");
    if (layer == System.IntPtr.Zero)
        throw new System.InvalidOperationException("The macOS launcher clipping layer is unavailable.");
    ALTRunMacDesktopNative.Bool(layer, ALTRunMacDesktopNative.Sel("setOpaque:"), 0);
    ALTRunMacObjC.SetDouble(layer, ALTRunMacDesktopNative.Sel("setCornerRadius:"), radius);
    ALTRunMacDesktopNative.Bool(layer, ALTRunMacDesktopNative.Sel("setMasksToBounds:"), 1);
    ALTRunMacDesktopNative.Send(window, "invalidateShadow");
    form.SizeChanged += (_, _) => ALTRunMacDesktopNative.Send(window, "invalidateShadow");
    form.Closed += (_, _) => ALTRunMacFade.Stop();
    form.Closing += (_, _) => ALTRunMacAccessibility.Clear();
}

public static void ALTRunMacAccessibleResults(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, string rows,
    Keysharp.Builtins.KeysharpFunc activate) => ALTRunMacAccessibility.Update((Eto.Forms.Control)wrapper.Native, rows, activate);
public static void ALTRunMacResetWindowIntegration() { ALTRunMacFade.Stop(); ALTRunMacAccessibility.Clear(); }

private static class ALTRunMacAccessibility
{
    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
    private delegate byte PressAction(System.IntPtr self, System.IntPtr selector);
    private static readonly PressAction pressAction = Press;
    private static readonly System.IntPtr elementClass = CreateClass();
    private static readonly System.Collections.Generic.Dictionary<System.IntPtr, Entry> entries = new();
    private static System.IntPtr host;
    private static Eto.Forms.Control hostControl;
    private static System.Collections.Generic.List<System.IntPtr> order = new();
    private static string announced = "";
    private sealed class Entry
    {
        internal System.IntPtr Element;
        internal long Index;
        internal string Identity;
        internal Keysharp.Builtins.KeysharpFunc Activate;
    }

    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")]
    private static extern System.IntPtr objc_allocateClassPair(System.IntPtr superclass, string name, long extraBytes);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")]
    private static extern byte class_addMethod(System.IntPtr cls, System.IntPtr name, System.IntPtr implementation, string types);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")]
    private static extern void objc_registerClassPair(System.IntPtr cls);
    [System.Runtime.InteropServices.DllImport("/System/Library/Frameworks/AppKit.framework/AppKit")]
    private static extern void NSAccessibilityPostNotificationWithUserInfo(System.IntPtr element, System.IntPtr notification, System.IntPtr userInfo);

    private static System.IntPtr CreateClass()
    {
        var cls = ALTRunMacDesktopNative.Class("ALTRunAccessibleResult");
        if (cls != System.IntPtr.Zero) return cls;
        cls = objc_allocateClassPair(ALTRunMacDesktopNative.Class("NSAccessibilityElement"), "ALTRunAccessibleResult", 0);
        if (cls == System.IntPtr.Zero) throw new System.InvalidOperationException("Could not create accessible launcher results.");
        class_addMethod(cls, ALTRunMacDesktopNative.Sel("accessibilityPerformPress"), System.Runtime.InteropServices.Marshal.GetFunctionPointerForDelegate(pressAction), "c@:");
        objc_registerClassPair(cls);
        return cls;
    }

    private static byte Press(System.IntPtr self, System.IntPtr selector)
    {
        try
        {
            if (!entries.TryGetValue(self, out var entry)) return 0;
            var callback = entry.Activate; long index = entry.Index; string identity = entry.Identity;
            Eto.Forms.Application.Instance.AsyncInvoke(() => callback.Call(index, identity));
            return 1;
        }
        catch { return 0; }
    }

    internal static void Clear()
    {
        if (host != System.IntPtr.Zero && hostControl?.IsDisposed == false)
            ALTRunMacDesktopNative.Arg(host, "setAccessibilityChildren:",
                ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSArray"), "array"));
        foreach (var entry in entries.Values)
            ALTRunMacDesktopNative.Send(entry.Element, "release");
        entries.Clear(); host = System.IntPtr.Zero; hostControl = null; order.Clear(); announced = "";
    }

    internal static void Update(Eto.Forms.Control control, string json, Keysharp.Builtins.KeysharpFunc activate)
    {
        var view = ALTRunMacObjC.Handle(control);
        if (view == System.IntPtr.Zero) return;
        if (host != System.IntPtr.Zero && host != view) Clear();
        hostControl = control;
        host = view;
        ALTRunMacDesktopNative.Bool(view, ALTRunMacDesktopNative.Sel("setAccessibilityElement:"), 1);
        ALTRunMacDesktopNative.Arg(view, "setAccessibilityRole:", ALTRunMacDesktopNative.Text("AXList"));
        ALTRunMacDesktopNative.Arg(view, "setAccessibilityLabel:", ALTRunMacDesktopNative.Text("ALTRun results"));
        var children = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSMutableArray"), "array");
        var remaining = new System.Collections.Generic.HashSet<System.IntPtr>(entries.Keys);
        var handles = new System.Collections.Generic.List<System.IntPtr>();
        var bounds = ALTRunMacObjC.GetRect(view, ALTRunMacDesktopNative.Sel("bounds"));
        var window = ALTRunMacDesktopNative.Send(view, "window");
        bool flipped = ALTRunMacObjC.GetBool(view, ALTRunMacDesktopNative.Sel("isFlipped")) != 0;
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        string selection = "", announcement = "";
        foreach (var row in doc.RootElement.EnumerateArray())
        {
            string identity = row.GetProperty("Identity").GetString();
            Entry entry = null;
            foreach (var candidate in entries.Values)
                if (remaining.Contains(candidate.Element) && candidate.Identity == identity) { entry = candidate; break; }
            if (entry == null)
            {
                var element = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Send(elementClass, "alloc"), "init");
                entry = new Entry { Element = element, Identity = identity };
                entries.Add(element, entry);
                ALTRunMacDesktopNative.Bool(element, ALTRunMacDesktopNative.Sel("setAccessibilityElement:"), 1);
                ALTRunMacDesktopNative.Arg(element, "setAccessibilityRole:", ALTRunMacDesktopNative.Text("AXButton"));
                ALTRunMacDesktopNative.Arg(element, "setAccessibilityParent:", view);
            }
            remaining.Remove(entry.Element);
            entry.Index = row.GetProperty("Index").GetInt64(); entry.Activate = activate;
            bool selected = row.GetProperty("Selected").ValueKind == System.Text.Json.JsonValueKind.True
                || row.GetProperty("Selected").ToString() == "1";
            string label = row.GetProperty("Label").GetString();
            ALTRunMacDesktopNative.Arg(entry.Element, "setAccessibilityLabel:", ALTRunMacDesktopNative.Text((selected ? "Selected. " : "") + label));
            var rect = new ALTRunMacObjC.Rect { X = row.GetProperty("X").GetDouble(), Y = row.GetProperty("Y").GetDouble(), W = row.GetProperty("W").GetDouble(), H = row.GetProperty("H").GetDouble() };
            if (!flipped) rect.Y = bounds.H - rect.Y - rect.H;
            rect = ALTRunMacObjC.ConvertToWindow(view, rect);
            rect = ALTRunMacObjC.ConvertToScreen(window, rect);
            ALTRunMacObjC.SetRect(entry.Element, ALTRunMacDesktopNative.Sel("setAccessibilityFrame:"), rect);
            ALTRunMacDesktopNative.Arg(children, "addObject:", entry.Element);
            handles.Add(entry.Element);
            if (selected) { selection = identity; announcement = label; }
        }
        if (!System.Linq.Enumerable.SequenceEqual(handles, order))
        {
            ALTRunMacDesktopNative.Arg(view, "setAccessibilityChildren:", children);
            order = handles;
        }
        foreach (var handle in remaining)
        {
            entries.Remove(handle);
            ALTRunMacDesktopNative.Send(handle, "release");
        }
        if (control.ParentWindow?.Visible == true && selection.Length > 0 && selection != announced)
        {
            var info = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSMutableDictionary"), "dictionary");
            ALTRunMacDesktopNative.Two(info, ALTRunMacDesktopNative.Sel("setObject:forKey:"), ALTRunMacDesktopNative.Text(announcement), ALTRunMacObjC.Constant("NSAccessibilityAnnouncementKey"));
            var priority = ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSNumber"), "numberWithInteger:", 10);
            ALTRunMacDesktopNative.Two(info, ALTRunMacDesktopNative.Sel("setObject:forKey:"), priority, ALTRunMacObjC.Constant("NSAccessibilityPriorityKey"));
            NSAccessibilityPostNotificationWithUserInfo(view, ALTRunMacObjC.Constant("NSAccessibilityAnnouncementRequestedNotification"), info);
            announced = selection;
        }
    }
}

public static void ALTRunMacFadeWindow(Keysharp.Builtins.Ks.Clr.ManagedInstance wrapper, bool showing, bool fade, long opacity)
    => ALTRunMacFade.Apply((Eto.Forms.Form)wrapper.Native, showing, fade, opacity / 255.0);

private static class ALTRunMacFade
{
    private static Eto.Forms.UITimer timer;
    private static System.IntPtr ghost;
    private static System.IntPtr realWindow;
    private static double targetAlpha = 1;

    internal static void Stop()
    {
        timer?.Stop(); timer?.Dispose(); timer = null;
        if (realWindow != System.IntPtr.Zero)
            ALTRunMacObjC.SetDouble(realWindow, ALTRunMacDesktopNative.Sel("setAlphaValue:"), targetAlpha);
        realWindow = System.IntPtr.Zero;
        if (ghost != System.IntPtr.Zero)
        {
            ALTRunMacDesktopNative.Arg(ghost, "orderOut:", System.IntPtr.Zero);
            ALTRunMacDesktopNative.Send(ghost, "release");
            ghost = System.IntPtr.Zero;
        }
    }

    internal static void Apply(Eto.Forms.Form form, bool showing, bool fade, double alpha)
    {
        Stop();
        var window = ALTRunMacObjC.Handle(form);
        if (window == System.IntPtr.Zero) return;
        var workspace = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSWorkspace"), "sharedWorkspace");
        bool reducedMotion = ALTRunMacObjC.GetBool(workspace, ALTRunMacDesktopNative.Sel("accessibilityDisplayShouldReduceMotion")) != 0;
        bool reducedTransparency = ALTRunMacObjC.GetBool(workspace, ALTRunMacDesktopNative.Sel("accessibilityDisplayShouldReduceTransparency")) != 0;
        targetAlpha = reducedTransparency ? 1 : System.Math.Clamp(alpha, 0, 1);
        ALTRunMacObjC.SetDouble(window, ALTRunMacDesktopNative.Sel("setAlphaValue:"), targetAlpha);
        if (!fade || reducedMotion) return;
        System.IntPtr animated;
        double from, to;
        if (showing)
        {
            if (form.Visible) return;
            realWindow = window; animated = window; from = 0; to = targetAlpha;
            ALTRunMacObjC.SetDouble(window, ALTRunMacDesktopNative.Sel("setAlphaValue:"), 0);
        }
        else
        {
            ghost = Snapshot(window);
            if (ghost == System.IntPtr.Zero) return;
            animated = ghost; from = targetAlpha; to = 0;
        }
        var clock = System.Diagnostics.Stopwatch.StartNew();
        double duration = showing ? 120 : 100;
        timer = new Eto.Forms.UITimer { Interval = 0.01 };
        timer.Elapsed += (_, _) =>
        {
            double elapsed = System.Math.Clamp(clock.Elapsed.TotalMilliseconds / duration, 0, 1);
            ALTRunMacObjC.SetDouble(animated, ALTRunMacDesktopNative.Sel("setAlphaValue:"), from + (to - from) * (1 - System.Math.Pow(1 - elapsed, 3)));
            if (elapsed >= 1) Stop();
        };
        timer.Start();
    }

    private static System.IntPtr Snapshot(System.IntPtr window)
    {
        var view = ALTRunMacDesktopNative.Send(window, "contentView");
        var bounds = ALTRunMacObjC.GetRect(view, ALTRunMacDesktopNative.Sel("bounds"));
        var frame = ALTRunMacObjC.GetRect(window, ALTRunMacDesktopNative.Sel("frame"));
        var bitmap = ALTRunMacObjC.SendRect(view, ALTRunMacDesktopNative.Sel("bitmapImageRepForCachingDisplayInRect:"), bounds);
        if (bitmap == System.IntPtr.Zero) return System.IntPtr.Zero;
        ALTRunMacObjC.CacheDisplay(view, ALTRunMacDesktopNative.Sel("cacheDisplayInRect:toBitmapImageRep:"), bounds, bitmap);
        var image = ALTRunMacObjC.SendSize(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSImage"), "alloc"),
            ALTRunMacDesktopNative.Sel("initWithSize:"), new ALTRunMacObjC.Size { W = bounds.W, H = bounds.H });
        ALTRunMacDesktopNative.Arg(image, "addRepresentation:", bitmap);
        var imageView = ALTRunMacObjC.SendRect(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSImageView"), "alloc"),
            ALTRunMacDesktopNative.Sel("initWithFrame:"), bounds);
        ALTRunMacDesktopNative.Arg(imageView, "setImage:", image);
        var overlay = ALTRunMacObjC.NewPanel(ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSPanel"), "alloc"),
            ALTRunMacDesktopNative.Sel("initWithContentRect:styleMask:backing:defer:"), frame, 128, 2, 0);
        ALTRunMacDesktopNative.Bool(overlay, ALTRunMacDesktopNative.Sel("setReleasedWhenClosed:"), 0);
        ALTRunMacDesktopNative.Bool(overlay, ALTRunMacDesktopNative.Sel("setOpaque:"), 0);
        ALTRunMacDesktopNative.Bool(overlay, ALTRunMacDesktopNative.Sel("setIgnoresMouseEvents:"), 1);
        ALTRunMacDesktopNative.Arg(overlay, "setBackgroundColor:",
            ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSColor"), "clearColor"));
        ALTRunMacDesktopNative.Arg(overlay, "setCollectionBehavior:", 1 | 8 | 64 | 256);
        ALTRunMacDesktopNative.Arg(overlay, "setLevel:", 3);
        ALTRunMacDesktopNative.Arg(overlay, "setContentView:", imageView);
        ALTRunMacDesktopNative.Send(overlay, "orderFrontRegardless");
        ALTRunMacDesktopNative.Send(imageView, "release");
        ALTRunMacDesktopNative.Send(image, "release");
        return overlay;
    }
}

private static class ALTRunMacObjC
{
    internal static System.IntPtr Handle(Eto.Forms.Control control) =>
        control.ControlObject?.GetType().GetProperty("Handle")?.GetValue(control.ControlObject) is System.IntPtr handle ? handle : System.IntPtr.Zero;
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    internal struct Rect { public double X, Y, W, H; }
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    internal struct Size { public double W, H; }
    private static readonly System.IntPtr appKit = System.Runtime.InteropServices.NativeLibrary.Load("/System/Library/Frameworks/AppKit.framework/AppKit");
    internal static System.IntPtr Constant(string name) => System.Runtime.InteropServices.Marshal.ReadIntPtr(System.Runtime.InteropServices.NativeLibrary.GetExport(appKit, name));
    private const string Library = "/usr/lib/libobjc.A.dylib";
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern byte Responds(System.IntPtr target, System.IntPtr selector, System.IntPtr argument);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern void SetDouble(System.IntPtr target, System.IntPtr selector, double value);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern byte GetBool(System.IntPtr target, System.IntPtr selector);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    private static extern Rect GetRectArm(System.IntPtr target, System.IntPtr selector);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend_stret")]
    private static extern void GetRectIntel(out Rect value, System.IntPtr target, System.IntPtr selector);
    internal static Rect GetRect(System.IntPtr target, System.IntPtr selector)
    {
        if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture != System.Runtime.InteropServices.Architecture.X64)
            return GetRectArm(target, selector);
        GetRectIntel(out var value, target, selector);
        return value;
    }
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    private static extern Rect ConvertRectArm(System.IntPtr target, System.IntPtr selector, Rect rect);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend_stret")]
    private static extern void ConvertRectIntel(out Rect value, System.IntPtr target, System.IntPtr selector, Rect rect);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    private static extern Rect ConvertViewRectArm(System.IntPtr target, System.IntPtr selector, Rect rect, System.IntPtr view);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend_stret")]
    private static extern void ConvertViewRectIntel(out Rect value, System.IntPtr target, System.IntPtr selector, Rect rect, System.IntPtr view);
    internal static Rect ConvertToWindow(System.IntPtr view, Rect rect)
    {
        if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture != System.Runtime.InteropServices.Architecture.X64)
            return ConvertViewRectArm(view, ALTRunMacDesktopNative.Sel("convertRect:toView:"), rect, System.IntPtr.Zero);
        ConvertViewRectIntel(out var value, view, ALTRunMacDesktopNative.Sel("convertRect:toView:"), rect, System.IntPtr.Zero);
        return value;
    }
    internal static Rect ConvertToScreen(System.IntPtr window, Rect rect)
    {
        if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture != System.Runtime.InteropServices.Architecture.X64)
            return ConvertRectArm(window, ALTRunMacDesktopNative.Sel("convertRectToScreen:"), rect);
        ConvertRectIntel(out var value, window, ALTRunMacDesktopNative.Sel("convertRectToScreen:"), rect);
        return value;
    }
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern void SetRect(System.IntPtr target, System.IntPtr selector, Rect rect);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern System.IntPtr SendRect(System.IntPtr target, System.IntPtr selector, Rect rect);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern System.IntPtr SendSize(System.IntPtr target, System.IntPtr selector, Size size);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern void CacheDisplay(System.IntPtr target, System.IntPtr selector, Rect rect, System.IntPtr bitmap);
    [System.Runtime.InteropServices.DllImport(Library, EntryPoint = "objc_msgSend")]
    internal static extern System.IntPtr NewPanel(System.IntPtr target, System.IntPtr selector, Rect rect, long style, long backing, byte deferred);
}
#EndCSharp
#endif

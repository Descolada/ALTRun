; Vision performs local text recognition on an explicitly selected image.
#if OSX
#CSharp
private static class ALTRunVisionNative
{
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] internal static extern nint objc_autoreleasePoolPush();
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib")] internal static extern void objc_autoreleasePoolPop(nint pool);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")] internal static extern nint Two(nint target, nint selector, nint first, nint second);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")] internal static extern byte Perform(nint target, nint selector, nint requests, out nint error);
}
private static System.Threading.Tasks.Task<string> ALTRunVisionTask;
public static object ALTRunVisionStart(string Filename)
{
    if (ALTRunVisionTask is { IsCompleted: false }) throw new System.InvalidOperationException("Text recognition is already running.");
    ALTRunVisionTask = System.Threading.Tasks.Task.Run(() => {
        nint pool = 0, request = 0, handler = 0;
        try
        {
            System.Runtime.InteropServices.NativeLibrary.Load("/System/Library/Frameworks/Vision.framework/Vision");
            pool = ALTRunVisionNative.objc_autoreleasePoolPush();
            nint Class(string value) => ALTRunMacDesktopNative.Class(value);
            nint Sel(string value) => ALTRunMacDesktopNative.Sel(value);
            nint Send(nint target, string selector) => ALTRunMacDesktopNative.Send(target, Sel(selector));
            request = Send(Send(Class("VNRecognizeTextRequest"), "alloc"), "init");
            if (request == 0) throw new System.InvalidOperationException("Vision text recognition is unavailable.");
            nint url = ALTRunMacDesktopNative.Arg(Class("NSURL"), Sel("fileURLWithPath:"), ALTRunMacDesktopNative.Text(Filename));
            handler = ALTRunVisionNative.Two(Send(Class("VNImageRequestHandler"), "alloc"), Sel("initWithURL:options:"), url, Send(Class("NSDictionary"), "dictionary"));
            nint requests = ALTRunMacDesktopNative.Array(Class("NSArray"), Sel("arrayWithObjects:count:"), new[] { request }, 1);
            nint error = 0;
            if (handler == 0 || ALTRunVisionNative.Perform(handler, Sel("performRequests:error:"), requests, out error) == 0)
                throw new System.IO.IOException(error == 0 ? "Could not read this image." : ALTRunMacDesktopNative.String(Send(error, "localizedDescription")));
            nint results = Send(request, "results");
            long count = (long)Send(results, "count");
            var lines = new System.Collections.Generic.List<string>();
            for (long index = 0; index < System.Math.Min(count, 10000); index++)
            {
                nint observation = ALTRunMacDesktopNative.Arg(results, Sel("objectAtIndex:"), (nint)index);
                nint candidates = ALTRunMacDesktopNative.Arg(observation, Sel("topCandidates:"), 1);
                if ((long)Send(candidates, "count") == 0) continue;
                nint candidate = ALTRunMacDesktopNative.Arg(candidates, Sel("objectAtIndex:"), 0);
                string text = ALTRunMacDesktopNative.String(Send(candidate, "string"));
                if (text.Length > 0) lines.Add(text);
            }
            return System.Text.Json.JsonSerializer.Serialize(new { Text = string.Join("\n", lines), Error = "" });
        }
        catch (System.Exception error) { return System.Text.Json.JsonSerializer.Serialize(new { Text = "", Error = error.Message }); }
        finally
        {
            if (handler != 0) ALTRunMacDesktopNative.Send(handler, ALTRunMacDesktopNative.Sel("release"));
            if (request != 0) ALTRunMacDesktopNative.Send(request, ALTRunMacDesktopNative.Sel("release"));
            if (pool != 0) ALTRunVisionNative.objc_autoreleasePoolPop(pool);
        }
    });
    return null;
}
public static string ALTRunVisionPoll() => ALTRunVisionTask is { IsCompletedSuccessfully: true } task ? task.Result : "";
public static string ALTRunOcrTemporaryFile()
{
    string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ALTRun-ocr-" + System.Guid.NewGuid().ToString("N"));
    System.IO.Directory.CreateDirectory(directory, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
    string file = System.IO.Path.Combine(directory, "image.png");
    using var stream = new System.IO.FileStream(file, new System.IO.FileStreamOptions { Mode = System.IO.FileMode.CreateNew, Access = System.IO.FileAccess.Write,
        UnixCreateMode = System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite });
    return file;
}
public static object ALTRunOcrDeleteTemporary(string Filename)
{
    if (string.IsNullOrEmpty(Filename)) return null;
    if (System.IO.File.Exists(Filename)) System.IO.File.Delete(Filename);
    string directory = System.IO.Path.GetDirectoryName(Filename);
    if (System.IO.Path.GetFileName(directory).StartsWith("ALTRun-ocr-", System.StringComparison.Ordinal)
        && System.IO.Path.GetDirectoryName(directory) == System.IO.Path.TrimEndingDirectorySeparator(System.IO.Path.GetTempPath()))
        try { System.IO.Directory.Delete(directory); } catch (System.IO.IOException) { }
    return null;
}
#EndCSharp

class MacOcr {
    static _timer := "", _temporary := "", Busy := false
    static Supports(path) => RegExMatch(path, "i)\.(png|jpe?g|tiff?|heic|bmp|gif|webp)$") ? true : false

    static ExtractFile(path, temporary := false) {
        if !Platform.IsMac || !FileExist(path)
            return false
        if MacOcr.Busy
            return App.Notify("Text recognition is already running.")
        ALTRunVisionStart(path)
        MacOcr.Busy := true, MacOcr._temporary := temporary ? path : ""
        if !IsObject(MacOcr._timer)
            MacOcr._timer := () => MacOcr._Poll()
        SetTimer(MacOcr._timer, 100)
        App.Notify("Recognizing text…")
        return true
    }

    static ExtractClipboard() {
        if MacOcr.Busy
            return App.Notify("Text recognition is already running.")
        if !ClipboardData.HasImage()
            return App.Notify("Copy an image first.")
        file := ALTRunOcrTemporaryFile()
        try {
            if ClipboardData.SaveImage(file)
                return MacOcr.ExtractFile(file, true)
            ALTRunOcrDeleteTemporary(file)
            return App.Notify("Could not read the clipboard image.")
        } catch {
            ALTRunOcrDeleteTemporary(file)
            throw
        }
    }

    static _Poll() {
        text := ALTRunVisionPoll()
        if text = ""
            return
        SetTimer(MacOcr._timer, 0)
        MacOcr.Busy := false
        if MacOcr._temporary != ""
            try ALTRunOcrDeleteTemporary(MacOcr._temporary)
        MacOcr._temporary := ""
        result := JSON.Parse(text)
        if result["Error"] != ""
            return App.Notify(result["Error"], 4000)
        if result["Text"] = ""
            return App.Notify("No text found in the image.")
        ActionCatalog.CopyText(result["Text"])
    }

    static Stop() {
        if IsObject(MacOcr._timer)
            SetTimer(MacOcr._timer, 0)
        if MacOcr._temporary != ""
            try ALTRunOcrDeleteTemporary(MacOcr._temporary)
        MacOcr._temporary := "", MacOcr.Busy := false
    }
}
#else
class MacOcr {
    static Supports(path) => false
    static ExtractFile(path, temporary := false) => false
    static ExtractClipboard() => false
    static Stop() {
    }
}
#endif

; Spotlight queries run outside the script/UI thread. Only the latest request may update the results.
#CSharp
private sealed record ALTRunSpotlightEntry(string Path, bool IsFolder, string Name);
private sealed class ALTRunSpotlightJob
{
    internal readonly System.Threading.CancellationTokenSource Stop = new();
    internal System.Threading.Tasks.Task<string> Task;
}
private static ALTRunSpotlightJob ALTRunSpotlightCurrent;

public static string ALTRunSpotlightExpression(string Text, bool FoldersOnly, string Extensions, bool Content)
{
    string Quote(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("*", "\\*").Replace("?", "\\?") + "\"";
    string Contains(string value) => "\"*" + value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("*", "\\*").Replace("?", "\\?") + "*\"cd";
    var expressions = new System.Collections.Generic.List<string> { "kMDItemFSInvisible != 1" };
    var names = new System.Collections.Generic.List<string>();
    bool metadata = false;
    var kinds = new System.Collections.Generic.Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase) {
        ["pdf"] = "com.adobe.pdf", ["image"] = "public.image", ["audio"] = "public.audio", ["video"] = "public.movie",
        ["text"] = "public.text", ["document"] = "public.content", ["folder"] = "public.folder", ["app"] = "com.apple.application-bundle"
    };
    foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(Text, "(?:[^\\s\"]+|\"[^\"]*\")+"))
    {
        string token = match.Value;
        int colon = token.IndexOf(':');
        string key = colon > 0 ? token[..colon].ToLowerInvariant() : "";
        string value = (colon > 0 ? token[(colon + 1)..] : token).Trim('"');
        if (value.Length == 0) continue;
        if (key == "tag") { expressions.Add("kMDItemUserTags == " + Contains(value)); metadata = true; }
        else if (key == "kind" && kinds.TryGetValue(value, out var kind)) { expressions.Add("kMDItemContentTypeTree == " + Quote(kind)); metadata = true; }
        else if (key == "content") { expressions.Add("kMDItemTextContent == " + Contains(value)); metadata = true; }
        else if ((key == "modified" || key == "created") && System.DateTime.TryParseExact(value, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var date))
        {
            var utc = System.TimeZoneInfo.ConvertTimeToUtc(System.DateTime.SpecifyKind(date, System.DateTimeKind.Unspecified));
            expressions.Add((key == "modified" ? "kMDItemFSContentChangeDate" : "kMDItemFSCreationDate") + " >= $time.iso(" + utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture) + ")");
            metadata = true;
        }
        else
        {
            value = token.Trim('"');
            names.Add(value);
            string name = "kMDItemFSName == " + Contains(value);
            expressions.Add(Content ? "(" + name + " || kMDItemTextContent == " + Contains(value) + ")" : name);
        }
    }
    if (FoldersOnly) expressions.Add("kMDItemContentTypeTree == \"public.folder\"");
    var types = System.Text.Json.JsonSerializer.Deserialize<string[]>(Extensions) ?? [];
    if (types.Length > 0)
        expressions.Add("(" + string.Join(" || ", System.Array.ConvertAll(types, extension => "kMDItemFSName == \"*." + extension.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("*", "\\*").Replace("?", "\\?") + "\"c")) + ")");
    return System.Text.Json.JsonSerializer.Serialize(new { Query = string.Join(" && ", expressions), Needle = string.Join(" ", names), Metadata = metadata });
}

public static object ALTRunSpotlightStart(string Query, string Scope, int Limit, long Request)
{
    var previous = ALTRunSpotlightCurrent;
    previous?.Stop.Cancel();
    var job = new ALTRunSpotlightJob();
    ALTRunSpotlightCurrent = job;
    job.Task = System.Threading.Tasks.Task.Run(async () => {
        if (previous?.Task != null) { try { await previous.Task; } catch { } }
        var token = job.Stop.Token;
        using var deadline = System.Threading.CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(5000);
        var entries = new System.Collections.Generic.List<ALTRunSpotlightEntry>();
        var seen = new System.Collections.Generic.HashSet<string>(System.StringComparer.Ordinal);
        using var process = new System.Diagnostics.Process();
        process.StartInfo = new System.Diagnostics.ProcessStartInfo("/usr/bin/mdfind") {
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8, StandardErrorEncoding = System.Text.Encoding.UTF8
        };
        process.StartInfo.ArgumentList.Add("-0");
        if (!string.IsNullOrEmpty(Scope)) { process.StartInfo.ArgumentList.Add("-onlyin"); process.StartInfo.ArgumentList.Add(Scope); }
        process.StartInfo.ArgumentList.Add(Query);
        try
        {
            deadline.Token.ThrowIfCancellationRequested();
            process.Start();
            var errors = process.StandardError.ReadToEndAsync(deadline.Token);
            char[] buffer = new char[8192];
            var path = new System.Text.StringBuilder();
            bool full = false;
            while (!full)
            {
                int length = await process.StandardOutput.ReadAsync(buffer.AsMemory(), deadline.Token);
                if (length == 0) break;
                for (int index = 0; index < length; index++)
                {
                    if (buffer[index] != '\0') { if (path.Length < 32768) path.Append(buffer[index]); continue; }
                    string filename = path.ToString(); path.Clear();
                    if (filename.StartsWith("/System/Volumes/Data/", System.StringComparison.Ordinal)) filename = filename[20..];
                    if (filename.Length == 0 || filename[0] != '/' || !seen.Add(filename)) continue;
                    bool folder = System.IO.Directory.Exists(filename);
                    if (!folder && !System.IO.File.Exists(filename)) continue;
                    entries.Add(new(filename, folder && !filename.EndsWith(".app", System.StringComparison.OrdinalIgnoreCase), System.IO.Path.GetFileName(filename.TrimEnd('/'))));
                    if (entries.Count >= System.Math.Clamp(Limit, 1, 1000)) { full = true; break; }
                }
            }
            if (full && !process.HasExited) process.Kill(true);
            await process.WaitForExitAsync(deadline.Token);
            string error = await errors;
            if (!full && process.ExitCode != 0) throw new System.IO.IOException(string.IsNullOrWhiteSpace(error) ? "Spotlight search failed." : error.Trim());
            token.ThrowIfCancellationRequested();
            return System.Text.Json.JsonSerializer.Serialize(new { Id = Request, Key = Query, Entries = entries, Error = "" });
        }
        catch (System.OperationCanceledException) { return System.Text.Json.JsonSerializer.Serialize(new { Id = Request, Key = Query, Entries = entries, Error = token.IsCancellationRequested ? "cancelled" : "Spotlight search timed out." }); }
        catch (System.Exception error) { return System.Text.Json.JsonSerializer.Serialize(new { Id = Request, Key = Query, Entries = entries, Error = error.Message }); }
        finally { try { if (process.Id != 0 && !process.HasExited) process.Kill(true); } catch (System.InvalidOperationException) { } }
    });
    return null;
}
public static string ALTRunSpotlightPoll() => ALTRunSpotlightCurrent?.Task is { IsCompletedSuccessfully: true } task ? task.Result : "";
public static object ALTRunSpotlightCancel() { ALTRunSpotlightCurrent?.Stop.Cancel(); return null; }
#EndCSharp

class MacSpotlight {
    static Cache := Map(), _key := "", _request := "", _timer := "", _pollTimer := "", _started := 0, _generation := 0
    static Enabled() {
        options := AppSettings.Feature("FileSearch")
        return Platform.IsMac && options.Has("Spotlight") && options["Spotlight"]
    }

    static Expression(term, scope := false) {
        extensions := []
        if IsObject(scope)
            for extension in scope.Extensions
                extensions.Push(extension)
        options := AppSettings.Feature("FileSearch")
        return JSON.Parse(ALTRunSpotlightExpression(term, !IsObject(scope) && scope, JSON.Stringify(extensions), options.Has("SpotlightContent") && options["SpotlightContent"]))
    }

    static Query(term, scope := false) {
        if !MacSpotlight.Enabled() || StrLen(Trim(term)) < 2
            return []
        expression := MacSpotlight.Expression(term, scope)
        key := expression["Query"]
        if MacSpotlight.Cache.Has(key) && A_TickCount - MacSpotlight.Cache[key].At < 30000
            return MacSpotlight.Cache[key].Entries
        if (MacSpotlight._key != key) {
            MacSpotlight._generation++
            MacSpotlight._key := key, MacSpotlight._request := {Id: MacSpotlight._generation, Key: key, Expression: expression}
            ALTRunSpotlightCancel()
            if !IsObject(MacSpotlight._timer)
                MacSpotlight._timer := () => MacSpotlight._Start()
            SetTimer(MacSpotlight._timer, -150)
        }
        return MacSpotlight.Cache.Has(key) ? MacSpotlight.Cache[key].Entries : []
    }

    static _Start() {
        if !SearchWindow.IsVisible() || !MacSpotlight.Enabled()
            return MacSpotlight.Stop()
        if !IsObject(MacSpotlight._request)
            return
        request := MacSpotlight._request
        ALTRunSpotlightStart(request.Key, "", 500, request.Id)
        MacSpotlight._started := A_TickCount
        if !IsObject(MacSpotlight._pollTimer)
            MacSpotlight._pollTimer := () => MacSpotlight._Poll()
        SetTimer(MacSpotlight._pollTimer, 50)
    }

    static _Poll() {
        if !SearchWindow.IsVisible() {
            MacSpotlight.Stop()
            return
        }
        text := ALTRunSpotlightPoll()
        if (text = "")
            return
        SetTimer(MacSpotlight._pollTimer, 0)
        if !IsObject(MacSpotlight._request)
            return
        request := MacSpotlight._request, data := JSON.Parse(text), entries := []
        if !(data["Key"] == request.Key) || data["Id"] != request.Id || data["Error"] = "cancelled"
            return
        if (data["Error"] != "" && data["Error"] != "cancelled")
            Logger.Debug("Spotlight: " data["Error"])
        for entry in data["Entries"] {
            score := request.Expression["Needle"] = "" ? 75 : FileSearchProvider.NameScore(StrLower(request.Expression["Needle"]), entry["Name"])
            if (score <= 0)
                score := 45
            entries.Push({Path: entry["Path"], IsFolder: entry["IsFolder"], Score: score})
        }
        if MacSpotlight.Cache.Count >= 32
            MacSpotlight.Cache := Map()
        MacSpotlight.Cache[request.Key] := {At: A_TickCount, Entries: entries}
        MacSpotlight._key := "", MacSpotlight._request := ""
        SearchWindow.RefreshResults()
    }

    static Stop() {
        if IsObject(MacSpotlight._timer)
            SetTimer(MacSpotlight._timer, 0)
        if IsObject(MacSpotlight._pollTimer)
            SetTimer(MacSpotlight._pollTimer, 0)
        ALTRunSpotlightCancel()
        MacSpotlight._key := "", MacSpotlight._request := ""
    }
}

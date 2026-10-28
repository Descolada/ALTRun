#CSharp
private sealed record ALTRunImportedBookmark(string Title, string Url, string Browser);
private static System.Threading.Tasks.Task<string> ALTRunExtraBookmarkTask;
private static int ALTRunExtraBookmarkGeneration;

private static async System.Threading.Tasks.Task<string> ALTRunReadBookmarkText(System.IO.Stream Stream)
{
    using var reader = new System.IO.StreamReader(Stream, System.Text.Encoding.UTF8, true);
    var text = new System.Text.StringBuilder();
    char[] buffer = new char[8192];
    while (true)
    {
        int count = await reader.ReadAsync(buffer.AsMemory());
        if (count == 0) return text.ToString();
        if (text.Length + count > 10_000_000) throw new System.IO.InvalidDataException("Bookmark import is too large.");
        text.Append(buffer, 0, count);
    }
}

private static string ALTRunBookmarkTitle(string Html)
{
    var text = new System.Text.StringBuilder();
    bool tag = false;
    foreach (char character in Html)
    {
        if (character == '<') tag = true;
        else if (character == '>' && tag) tag = false;
        else if (!tag) text.Append(character);
    }
    return System.Net.WebUtility.HtmlDecode(text.ToString()).Trim();
}

private static ALTRunImportedBookmark[] ALTRunBookmarkHtml(string Text)
{
    var bookmarks = new System.Collections.Generic.List<ALTRunImportedBookmark>();
    foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(Text,
        "<a\\b[^>]*\\bhref\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')[^>]*>(.*?)</a\\s*>",
        System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline,
        System.TimeSpan.FromSeconds(2)))
    {
        string url = System.Net.WebUtility.HtmlDecode(match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value);
        if (!System.Uri.TryCreate(url, System.UriKind.Absolute, out var uri) || (uri.Scheme != "https" && uri.Scheme != "http")) continue;
        string title = ALTRunBookmarkTitle(match.Groups[3].Value);
        bookmarks.Add(new(title.Length == 0 ? url : title, url, "Imported"));
        if (bookmarks.Count >= 10000) break;
    }
    return bookmarks.ToArray();
}

private static ALTRunImportedBookmark[] ALTRunBookmarkPlist(string Text)
{
    var settings = new System.Xml.XmlReaderSettings { DtdProcessing = System.Xml.DtdProcessing.Ignore, XmlResolver = null, MaxCharactersInDocument = 10_000_000 };
    using var reader = System.Xml.XmlReader.Create(new System.IO.StringReader(Text), settings);
    var document = System.Xml.Linq.XDocument.Load(reader);
    var bookmarks = new System.Collections.Generic.List<ALTRunImportedBookmark>();
    System.Xml.Linq.XElement Value(System.Xml.Linq.XElement node, string key)
    {
        foreach (var entry in node.Elements()) if (entry.Name.LocalName == "key" && entry.Value == key) return System.Linq.Enumerable.FirstOrDefault(entry.ElementsAfterSelf());
        return null;
    }
    foreach (var node in System.Linq.Enumerable.Where(document.Descendants(), element => element.Name.LocalName == "dict"))
    {
        var url = Value(node, "URLString")?.Value ?? "";
        if (!System.Uri.TryCreate(url, System.UriKind.Absolute, out var uri) || (uri.Scheme != "https" && uri.Scheme != "http")) continue;
        var info = Value(node, "URIDictionary");
        string title = info == null ? "" : Value(info, "title")?.Value ?? "";
        if (title.Length == 0) title = Value(node, "Title")?.Value ?? url;
        bookmarks.Add(new(title, url, "Safari"));
        if (bookmarks.Count >= 10000) break;
    }
    return bookmarks.ToArray();
}

public static string ALTRunParseBookmarkImport(string Text, bool Plist)
    => System.Text.Json.JsonSerializer.Serialize(Plist ? ALTRunBookmarkPlist(Text) : ALTRunBookmarkHtml(Text));

public static long ALTRunExtraBookmarksStart(string Files)
{
    int generation = System.Threading.Interlocked.Increment(ref ALTRunExtraBookmarkGeneration);
    ALTRunExtraBookmarkTask = System.Threading.Tasks.Task.Run(async () => {
        var all = new System.Collections.Generic.List<ALTRunImportedBookmark>();
        var failed = new System.Collections.Generic.List<string>();
        foreach (var file in System.Text.Json.JsonSerializer.Deserialize<string[]>(Files) ?? [])
        {
            if (generation != ALTRunExtraBookmarkGeneration) break;
            try
            {
                if (new System.IO.FileInfo(file).Length > 10_000_000) throw new System.IO.InvalidDataException("Bookmark import is too large.");
                string extension = System.IO.Path.GetExtension(file).ToLowerInvariant();
                if (extension == ".plist" && System.OperatingSystem.IsMacOS())
                {
                    using var deadline = new System.Threading.CancellationTokenSource(5000);
                    using var process = new System.Diagnostics.Process { StartInfo = new System.Diagnostics.ProcessStartInfo("/usr/bin/plutil") {
                        UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
                        StandardOutputEncoding = System.Text.Encoding.UTF8, StandardErrorEncoding = System.Text.Encoding.UTF8
                    }};
                    foreach (var argument in new[] { "-convert", "xml1", "-o", "-", "--", file }) process.StartInfo.ArgumentList.Add(argument);
                    try
                    {
                        process.Start();
                        var output = ALTRunReadBookmarkText(process.StandardOutput.BaseStream);
                        var error = process.StandardError.ReadToEndAsync(deadline.Token);
                        await process.WaitForExitAsync(deadline.Token);
                        if (process.ExitCode != 0) throw new System.IO.IOException("Safari bookmarks could not be read.");
                        all.AddRange(ALTRunBookmarkPlist(await output));
                        await error;
                    }
                    finally { try { if (process.Id != 0 && !process.HasExited) process.Kill(true); } catch (System.InvalidOperationException) { } }
                }
                else if (extension is ".html" or ".htm")
                {
                    using var stream = System.IO.File.OpenRead(file);
                    all.AddRange(ALTRunBookmarkHtml(await ALTRunReadBookmarkText(stream)));
                }
                else if (extension == ".zip")
                {
                    using var archive = System.IO.Compression.ZipFile.OpenRead(file);
                    long expanded = 0;
                    foreach (var entry in archive.Entries)
                    {
                        if (entry.Length > 10_000_000 || !entry.Name.Contains("bookmark", System.StringComparison.OrdinalIgnoreCase)
                            || !(entry.Name.EndsWith(".html", System.StringComparison.OrdinalIgnoreCase) || entry.Name.EndsWith(".htm", System.StringComparison.OrdinalIgnoreCase))) continue;
                        expanded += entry.Length;
                        if (expanded > 20_000_000 || all.Count >= 20000) break;
                        using var stream = entry.Open();
                        all.AddRange(ALTRunBookmarkHtml(await ALTRunReadBookmarkText(stream)));
                    }
                }
            }
            catch (System.Exception) { failed.Add(file); }
            if (all.Count >= 20000) break;
        }
        return System.Text.Json.JsonSerializer.Serialize(new { Generation = generation, Entries = all, Failed = failed });
    });
    return generation;
}
public static string ALTRunExtraBookmarksPoll() => ALTRunExtraBookmarkTask is { IsCompletedSuccessfully: true } task ? task.Result : "";
#EndCSharp

;===============================================================================
; BookmarkProvider.ahk - browser bookmarks (AutoHotkey v2)
;-------------------------------------------------------------------------------
; Like Alfred's Web Bookmarks: typing a bookmark's name finds it (InDefaultResults, after applications and commands),
; "bm word" (Keyword) searches bookmarks only. Enter opens in the default browser, Alt+Enter copies the URL.
; Reads the Bookmarks file (JSON) of every profile (Default, Profile 1...) of Chromium browsers (Chrome, Edge, Brave, Vivaldi).
; Firefox keeps its bookmarks in an SQLite database, which can't be read.
; Read once at start-up; then every 30 s a background check whether the files changed (modified time) reads them again (not while typing; one read takes 20 ~ 30 ms).
;
; Settings (ALTRun.json -> Features.Bookmarks): Enabled / Keyword / InDefaultResults
;===============================================================================

class BookmarkProvider {
    static ExtraItems := [], _extraStamp := "", _extraTimer := "", _extraRequestedStamp := "", _extraNextTry := 0, _extraPending := "", _extraGeneration := 0
    static Id := "Bookmarks"
    static Items := []                                                      ; [{Title, Url, Key, Browser}]
    static _stamp := "", _checked := 0
    static Browsers := [["Chrome", "Google\Chrome\User Data"], ["Edge", "Microsoft\Edge\User Data"]
                      , ["Brave", "BraveSoftware\Brave-Browser\User Data"], ["Vivaldi", "Vivaldi\User Data"]]

    static Init() {
        BookmarkProvider.Load()
        SetTimer(Logger.Watch("bookmarks refresh", () => BookmarkProvider._RefreshIfChanged()), 30000)         ; check the bookmark files in the background, not during searches while typing
    }

    static Search(query) {
        options := AppSettings.Feature("Bookmarks")
        exclusive := false, term := query.Text, keyword := ""
        if query.MatchKeyword([options["Keyword"]], &rest, &keyword) {
            if !query.HasRest                                               ; "bm" alone: the keyword's hint, Enter completes "bm "
                return [ResultItem.KeywordHint(I18n.T("Bookmarks.Keyword"), keyword, "url:")]
            term := rest, exclusive := true
        } else if !options["InDefaultResults"] || StrLen(query.Text) < 2 {
            return []
        }
        if !BookmarkProvider._checked                                       ; bookmarks were off at start-up and switched on later
            BookmarkProvider.Init()
        needle := StrLower(Trim(term))
        results := []
        if (needle = "")
            return results
        scores := Map()
        for index, bookmark in BookmarkProvider.Items
            if ((score := FuzzyMatcher.BestKey(needle, bookmark.Keys)) > 0)
                scores[index] := score
        for index in FuzzyMatcher.TopIndexes(scores, exclusive ? ProviderRegistry.MaxResults : 8) {
            bookmark := BookmarkProvider.Items[index]
            results.Push(ResultItem(bookmark.Title, bookmark.Url, {
                Kind: "url", Arg: bookmark.Url, Icon: "url:", Uid: "bookmark:" bookmark.Url,
                Score: scores[index] - (exclusive ? 0 : 12), Exclusive: exclusive     ; in the default results after applications and commands
            }))
        }
        return results
    }

    ; The Bookmarks files of every profile of every browser
    static Files() {
        files := []
        for browser in BookmarkProvider.BrowserRoots() {
            root := browser[2]
            if !DirExist(root)
                continue
            Loop Files, Platform.Join(root, "*"), "D"
                if FileExist(file := Platform.Join(A_LoopFileFullPath, "Bookmarks"))
                    files.Push([browser[1], file])
        }
        return files
    }

    static BrowserRoots() {
        roots := []
        if Platform.IsWindows {
            base := EnvGet("LOCALAPPDATA")
            if (base != "")
                for browser in BookmarkProvider.Browsers
                    roots.Push([browser[1], Platform.Join(base, browser[2])])
            return roots
        }
        if Platform.IsMac {
            base := Platform.Join(Platform.Home, "Library", "Application Support")
            browsers := [["Chrome", "Google/Chrome"], ["Edge", "Microsoft Edge"], ["Brave", "BraveSoftware/Brave-Browser"], ["Vivaldi", "Vivaldi"]]
        } else {
            base := EnvGet("XDG_CONFIG_HOME")
            if (SubStr(base, 1, 1) != "/")
                base := Platform.Join(Platform.Home, ".config")
            browsers := [["Chrome", "google-chrome"], ["Chromium", "chromium"], ["Edge", "microsoft-edge"], ["Brave", "BraveSoftware/Brave-Browser"], ["Vivaldi", "vivaldi"]]
        }
        for browser in browsers
            roots.Push([browser[1], Platform.Join(base, browser[2])])
        return roots
    }

    static Load() {
        items := [], seen := Map(), stamp := ""
        seen.CaseSense := "On"
        for bookmarkFile in BookmarkProvider.Files() {
            try {
                fileStamp := bookmarkFile[2] FileGetTime(bookmarkFile[2], "M") "|"
                for bookmark in BookmarkProvider.ParseFile(FileRead(bookmarkFile[2], "UTF-8"))
                    if !seen.Has(bookmark.Url) {                            ; a bookmark several browsers have is kept once
                        seen[bookmark.Url] := true
                        bookmark.Browser := bookmarkFile[1]
                        items.Push(bookmark)
                    }
                stamp .= fileStamp                                          ; noted only after a successful read: reading fails while the browser is writing the file, so read again next time
            } catch as e {
                Logger.Error("BookmarkProvider: " bookmarkFile[2] " - " e.Message)
            }
        }
        extraFiles := BookmarkProvider.ExtraFiles()
        extraStamp := ""
        for file in extraFiles
            try extraStamp .= file FileGetTime(file, "M") "|"
        if !(extraStamp == BookmarkProvider._extraStamp) && A_TickCount >= BookmarkProvider._extraNextTry {
            BookmarkProvider._extraRequestedStamp := extraStamp, BookmarkProvider._extraNextTry := 0, BookmarkProvider._extraPending := ""
            BookmarkProvider._extraGeneration := ALTRunExtraBookmarksStart(JSON.Stringify(extraFiles))
            if !IsObject(BookmarkProvider._extraTimer)
                BookmarkProvider._extraTimer := () => BookmarkProvider._PollExtra()
            SetTimer(BookmarkProvider._extraTimer, 200)
        }
        for bookmark in BookmarkProvider.ExtraItems
            if !seen.Has(bookmark.Url) {
                seen[bookmark.Url] := true
                items.Push(bookmark)
            }
        BookmarkProvider.Items := items, BookmarkProvider._stamp := stamp extraStamp, BookmarkProvider._checked := A_TickCount
        Logger.Debug("BookmarkProvider: " items.Length " bookmarks")
    }

    static ExtraFiles() {
        options := AppSettings.Feature("Bookmarks"), files := []
        if Platform.IsMac && options.Has("Safari") && options["Safari"] {
            safariFile := Platform.Join(Platform.Home, "Library", "Safari", "Bookmarks.plist")
            if FileExist(safariFile)
                files.Push(safariFile)
        }
        if options.Has("Imports")
            for importFile in options["Imports"]
                if FileExist(file := Path.Resolve(importFile))
                    files.Push(file)
        return files
    }

    static _PollExtra() {
        if !BackgroundWork.CanRun()
            return
        if !IsObject(BookmarkProvider._extraPending) {
            result := ALTRunExtraBookmarksPoll()
            if result = ""
                return
            data := JSON.Parse(result)
            if data["Generation"] != BookmarkProvider._extraGeneration
                return
            BookmarkProvider._extraPending := {Data: data, Index: 1, Items: []}
        }
        pending := BookmarkProvider._extraPending, started := Logger.Ms(), processed := 0
        while pending.Index <= pending.Data["Entries"].Length {
            entry := pending.Data["Entries"][pending.Index++]
            title := entry["Title"], url := entry["Url"]
            host := RegExReplace(url, "i)^https?://(www\.)?([^/:?#]+).*$", "$2")
            pending.Items.Push({Title: title, Url: url, Browser: entry["Browser"], Keys: [FuzzyMatcher.Key(title), FuzzyMatcher.Key(host), FuzzyMatcher.Key(Pinyin.Initials(title))]})
            processed++
            if processed >= 100 || Logger.Ms() - started >= 8
                return
        }
        SetTimer(BookmarkProvider._extraTimer, 0)
        BookmarkProvider.ExtraItems := pending.Items
        if pending.Data["Failed"].Length {
            BookmarkProvider._extraNextTry := A_TickCount + 30000
            Logger.Debug("Bookmarks: " pending.Data["Failed"].Length " import(s) could not be read; retrying while idle.")
        } else
            BookmarkProvider._extraStamp := BookmarkProvider._extraRequestedStamp
        BookmarkProvider._extraPending := ""
        BookmarkProvider.Load()
    }

    ; Bookmarks file (JSON) -> [{Title, Url, Keys}], only http / https URLs
    static ParseFile(text) {
        data := JSON.Parse(text)
        list := []
        if (data is Map && data.Has("roots") && data["roots"] is Map)
            for name, root in data["roots"]
                BookmarkProvider._Walk(root, list)
        return list
    }

    static _Walk(node, list) {
        if !(node is Map)
            return
        if (node.Has("type") && node["type"] = "url" && node.Has("url") && RegExMatch(node["url"], "i)^https?://")) {
            title := (node.Has("name") && node["name"] != "") ? node["name"] : node["url"]
            host := RegExReplace(node["url"], "i)^https?://(www\.)?([^/:?#]+).*$", "$2")
            pinyinText := Pinyin.Initials(title)
            list.Push({Title: title, Url: node["url"], Keys: [FuzzyMatcher.Key(title), FuzzyMatcher.Key(host), (pinyinText != title) ? FuzzyMatcher.Key(pinyinText) : ""]})
            return
        }
        if (node.Has("children") && node["children"] is Array)
            for child in node["children"]
                BookmarkProvider._Walk(child, list)
    }

    static _RefreshIfChanged() {
        if (!BackgroundWork.CanRun() || A_TickCount - BookmarkProvider._checked < 25000 || !ProviderRegistry.IsEnabled(BookmarkProvider))
            return
        BookmarkProvider._checked := A_TickCount
        stamp := ""
        for bookmarkFile in BookmarkProvider.Files()
            try stamp .= bookmarkFile[2] FileGetTime(bookmarkFile[2], "M") "|"
        for file in BookmarkProvider.ExtraFiles()
            try stamp .= file FileGetTime(file, "M") "|"
        if !(stamp == BookmarkProvider._stamp) || (BookmarkProvider._extraNextTry && A_TickCount >= BookmarkProvider._extraNextTry)
            BookmarkProvider.Load()
    }
}

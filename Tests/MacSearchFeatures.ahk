#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

#CSharp
public static object ALTRunBookmarkZipFixture(string Filename, string Html)
{
    using var stream = System.IO.File.Create(Filename);
    using var archive = new System.IO.Compression.ZipArchive(stream, System.IO.Compression.ZipArchiveMode.Create);
    using (var writer = new System.IO.StreamWriter(archive.CreateEntry("Bookmarks.html").Open())) writer.Write(Html);
    using (var writer = new System.IO.StreamWriter(archive.CreateEntry("passwords.csv").Open())) writer.Write("<a href=\"https://must-not-import.test\">Wrong entry</a>");
    return null;
}
#EndCSharp

OnError((error, mode) => MacSearchFeatures.Fail(error.Message "`n" error.Stack))
OnExit((*) => MacSearchFeatures.CleanUp())
SetTimer(() => MacSearchFeatures.Fail("Timed out."), -30000)
MacSearchFeatures.Run()

class MacSearchFeatures {
    static Folder := ""
    static Check(condition, message) {
        if !condition
            throw Error(message)
    }
    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_SEARCH_FEATURES requires macOS`n", "*")
            ExitApp()
        }
        AppSettings.Data := AppSettings.Defaults()
        Logger.Enabled := false
        MacSearchFeatures.Folder := Platform.Join(A_Temp, "ALTRun-search-" Platform.NewUuid())
        DirCreate(MacSearchFeatures.Folder)
        MacSearchFeatures.Expressions()
        MacSearchFeatures.Bookmarks()
        MacSearchFeatures.Shortcuts()
        MacSearchFeatures.Updates()
        MacSearchFeatures.Scripts()
        MacSearchFeatures.NativeSearch()
        MacSearchFeatures.Ocr()
        FileAppend("PASS MAC_SEARCH_FEATURES query escaping and filters, bookmark formats, Shortcuts identifiers and input, native scripts, async Spotlight cancellation and local Vision OCR`n", "*")
        ExitApp()
    }
    static Expressions() {
        expression := MacSpotlight.Expression('budget tag:"Work Projects" kind:pdf modified:2026-01-01')
        MacSearchFeatures.Check(expression["Metadata"] && expression["Needle"] = "budget", "Metadata filters must leave the filename needle intact.")
        for part in ["kMDItemUserTags", "Work Projects", "com.adobe.pdf", "kMDItemFSContentChangeDate", "$time.iso("]
            MacSearchFeatures.Check(InStr(expression["Query"], part), "Missing Spotlight predicate: " part)
        injection := MacSpotlight.Expression('x`" || kMDItemFSName == `"*')
        MacSearchFeatures.Check(InStr(injection["Query"], '\"') && InStr(injection["Query"], '\*'), "Spotlight literals must escape quotes and wildcard characters.")
        filter := FileSearchProvider.ParseTypeFilter("doc = pdf docx")
        typed := MacSpotlight.Expression("budget", filter)
        MacSearchFeatures.Check(InStr(typed["Query"], "*.pdf") && InStr(typed["Query"], "*.docx"), "Type filter extensions must reach Spotlight.")
        MacSearchFeatures.Check(InStr(MacSpotlight.Expression("budget", true)["Query"], "public.folder"), "Folder-only Spotlight queries must preserve scope.")
    }
    static Bookmarks() {
        html := '<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><DT><A HREF="https://example.test/?a=1&amp;b=2">Work &amp; Notes</A><DT><A HREF="javascript:alert(1)">Ignore</A></DL>'
        parsed := JSON.Parse(ALTRunParseBookmarkImport(html, false))
        MacSearchFeatures.Check(parsed.Length = 1 && parsed[1]["Title"] = "Work & Notes" && parsed[1]["Url"] = "https://example.test/?a=1&b=2", "HTML bookmark import must decode entities and reject executable schemes.")
        plist := '<?xml version="1.0"?><plist><dict><key>Children</key><array><dict><key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string><key>URLString</key><string>https://example.test/safari</string><key>URIDictionary</key><dict><key>title</key><string>Safari 漢字</string></dict></dict></array></dict></plist>'
        parsed := JSON.Parse(ALTRunParseBookmarkImport(plist, true))
        MacSearchFeatures.Check(parsed.Length = 1 && parsed[1]["Title"] = "Safari 漢字" && parsed[1]["Browser"] = "Safari", "Safari nested plist bookmarks must preserve titles.")
        binary := Platform.Join(MacSearchFeatures.Folder, "Bookmarks.plist")
        FileAppend(plist, binary, "UTF-8-RAW")
        job := ProcessRunner.Start("/usr/bin/plutil", ["-convert", "binary1", binary], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        MacSearchFeatures.Check(ProcessRunner.Result(job)["ExitCode"] = 0, "Could not prepare binary Safari fixture.")
        ALTRunExtraBookmarksStart(JSON.Stringify([binary]))
        started := A_TickCount
        while (output := ALTRunExtraBookmarksPoll()) = "" && A_TickCount - started < 6000
            Sleep(10)
        MacSearchFeatures.Check(output != "" && JSON.Parse(output)["Entries"].Length = 1 && !JSON.Parse(output)["Failed"].Length, "Background Safari conversion must support binary plists.")
        zipped := Platform.Join(MacSearchFeatures.Folder, "Safari.zip")
        ALTRunBookmarkZipFixture(zipped, html)
        ALTRunExtraBookmarksStart(JSON.Stringify([zipped]))
        started := A_TickCount
        while (output := ALTRunExtraBookmarksPoll()) = "" && A_TickCount - started < 6000
            Sleep(10)
        MacSearchFeatures.Check(output != "" && JSON.Parse(output)["Entries"].Length = 1, "Safari ZIP imports must read only bookmark HTML, never other exported data.")
        broken := Platform.Join(MacSearchFeatures.Folder, "Broken.plist")
        FileAppend("not a property list", broken, "UTF-8-RAW")
        ALTRunExtraBookmarksStart(JSON.Stringify([broken]))
        started := A_TickCount
        while (output := ALTRunExtraBookmarksPoll()) = "" && A_TickCount - started < 6000
            Sleep(10)
        MacSearchFeatures.Check(output != "" && JSON.Parse(output)["Failed"].Length = 1, "Failed Safari reads must be reported so permission changes can be retried.")
    }
    static Shortcuts() {
        id := "01234567-89ab-cdef-0123-456789abcdef"
        parsed := ShortcutsProvider.Parse("Work (draft) (" id ")`nUntrusted error output`nDuplicate (" id ")")
        MacSearchFeatures.Check(parsed.Length = 1 && parsed[1].Name = "Work (draft)", "Shortcut names may contain parentheses; errors and duplicates are excluded.")
        ShortcutsProvider.Items := parsed
        found := ShortcutsProvider.Search(SearchQuery("shortcut work"))
        MacSearchFeatures.Check(found.Length = 1 && found[1].Exclusive && found[1].Uid = "shortcut:" id, "Shortcut keyword mode must return stable identified results.")
        input := Platform.Join(MacSearchFeatures.Folder, "private-input.txt")
        ALTRunShortcutInput(input, "private literal $() ' 漢字`nsecond line")
        MacSearchFeatures.Check(FileRead(input, "UTF-8") = "private literal $() ' 漢字`nsecond line", "Shortcut input must preserve literal content.")
        permissions := Clr.System.IO.File.GetUnixFileMode(input).ToString()
        MacSearchFeatures.Check(!InStr(permissions, "Other") && !InStr(permissions, "Group"), "Shortcut input must be private from creation.")
    }
    static Scripts() {
        for ext in ["command", "applescript", "jxa", "scpt"] {
            path := Platform.Join(MacSearchFeatures.Folder, "literal ' $() 漢字." ext)
            FileAppend(ext = "command" ? "#!/bin/zsh -f`n# @altrun.title Native Shell`n" : "-- @altrun.title Native Script`nreturn 1`n", path, "UTF-8-RAW")
            script := ScriptProvider.ReadScript(path), spec := ScriptProvider._Spec(script, "one argument ' $()")
            MacSearchFeatures.Check(spec.Arguments[spec.Arguments.Length] = "one argument ' $()", "Native scripts must preserve one literal argument.")
            MacSearchFeatures.Check(ext = "command" ? spec.Executable = "/bin/zsh" : spec.Executable = "/usr/bin/osascript", "Native script interpreter is wrong: " ext)
            if ext = "jxa"
                MacSearchFeatures.Check(spec.Arguments[1] = "-l" && spec.Arguments[2] = "JavaScript", "JXA must select JavaScript explicitly.")
            if ext = "applescript"
                MacSearchFeatures.Check(script.Title = "Native Script", "AppleScript -- metadata comments must be recognized.")
        }
        job := ProcessRunner.Start("/bin/sh", ["-c", "printf output; printf problem >&2; exit 7"], "", true)
        while !ProcessRunner.IsFinished(job)
            Sleep(10)
        result := ProcessRunner.Result(job)
        MacSearchFeatures.Check(result["ExitCode"] = 7 && result["Output"] = "output" && result["Error"] = "problem", "Structured process results must separate errors and preserve exit status.")
    }
    static Updates() {
        AppSettings.General["UpdateRepository"] := "invalid/../repository"
        UpdateChecker.Configure()
        MacSearchFeatures.Check(AppSettings.General["UpdateRepository"] = "Descolada/ALTRun", "Invalid update repositories must use the macOS channel.")
        digest := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        base := "https://github.com/Descolada/ALTRun/releases/download/v9999.0/"
        name := "ALTRun_v9999.0_macos-" ALTRunMacArchitecture() ".zip"
        assets := [Map("name", "ALTRun_v9999.0.zip", "browser_download_url", base "ALTRun_v9999.0.zip", "digest", "sha256:" digest)
            , Map("name", name, "browser_download_url", base name, "digest", "sha256:" digest)]
        document := Map("tag_name", "v9999.0", "assets", assets)
        release := UpdateChecker.ParseRelease(JSON.Stringify(document))
        MacSearchFeatures.Check(release.ZipUrl = base name && release.Sha256 = digest, "macOS must choose its architecture-specific asset instead of the Windows package.")
        assets[2]["browser_download_url"] := "https://example.test/" name
        release := UpdateChecker.ParseRelease(JSON.Stringify(document))
        MacSearchFeatures.Check(release.ZipUrl = "" && !UpdateChecker.CanInstall(release), "Untrusted package URLs and source auto-install must be rejected.")
    }
    static NativeSearch() {
        first := MacSpotlight.Expression("ALTRunNoSuchFirst"), last := MacSpotlight.Expression("ALTRunNoSuchSecond")
        started := Logger.Ms()
        ALTRunSpotlightStart(first["Query"], MacSearchFeatures.Folder, 20, 1)
        ALTRunSpotlightStart(last["Query"], MacSearchFeatures.Folder, 20, 2)
        ALTRunSpotlightStart(first["Query"], MacSearchFeatures.Folder, 20, 3)
        MacSearchFeatures.Check(Logger.Ms() - started < 100, "Spotlight startup must not wait for the search process.")
        deadline := A_TickCount
        while (output := ALTRunSpotlightPoll()) = "" && A_TickCount - deadline < 7000
            Sleep(10)
        MacSearchFeatures.Check(output != "", "Native Spotlight query did not complete.")
        result := JSON.Parse(output)
        MacSearchFeatures.Check(result["Id"] = 3 && result["Key"] = first["Query"] && result["Error"] = "", "An A/B/A search sequence must complete only the latest request, without syntax errors.")
    }
    static Ocr() {
        file := Platform.Join(MacSearchFeatures.Folder, "ocr.png")
        canvas := Image.Create(900, 180, "0xFFFFFFFF")
        try {
            canvas.DrawText("ALTRUN OCR 12345", 35, 50, "0xFF000000", "s42", "Helvetica")
            canvas.Save(file)
        } finally canvas.Dispose()
        ALTRunVisionStart(file)
        started := A_TickCount
        while (text := ALTRunVisionPoll()) = "" && A_TickCount - started < 12000
            Sleep(20)
        MacSearchFeatures.Check(text != "", "Vision OCR did not finish.")
        result := JSON.Parse(text)
        MacSearchFeatures.Check(result["Error"] = "" && InStr(result["Text"], "12345"), "Vision must recognize locally generated text: " result["Error"] " " result["Text"])
        privateFile := ALTRunOcrTemporaryFile(), directory := ActionCatalog.ParentDir(privateFile)
        try {
            permissions := Clr.System.IO.File.GetUnixFileMode(directory).ToString()
            MacSearchFeatures.Check(!InStr(permissions, "Other") && !InStr(permissions, "Group"), "Clipboard OCR staging must be private even if an image encoder replaces its file.")
        } finally ALTRunOcrDeleteTemporary(privateFile)
        MacSearchFeatures.Check(!DirExist(directory), "OCR temporary directories must be removed after use.")
    }
    static CleanUp() {
        ALTRunSpotlightCancel()
        ProcessRunner.CancelAll()
        if MacSearchFeatures.Folder != ""
            try DirDelete(MacSearchFeatures.Folder, true)
    }
    static Fail(message) {
        FileAppend("FAIL MAC_SEARCH_FEATURES " message "`n", "**")
        ExitApp(1)
    }
}

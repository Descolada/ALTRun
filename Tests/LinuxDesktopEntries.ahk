; LinuxDesktopEntries.ahk - Isolated desktop parsing, XDG indexing, icons and storage checks; no programs are launched.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => LinuxDesktopEntries.Failed(err.Message "`n" err.Stack))
OnExit((*) => LinuxDesktopEntries.CleanUp())
SetTimer(() => LinuxDesktopEntries.Failed("Timed out after 20 seconds."), -20000)
LinuxDesktopEntries.Run()

class LinuxDesktopEntries {
    static Folder := "", Environment := Map()

    static Check(condition, message) {
        if !condition
            throw Error(message)
    }

    static Write(relative, text) {
        filename := Platform.Join(LinuxDesktopEntries.Folder, relative)
        SplitPath(filename, , &directory)
        DirCreate(directory)
        FileAppend(text, filename, "UTF-8-RAW")
        return filename
    }

    static SetEnvironment(name, value) {
        if !LinuxDesktopEntries.Environment.Has(name)
            LinuxDesktopEntries.Environment[name] := EnvGet(name)
        EnvSet(name, value)
    }

    static Run() {
        LinuxDesktopEntries.Folder := Platform.Join(A_Temp, "ALTRun-LinuxDesktop-" Platform.NewUuid())
        DirCreate(LinuxDesktopEntries.Folder)
        LinuxDesktopEntries.Parsing()
        if Platform.IsLinux {
            AppSettings.Portable := false
            AppSettings.UserDir := LinuxDesktopEntries.Folder
            AppSettings.DataDir := Platform.Join(LinuxDesktopEntries.Folder, "Data")
            DirCreate(AppSettings.DataDir)
            AppSettings.File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
            AppSettings.Data := AppSettings.Defaults()
            ApplicationProvider.IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
            Logger.Enabled := false
            LinuxDesktopEntries.Icons()
            LinuxDesktopEntries.Indexing()
            LinuxDesktopEntries.Storage()
            LinuxDesktopEntries.ScriptInterpreters()
        }
        FileAppend("PASS LINUX_DESKTOP_ENTRIES`n", "*")
        ExitApp(0)
    }

    static Parsing() {
        filename := LinuxDesktopEntries.Write("Fixtures/localized.desktop", "[Desktop Entry]`nType=Application`nName=Base`nName[sr]=Language`nName[sr@latin]=Modifier`nName[sr_RS]=Territory`nName[sr_RS@latin]=Exact`n"
            . "GenericName=Editor`nGenericName[sr_RS@latin]=Localized Editor`nKeywords=write;edit;`nOnlyShowIn=GNOME;`nNotShowIn=KDE;`n"
            . 'Exec=/usr/bin/tool "C:\\\\temp" "\\$HOME" "" %d --title=%c %F' "`n")
        entry := JSON.Parse(ALTRunDesktopRead(filename, "sr_RS.UTF-8@latin", "GNOME:Unity"))
        LinuxDesktopEntries.Check(entry["Name"] == "Exact" && entry["GenericName"] == "Localized Editor", "POSIX locale modifiers must select localized names and generic names.")
        LinuxDesktopEntries.Check(InStr(entry["Keywords"], "write") && InStr(entry["Keywords"], "edit"), "Desktop keywords must be available for searching.")
        spec := ProcessRunner.DesktopCommand(entry, filename)
        expected := ["C:\temp", "$HOME", "", "--title=Exact"]
        LinuxDesktopEntries.Check(spec.Executable == "/usr/bin/tool" && spec.Arguments.Length = expected.Length, "Exec must preserve argument boundaries and remove unused file codes.")
        for index, value in expected
            LinuxDesktopEntries.Check(spec.Arguments[index] == value, "Exec literal argument " index " was changed.")
        LinuxDesktopEntries.Check(JSON.Parse(ALTRunDesktopRead(filename, "sr_BA@latin", "GNOME"))["Name"] == "Modifier", "Locale fallback must preserve a modifier without a matching territory.")
        LinuxDesktopEntries.Check(JSON.Parse(ALTRunDesktopRead(filename, "sr_RS@other", "GNOME"))["Name"] == "Territory", "Territory fallback must precede language fallback.")
        LinuxDesktopEntries.Check(JSON.Parse(ALTRunDesktopRead(filename, "en", "GNOME:KDE")).Count = 0, "NotShowIn must filter any matching desktop.")
        invalid := false
        try ALTRunDesktopCommand("tool %Z", filename, "Name", "")
        catch
            invalid := true
        LinuxDesktopEntries.Check(invalid, "Unknown Exec field codes must be rejected.")
    }

    static Icons() {
        data := Platform.Join(LinuxDesktopEntries.Folder, "XdgData")
        config := Platform.Join(LinuxDesktopEntries.Folder, "XdgConfig")
        LinuxDesktopEntries.SetEnvironment("XDG_DATA_HOME", data)
        LinuxDesktopEntries.SetEnvironment("XDG_DATA_DIRS", Platform.Join(LinuxDesktopEntries.Folder, "SystemData"))
        LinuxDesktopEntries.SetEnvironment("XDG_CONFIG_HOME", config)
        LinuxDesktopEntries.Write("XdgConfig/gtk-3.0/settings.ini", "[Settings]`ngtk-icon-theme-name=ALTRunTest`n")
        LinuxDesktopEntries.Write("XdgData/icons/ALTRunTest/index.theme", "[Icon Theme]`nName=ALTRunTest`nInherits=ALTRunBase`n")
        iconName := "org.altrun.Test." Platform.NewUuid()
        icon := LinuxDesktopEntries.Write("XdgData/icons/ALTRunBase/32x32/apps/" iconName ".png", "fixture")
        LinuxDesktopEntries.Check(ProcessRunner.DesktopIcon(iconName) == icon, "Dotted desktop icon names must resolve through a GTK theme's inherited XDG theme.")
        LinuxDesktopEntries.Check(ProcessRunner.DesktopIcon(icon) == icon, "Absolute desktop icon paths must remain literal.")
        iconName := "org.altrun.Pixmap." Platform.NewUuid()
        pixmap := LinuxDesktopEntries.Write("XdgData/pixmaps/" iconName ".png", "fixture")
        LinuxDesktopEntries.Check(ProcessRunner.DesktopIcon(iconName) == pixmap, "XDG pixmaps must be used when a themed icon is absent.")
    }

    static Indexing() {
        user := Platform.Join(LinuxDesktopEntries.Folder, "ApplicationsUser")
        system := Platform.Join(LinuxDesktopEntries.Folder, "ApplicationsSystem")
        target := LinuxDesktopEntries.Write("ApplicationsUser/org/tool.desktop", "[Desktop Entry]`nType=Application`nName=User Override`nGenericName=Editor`nKeywords=writing;manuscript;`nExec=sh`n")
        LinuxDesktopEntries.Write("ApplicationsSystem/org-tool.desktop", "[Desktop Entry]`nType=Application`nName=System Entry`nExec=sh`n")
        LinuxDesktopEntries.Write("ApplicationsUser/org/masked.desktop", "[Desktop Entry]`nHidden=true`n")
        LinuxDesktopEntries.Write("ApplicationsSystem/org-masked.desktop", "[Desktop Entry]`nType=Application`nName=Masked Entry`nExec=sh`n")
        for name in ["Case", "case"]
            LinuxDesktopEntries.Write("ApplicationsUser/" name ".desktop", "[Desktop Entry]`nType=Application`nName=" name "`nExec=sh`n")
        options := AppSettings.Feature("Applications")
        options["Folders"] := [user, system], options["FileTypes"] := ["*.desktop"], options["StoreApps"] := 0
        options["Depth"] := 2, options["Exclude"] := "", options["MatchPinyin"] := 0
        LinuxDesktopEntries.Check(ApplicationProvider.Rebuild() = 3, "Nested desktop IDs must preserve user masking, root precedence and case-sensitive IDs.")
        for term in ["editor", "manuscript"] {
            matches := ApplicationProvider.Search(SearchQuery(term))
            LinuxDesktopEntries.Check(matches.Length = 1 && matches[1].Arg == target, "Desktop generic names and keywords must find the application.")
        }
    }

    static Storage() {
        data := Platform.Join(LinuxDesktopEntries.Folder, "StorageData")
        localDir := Platform.Join(LinuxDesktopEntries.Folder, "StorageLocal")
        LinuxDesktopEntries.Write("StorageData/ClipboardHistory.json", '{"Entries":[]}')
        LinuxDesktopEntries.Write("StorageData/Clipboard/long.txt", "history")
        ClipboardProvider.PlaceStorage(2, data, localDir)
        LinuxDesktopEntries.Check(ClipboardProvider.File == Platform.Join(localDir, "ClipboardHistory.json") && FileExist(ClipboardProvider.File), "Private history storage must move JSON using native paths.")
        LinuxDesktopEntries.Check(ClipboardProvider.Folder == Platform.Join(localDir, "Clipboard") && FileExist(Platform.Join(ClipboardProvider.Folder, "long.txt")), "Private history storage must move attachments using native paths.")
        ClipboardProvider.PlaceStorage(0, data, localDir)
        LinuxDesktopEntries.Check(FileExist(Platform.Join(data, "ClipboardHistory.json")) && FileExist(Platform.Join(data, "Clipboard", "long.txt")), "Disabling local storage must restore history and attachments to Data.")
    }

    static ScriptInterpreters() {
        env := Platform.FindExecutable("env")
        if env = ""
            return
        filename := LinuxDesktopEntries.Write("Fixtures/interpreter.py", "#!" env " -S python3 -u`nprint('example')`n")
        spec := ScriptProvider._Spec({Path: filename, Ext: "py"}, "spaces % literal")
        LinuxDesktopEntries.Check(spec.Executable == env && spec.Arguments.Length = 3, "Script shebangs must select their own interpreter without a shell.")
        LinuxDesktopEntries.Check(spec.Arguments[1] == "-S python3 -u" && spec.Arguments[2] == filename && spec.Arguments[3] == "spaces % literal", "Shebang optional arguments and user arguments must preserve kernel argument boundaries.")
    }

    static CleanUp() {
        for name, value in LinuxDesktopEntries.Environment
            try EnvSet(name, value)
        try {
            if LinuxDesktopEntries.Folder != "" && InStr(LinuxDesktopEntries.Folder, Platform.Join(A_Temp, "ALTRun-LinuxDesktop-")) = 1 && DirExist(LinuxDesktopEntries.Folder)
                DirDelete(LinuxDesktopEntries.Folder, true)
        }
    }

    static Failed(message) {
        FileAppend("FAIL LINUX_DESKTOP_ENTRIES " message "`n", "**")
        ExitApp(1)
        return true
    }
}

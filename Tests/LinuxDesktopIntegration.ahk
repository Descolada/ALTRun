; Isolated XDG autostart and recent-document checks; never changes the desktop's real configuration.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((error, mode) => DesktopIntegrationTest.Fail(error))
OnExit((*) => DesktopIntegrationTest.CleanUp())
SetTimer(() => DesktopIntegrationTest.Fail(Error("Desktop integration check timed out.")), -15000)
DesktopIntegrationTest.Run()

class DesktopIntegrationTest {
    static Folder := ""

    static Assert(value, message) {
        if !value
            throw Error(message)
    }

    static Run() {
        DesktopIntegrationTest.Folder := Platform.Join(A_Temp, "ALTRun-DesktopIntegration-" Platform.NewUuid())
        folder := DesktopIntegrationTest.Folder
        DirCreate(folder)
        if Platform.IsLinux {
            AppSettings.Data := AppSettings.Defaults()
            I18n.Init("en")
            report := App.SystemInfo()
            DesktopIntegrationTest.Assert(InStr(report, "OS: ") && InStr(report, "Runtime: .NET"), "Portable system information was not available.")
        }
        executable := Platform.Join(folder, "Keysharp $percent%.exe")
        script := Platform.Join(folder, "汉字 launcher%.ahk")
        arguments := ["--errorstdout", script, "-Startup", "dollar$ and percent%"]
        config := Platform.Join(folder, "config")
        DesktopIntegrationTest.Assert(ALTRunAutostartSet(config, true, executable, JSON.Stringify(arguments), script, ""), "Autostart was not created.")
        file := Platform.Join(config, "autostart", "org.keysharp.ALTRun.desktop")
        text := FileRead(file, "UTF-8")
        DesktopIntegrationTest.Assert(InStr(text, "Terminal=false") && InStr(text, "X-ALTRun-Source="), "Autostart metadata is missing.")
        entry := ProcessRunner.DesktopEntry(file)
        DesktopIntegrationTest.Assert(IsObject(entry), "The autostart desktop entry could not be parsed.")
        command := ProcessRunner.DesktopCommand(entry, file)
        DesktopIntegrationTest.Assert(command.Executable == executable, "Autostart executable escaping did not round trip.")
        DesktopIntegrationTest.Assert(command.Arguments.Length = arguments.Length, "Autostart arguments changed count.")
        for argument in arguments
            DesktopIntegrationTest.Assert(command.Arguments[A_Index] == argument, "Autostart argument escaping did not round trip.")
        DesktopIntegrationTest.Assert(ALTRunAutostartSet(config, true, executable, JSON.Stringify(arguments), script, ""), "Autostart update failed.")
        DesktopIntegrationTest.Assert(FileRead(file, "UTF-8") == text, "An unchanged autostart entry was rewritten differently.")
        DesktopIntegrationTest.Assert(ALTRunAutostartSet(config, false, executable, "[]", script, "") && !FileExist(file), "Owned autostart was not removed.")
        FileAppend("[Desktop Entry]`nName=User entry`n", file, "UTF-8-RAW")
        DesktopIntegrationTest.Assert(!ALTRunAutostartSet(config, true, executable, "[]", script, ""), "An unrelated autostart entry was overwritten.")
        DesktopIntegrationTest.Assert(!ALTRunAutostartSet(config, false, executable, "[]", script, "") && FileExist(file), "An unrelated autostart entry was removed.")
        FileAppend("PASS DESKTOP_INTEGRATION owned autostart and escaped arguments`n", "*")

        fixture := JSON.Parse(ALTRunRecentFixture(folder))
        items := DesktopIntegration.RecentItems(10, fixture["File"])
        DesktopIntegrationTest.Assert(items.Length = 2, "Recent files did not filter private, missing, duplicate or remote entries.")
        DesktopIntegrationTest.Assert(items[1].Path == fixture["Newest"] && items[2].Path == fixture["Older"], "Recent files were not sorted by activity time.")
        if Platform.IsLinux {
            recent := WindowsRecent.Items(10, fixture["File"])
            DesktopIntegrationTest.Assert(recent[1].Path == fixture["Newest"] && recent[1].Name != "", "The recent provider contract was not preserved.")
        }
        DesktopIntegrationTest.Assert(DesktopIntegration.RecentItems(1, fixture["File"]).Length = 1, "Recent file limit was ignored.")
        DesktopIntegrationTest.Assert(DesktopIntegration.RecentItems(0, fixture["File"]).Length = 0, "A zero recent file limit returned entries.")
        FileDelete(fixture["File"])
        FileAppend('<!DOCTYPE xbel [<!ENTITY secret SYSTEM "file:///etc/passwd">]><xbel>&secret;</xbel>', fixture["File"], "UTF-8-RAW")
        DesktopIntegrationTest.Assert(DesktopIntegration.RecentItems(10, fixture["File"]).Length = 0, "An external-entity document was accepted.")
        FileAppend("PASS DESKTOP_INTEGRATION recent files, privacy, limits and XML safety`n", "*")
        ExitApp(0)
    }

    static Fail(error) {
        FileAppend("FAIL DESKTOP_INTEGRATION " error.Message " (" error.File ":" error.Line ")`n", "**")
        ExitApp(1)
    }

    static CleanUp() {
        if (DesktopIntegrationTest.Folder != "" && DirExist(DesktopIntegrationTest.Folder))
            DirDelete(DesktopIntegrationTest.Folder, true)
    }
}

#CSharp
public static string ALTRunRecentFixture(string folder)
{
    string older = System.IO.Path.Combine(folder, "Report 汉字 %.txt");
    string newer = System.IO.Path.Combine(folder, System.OperatingSystem.IsWindows() ? "Second.txt" : "report 汉字 %.txt");
    string secret = System.IO.Path.Combine(folder, "private.txt");
    foreach (string path in new[] { older, newer, secret }) System.IO.File.WriteAllText(path, "fixture");
    System.Xml.Linq.XNamespace ns = "http://www.freedesktop.org/standards/desktop-bookmarks";
    System.Xml.Linq.XElement Bookmark(string path, string time) => new("bookmark",
        new System.Xml.Linq.XAttribute("href", new System.Uri(path).AbsoluteUri), new System.Xml.Linq.XAttribute("visited", time));
    var hidden = Bookmark(secret, "2026-10-26T15:00:00Z");
    hidden.Add(new System.Xml.Linq.XElement("info", new System.Xml.Linq.XElement("metadata", new System.Xml.Linq.XElement(ns + "private"))));
    var document = new System.Xml.Linq.XDocument(new System.Xml.Linq.XElement("xbel",
        Bookmark(older, "2026-10-25T00:00:00Z"), Bookmark(newer, "2026-10-26T00:00:00Z"), Bookmark(older, "2026-10-24T00:00:00Z"), hidden,
        Bookmark(System.IO.Path.Combine(folder, "missing.txt"), "2026-10-27T00:00:00Z"),
        new System.Xml.Linq.XElement("bookmark", new System.Xml.Linq.XAttribute("href", "file://remote-server/private.txt"))));
    string file = System.IO.Path.Combine(folder, "recently-used.xbel");
    document.Save(file);
    return System.Text.Json.JsonSerializer.Serialize(new { File = file, Newest = newer, Older = older });
}
#EndCSharp

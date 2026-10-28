; Archive validation and replacement rollback run only on private synthetic directories, never an installed app.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => MacUpdateTests.Fail(err.Message "`n" err.Stack))
OnExit((*) => MacUpdateTests.CleanUp())
SetTimer(() => MacUpdateTests.Fail("Timed out after 20 seconds."), -20000)
MacUpdateTests.Run()

class MacUpdateTests {
    static Folder := "", Job := 0, ChildPid := 0
    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }
    static Run() {
        if !Platform.IsMac {
            FileAppend("SKIP MAC_UPDATE macOS-only fixture.`n", "*")
            ExitApp(0)
        }
        MacUpdateTests.Folder := Platform.Join(A_Temp, "ALTRun-MacUpdate-" Platform.NewUuid())
        DirCreate(MacUpdateTests.Folder)
        for kind in ["valid", "traversal", "absolute", "backslash", "collision", "unicode", "escape", "ordered-link", "linked-alias", "cycle", "special", "top", "ancestor", "bomb"] {
            archive := Platform.Join(MacUpdateTests.Folder, kind ".zip")
            ALTRunMacUpdateZipFixture(archive, kind)
            result := ALTRunMacValidateUpdateArchive(archive)
            MacUpdateTests.Assert(kind = "valid" ? result = "ALTRun.app" : InStr(result, "ERROR:") = 1
                , "Archive validation returned an unexpected result for " kind ": " result)
        }
        FileAppend("PASS MAC_UPDATE valid framework links and unsafe ZIP path/link/type/size rejection`n", "*")
        if A_Args.Length {
            MacUpdateTests.Assert(ALTRunMacValidateUpdateArchive(A_Args[1]) = "ALTRun.app", "The actual native package failed archive validation.")
            FileAppend("PASS MAC_UPDATE actual packaged app archive structure and framework links`n", "*")
        }
        for succeeds in [true, false] {
            prefix := Platform.Join(MacUpdateTests.Folder, succeeds ? "success ' ü $ literal" : "rollback ' ü $ literal")
            DirCreate(prefix)
            current := Platform.Join(prefix, "ALTRun.app"), incoming := Platform.Join(prefix, "incoming.app"), backup := Platform.Join(prefix, "backup.app")
            DirCreate(current), DirCreate(incoming)
            FileAppend("old", Platform.Join(current, "owned-marker"), "UTF-8")
            FileAppend("new", Platform.Join(incoming, "owned-marker"), "UTF-8")
            helper := Platform.Join(prefix, "helper.sh")
            FileAppend(ALTRunMacUpdateFixtureHelper(current, incoming, backup, succeeds), helper, "UTF-8-RAW")
            MacUpdateTests.Job := ProcessRunner.Start("/bin/sh", [helper], "", true)
            started := A_TickCount
            while !ProcessRunner.IsFinished(MacUpdateTests.Job) {
                MacUpdateTests.Assert(A_TickCount - started < 3000, "The owned transaction helper did not finish.")
                Sleep(15)
            }
            result := ProcessRunner.Result(MacUpdateTests.Job)
            MacUpdateTests.Job := 0
            MacUpdateTests.Assert(result["ExitCode"] = (succeeds ? 0 : 5), "The owned transaction returned the wrong status: " result["Error"])
            MacUpdateTests.Assert(FileRead(Platform.Join(current, "owned-marker"), "UTF-8") = (succeeds ? "new" : "old"), "The transaction lost the current fixture app.")
            if succeeds
                MacUpdateTests.Assert(FileRead(Platform.Join(backup, "owned-marker"), "UTF-8") = "old" && !DirExist(incoming), "The previous app was not preserved as backup.")
            else
                MacUpdateTests.Assert(FileRead(Platform.Join(incoming, "owned-marker"), "UTF-8") = "new" && !DirExist(backup), "The failed launch did not restore the original app.")
        }
        FileAppend("PASS MAC_UPDATE same-volume replacement/backup and launch-failure rollback with literal paths`n", "*")
        MacUpdateTests.Readiness()
        MacUpdateTests.Assert(MacUpdate.TrustedTeam() = "" && !MacUpdate.CanInstall({ZipUrl: "https://github.com/Descolada/ALTRun/releases/download/test/fixture.zip", Sha256: StrReplace(Format("{:64}", ""), " ", "a"), Version: "9999.1"})
            , "Source/ad-hoc runtime unexpectedly allows native self-updates.")
        FileAppend("PASS MAC_UPDATE source/ad-hoc builds decline automatic installation`n", "*")
        ExitApp(0)
    }

    static Readiness() {
        nonce := StrReplace(Platform.NewUuid(), "-")
        staging := Platform.Join(MacUpdateTests.Folder, "ALTRun-update-signal")
        bundle := Platform.Join(MacUpdateTests.Folder, "signal.app")
        DirCreate(staging), DirCreate(bundle)
        ALTRunMacUpdateReadinessFixture(staging, bundle, nonce)
        marker := Platform.Join(staging, "ready")
        MacUpdateTests.Assert(!ALTRunMacUpdateSignalReady(bundle, "fixture", marker, "bad"), "A malformed readiness nonce was accepted.")
        MacUpdateTests.Assert(!ALTRunMacUpdateSignalReady(bundle, "wrong-version", marker, nonce), "A readiness version mismatch was accepted.")
        MacUpdateTests.Assert(ALTRunMacUpdateSignalReady(bundle, "fixture", marker, nonce), "The private matching readiness handshake failed.")
        MacUpdateTests.Assert(!ALTRunMacUpdateSignalReady(bundle, "fixture", marker, nonce), "A readiness marker was overwritten.")
        FileAppend("PASS MAC_UPDATE private nonce/bundle/version startup readiness validation`n", "*")
        for succeeds in [true, false] {
            parent := Platform.Join(MacUpdateTests.Folder, succeeds ? "ready-success" : "ready-crash")
            current := Platform.Join(parent, "current.app"), incoming := Platform.Join(parent, "incoming.app"), backup := Platform.Join(parent, "backup.app")
            staging := Platform.Join(parent, "ALTRun-update-stage")
            DirCreate(current), DirCreate(Platform.Join(incoming, "Contents", "MacOS")), DirCreate(staging)
            FileAppend("old", Platform.Join(current, "owned-marker"), "UTF-8")
            FileAppend("new", Platform.Join(incoming, "owned-marker"), "UTF-8")
            pidFile := Platform.Join(parent, "child-pid")
            ALTRunMacUpdateExecutableFixture(Platform.Join(incoming, "Contents", "MacOS", "Fixture"), pidFile, succeeds)
            helper := Platform.Join(parent, "helper.sh")
            FileAppend(ALTRunMacUpdateFixtureReadyHelper(current, incoming, backup, staging, nonce), helper, "UTF-8-RAW")
            MacUpdateTests.Job := ProcessRunner.Start("/bin/sh", [helper], "", true)
            started := A_TickCount
            while !ProcessRunner.IsFinished(MacUpdateTests.Job) {
                MacUpdateTests.Assert(A_TickCount - started < 4500, "The owned readiness helper did not finish.")
                Sleep(15)
            }
            result := ProcessRunner.Result(MacUpdateTests.Job)
            MacUpdateTests.Job := 0
            MacUpdateTests.Assert(result["ExitCode"] = (succeeds ? 0 : 6), "The readiness helper returned the wrong status: " result["Error"])
            MacUpdateTests.Assert(FileRead(Platform.Join(current, "owned-marker"), "UTF-8") = (succeeds ? "new" : "old"), "Startup-crash rollback lost the original app.")
            if succeeds {
                record := StrSplit(Trim(FileRead(pidFile, "UTF-8"), " `t`r`n"), " ")
                MacUpdateTests.Assert(record.Length = 2 && record[1] = nonce, "The owned child PID record is invalid.")
                MacUpdateTests.ChildPid := Integer(record[2])
                if ProcessExist(MacUpdateTests.ChildPid)
                    ProcessClose(MacUpdateTests.ChildPid)
                MacUpdateTests.ChildPid := 0
                MacUpdateTests.Assert(!DirExist(staging), "Successful readiness did not remove private download staging.")
            }
        }
        FileAppend("PASS MAC_UPDATE startup readiness/liveness and pre-readiness crash rollback on owned executable fixtures`n", "*")
    }
    static CleanUp() {
        if MacUpdateTests.ChildPid
            try ProcessClose(MacUpdateTests.ChildPid)
        if MacUpdateTests.Job
            try ProcessRunner.Finish(MacUpdateTests.Job, true)
        MacUpdate.Stop()
        if (MacUpdateTests.Folder != "" && InStr(Platform.FullPath(MacUpdateTests.Folder), Platform.FullPath(Platform.Join(A_Temp, "ALTRun-MacUpdate-")), true) = 1)
            try DirDelete(MacUpdateTests.Folder, true)
    }
    static Fail(message) {
        FileAppend("FAIL MAC_UPDATE " message "`n", "*")
        ExitApp(1)
    }
}

#if OSX
#CSharp
public static void ALTRunMacUpdateReadinessFixture(string stage, string bundle, string nonce)
{
    System.IO.File.SetUnixFileMode(stage, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
    System.IO.File.WriteAllText(System.IO.Path.Combine(stage, "readiness.json"), System.Text.Json.JsonSerializer.Serialize(new { Bundle = bundle, Version = "fixture", Nonce = nonce }));
}
public static void ALTRunMacUpdateExecutableFixture(string file, string pidFile, bool ready)
{
    string quote(string value) => "'" + value.Replace("'", "'\"'\"'") + "'";
    string script = "#!/bin/sh\nset -eu\numask 077\n";
    if (!ready) script += "exit 9\n";
    else script += "printf '%s %s\\n' \"$3\" \"$$\" > \"$2.next\"\n/bin/mv \"$2.next\" \"$2\"\n/bin/cp \"$2\" " + quote(pidFile) + "\ni=0\nwhile [ \"$i\" -lt 50 ]; do /bin/sleep 0.1; i=$((i+1)); done\n";
    System.IO.File.WriteAllText(file, script, new System.Text.UTF8Encoding(false));
    System.IO.File.SetUnixFileMode(file, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
}
public static void ALTRunMacUpdateZipFixture(string file, string kind)
{
    using var zip = System.IO.Compression.ZipFile.Open(file, System.IO.Compression.ZipArchiveMode.Create);
    void Entry(string name, string text = "fixture", int mode = 0x8000)
    {
        var item = zip.CreateEntry(name, System.IO.Compression.CompressionLevel.Optimal);
        item.ExternalAttributes = unchecked((mode | 0x1ED) << 16);
        using var writer = new System.IO.StreamWriter(item.Open(), new System.Text.UTF8Encoding(false));
        writer.Write(text);
    }
    Entry("ALTRun.app/Contents/Info.plist", "<plist/>");
    switch (kind)
    {
        case "valid":
            Entry("ALTRun.app/Contents/Frameworks/Foo.framework/Versions/A/Foo");
            Entry("ALTRun.app/Contents/Frameworks/Foo.framework/Versions/Current", "A", 0xA000);
            Entry("ALTRun.app/Contents/Frameworks/Foo.framework/Foo", "Versions/Current/Foo", 0xA000);
            break;
        case "traversal": Entry("ALTRun.app/../../outside"); break;
        case "absolute": Entry("/tmp/outside"); break;
        case "backslash": Entry("ALTRun.app\\Contents\\outside"); break;
        case "collision": Entry("ALTRun.app/contents/info.plist"); break;
        case "unicode": Entry("ALTRun.app/Contents/é"); Entry("ALTRun.app/Contents/e\u0301"); break;
        case "escape": Entry("ALTRun.app/Contents/link", "../../outside", 0xA000); break;
        case "ordered-link":
            Entry("ALTRun.app/Contents/a/b/c/d/root", "../../../../..", 0xA000);
            Entry("ALTRun.app/Contents/a/b/c/d/escape", "root/../../../../../../outside", 0xA000);
            Entry("ALTRun.app/Contents/a/b/c/d/escape/file");
            break;
        case "linked-alias":
            Entry("ALTRun.app/Contents/link", ".", 0xA000);
            Entry("ALTRun.app/Contents/link/Info.plist");
            break;
        case "cycle": Entry("ALTRun.app/Contents/A", "B", 0xA000); Entry("ALTRun.app/Contents/B", "A", 0xA000); break;
        case "special": Entry("ALTRun.app/Contents/device", "", 0x2000); break;
        case "top": Entry("unexpected.txt"); break;
        case "ancestor": Entry("ALTRun.app/Contents/file"); Entry("ALTRun.app/Contents/file/nested"); break;
        case "bomb":
            var entry = zip.CreateEntry("ALTRun.app/Contents/bomb", System.IO.Compression.CompressionLevel.SmallestSize);
            using (var target = entry.Open()) { var zeros = new byte[4 * 1024 * 1024]; target.Write(zeros); }
            break;
    }
}
#EndCSharp
#endif

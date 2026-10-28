; FolderWatcherSmoke - bounded folder notifications and index path filtering in isolated data.
#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => FolderWatcherSmoke.Fail(err.Message "`n" err.Stack))
OnExit((*) => FolderWatcherSmoke.CleanUp())
SetTimer(() => FolderWatcherSmoke.Fail("Timed out after 20 seconds."), -20000)
FolderWatcherSmoke.Run()

class FolderWatcherSmoke {
    static Folder := "", External := "", Watcher := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        FolderWatcherSmoke.Folder := Platform.Join(A_Temp, "ALTRun-FolderWatcher-" Platform.NewUuid())
        nested := Platform.Join(FolderWatcherSmoke.Folder, "Nested")
        DirCreate(nested)
        preexisting := Platform.Join(nested, "Preexisting.txt")
        FileAppend("before watching", preexisting, "UTF-8")
        watcher := FolderWatcherSmoke.Watcher := FolderWatcher([FolderWatcherSmoke.Folder], FolderWatcher.NameChanges)
        FolderWatcherSmoke.Assert(watcher.Count = 1, "The temporary folder could not be watched.")
        started := A_TickCount
        while !watcher.Ready {
            FolderWatcherSmoke.Assert(A_TickCount - started < 4000, "Initial watcher snapshot did not finish.")
            Sleep(10)
        }
        FolderWatcherSmoke.Drain()
        FileAppend(" content only", preexisting, "UTF-8")
        FolderWatcherSmoke.AssertQuiet()
        original := Platform.Join(nested, "Case 漢字.txt"), renamed := Platform.Join(nested, "Renamed.txt")
        FileAppend("first", original, "UTF-8")
        FolderWatcherSmoke.WaitFor([original])
        FileMove(original, renamed)
        FolderWatcherSmoke.WaitFor([original, renamed])
        FolderWatcherSmoke.Drain()
        FileAppend("second", renamed, "UTF-8")
        FolderWatcherSmoke.AssertQuiet()
        FileDelete(renamed)
        FolderWatcherSmoke.WaitFor([renamed])
        FolderWatcherSmoke.Drain()
        moved := Platform.Join(FolderWatcherSmoke.Folder, "Moved")
        DirMove(nested, moved)
        FolderWatcherSmoke.WaitFor([nested, moved])
        FolderWatcherSmoke.Drain()
        preexisting := Platform.Join(moved, "Preexisting.txt")
        FileAppend(" after folder rename", preexisting, "UTF-8")
        FolderWatcherSmoke.AssertQuiet()
        external := FolderWatcherSmoke.External := FolderWatcherSmoke.Folder "-incoming"
        DirCreate(external)
        FileAppend("already populated", Platform.Join(external, "Child.txt"), "UTF-8")
        incoming := Platform.Join(FolderWatcherSmoke.Folder, "Incoming")
        DirMove(external, incoming)
        FolderWatcherSmoke.WaitFor([incoming])
        FolderWatcherSmoke.Drain()
        imported := Platform.Join(incoming, "Child.txt")
        FileDelete(imported)
        FolderWatcherSmoke.WaitFor([imported])
        FileAppend("PASS FOLDER_WATCHER nested Unicode create, rename, delete and preexisting name filters`n", "*")

        watched := Platform.Join(FolderWatcherSmoke.Folder, "WatchRoot")
        FolderWatcherSmoke.Assert(FileIndex.IsWatchedChange(Platform.Join(watched, "one.txt"), [watched], 1, "", ""), "A direct file was excluded.")
        FolderWatcherSmoke.Assert(!FileIndex.IsWatchedChange(Platform.Join(watched, "deep", "one.txt"), [watched], 1, "", ""), "A file beyond the scan depth was included.")
        FolderWatcherSmoke.Assert(!FileIndex.IsWatchedChange(Platform.Join(watched, "one.tmp"), [watched], 1, "", ""), "A temporary file was included.")
        if !Platform.IsWindows
            FolderWatcherSmoke.Assert(!FileIndex.IsWatchedChange(Platform.Join(FolderWatcherSmoke.Folder, "watchroot", "one.txt"), [watched], 1, "", ""), "Unix watch roots ignored path case.")
        watcher.Stop()
        watcher.Stop()
        FolderWatcherSmoke.Assert(!watcher.Count && !watcher.Poll().Length, "Stopped watchers retained notifications.")
        FileAppend("PASS FOLDER_WATCHER depth, temporary files, case and disposal`n", "*")
        watcher := FolderWatcherSmoke.Watcher := FolderWatcher([FolderWatcherSmoke.Folder])
        FolderWatcherSmoke.Drain()
        FileAppend(" include modifications", preexisting, "UTF-8")
        FolderWatcherSmoke.WaitFor([preexisting])
        watcher.Stop()
        FileAppend("PASS FOLDER_WATCHER content notifications when requested`n", "*")
        if FolderWatcher.Managed {
            recovery := Platform.Join(FolderWatcherSmoke.Folder, "Recovery")
            DirCreate(recovery)
            watcher := FolderWatcherSmoke.Watcher := FolderWatcher([recovery])
            DirDelete(recovery)
            changes := watcher.Poll()
            FolderWatcherSmoke.Assert(watcher.Watches[1].Disabled, "A removed root was not scheduled for recovery.")
            unknown := false
            for path in changes
                if (path = "*")
                    unknown := true
            FolderWatcherSmoke.Assert(unknown, "A removed root did not signal that changes were missed.")
            DirCreate(recovery)
            watcher.Watches[1].RetryAt := 0
            watcher.Poll()
            FolderWatcherSmoke.Assert(!watcher.Watches[1].Disabled, "A recreated root was not watched again.")
            restored := Platform.Join(recovery, "Restored.txt")
            FileAppend("restored", restored, "UTF-8")
            FolderWatcherSmoke.WaitFor([restored])
            watcher.Stop()
            FileAppend("PASS FOLDER_WATCHER removed-root recovery`n", "*")
        }
        ExitApp(0)
    }

    static WaitFor(paths) {
        pending := Map()
        pending.CaseSense := "On"
        for path in paths
            pending[path] := true
        started := A_TickCount
        while pending.Count {
            for path in FolderWatcherSmoke.Watcher.Poll()
                if pending.Has(path)
                    pending.Delete(path)
            FolderWatcherSmoke.Assert(A_TickCount - started < 4000, "Expected folder notifications did not arrive.")
            Sleep(10)
        }
    }

    static Drain() {
        started := A_TickCount
        while A_TickCount - started < 200 {
            FolderWatcherSmoke.Watcher.Poll()
            Sleep(10)
        }
    }

    static AssertQuiet() {
        started := A_TickCount
        while A_TickCount - started < 250 {
            FolderWatcherSmoke.Assert(!FolderWatcherSmoke.Watcher.Poll().Length, "NameChanges reported a content-only write.")
            Sleep(10)
        }
    }

    static CleanUp() {
        if IsObject(FolderWatcherSmoke.Watcher)
            try FolderWatcherSmoke.Watcher.Stop()
        if (FolderWatcherSmoke.Folder != "" && InStr(FolderWatcherSmoke.Folder, "ALTRun-FolderWatcher-") && DirExist(FolderWatcherSmoke.Folder))
            try DirDelete(FolderWatcherSmoke.Folder, true)
        if (FolderWatcherSmoke.External != "" && DirExist(FolderWatcherSmoke.External))
            try DirDelete(FolderWatcherSmoke.External, true)
    }

    static Fail(message) {
        FileAppend("FAIL FOLDER_WATCHER " message "`n", "**")
        ExitApp(1)
        return true
    }
}

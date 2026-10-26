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
    static Folder := "", Watcher := ""

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        FolderWatcherSmoke.Folder := Platform.Join(A_Temp, "ALTRun-FolderWatcher-" Platform.NewUuid())
        nested := Platform.Join(FolderWatcherSmoke.Folder, "Nested")
        DirCreate(nested)
        watcher := FolderWatcherSmoke.Watcher := FolderWatcher([FolderWatcherSmoke.Folder], FolderWatcher.NameChanges)
        FolderWatcherSmoke.Assert(watcher.Count = 1, "The temporary folder could not be watched.")
        original := Platform.Join(nested, "Case 漢字.txt"), renamed := Platform.Join(nested, "Renamed.txt")
        FileAppend("first", original, "UTF-8")
        FolderWatcherSmoke.WaitFor([original])
        FileMove(original, renamed)
        FolderWatcherSmoke.WaitFor([original, renamed])
        FolderWatcherSmoke.Drain()
        FileAppend("second", renamed, "UTF-8")
        started := A_TickCount
        while A_TickCount - started < 250 {
            FolderWatcherSmoke.Assert(!watcher.Poll().Length, "NameChanges reported a content-only write.")
            Sleep(10)
        }
        FileDelete(renamed)
        FolderWatcherSmoke.WaitFor([renamed])
        FileAppend("PASS FOLDER_WATCHER nested Unicode create, rename, delete and name filters`n", "*")

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

    static CleanUp() {
        if IsObject(FolderWatcherSmoke.Watcher)
            try FolderWatcherSmoke.Watcher.Stop()
        if (FolderWatcherSmoke.Folder != "" && InStr(FolderWatcherSmoke.Folder, "ALTRun-FolderWatcher-") && DirExist(FolderWatcherSmoke.Folder))
            try DirDelete(FolderWatcherSmoke.Folder, true)
    }

    static Fail(message) {
        FileAppend("FAIL FOLDER_WATCHER " message "`n", "**")
        ExitApp(1)
        return true
    }
}

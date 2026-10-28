;===============================================================================
; FolderWatcher.ahk - watches folders (with subfolders) for file changes (AutoHotkey v2)
;-------------------------------------------------------------------------------
; Uses ReadDirectoryChangesW on Windows and FileSystemWatcher elsewhere; Poll() on a timer returns the full paths changed since
; the last time (files / folders added, deleted, renamed; files modified). "*" when it isn't known which: the buffer overflowed (too many at once),
; a read failed, or a folder couldn't be watched for a while and is back (e.g. deleted and created again; retried every RetryMs).
; Uses almost no resources while idle; Wine doesn't support subfolders (only the first level is reported).
;
; Usage:
;   watcher := FolderWatcher(["C:\Users\me\Desktop", "D:\Docs"])   folders that can't be opened are skipped
;   FolderWatcher(folders, FolderWatcher.NameChanges)              only additions, deletions and renames, no modifications
;   watcher.Count                                                  how many folders are watched
;   for fullPath in watcher.Poll()                                 "C:\Users\me\Desktop\a.lnk" or "*"
;   watcher.Stop()                                                 (also stops when the object is released)
;===============================================================================

class FolderWatcher {
    static RetryMs := 30000
    static NameChanges := 0x1 | 0x2, AllChanges := 0x1 | 0x2 | 0x10    ; file names, folder names (| modified time)
#if WINDOWS && !ALTRUN_MANAGED_WATCHER
    static Managed := false
#else
    static Managed := true
#endif

    __New(folders, filter := FolderWatcher.AllChanges) {
        this.Watches := []
        for folder in folders
            if IsObject(watch := FolderWatcher.Create(folder, filter))
                this.Watches.Push(watch)
    }

    Count => this.Watches.Length
    ; macOS names-only watchers take their bounded initial snapshot off the GUI thread.
    Ready {
        get {
            if FolderWatcher.Managed
                for watch in this.Watches
                    if !ALTRunFolderWatchReady(watch.Managed)
                        return false
            return true
        }
    }

    ; The changes that have arrived (no waiting); each folder starts waiting for the next batch right after it is read
    Poll() {
        changes := []
        for index, watch in this.Watches {
            if watch.Disabled {                                             ; couldn't start waiting again last time: reopen when it is time
                if (A_TickCount < watch.RetryAt)
                    continue
                if IsObject(replacement := FolderWatcher.Create(watch.Folder, watch.Filter)) {
                    FolderWatcher.Close(watch)
                    this.Watches[index] := replacement
                    changes.Push("*")                                       ; changes may have been missed while it was stopped
                } else {
                    watch.RetryAt := A_TickCount + FolderWatcher.RetryMs
                }
                continue
            }
            if FolderWatcher.Managed {
                for fullPath in ALTRunFolderWatchPoll(watch.Managed)
                    changes.Push(fullPath)
                if ALTRunFolderWatchFailed(watch.Managed)
                    watch.Disabled := true, watch.RetryAt := A_TickCount + FolderWatcher.RetryMs
                continue
            }
            if (DllCall("WaitForSingleObject", "Ptr", watch.Event, "UInt", 0, "UInt") != 0)
                continue
            watch.Pending := false                                          ; signaled = this read has completed
            bytes := 0
            if !DllCall("GetOverlappedResult", "Ptr", watch.Handle, "Ptr", watch.Overlapped, "UInt*", &bytes, "Int", false)
                changes.Push("*")                                           ; the read failed: changes may have been missed
            else if !bytes                                                  ; the buffer overflowed: unknown which, treat it as "everything changed"
                changes.Push("*")
            offset := 0
            while (bytes && offset < bytes) {                               ; FILE_NOTIFY_INFORMATION list
                next := NumGet(watch.Buffer, offset, "UInt"), length := NumGet(watch.Buffer, offset + 8, "UInt")
                changes.Push(watch.Folder "\" StrGet(watch.Buffer.Ptr + offset + 12, length // 2, "UTF-16"))
                if !next
                    break
                offset += next
            }
            if !FolderWatcher._Read(watch) {
                watch.Disabled := true, watch.RetryAt := A_TickCount + FolderWatcher.RetryMs
                changes.Push("*")
            }
        }
        return changes
    }

    Stop() {
        for watch in this.Watches
            FolderWatcher.Close(watch)
        this.Watches := []
    }

    __Delete() => this.Stop()

    ; Opens a folder and starts waiting for changes; "" if it can't be opened
    static Create(folder, filter := FolderWatcher.AllChanges) {
        if FolderWatcher.Managed {
            folder := Platform.FullPath(folder)
            job := ALTRunFolderWatchCreate(folder, filter)
            return job ? {Folder: folder, Managed: job, Filter: filter, Disabled: false, RetryAt: 0} : ""
        }
        static FILE_LIST_DIRECTORY := 0x1, SHARE_ALL := 0x7, OPEN_EXISTING := 3, BACKUP_SEMANTICS := 0x02000000, OVERLAPPED := 0x40000000
        folder := RTrim(folder, "\")
        if (folder = "" || !DirExist(folder))
            return ""
        handle := DllCall("CreateFileW", "Str", folder, "UInt", FILE_LIST_DIRECTORY, "UInt", SHARE_ALL, "Ptr", 0, "UInt", OPEN_EXISTING
            , "UInt", BACKUP_SEMANTICS | OVERLAPPED, "Ptr", 0, "Ptr")
        if (handle = -1 || !handle)
            return ""
        watch := {Folder: folder, Handle: handle, Event: DllCall("CreateEventW", "Ptr", 0, "Int", true, "Int", false, "Ptr", 0, "Ptr")
            , Overlapped: Buffer(A_PtrSize * 2 + 8 + A_PtrSize, 0), Buffer: Buffer(32768), Filter: filter, Pending: false, Disabled: false, RetryAt: 0}
        if !watch.Event {
            DllCall("CloseHandle", "Ptr", handle)
            return ""
        }
        NumPut("Ptr", watch.Event, watch.Overlapped, A_PtrSize * 2 + 8)    ; OVERLAPPED.hEvent
        if !FolderWatcher._Read(watch) {
            FolderWatcher.Close(watch)
            return ""
        }
        return watch
    }

    ; Cancels a pending read and waits until it has really ended (CancelIoEx only requests it); only then can the OVERLAPPED and buffer be freed
    static Close(watch) {
        if FolderWatcher.Managed {
            ALTRunFolderWatchClose(watch.Managed)
            return
        }
        if watch.Pending {
            DllCall("CancelIoEx", "Ptr", watch.Handle, "Ptr", watch.Overlapped)
            bytes := 0
            DllCall("GetOverlappedResult", "Ptr", watch.Handle, "Ptr", watch.Overlapped, "UInt*", &bytes, "Int", true)
            watch.Pending := false
        }
        if watch.Handle
            DllCall("CloseHandle", "Ptr", watch.Handle), watch.Handle := 0
        if watch.Event
            DllCall("CloseHandle", "Ptr", watch.Event), watch.Event := 0
    }

    ; Starts (again) waiting asynchronously for the next batch of changes in this folder (with subfolders)
    static _Read(watch) {
        DllCall("ResetEvent", "Ptr", watch.Event)
        watch.Pending := DllCall("ReadDirectoryChangesW", "Ptr", watch.Handle, "Ptr", watch.Buffer, "UInt", watch.Buffer.Size, "Int", true
            , "UInt", watch.Filter, "Ptr", 0, "Ptr", watch.Overlapped, "Ptr", 0) ? true : false
        return watch.Pending
    }
}

#CSharp
private sealed class ALTRunManagedFolderWatch : System.IDisposable
{
    internal readonly System.IO.FileSystemWatcher Watcher;
    internal readonly System.Collections.Concurrent.ConcurrentQueue<string> Changes = new();
    internal int Failed;
    private int overflow, stopped;
    private const int NameLimit = 65536;
    private readonly bool namesOnly;
    private readonly object nameGate = new();
    private System.Collections.Generic.Dictionary<string, bool> names;
    private int nameState, startupChanged; // 0 = snapshot pending, 1 = tracked names, 2 = conservative invalidation
    internal bool Ready => !namesOnly || System.Threading.Volatile.Read(ref nameState) != 0;

    internal ALTRunManagedFolderWatch(string folder, long filter)
    {
        namesOnly = System.OperatingSystem.IsMacOS() && (filter & ~3L) == 0;
        Watcher = new System.IO.FileSystemWatcher(folder)
        {
            IncludeSubdirectories = true,
            NotifyFilter = (System.IO.NotifyFilters)(filter & 0x17F),
            InternalBufferSize = 32768
        };
        Watcher.Created += (_, e) => NameChange(null, e.FullPath);
        Watcher.Deleted += (_, e) => NameChange(e.FullPath, null);
        // FSEvents can repeat historical Created flags on content writes, even with a names-only filter.
        // Changed notifications also have no purpose when the caller requested names alone.
        if ((filter & 0x17C) != 0)
            Watcher.Changed += (_, e) => Queue(e.FullPath);
        Watcher.Renamed += (_, e) => NameChange(e.OldFullPath, e.FullPath);
        Watcher.Error += (_, e) =>
        {
            Queue("*");
            if (e.GetException() is not System.IO.InternalBufferOverflowException)
                System.Threading.Interlocked.Exchange(ref Failed, 1);
        };
    }

    internal void StartSnapshot()
    {
        if (!namesOnly) return;
        System.Threading.Tasks.Task.Run(() =>
        {
            var found = new System.Collections.Generic.Dictionary<string, bool>(System.StringComparer.Ordinal);
            var pending = new System.Collections.Generic.Stack<string>();
            pending.Push(Watcher.Path);
            var timer = System.Diagnostics.Stopwatch.StartNew();
            bool complete = true;
            try
            {
                while (pending.Count != 0 && complete && System.Threading.Volatile.Read(ref stopped) == 0)
                    foreach (string path in System.IO.Directory.EnumerateFileSystemEntries(pending.Pop()))
                    {
                        if (found.Count >= NameLimit || timer.ElapsedMilliseconds > 2000
                            || System.Threading.Volatile.Read(ref stopped) != 0) { complete = false; break; }
                        var attributes = System.IO.File.GetAttributes(path);
                        bool directory = (attributes & System.IO.FileAttributes.Directory) != 0;
                        found[path] = directory;
                        if (directory && (attributes & System.IO.FileAttributes.ReparsePoint) == 0) pending.Push(path);
                    }
            }
            catch (System.Exception error) when (error is System.IO.IOException || error is System.UnauthorizedAccessException)
            { complete = false; }
            lock (nameGate)
            {
                if (System.Threading.Volatile.Read(ref stopped) != 0) return;
                bool stable = complete && startupChanged == 0;
                names = stable ? found : null;
                System.Threading.Volatile.Write(ref nameState, stable ? 1 : 2);
                // Even a complete traversal can race a name event whose native callback has not arrived yet.
                // One invalidation after initialization closes that gap without blocking launcher startup.
                Queue("*");
            }
        });
    }

    private void NameChange(string oldPath, string newPath)
    {
        if (!namesOnly)
        {
            if (oldPath != null) Queue(oldPath);
            if (newPath != null) Queue(newPath);
            return;
        }
        lock (nameGate)
        {
            if (System.Threading.Volatile.Read(ref stopped) != 0) return;
            if (nameState != 1)
            {
                startupChanged = 1;
                Queue("*");
                return;
            }
            if (oldPath != null)
            {
                Queue(oldPath);
                // A populated directory can move into the watch without separate child creation events.
                // An unknown old path must still invalidate the index when such a child is removed.
                bool directory = names.Remove(oldPath, out bool wasDirectory) && wasDirectory;
                if (directory)
                {
                    string prefix = oldPath + System.IO.Path.DirectorySeparatorChar;
                    var children = System.Linq.Enumerable.ToArray(System.Linq.Enumerable.Where(names,
                        entry => entry.Key.StartsWith(prefix, System.StringComparison.Ordinal)));
                    foreach (var child in children)
                    {
                        names.Remove(child.Key);
                        if (newPath != null) names[newPath + child.Key[oldPath.Length..]] = child.Value;
                    }
                }
            }
            if (newPath != null && !names.ContainsKey(newPath))
            {
                names[newPath] = System.IO.Directory.Exists(newPath);
                Queue(newPath);
            }
            if (names.Count > NameLimit)
            {
                names = null;
                System.Threading.Volatile.Write(ref nameState, 2);
                Queue("*");
            }
        }
    }

    private void Queue(string path)
    {
        if (System.Threading.Volatile.Read(ref stopped) != 0) return;
        if (Changes.Count < 4096) Changes.Enqueue(path);
        else System.Threading.Interlocked.Exchange(ref overflow, 1);
    }

    internal Keysharp.Builtins.Array Poll()
    {
        var result = new Keysharp.Builtins.Array();
        if (!System.IO.Directory.Exists(Watcher.Path)
            && System.Threading.Interlocked.Exchange(ref Failed, 1) == 0)
            result.Push("*");
        for (int count = 0; count < 4096 && Changes.TryDequeue(out var path); count++)
            result.Push(path);
        if (System.Threading.Interlocked.Exchange(ref overflow, 0) != 0)
            result.Push("*");
        return result;
    }

    public void Dispose()
    {
        System.Threading.Interlocked.Exchange(ref stopped, 1);
        Watcher.Dispose();
    }
}

private static readonly System.Collections.Concurrent.ConcurrentDictionary<long, ALTRunManagedFolderWatch> ALTRunFolderWatches = new();
private static long ALTRunNextFolderWatch;

public static long ALTRunFolderWatchCreate(string Folder, long Filter)
{
    ALTRunManagedFolderWatch watch = null;
    try
    {
        if (!System.IO.Directory.Exists(Folder)) return 0;
        watch = new ALTRunManagedFolderWatch(Folder, Filter);
        watch.Watcher.EnableRaisingEvents = true;
        watch.StartSnapshot();
        var id = System.Threading.Interlocked.Increment(ref ALTRunNextFolderWatch);
        ALTRunFolderWatches[id] = watch;
        return id;
    }
    catch
    {
        watch?.Dispose();
        return 0;
    }
}

public static Keysharp.Builtins.Array ALTRunFolderWatchPoll(long Job)
    => ALTRunFolderWatches.TryGetValue(Job, out var watch) ? watch.Poll() : new Keysharp.Builtins.Array();

public static bool ALTRunFolderWatchFailed(long Job)
    => !ALTRunFolderWatches.TryGetValue(Job, out var watch) || System.Threading.Volatile.Read(ref watch.Failed) != 0;

public static bool ALTRunFolderWatchReady(long Job)
    => !ALTRunFolderWatches.TryGetValue(Job, out var watch) || watch.Ready;

public static void ALTRunFolderWatchClose(long Job)
{
    if (ALTRunFolderWatches.TryRemove(Job, out var watch)) watch.Dispose();
}
#EndCSharp

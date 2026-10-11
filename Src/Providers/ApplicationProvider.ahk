;===============================================================================
; ApplicationProvider.ahk - 应用程序搜索 (AutoHotkey v2)
;-------------------------------------------------------------------------------
; 索引开始菜单、桌面 (Features.Applications.Folders) 里的快捷方式和程序, 以及
; 应用商店应用 (PowerShell Get-StartApps, 在后台运行不卡界面)。中文名称同时
; 按拼音首字母匹配 ("wx" -> 微信)。
;
; 索引缓存在 Data\AppIndex.json, 启动时直接读缓存, 超过 RefreshMinutes 分钟
; 才在后台重新扫描; 托盘菜单 "重建索引" 或系统命令 "Rebuild ALTRun Index"
; 会立即重建。
;
; 不需要的应用: 在搜索结果里按 Ctrl+Del (或右键 "删除") 把它加入 Hidden 列表, 不再显示,
; 重建索引后也不会回来 (不会卸载程序, 也不改 AppIndex.json)。偏好设置 -> 应用搜索里
; 删掉 Hidden 的一行即可恢复。
;
; 设置 (ALTRun.json -> Features.Applications):
;   Folders / FileTypes / Depth / Exclude / Hidden / StoreApps / MatchPinyin / RefreshMinutes
;===============================================================================

class ApplicationProvider {
    static Id        := "Applications"
    static IndexFile := Platform.Join(AppSettings.DataDir, "AppIndex.json")
    static Apps      := []            ; [Map("Title", "Target", "Detail", "Search")...]
    static _storePid := 0, _storeFile := "", _storeTimer := ""
    static _entries := [], _keys := [], _keysFor := "", _lastNeedle := "", _lastMatches := []

    static Init() {
        if !ApplicationProvider._LoadCache() || ApplicationProvider._CacheExpired()
            SetTimer(() => ApplicationProvider.Rebuild(), -3000)            ; 先让窗口出来, 再在后台扫描
        SetTimer(() => ApplicationProvider._SearchKeys(), -500)             ; 预先算好搜索 Key, 第一次搜索不用等
    }

    static Search(query) {
        needle := StrLower(query.Text)
        if (needle = "")
            return []
        keys := ApplicationProvider._SearchKeys()
        apps := ApplicationProvider._entries

        ; 继续输入 (新输入以上一次的输入开头) 时只需要在上一次匹配到的里面找。
        ; 3 个字母以下时 "按顺序出现的字母" 规则不生效, 那时的结果不能用来缩小范围。
        candidates := ""
        if (StrLen(ApplicationProvider._lastNeedle) >= 3 && InStr(needle, ApplicationProvider._lastNeedle) = 1)
            candidates := ApplicationProvider._lastMatches
        scores := Map()
        if IsObject(candidates) {
            for index in candidates
                if (score := FuzzyMatcher.BestKey(needle, keys[index]))
                    scores[index] := score
        } else {
            for index, entryKeys in keys
                if (score := FuzzyMatcher.BestKey(needle, entryKeys))
                    scores[index] := score
        }
        matches := [], ranks := Map()
        for index, score in scores {
            matches.Push(index)
            ranks[index] := score + Knowledge.Boost(query.Text, ApplicationProvider._Uid(apps[index]["Target"]))
        }
        ApplicationProvider._lastNeedle := needle, ApplicationProvider._lastMatches := matches

        results := []
        for index in FuzzyMatcher.TopIndexes(ranks, ProviderRegistry.MaxResults) {
            entry := apps[index]
            isStore := InStr(entry["Target"], "shell:AppsFolder\") = 1
            subtitle := isStore ? I18n.T("App.Subtitle.Store") : (entry["Detail"] != "") ? entry["Detail"] : entry["Target"]
            props := {
                Kind: "file", Arg: entry["Target"], Source: entry,
                Icon: entry.Has("Icon") && entry["Icon"] != "" ? entry["Icon"] : entry["Target"],
                Uid: ApplicationProvider._Uid(entry["Target"]), Score: scores[index] + 10
            }
            if !Platform.IsWindows
                props.OnRun := ObjBindMethod(ApplicationProvider, "Launch", entry["Target"])
            results.Push(ResultItem(entry["Title"], subtitle, props))
        }
        return results
    }

    ; 启动后空闲时先算好搜索 Key, 第一次输入不用等
    static Warm() {
        ApplicationProvider._SearchKeys()
    }

    static _Uid(target) => "app:" (Platform.IsWindows ? StrLower(target) : target)

    static Launch(target, *) {
        if Platform.IsLinux && RegExMatch(target, "\.desktop$") {
            gio := Platform.FindExecutable("gio")
            if (gio != "")
                return ProcessRunner.Start(gio, ["launch", target])
            entry := ProcessRunner.DesktopEntry(target)
            if !entry.Has("Exec") || entry["Exec"] = ""
                throw Error("This desktop entry requires gio to launch.")
            spec := ProcessRunner.DesktopCommand(entry, target)
            if entry["Terminal"] {
                command := ProcessRunner.QuoteShell(spec.Executable)
                for argument in spec.Arguments
                    command .= " " ProcessRunner.QuoteShell(argument)
                return TerminalProvider._Launch(command, entry["Path"] != "" ? entry["Path"] : A_MyDocuments)
            }
            return ProcessRunner.Start(spec.Executable, spec.Arguments, entry["Path"])
        }
        return Platform.Open(target)
    }

    ; 没有隐藏的应用 (_entries) 和它们的搜索 Key (名称 + 拼音首字母);
    ; Apps 换成新数组或隐藏列表变化时重新计算
    static _SearchKeys() {
        version := Platform.ObjectId(ApplicationProvider.Apps) "|" ApplicationProvider._HiddenSignature()
        if (ApplicationProvider._keysFor = version)
            return ApplicationProvider._keys
        hidden := ApplicationProvider._HiddenTargets()
        entries := [], keys := []
        for entry in ApplicationProvider.Apps {
            if hidden.Has(entry["Target"])
                continue
            pinyinText := entry.Has("Search") ? entry["Search"] : ""
            entries.Push(entry)
            keys.Push([FuzzyMatcher.Key(entry["Title"]), (pinyinText != "") ? FuzzyMatcher.Key(pinyinText) : ""])
        }
        ApplicationProvider._entries := entries, ApplicationProvider._keys := keys
        ApplicationProvider._keysFor := version
        ApplicationProvider._lastNeedle := "", ApplicationProvider._lastMatches := []
        return keys
    }

    ;---------------------------------------------------------------------------
    ; 隐藏不需要的应用 (搜索结果里 Ctrl+Del / 右键 "删除")
    ;---------------------------------------------------------------------------
    static DeleteItem(item) {
        return ApplicationProvider.Hide(item.Arg)
    }

    static DeletePrompt(item) {
        return I18n.T("App.ConfirmHide", item.Title)
    }

    static Hide(target) {
        hidden := AppSettings.Feature("Applications")["Hidden"]
        if ApplicationProvider._HiddenTargets().Has(target)
            return true
        hidden.Push(target)
        return AppSettings.Save()
    }

    ; 隐藏列表 -> Map (不区分大小写), 列表变化 (换了数组或条数变了) 时重新生成
    static _HiddenTargets() {
        static cache := "", cacheFor := ""
        signature := ApplicationProvider._HiddenSignature()
        if (cacheFor != signature) {
            cache := Map()
            cache.CaseSense := Platform.IsWindows ? "Off" : "On"
            for target in AppSettings.Feature("Applications")["Hidden"]
                cache[target] := true
            cacheFor := signature
        }
        return cache
    }

    static _HiddenSignature() {
        hidden := AppSettings.Feature("Applications")["Hidden"]
        return Platform.ObjectId(hidden) ":" hidden.Length
    }

    ; 重新扫描, 返回找到的应用数量
    static Rebuild() {
        options := AppSettings.Feature("Applications")
        found := Map()
        found.CaseSense := Platform.IsWindows ? "Off" : "On"
        for folder in options["Folders"]
            ApplicationProvider._ScanFolder(Path.Resolve(folder), options, found)

        apps := []
        for key, entry in found
            if (entry is Map)
                apps.Push(entry)
        if Platform.IsWindows
            ApplicationProvider._MergeStoreApps(apps)
        ApplicationProvider.Apps := apps
        ApplicationProvider._SaveCache()
        if Platform.IsWindows && options["StoreApps"]
            ApplicationProvider._StartStoreScan()
        Logger.Debug("ApplicationProvider: indexed " apps.Length " apps")
        return apps.Length
    }

    static _ScanFolder(folder, options, found) {
        trimmed := RTrim(folder, "\/")
        folder := trimmed != "" ? trimmed : folder
        if (folder = "" || !DirExist(folder))
            return
        if Platform.IsMac {
            ApplicationProvider._ScanBundles(folder, options, found)
            return
        }
        exclude := options["Exclude"]
        maxDepth := options["Depth"]
        for pattern in options["FileTypes"] {
            Loop Files, Platform.Join(folder, pattern), "R" {
                relative := SubStr(A_LoopFileFullPath, StrLen(folder) + (RegExMatch(folder, "[/\\]$") ? 1 : 2))
                depth := StrLen(relative) - StrLen(RegExReplace(relative, "[/\\]"))
                if (depth > maxDepth)
                    continue
                SplitPath(A_LoopFileName, , , &ext, &title)
                if (exclude != "" && RegExMatch(title, exclude))
                    continue
                detail := ""
                if Platform.IsLinux && ext = "desktop" {
                    key := "desktop:" StrReplace(relative, "/", "-")
                    if found.Has(key)
                        continue
                    found[key] := ""                                      ; A hidden user entry masks the system entry with the same desktop ID.
                    try desktop := ProcessRunner.DesktopEntry(A_LoopFileFullPath)
                    catch as e {
                        Logger.Debug("ApplicationProvider: " A_LoopFileFullPath " - " e.Message)
                        continue
                    }
                    if !desktop.Has("Name") || desktop["Name"] = "" || (exclude != "" && RegExMatch(desktop["Name"], exclude))
                        continue
                    if desktop["TryExec"] != "" && Platform.FindExecutable(desktop["TryExec"]) = ""
                        continue
                    entry := ApplicationProvider._Entry(desktop["Name"], A_LoopFileFullPath, desktop["Exec"], options)
                    entry["Icon"] := desktop["Icon"]
                    found[key] := entry
                    continue
                }
#if WINDOWS
                if (ext = "lnk") {                                          ; 同一个程序在多个位置有快捷方式时只保留一个
                    linkTarget := "", linkArgs := ""
                    try FileGetShortcut(A_LoopFileFullPath, &linkTarget, , &linkArgs)
                    detail := Trim(linkTarget " " linkArgs)
                    key := StrLower(title "|" detail)
                } else {
                    key := StrLower(title "|" A_LoopFileFullPath)
                }
#else
                key := title "|" A_LoopFileFullPath
#endif
                if !found.Has(key)
                    found[key] := ApplicationProvider._Entry(title, A_LoopFileFullPath, detail, options)
            }
        }
    }

    static _ScanBundles(folder, options, found, depth := 0) {
        if (depth > options["Depth"])
            return
        Loop Files, Platform.Join(folder, "*"), "D" {
            if RegExMatch(A_LoopFileName, "\.app$") {
                title := SubStr(A_LoopFileName, 1, -4)
                if options["Exclude"] != "" && RegExMatch(title, options["Exclude"])
                    continue
                found[A_LoopFileFullPath] := ApplicationProvider._Entry(title, A_LoopFileFullPath, "", options)
            } else
                ApplicationProvider._ScanBundles(A_LoopFileFullPath, options, found, depth + 1)
        }
    }

    static _Entry(title, target, detail, options) {
        search := options["MatchPinyin"] ? Pinyin.Initials(title) : ""
        return Map("Title", title, "Target", target, "Detail", detail, "Search", (search != title) ? search : "")
    }

    ;---------------------------------------------------------------------------
    ; Microsoft Store apps (后台 PowerShell)
    ;---------------------------------------------------------------------------
    static _StartStoreScan() {
#if WINDOWS
        if (ApplicationProvider._storePid && ProcessExist(ApplicationProvider._storePid))
            return
        outFile := A_Temp "\ALTRun_StoreApps.csv"
        try FileDelete(outFile)
        command := "powershell.exe -NoProfile -Command `"Get-StartApps | Select-Object Name, AppID | ConvertTo-Csv -NoTypeInformation | Out-File -Encoding UTF8 -FilePath '" outFile "'`""
        try {
            Run(command, , "Hide", &pid)
        } catch as e {
            Logger.Error("ApplicationProvider: cannot start Get-StartApps - " e.Message)
            return
        }
        ApplicationProvider._storePid := pid
        ApplicationProvider._storeFile := outFile
        if (ApplicationProvider._storeTimer = "")
            ApplicationProvider._storeTimer := () => ApplicationProvider._CheckStoreScan()
        SetTimer(ApplicationProvider._storeTimer, 500)
#endif
    }

    static _CheckStoreScan() {
        if ProcessExist(ApplicationProvider._storePid)
            return
        SetTimer(ApplicationProvider._storeTimer, 0)
        ApplicationProvider._storePid := 0
        csvFile := ApplicationProvider._storeFile
        if !FileExist(csvFile)
            return
        options := AppSettings.Feature("Applications")
        storeApps := []
        for line in StrSplit(FileRead(csvFile, "UTF-8"), "`n", "`r") {
            if (A_Index = 1 || !RegExMatch(line, '^"(.*)","(.*)"$', &m))    ; 第一行是表头
                continue
            if (m[1] = "" || m[2] = "" || RegExMatch(m[1], options["Exclude"]))
                continue
            if !InStr(m[2], "!")                                            ; 只要 "包名!应用" 形式的真正商店应用, 普通程序已在开始菜单里索引过
                continue
            storeApps.Push(ApplicationProvider._Entry(m[1], "shell:AppsFolder\" m[2], "", options))
        }
        try FileDelete(csvFile)

        apps := []
        for entry in ApplicationProvider.Apps
            if (InStr(entry["Target"], "shell:AppsFolder\") != 1)
                apps.Push(entry)
        for entry in storeApps
            apps.Push(entry)
        ApplicationProvider.Apps := apps
        ApplicationProvider._SaveCache()
        Logger.Debug("ApplicationProvider: indexed " storeApps.Length " store apps")
    }

    static _MergeStoreApps(apps) {
        for entry in ApplicationProvider.Apps
            if (InStr(entry["Target"], "shell:AppsFolder\") = 1)
                apps.Push(entry)
    }

    ;---------------------------------------------------------------------------
    ; Cache
    ;---------------------------------------------------------------------------
    static _LoadCache() {
        if !FileExist(ApplicationProvider.IndexFile)
            return false
        try {
            data := JSON.Parse(FileRead(ApplicationProvider.IndexFile, "UTF-8"))
            if data.Has("Platform") ? data["Platform"] != A_OSType : !Platform.IsWindows
                return false
            ApplicationProvider.Apps := data["Apps"]
            return true
        } catch as e {
            Logger.Error("ApplicationProvider: cannot read cache - " e.Message)
            return false
        }
    }

    static _CacheExpired() {
        minutes := AppSettings.Feature("Applications")["RefreshMinutes"]
        return DateDiff(A_Now, FileGetTime(ApplicationProvider.IndexFile, "M"), "Minutes") >= minutes
    }

    static _SaveCache() {
        try {
            JSON.WriteFile(ApplicationProvider.IndexFile, Map("Platform", A_OSType, "Apps", ApplicationProvider.Apps))
        } catch as e {
            Logger.Error("ApplicationProvider: cannot write cache - " e.Message)
        }
    }
}

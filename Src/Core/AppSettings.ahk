;===============================================================================
; AppSettings.ahk - 用户设置 Data\ALTRun.json 的读写和默认值 (AutoHotkey v2)
;-------------------------------------------------------------------------------
; ALTRun.json 只保存用户设置和用户数据 (自定义命令 / 片段 / 网页搜索引擎 /
; 自定义热键)。它和运行时生成的数据 (应用索引、学习记录、剪贴板历史) 都放在
; Data\ 目录里, 各是一个单独的文件: 删掉索引等文件只会让它们重新生成, 不影响设置。
; 3.x 到 v2026.09.26 把 ALTRun.json 放在程序目录, 启动时自动移到 Data\ (MoveLegacyFile)。
;
; 文件结构 (SchemaVersion 3):
; {
;   "SchemaVersion" : 3,
;   "General"       : { 呼出热键 / 开机启动 / 托盘图标 / 失焦隐藏 / 语言 ... },
;   "Appearance"    : { 主题 / 窗口宽度 / 可见行数 },
;   "Features"      : { "<功能名>": { "Enabled": 1, ...该功能自己的设置 } },
;   "Extensions"    : { "QuickSwitch": {...}, "AutoDate": {...}, "PTTools": {...} },
;   "Hotkeys"       : [ { "Key", "Action", "WinTitle" } ],   自定义热键 -> 系统命令
;   "CustomCommands": [ { "Title", "Type", "Target", "Arguments", "Keyword" } ],
;   "Snippets"      : [ { "Name", "Keyword", "Text", "AutoExpand" } ],
;   "DataLocation"  : "D:\\OneDrive\\ALTRun"   可选, 只在默认位置的文件里有: 改用这个数据文件夹 (见 ResolveDataDir)
; }
;
; 旧版本 (没有 SchemaVersion 的 2.x 格式) 由 SchemaMigration 自动升级, 升级前
; 会先把原文件备份一份, 见 SchemaMigration.ahk。
;
; 用法:
;   AppSettings.Load()                       启动时调用一次
;   AppSettings.General["Hotkey"]            读某一节的某个值
;   AppSettings.Feature("WebSearch")         某个功能的设置 (Map)
;   AppSettings.Save()                       写回 Data\ALTRun.json
;===============================================================================

class AppSettings {
    static CurrentVersion := 4
    static Portable := Path.IsWritable(A_ScriptDir)                          ; 程序目录能写入: 数据放在程序目录 (便携)
    static UserDir := Platform.Join(Platform.UserDataDir, "ALTRun")           ; 程序目录不能写入时用这里
    static DataDir := AppSettings.ResolveDataDir()
    static File := Platform.Join(AppSettings.DataDir, "ALTRun.json")
    static LegacyFile := Platform.Join(A_ScriptDir, "ALTRun.json")           ; 旧版本的位置, 2.x 的 ALTRun.ini 也在这个目录
    static Data := Map()
    static MigratedFrom := 0          ; 本次启动时从哪个版本升级过来的 (0 = 没有升级)
    static ImportedFrom := ""         ; 本次启动时从旧版本的 ALTRun.ini 导入 ("" = 没有)
    static MovedFrom := ""            ; 本次启动时从程序目录移到 Data\ ("" = 没有)
    static _runtimeFallbacks := []

    static General        => AppSettings.Data["General"]
    static Appearance     => AppSettings.Data["Appearance"]
    static Hotkeys        => AppSettings.Data["Hotkeys"]
    static CustomCommands => AppSettings.Data["CustomCommands"]
    static Snippets       => AppSettings.Data["Snippets"]

    ; 数据文件夹 (设置、索引、学习记录、剪贴板历史...):
    ;   1. 默认位置的 ALTRun.json 里有 "DataLocation" (偏好设置 → 高级 → 更改位置): 改用那个文件夹,
    ;      例如 OneDrive 里的, 几台电脑共用一份设置 (可以写 %OneDrive%\ALTRun, 相对路径从程序目录算起)。
    ;      只看默认位置的这一项, 那个文件夹里的 ALTRun.json 不再跳转
    ;   2. 程序目录能写入: 程序目录\Data (便携, 默认)
    ;   3. 否则: %APPDATA%\ALTRun\Data
    static ResolveDataDir() {
        if ((location := AppSettings.DataLocationIn(Platform.Join(AppSettings.DefaultDataDir(), "ALTRun.json"))) != "")
            return location
        return AppSettings.DefaultDataDir()
    }

    static DefaultDataDir() => Platform.Join(AppSettings.Portable ? A_ScriptDir : AppSettings.UserDir, "Data")

    static _SameLocation(first, second) => Platform.Identity(first) == Platform.Identity(second)

    ; 设置文件里 "DataLocation" 指定的文件夹 (没有、为空或就是默认位置时 "")。启动时调用:
    ; 只找这一项, 不解析整个文件 (不跳转时同一个文件马上还要完整读一次)
    static DataLocationIn(settingsFile) {
        if !FileExist(settingsFile)
            return ""
        try {
            if !RegExMatch(FileRead(settingsFile, "UTF-8"), '"DataLocation"\s*:\s*("(?:[^"\\]|\\.)*")', &m)
                return ""
            location := Trim(JSON.Parse("[" m[1] "]")[1])
            if (!Platform.IsWindows && RegExMatch(location, "^(?:[A-Za-z]:[\\/]|\\\\)"))
                return ""
            if (location != "" && !AppSettings._SameLocation(location := Path.Full(location), AppSettings.DefaultDataDir()))
                return location
        }
        return ""
    }

    ; 把数据文件夹改成 folder ("" 或默认位置 = 恢复默认): 写进默认位置的 ALTRun.json ("DataLocation"), 重新载入后生效
    static SetDataLocation(folder) {
        settingsFile := Platform.Join(AppSettings.DefaultDataDir(), "ALTRun.json")
        reset := (folder = "" || AppSettings._SameLocation(Path.Full(folder), AppSettings.DefaultDataDir()))
        data := Map()
        if FileExist(settingsFile)
            data := JSON.Parse(FileRead(settingsFile, "UTF-8"))
        else if reset
            return
        if !reset
            data["DataLocation"] := folder
        else if data.Has("DataLocation")
            data.Delete("DataLocation")
        DirCreate(AppSettings.DefaultDataDir())
        JSON.WriteFile(settingsFile, data)
        if AppSettings._SameLocation(AppSettings.DataDir, AppSettings.DefaultDataDir()) { ; 正在用默认位置的设置: 之后保存时也要留着这一项
            if !reset
                AppSettings.Data["DataLocation"] := folder
            else if AppSettings.Data.Has("DataLocation")
                AppSettings.Data.Delete("DataLocation")
        }
    }

    static Feature(name) {
        return AppSettings.Data["Features"][name]
    }

    static Extension(name) {
        return AppSettings.Data["Extensions"][name]
    }

    static Load() {
        AppSettings._runtimeFallbacks := []
        AppSettings.MoveLegacyFile()
        data := AppSettings._ReadFile()
        changed := false

        ; 已发布的 2.x (到 v2026.08.12) 把设置存在 ALTRun.ini: 还没有 ALTRun.json 时从它导入。
        ; ALTRun.ini 保持不变, 退回旧版本时仍然可以用
        if (!data.Count && !FileExist(AppSettings.File)) {
            iniFile := SchemaMigration.LegacyIniFile(AppSettings.LegacyFile)
            if FileExist(iniFile) {
                data := SchemaMigration.ReadLegacyIni(iniFile)
                AppSettings.ImportedFrom := iniFile
            }
        }

        if (data.Count) {
            fromVersion := SchemaMigration.DetectVersion(data)
            if (fromVersion < AppSettings.CurrentVersion) {
                SchemaMigration.Backup(AppSettings.File, fromVersion)
                data := SchemaMigration.Upgrade(data, fromVersion)
                AppSettings.MigratedFrom := fromVersion
                changed := true
            }
        } else {
            changed := true                                                 ; 第一次运行: 写出一份带默认值的文件
        }

        if AppSettings._MergeDefaults(data, AppSettings.Defaults())
            changed := true
        if (!AppSettings._SameLocation(AppSettings.DataDir, AppSettings.DefaultDataDir()) && data.Has("DataLocation"))
            data.Delete("DataLocation")                                     ; 跳转到的文件夹里的这一项没有作用, 去掉免得混淆
        data["SchemaVersion"] := AppSettings.CurrentVersion
        AppSettings.Data := data

        if (changed)
            AppSettings.Save()
        AppSettings.EffectiveDefaults(data)
    }

    static Save() {
        try {
            data := AppSettings.Data, remaining := []
            if AppSettings._runtimeFallbacks.Length {
                data := AppSettings._CopyValue(data)
                for fallback in AppSettings._runtimeFallbacks {
                    parent := AppSettings._ParentFor(data, fallback.Path)
                    key := fallback.Path[fallback.Path.Length]
                    if AppSettings._SameValue(parent[key], fallback.Effective) {
                        parent[key] := fallback.Stored
                        remaining.Push(fallback)
                    }
                }
            }
            JSON.WriteFile(AppSettings.File, data)
            AppSettings._runtimeFallbacks := remaining
            return true
        } catch as e {
            Logger.Error("AppSettings.Save: " e.Message)
            MsgBox(I18n.T("Settings.SaveError", e.Message), App.Name, "Icon! 0x40000")   ; 总在最前面: 启动时还没有窗口, 不能被别的窗口挡住像是卡死了
            return false
        }
    }

    ; 旧版本的 ALTRun.json 在程序目录: 还没有 Data\ALTRun.json 时连同升级备份 (ALTRun.v*.backup.json)
    ; 和解析失败留下的 ALTRun.json.bad 一起移过去。两边都有时用 Data\ 里的, 旧文件不动。
    ; 移不动 (例如文件被占用) 时这次继续用旧位置, 下次启动再试
    static MoveLegacyFile() {
        legacy := AppSettings.LegacyFile, target := AppSettings.File
        if (AppSettings._SameLocation(legacy, target) || !FileExist(legacy) || FileExist(target))
            return
        SplitPath(legacy, , &fromDir)
        SplitPath(target, , &toDir)
        try {
            DirCreate(toDir)
            FileMove(legacy, target)
        } catch as e {
            Logger.Error("AppSettings: cannot move " legacy " to " toDir " - " e.Message)
            AppSettings.File := legacy
            return
        }
        AppSettings.MovedFrom := legacy
        Loop Files, Platform.Join(fromDir, "ALTRun.*"), "F" {
            if (A_LoopFileName = "ALTRun.json.bad" || RegExMatch(A_LoopFileName, "i)^ALTRun\.v\d+\.backup\.json$"))
                if !FileExist(Platform.Join(toDir, A_LoopFileName))
                    try FileMove(A_LoopFileFullPath, Platform.Join(toDir, A_LoopFileName))
        }
        Logger.Debug("AppSettings: moved " legacy " to " target)
    }

    static _ReadFile() {
        if !FileExist(AppSettings.File)
            return Map()
        try {
            parsed := JSON.Parse(FileRead(AppSettings.File, "UTF-8"))
            return (parsed is Map) ? parsed : Map()
        } catch as e {
            badFile := AppSettings.File ".bad"
            try FileMove(AppSettings.File, badFile, true)
            Logger.Error("AppSettings: invalid JSON - " e.Message)
            MsgBox(I18n.T("Settings.ParseError", e.Message, badFile), App.Name, "Icon! 0x40000")
            return Map()
        }
    }

    ; 把 defaults 里有、target 里没有的键补上 (逐层递归, 只补 Map, 数组整体看待)。
    ; 返回是否有改动。类型不一致 (比如该是 Map 的地方被手改成了字符串) 也用默认值覆盖。
    static _MergeDefaults(target, defaults) {
        changed := false
        for key, defaultValue in defaults {
            if !target.Has(key) {
                target[key] := defaultValue
                changed := true
            } else if (defaultValue is Map) {
                if (target[key] is Map) {
                    if AppSettings._MergeDefaults(target[key], defaultValue)
                        changed := true
                } else {
                    target[key] := defaultValue
                    changed := true
                }
            } else if (defaultValue is Array && !(target[key] is Array)) {
                target[key] := defaultValue
                changed := true
            }
        }
        return changed
    }

    ; 每次调用都新建一份, 调用方可以随意修改返回值
    static Defaults() {
        defaults := Map(
            "SchemaVersion", AppSettings.CurrentVersion,
            "General", Map(
                "Hotkey"              , "!Space",
                "SecondaryHotkey"     , "!r",                               ; Alt+R
                "DoubleTap"           , "",                                ; 双击 Ctrl / Shift 呼出搜索窗口 (和 Listary 一样), "" = 不用
                "CapsLock"            , "",                                 ; 按 CapsLock: Layout = 切换输入法, Mode = 切换中英模式, "" = 照常 (见 CapsLockSwitch)
                "SelectionHotkey"     , "^!\",                              ; 选中文字 / 文件后按: 直接打开它们的操作 (Ctrl+Alt+\)
                "Language"            , "auto",                             ; auto 或 Resources\Lang 里的语言代码 (zh-CN / zh-TW / ja), en
                "LaunchAtLogin"       , 1,
                "ShowTrayIcon"        , 1,
                "HideOnDeactivate"    , 1,
                "SwitchToEnglishInput", 0,
                "RestoreInput"        , 1,                                 ; SwitchToEnglishInput 时: 窗口隐藏后切回原来的输入法
                "SpaceToRun"          , 0,                                  ; 空格执行选中项 (Shift+空格输入空格)
                "KeepLastQuery"       , 0,                                  ; 呼出窗口时恢复上一次的搜索 (文字全选)
                "ShowTips"            , 1,                                  ; 空搜索框里轮换显示使用提示
                "FileManager"         , "explorer.exe",
                "SendToMenu"          , 1,
                "StartMenuShortcut"   , 1,
                "CheckForUpdates"     , 1,
                "SaveLog"             , 0,
                "HistorySize"         , 30
            ),
            "Appearance", Map(
                "Theme"      , "Light",                                     ; 内置主题名 (见 ThemeManager) 或 Themes\<名称>.json
                "Width"      , 700,
                "VisibleRows", 8,
                "ShowOn"     , "Mouse",                                     ; 显示在哪块屏幕: Mouse 鼠标所在 / Primary 主屏幕 / Active 当前窗口所在
                "RememberPosition", 0,                                      ; 拖动窗口后记住位置
                "Position"   , Map("X", 500, "Y", 200)                      ; 记住的位置: 屏幕里的千分比 (见 SearchWindow.Place)
            ),
            "Features", Map(
                "Applications", Map(
                    "Enabled"       , 1,
                    "Folders"       , ["A_Programs", "A_ProgramsCommon", "A_Desktop", "A_DesktopCommon"],
                    "FileTypes"     , ["*.lnk", "*.exe", "*.url", "*.appref-ms"],
                    "Depth"         , 3,
                    "Exclude"       , "i)(uninstall|卸载|readme|help|documentation)",
                    "Hidden"        , [],                                   ; 在搜索结果里删除 (Ctrl+Del) 的应用的路径
                    "StoreApps"     , 1,
                    "MatchPinyin"   , 1,
                    "RefreshMinutes", 60
                ),
                "CustomCommands", Map("Enabled", 1),
                "Snippets", Map(
                    "Enabled"     , 1,
                    "Keyword"     , "snip",
                    "SearchText"  , 1,                                      ; 也搜索正文 (至少 3 个字符)
                    "PasteMode"   , "Clipboard",                            ; Clipboard = 剪贴板 + Ctrl+V; Type = 逐字输入
                    "PasteDelay"  , 300,
                    "AutoExpand"  , 1,                                      ; 在任何程序里输入 前缀+关键字 自动展开
                    "ExpandPrefix", ";",
                    "ExpandExclude", "ahk_exe mstsc.exe, ahk_exe KeePass.exe, ahk_exe KeePassXC.exe"   ; 这些窗口里不自动展开
                ),
                "Clipboard", Map(
                    "Enabled"      , 1,
                    "Keyword"      , "clip",
                    "Hotkey"       , "^!c",                                 ; 直接打开剪贴板历史
                    "MaxItems"     , 200,
                    "MaxItemLength", 100000,                                ; 超过这么多字的内容不记录
                    "Persist"      , 1,                                     ; 0 = 只在内存里, 退出即清空
                    "Images"       , 1,                                     ; 也记录图片 (存成 Clipboard\*.png, 需要 Persist = 1)
                    "LocalFiles"   , 1,                                     ; 图片和很长的条目存在本机 (%LOCALAPPDATA%\ALTRun\Clipboard), 不跟着 Data 文件夹进同步盘
                    "MaxImages"    , 50,
                    "MergeDoubleCopy", 0,                                   ; 快速按两次 Ctrl+C: 接到上一条后面
                    "IgnoreApps"   , ["KeePass.exe", "KeePassXC.exe", "1Password.exe", "Bitwarden.exe"]
                ),
                "Calculator", Map(
                    "Enabled"       , 1,
                    "StructuralCalc", 0,                                    ; 结果下方附带梁主筋 / 配筋面积计算
                    "RebarCover"    , 40,                                   ; 保护层 (mm, 每边)
                    "MaxBarSpacing" , 300,                                  ; 主筋最大间距 (mm)
                    "BarSizes"      , [13, 16, 20, 25, 32],                 ; 配筋面积那一行列出的钢筋直径 (mm)
                    "BarPrefix"     , "H",                                  ; 钢筋代号前缀 (H / T / Y / Φ...)
                    "Currency"      , 0                                     ; 货币换算 (100 usd to sgd): 每天从 frankfurter.dev 下载汇率, 默认关闭
                ),
                "WebSearch", Map(
                    "Enabled"  , 1,
                    "Engines"  , AppSettings._DefaultEngines(),
                    "Fallbacks", ["google", "files", "bing"]                ; 没有任何结果时显示的兜底项 (引擎 Id 或 "files")
                ),
                "FileSearch", Map(
                    "Enabled"            , 1,
                    "Keywords"           , ["open", "find"],
                    "FolderKeywords"     , ["folder"],                      ; "folder bk" 只搜文件夹
                    "TypeFilters"        , [                                ; "doc 报告" 只搜这些扩展名的文件, 每行 "关键字 = 扩展名 ..."
                        "doc = doc docx xls xlsx xlsm csv ppt pptx pdf txt md rtf odt ods",
                        "pic = jpg jpeg png gif bmp tif tiff webp svg ico heic",
                        "video = mp4 mkv avi mov wmv flv webm m4v",
                        "audio = mp3 wav flac aac m4a ogg wma",
                        "zip = zip rar 7z tar gz tgz bz2 xz iso",
                        "exe = exe msi bat cmd ps1 lnk",
                        "cad = dwg dxf dgn dwf rvt ifc skp"
                    ],
                    "SpacePrefix"        , 1,                               ; 空的搜索框里先按空格 = 只搜文件, 和 Alfred 一样
                    "QuotePrefix"        , 1,                               ; 以 ' 开头直接搜索文件, 和 Alfred 一样
                    "MaxResults"         , 30,
                    "InDefaultResults"   , 0,                               ; 直接输入名称时也显示匹配的文件 / 文件夹 (默认关闭, 避免全盘的无关文件混进来)
                    "DefaultResultsLimit", 6,
                    "MinQueryLength"     , 2,
                    "UseEverything"      , 1,                               ; Everything 在运行时通过 IPC 查询全盘
                    "EverythingFilter"   , "!C:\Windows\ !\AppData\ !\$Recycle.Bin\",
                    "EverythingPath"     , "",                              ; Everything.exe 的位置, 留空自动查找 (只用于 "在 Everything 中搜索")
                    "ScopeFolders"       , ["A_Desktop", "A_MyDocuments", "%UserProfile%\Downloads"],   ; 没有 Everything 时的内置索引范围
                    "ScopeDepth"         , 4,
                    "ScopeExclude"       , "i)\\(node_modules|\.git|__pycache__|\$RECYCLE\.BIN)(\\|$)",
                    "MaxEntries"         , 30000,
                    "RefreshMinutes"     , 30
                ),
                "Terminal", Map(
                    "Enabled", 1,
                    "Prefix" , ">",
                    "Shell"  , "cmd"                                        ; cmd / powershell / pwsh / wt
                ),
                "Help", Map("Enabled", 1),                                  ; 输入 ? 显示所有输入语法和快捷键
                "Bookmarks", Map(
                    "Enabled"         , 1,
                    "Keyword"         , "bm",                               ; "bm 关键词" 只搜书签
                    "InDefaultResults", 1                                   ; 直接输入名称时也显示匹配的书签 (排在应用和命令后面)
                ),
                "Scripts", Map(
                    "Enabled"    , 1                                        ; Scripts\ 文件夹里的脚本变成命令
                ),
                "Recent", Map(
                    "Enabled"    , 1,
                    "RecentCount", 0,                                       ; 空搜索框里显示几个最近打开的项目 (0 = 不显示, 默认只显示置顶的)
                    "Pinned"     , []                                       ; 置顶到空搜索框的项目 (操作面板里 "置顶")
                ),
                "Windows", Map(
                    "Enabled"         , 1,
                    "Keyword"         , "w",                                ; "w 标题" 只搜已打开的窗口, "w " 列出全部
                    "InDefaultResults", 1                                   ; 直接输入时也显示标题匹配得好的窗口 (最多 3 个)
                ),
                "System", Map(
                    "Enabled"       , 1,
                    "ConfirmActions", 1,                                    ; 关机/重启/注销/清空回收站前确认
                    "SettingsPages" , 1,                                    ; 搜索 Windows 设置的页面 (显示、蓝牙、WLAN...)
                    "Hidden"        , []                                    ; 在搜索结果里删除 (Ctrl+Del) 的系统命令的 Id
                )
            ),
            "Extensions", Map(
                "QuickSwitch", Map(
                    "Enabled"          , 1,
                    "ExplorerHotkey"   , "^e",
                    "TotalCmdHotkey"   , "^g",
                    "MenuHotkey"       , "^+g",                             ; 文件夹菜单: 所有 TC 面板、资源管理器窗口、最近的文件夹
                    "RecentFolders"    , 10,                                ; 菜单里列出几个最近的文件夹, 0 = 不列
                    "PanelSearch"      , "folders",                         ; 面板搜索框: folders = 只搜文件夹, all = 文件夹和文件
                    "ShowPanel"        , 1,                                 ; 对话框一出现就在下面显示文件夹面板 (和 Listary 一样), 点一下就跳过去
                    "AutoSwitch"       , 0,
                    "DialogWindows"    , "ahk_class #32770",                ; 标准的 Windows 对话框, 另外可以加 "ahk_class Qt5QWindowIcon" (WPS) 等
                    "ExcludeWindows"   , "ahk_class SysListView32, ahk_exe Explorer.exe",
                    "AutoSwitchExclude", ""                                 ; 这些对话框不自动跳转 (仍然可以按热键)
                ),
                "AutoDate", Map(
                    "Enabled"      , 1,
                    "DateFormat"   , "dd.MM.yyyy",
                    "RenameHotkey" , "^d",
                    "RenameWindows", "ahk_class CabinetWClass,ahk_class Progman,ahk_class WorkerW,ahk_class #32770,ahk_class TTOTAL_CMD",
                    "AppendHotkey" , "^d",
                    "AppendWindows", "ahk_class TCmtEditForm,ahk_exe Notepad4.exe"
                ),
                "PTTools", Map()                                            ; 由 PTToolsWindow 自己补默认值
            ),
            "Hotkeys", [
                Map("Key", "~MButton", "Action", "PTTools", "WinTitle", "ahk_exe RAPTW.exe")
            ],
            "CustomCommands", AppSettings._DefaultCommands(),
            "Snippets", AppSettings._DefaultSnippets()
        )
        if !Platform.IsWindows
            AppSettings._PortableDefaults(defaults)
        return defaults
    }

    static _PortableDefaults(defaults) {
        general := defaults["General"], features := defaults["Features"]
        for name in ["LaunchAtLogin", "SwitchToEnglishInput", "RestoreInput", "SendToMenu", "StartMenuShortcut"]
            general[name] := 0
        general["CapsLock"] := ""
        general["FileManager"] := ""
        applications := features["Applications"]
        applications["StoreApps"] := 0
        applications["Folders"] := AppSettings._ApplicationFolders()
        applications["FileTypes"] := Platform.IsMac ? ["*.app"] : ["*.desktop"]
        features["FileSearch"]["UseEverything"] := 0
        features["FileSearch"]["EverythingFilter"] := ""
        features["FileSearch"]["ScopeFolders"] := ["A_Desktop", "A_MyDocuments", Platform.Join(Platform.Home, "Downloads")]
        features["FileSearch"]["ScopeExclude"] := "i)/(node_modules|\.git|__pycache__)(/|$)"
        features["FileSearch"]["TypeFilters"][6] := Platform.IsMac ? "exe = app sh command" : "exe = desktop sh AppImage"
        features["Terminal"]["Shell"] := Platform.IsMac ? "zsh" : "bash"
        features["System"]["SettingsPages"] := 0
        features["Clipboard"]["IgnoreApps"] := ["keepass", "keepassxc", "1password", "bitwarden"]
        features["Snippets"]["ExpandExclude"] := "ahk_exe keepass, ahk_exe keepassxc, ahk_exe 1password, ahk_exe bitwarden"
        defaults["Extensions"]["QuickSwitch"]["Enabled"] := 0
        defaults["Extensions"]["AutoDate"]["Enabled"] := 0
        defaults["Hotkeys"] := []
    }

    ; Stock Windows choices get portable runtime values; saving retains their originals until edited.
    static EffectiveDefaults(data) {
        AppSettings._runtimeFallbacks := []
        if Platform.IsWindows
            return data
        defaults := AppSettings.Defaults()
        applications := data["Features"]["Applications"]
        if AppSettings._SameTokens(applications["Folders"], ["A_Programs", "A_ProgramsCommon", "A_Desktop", "A_DesktopCommon"])
            AppSettings._SetEffective(data, ["Features", "Applications", "Folders"], defaults["Features"]["Applications"]["Folders"])
        if AppSettings._SameTokens(applications["FileTypes"], ["*.lnk", "*.exe", "*.url", "*.appref-ms"])
            AppSettings._SetEffective(data, ["Features", "Applications", "FileTypes"], defaults["Features"]["Applications"]["FileTypes"])
        if (data["Features"]["Terminal"]["Shell"] = "cmd")
            AppSettings._SetEffective(data, ["Features", "Terminal", "Shell"], defaults["Features"]["Terminal"]["Shell"])
        if (data["General"]["FileManager"] = "explorer.exe" || data["General"]["FileManager"] = "explorer")
            AppSettings._SetEffective(data, ["General", "FileManager"], "")
        if AppSettings._SameValue(data["CustomCommands"], AppSettings._WindowsCommands())
            AppSettings._SetEffective(data, ["CustomCommands"], defaults["CustomCommands"])
        return data
    }

    static _SetEffective(data, path, value) {
        parent := AppSettings._ParentFor(data, path), key := path[path.Length]
        AppSettings._runtimeFallbacks.Push({Path: path, Stored: AppSettings._CopyValue(parent[key]), Effective: AppSettings._CopyValue(value)})
        parent[key] := value
    }

    static _ParentFor(data, path) {
        parent := data
        Loop path.Length - 1
            parent := parent[path[A_Index]]
        return parent
    }

    static _CopyValue(value) => JSON.Parse(JSON.Stringify(value))

    static _SameTokens(first, second) {
        if !(first is Array) || first.Length != second.Length
            return false
        counts := Map()
        for token in second
            counts[StrLower(token)] := (counts.Has(StrLower(token)) ? counts[StrLower(token)] : 0) + 1
        for token in first {
            if !(token is String)
                return false
            key := StrLower(token)
            if (!counts.Has(key) || !counts[key])
                return false
            counts[key] -= 1
        }
        return true
    }

    static _SameValue(first, second) {
        if (first is Array || second is Array) {
            if !(first is Array && second is Array) || first.Length != second.Length
                return false
            for index, value in first
                if !AppSettings._SameValue(value, second[index])
                    return false
            return true
        }
        if (first is Map || second is Map) {
            if !(first is Map && second is Map) || first.Count != second.Count
                return false
            for key, value in first
                if !second.Has(key) || !AppSettings._SameValue(value, second[key])
                    return false
            return true
        }
        return first == second
    }

    static _ApplicationFolders() {
        if Platform.IsMac
            return ["/Applications", "/System/Applications", Platform.Join(Platform.Home, "Applications")]
        folders := [Platform.Join(Platform.UserDataDir, "applications")]
        roots := EnvGet("XDG_DATA_DIRS")
        if (roots = "")
            roots := "/usr/local/share:/usr/share"
        for root in StrSplit(roots, ":")
            if (SubStr(root, 1, 1) = "/")
                folders.Push(Platform.Join(root, "applications"))
        folders.Push("A_Desktop")
        return folders
    }

    ; 默认的自定义命令: 每种类型都有, 让新用户看到能做什么 (已有的用户不受影响)
    static _DefaultCommands() {
        if !Platform.IsWindows
            return AppSettings._PortableCommands()
        return AppSettings._WindowsCommands()
    }

    static _WindowsCommands() {
        commands := []
        for row in [
            ; 文件 / 程序: 运行程序, 或打开文件; Arguments 附带参数
            ["Notepad"             , "File"   , "notepad.exe"            , ""                                       , "np"],
            ["Edit hosts file"     , "File"   , "notepad.exe"            , "C:\Windows\System32\drivers\etc\hosts"  , "hosts"],
            ["Paint"               , "File"   , "mspaint.exe"            , ""                                       , ""],
            ; 文件夹: 用文件管理器打开; 可以用 A_Desktop 等内置变量或 %UserProfile% 等环境变量
            ["Desktop"             , "Folder" , "A_Desktop"              , ""                                       , ""],
            ["Downloads"           , "Folder" , "%UserProfile%\Downloads", ""                                       , "dl"],
            ["ALTRun Folder"       , "Folder" , "A_ScriptDir"            , ""                                       , ""],
            ["Documents subfolder" , "Folder" , "%UserProfile%\Documents\{query}", ""                               , "docs"],   ; {query}: "docs 文件夹名"
            ; 命令行: 程序 + 参数
            ["IP Configuration"    , "Command", "cmd.exe"                , "/k ipconfig /all"                       , "ipconfig"],
            ["Ping"                , "Command", "cmd.exe"                , "/k ping {query}"                        , "ping"],     ; {query}: "ping 10.0.0.1"
            ; 网址: 网页, 也可以是 ms-settings: 等系统链接
            ["ALTRun on GitHub"    , "Url"    , "https://github.com/zhugecaomao/ALTRun", ""                     , "altrun"],
            ["Google Maps"         , "Url"    , "https://www.google.com/maps/search/{query}", ""                 , "maps"],     ; {query}: "maps Changi Airport"
            ["Windows Update"      , "Url"    , "ms-settings:windowsupdate", ""                                  , ""]
        ]
            commands.Push(Map("Title", row[1], "Type", row[2], "Target", row[3], "Arguments", row[4], "Keyword", row[5]))
        return commands
    }

    static _PortableCommands() {
        commands := []
        rows := [
            ["Home", "Folder", Platform.Home, "", "home"],
            ["Desktop", "Folder", "A_Desktop", "", ""],
            ["Downloads", "Folder", Platform.Join(Platform.Home, "Downloads"), "", "dl"],
            ["ALTRun Folder", "Folder", "A_ScriptDir", "", ""],
            ["Documents subfolder", "Folder", Platform.Join(A_MyDocuments, "{query}"), "", "docs"],
            ["ALTRun on GitHub", "Url", "https://github.com/zhugecaomao/ALTRun", "", "altrun"],
            ["Google Maps", "Url", "https://www.google.com/maps/search/{query}", "", "maps"]
        ]
        if Platform.IsMac
            rows.InsertAt(1, ["TextEdit", "File", "/System/Applications/TextEdit.app", "", "edit"])
        for row in rows
            commands.Push(Map("Title", row[1], "Type", row[2], "Target", row[3], "Arguments", row[4], "Keyword", row[5]))
        return commands
    }

    ; 默认的文字片段: 日期、剪贴板、写邮件常用的几段 (输入 ;关键字 自动展开, 或在搜索窗口里搜名称)
    static _DefaultSnippets() {
        snippets := []
        for row in [
            ["Today's date"             , "today", "{date}"],
            ["Date and time"            , "now"  , "{datetime}"],
            ["Paste as plain text"      , "plain", "{clipboard}"],
            ["Email: thank you"         , "thx"  , "Hi {cursor},`r`n`r`nThank you for your email. I will look into it and get back to you shortly.`r`n`r`nBest regards,"],
            ["Email: please find attached", "pfa", "Hi,`r`n`r`nPlease find attached {cursor} for your reference.`r`n`r`nBest regards,"],
            ["Email: meeting request"   , "meet" , "Hi,`r`n`r`nWould you be available for a short meeting on {cursor}? Please let me know a time that suits you.`r`n`r`nThanks,"],
            ["Email signature"          , "sig"  , "Best regards,`r`n`r`nYour Name`r`nJob Title | Company`r`nPhone: +1 234 567 890"],
            ["My address"               , "addr" , "123 Example Street`r`nCity, Country 12345"]
        ]
            snippets.Push(Map("Name", row[1], "Keyword", row[2], "Text", row[3], "AutoExpand", 1))
        return snippets
    }

    static _DefaultEngines() {
        engines := []
        for row in [
            ["google"   , "g"   , "Google"   , "https://www.google.com/search?q={query}"],
            ["bing"     , "bing", "Bing"     , "https://www.bing.com/search?q={query}"],
            ["baidu"    , "bd"  , "Baidu"    , "https://www.baidu.com/s?wd={query}"],
            ["github"   , "gh"  , "GitHub"   , "https://github.com/search?q={query}"],
            ["wikipedia", "wiki", "Wikipedia", "https://en.wikipedia.org/wiki/Special:Search?search={query}"],
            ["youtube"  , "yt"  , "YouTube"  , "https://www.youtube.com/results?search_query={query}"],
            ["taobao"   , "tb"  , "Taobao"   , "https://s.taobao.com/search?q={query}"],
            ["jd"       , "jd"  , "JD.com"   , "https://search.jd.com/Search?keyword={query}&enc=utf-8"],
            ["translate", "tr"  , "Google Translate", "https://translate.google.com/?sl=auto&tl=zh-CN&text={query}"]
        ]
            engines.Push(Map("Id", row[1], "Keyword", row[2], "Title", row[3], "Url", row[4]))
        return engines
    }
}

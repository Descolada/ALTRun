[English](Installation) · **中文**

# 安装与升级

## 已发布 Windows 安装包的系统要求
- Windows 10 或 Windows 11 (64 位)
- 已发布的可执行文件包含 AutoHotkey，不需要另装解释器
- 不需要 .NET、Electron 或其他运行库; 下载的 zip 不到 1 MB, 解压后约 2 MB

## 用 Keysharp 运行当前源码

当前源码需要包含解析器和编译器组件的 [Keysharp](https://github.com/keysharp-org/Keysharp)。源码使用 `#Import`、平台条件指令和托管辅助代码，AutoHotkey v2 与 Ahk2Exe 无法运行或编译它。安装 Keysharp 在本机系统上的依赖，保留 `ALTRun.ahk`、`ALTRun.Modules.ahk`、`Lib/`、`Src/`、`Resources/`，在 ALTRun 文件夹中运行：

```powershell
# Windows
& 'C:\path\to\Keysharp.exe' .\ALTRun.ahk
```

```sh
# Linux 或 macOS
/path/to/Keysharp ALTRun.ahk
```

Linux/macOS 使用标准控件界面。Linux 通过 XDG `.desktop` 文件发现应用，macOS 扫描 `.app` 包。文件浏览支持 `/绝对路径/`、`~/`、`$HOME/`，Unix 文件身份保留大小写。终端与 `.sh`、`.py`、`.ps1`、`.ahk`/`.ks` 脚本使用本机解释器及参数数组；后台脚本捕获标准输出/错误，超时会终止整个进程树。输出按 UTF-8 解码；Windows 脚本调用仍输出 OEM 编码的旧工具时，应把输出转为 UTF-8。运行源码脚本时须保留 Keysharp 编译器。

标准界面已在 Windows 和 Ubuntu 24.04 的 X11/Xvfb 环境通过冒烟检查，涵盖搜索结果、操作面板、偏好设置和文件夹浏览。这些检查不代表验证了原生 Wayland 或全局钩子集成。macOS 为实验性支持，尚未验证。全局热键、托盘、窗口枚举/激活和剪贴板自动化取决于 Keysharp 桌面后端与桌面会话。窗口管理器可能占用 `Alt+Space`，可在偏好设置里换一个热键。

Everything、Microsoft Store 索引、资源管理器/Total Commander 对话框快速跳转、Windows 输入法/CapsLock、外壳属性/提权、Windows 启动/开始菜单/“发送到”集成仅限 Windows，在其它平台禁用。其它平台使用本地文件索引。可写的源码目录在程序旁保留 `Data/`；否则使用本机用户应用数据位置：Linux 的 `$XDG_DATA_HOME/ALTRun` 或 `~/.local/share/ALTRun`，macOS 的 `~/Library/Application Support/ALTRun`。

现有可下载程序、Scoop/winget 包和发布工作流都是 AutoHotkey Windows 构建，不包含此 Keysharp 移植版。用 Keysharp 检查更新时打开发布页面或提示更新源码，不会用 AutoHotkey 包替换 Keysharp 可执行文件。请从源码更新此版本；Keysharp 发布需要单独的平台打包工作流。

### Linux 桌面功能

应用与文件索引递归监视目录变化，并能在目录删除后重建时恢复。应用搜索包含本地化通用名称与关键字，遵守 XDG 桌面 ID 的优先级和隐藏覆盖，支持常用位图图标主题及继承；只有 SVG/XPM 的图标使用内置图标。Shell/Python 脚本支持 shebang 解释器，终端发现覆盖常见 GNOME、KDE、Xfce、MATE、Wayland 和独立终端。

`recent ...` 按时间读取 `$XDG_DATA_HOME/recently-used.xbel` (默认 `~/.local/share/recently-used.xbel`)，忽略私密、已删除和远程文档。登录自启只管理 `$XDG_CONFIG_HOME/autostart/org.keysharp.ALTRun.desktop` (默认 `~/.config/autostart/`)，不会覆盖无关条目；格式遵循 [freedesktop 规范](https://specifications.freedesktop.org/autostart/latest/)。

操作面板支持复制文件到剪贴板，有 `gio` 时可移入回收站；剪切文件仍仅限 Windows。有 `gdbus` 和支持的桌面会话时，“显示文件位置”通过 `org.freedesktop.FileManager1` 选中文件，否则打开所在目录。系统命令检测 `systemctl`/`loginctl`、`wpctl`/`pactl`、`playerctl` 及 GNOME/KDE/Xfce 工具；电源、注销和清空回收站保留确认设置。工具存在不代表已有桌面授权、正在播放的媒体或休眠支持。

更新和汇率下载使用异步请求。标准界面的设置包含剪贴板、书签、窗口搜索、显示密度、输入提示和 Tab 导航。原生 Wayland 全局输入与 Windows 专用扩展仍不属于上述已验证范围。

## 安装已发布的 Windows 版本
ALTRun 是绿色软件, 不需要安装, 不写注册表。

1. 从 [Releases](https://github.com/zhugecaomao/ALTRun/releases/latest) 下载最新版本, 解压到任意文件夹 (例如 `D:\Apps\ALTRun`)
   - 运行当前源码请参考上面的 Keysharp 说明
2. 运行后托盘出现 ALTRun 图标, 按 `Alt+Space` 呼出搜索窗口
3. 第一次运行会在后台建立应用索引, 几秒后就能搜到开始菜单里的程序

第一次运行时如果 Windows SmartScreen 提示 "Windows 已保护你的电脑", 点 **更多信息** → **仍要运行**; 杀毒软件误报见 [常见问题](FAQ#杀毒软件报毒)。

建议放在自己能写入的文件夹里 (例如 `D:\Apps\ALTRun`), 设置和数据保存在程序目录的 `Data\` 里, 整个文件夹可以直接带走。放在需要管理员权限才能写入的文件夹 (例如 `C:\Program Files`) 时, 设置和数据改为保存在 `%APPDATA%\ALTRun\`, 但一键更新不能替换程序文件, 要手动下载新版本。

### 用 Scoop 安装
[Scoop](https://scoop.sh/) 是 Windows 的命令行软件管理工具。ALTRun 的仓库本身就是一个 Scoop bucket:

```powershell
scoop bucket add altrun https://github.com/zhugecaomao/ALTRun
scoop install altrun
```

- 安装后开始菜单里有 "Scoop Apps → ALTRun", 程序在 `scoop\apps\altrun\current`
- 升级: 先退出 ALTRun, 再运行 `scoop update altrun`。设置和数据 (`Data\`, 包括 `Data\ALTRun.json`)、`Themes\` 都会保留
- 卸载: `scoop uninstall altrun`, 设置留在 `scoop\persist\altrun`, 重新安装后自动恢复; 连设置一起删除用 `scoop uninstall altrun --purge`
- 用 Scoop 安装时, "检查更新" 发现新版本会提示用 `scoop update altrun` 升级, 不要手动解压覆盖

### 用 winget 安装
winget 清单已经准备好 (`packaging\winget`), 等 [winget 官方仓库](https://github.com/microsoft/winget-pkgs) 收录后就可以:

```powershell
winget install zhugecaomao.ALTRun
winget upgrade zhugecaomao.ALTRun     # 以后升级 (先退出 ALTRun)
```

- 程序在 `%LOCALAPPDATA%\Microsoft\WinGet\Packages\zhugecaomao.ALTRun_...`, 命令行里可以直接输入 `altrun` 启动
- 升级和卸载只删除 zip 里原有的文件, 设置和数据 (`Data\`、`Themes\`) 会保留; `winget uninstall --purge` 才会连同它们一起删除
- winget 本身不创建开始菜单快捷方式: 第一次用 `altrun` 启动后, ALTRun 会自己添加到开始菜单 (偏好设置 → 通用 → "添加到开始菜单")
- 卸载前先在 偏好设置 → 通用 里关闭 "开机自动启动"、"添加到开始菜单"、"添加到 '发送到' 菜单", 否则这些快捷方式会留下
- 第一次运行时 Windows 可能提示 "无法验证发布者" (程序是从网上下载的), 选择 "运行" 即可
- 升级和卸载都保留设置、`Data\`、`Themes\`; 卸载后想彻底删除, 手动删掉上面的文件夹

## 程序目录里的文件
| 文件 / 文件夹 | 说明 | 升级时 |
|---|---|---|
| `ALTRun.ahk` 或 `ALTRun.exe` | 主程序 | 替换 |
| `Lib\` `Src\` | 程序代码 (源码版) | 替换 |
| `Resources\` | 随程序发布的数据: 简繁对照表、内置主题、界面语言、图标 | 覆盖 |
| `Data\ALTRun.json` | 你的全部设置和自定义命令、片段 | 保留 (自动升级格式) |
| `Data\` 里的其它文件 | 应用索引、文件索引、学习记录、剪贴板历史、使用统计 | 保留 (删掉会重新生成) |
| `Themes\` | 你自己的主题 | 保留 |
| `Scripts\` | 你自己的[脚本](Extensions#脚本扩展) | 保留 |

## 开机启动、开始菜单、"发送到"
在 偏好设置 → 通用 里设置:
- **开机自动启动**: 在 "启动" 文件夹里创建快捷方式
- **添加到开始菜单**: 可以从开始菜单打开 ALTRun
- **添加到 "发送到" 菜单**: 在资源管理器里右键文件 → 发送到 → ALTRun, 把它加为自定义命令 (1 个时弹出编辑对话框, 多个时直接全部添加)

## 升级
### 一键更新
ALTRun 在后台到 GitHub 检查新版本 (启动时和之后每 6 小时一次) (偏好设置 → 通用 → "自动检查更新")。和 Alfred 一样不弹窗: 发现新版本后, 呼出搜索窗口时空搜索框下面会显示一条 **"发现新版本: ALTRun x"** (下面一行是当前版本和按键说明) (输入 `更新` / `update` 也能找到):
- `Enter`: **安装更新**。下载新版本, 核对 SHA256 校验值, 替换程序文件后自动重新启动。`Data\` (设置和数据)、`Themes\` 不会改动
- `→`: **更新说明** (打开 GitHub 上这个版本的说明), 或 **跳过此版本** (有更新的版本时再提醒)

开机后先等 1 分钟 (网络可能还没连上), 离上次检查满 1 小时就检查, 所以每天开机就能发现前一天发布的版本; 之后每小时看一下离上次检查是否满 6 小时。检查的时间和跳过的版本记在 `Data\Update.json`, 改完设置重新载入 ALTRun 不会反复检查。网络不通时只写日志, 一小时后再试。

想马上检查: 托盘菜单 → "检查更新", 或搜索 "检查更新" (`CheckUpdate`)。手动检查总会弹出结果: 已是最新版本, 或 "ALTRun 有可用的更新" 对话框: 安装更新 / 更新说明 / 稍后。

更新过程中出现任何问题 (网络、校验、写入权限), 原来的程序保持不变, 并提示打开下载页面手动更新。命令行 `ALTRun.exe -Update` 会直接检查并安装更新, 不询问。

以下情况不能一键更新, 搜索窗口里的那一条会说明怎么做:
- 用 Scoop / winget 安装: `Enter` 复制升级命令 (`scoop update altrun` / `winget upgrade zhugecaomao.ALTRun`), 退出 ALTRun 后在终端里运行
- 运行源码 `ALTRun.ahk`: 用 `git pull` 更新, 或 `Enter` 打开下载页面
- 程序放在没有写入权限的文件夹里: `Enter` 打开下载页面

### 手动更新
把新版本复制覆盖到程序目录即可, 设置和数据不受影响。设置文件的格式有变化时, ALTRun 启动时会自动升级, 并先备份原文件。

### 从 2.x (v2026.08.12 及更早) 升级到 3.0
1. 托盘图标 → 退出旧版本
2. 把新版本的压缩包解压到原来的 ALTRun 文件夹, 覆盖 `ALTRun.exe`
3. 运行 `ALTRun.exe`

第一次运行时, 旧版本的 `ALTRun.ini` 会自动导入 (设置、自定义命令、热键), 保存为新的 `Data\ALTRun.json`。`ALTRun.ini` 保持不变: 想退回旧版本, 放回旧的 `ALTRun.exe` 即可。开机启动、开始菜单、"发送到" 的快捷方式沿用同一个 `ALTRun.exe`, 不需要重新设置。

- **保留**: 呼出热键、开机启动等通用设置; 用户命令 (File / Dir / CMD / URL → 自定义命令, Clip → 文字片段); 索引目录、文件类型和深度; 结构计算开关; 对话框快速跳转; 一键加日期 (Ctrl+D); PT 工具箱设置; 条件热键
- **不再保留**: 内置命令列表 (由 [系统命令](Extensions#系统命令) 取代)、旧的索引 (会重新建立)、执行历史、使用统计、旧的列表外观选项

旧版本的 `Res\` 文件夹已改名为 `Resources\`, 启动时会自动把 `Res\` 里你自己放的文件移过去。

## 卸载
1. 托盘菜单 → 退出
2. 在 偏好设置 → 通用 里先关闭 "开机自动启动"、"添加到开始菜单"、"添加到 '发送到' 菜单" (或者手动删除对应的快捷方式)
3. 删除程序文件夹

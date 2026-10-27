<h1 align="center"><img width="48" alt="ALTRun" src="docs/images/logo.png" /> ALTRun</h1>

<p align="center"><a href="README.md">English</a> | <b>简体中文</b></p>

<p align="center">
  <b>轻量、开源的 Windows 启动器，操作方式参照 macOS 上的 <a href="https://www.alfredapp.com/">Alfred</a></b><br>
  按 <code>Alt+Space</code>，输入几个字母，按 <code>Enter</code>：程序、文件、网页、计算、剪贴板、系统命令，一个窗口完成
</p>

<p align="center">
  <a href="https://github.com/zhugecaomao/ALTRun/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/zhugecaomao/ALTRun?label=release"></a>
  <a href="https://github.com/zhugecaomao/ALTRun/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/zhugecaomao/ALTRun/total"></a>
  <a href="https://github.com/zhugecaomao/ALTRun/actions/workflows/tests.yml"><img alt="Tests" src="https://github.com/zhugecaomao/ALTRun/actions/workflows/tests.yml/badge.svg?branch=main"></a>
  <a href="https://www.autohotkey.com/"><img alt="AutoHotkey v2" src="https://img.shields.io/badge/AutoHotkey-v2.0-334455?logo=autohotkey"></a>
  <img alt="Windows" src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/github/license/zhugecaomao/ALTRun"></a>
</p>

<p align="center">
  <a href="https://zhugecaomao.github.io/ALTRun/">官网</a> ·
  <a href="#为什么选择-altrun">为什么选择</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#功能">功能</a> ·
  <a href="#快捷键">快捷键</a> ·
  <a href="https://github.com/zhugecaomao/ALTRun/wiki">使用文档 (Wiki)</a> ·
  <a href="CHANGELOG.md">更新日志</a>
</p>

<p align="center">
  <img src="docs/images/screenshots/demo.png" width="700" alt="ALTRun：输入即搜、操作面板、单位换算、文件搜索">
</p>


## 为什么选择 ALTRun
- **小巧**：约 2.5 MB，由一个 `ALTRun.exe` 和少量资源文件组成，无需安装 .NET、Electron 或其他运行库。
- **快速响应**：输入即出结果；配合 [Everything](https://www.voidtools.com/) 可在毫秒内搜索全盘文件，否则使用内置索引。
- **智能排序**：根据使用习惯自动调整排名；支持单词首字母（`vsc` → Visual Studio Code）和拼音首字母（`wx` → 微信；文件也可以：`cs` → 测试文件.zip），并高亮匹配内容。
- **不只是启动器**：[对话框快速跳转（Quick Switch）](#功能)可将打开 / 保存对话框快速切换到 Total Commander、Directory Opus 或资源管理器中已打开的文件夹；可操作任意程序中选中的文字、文件或网址；输入 `;关键字` 可展开文字片段。
- **多合一**：集成计算与单位换算、网页搜索、浏览器书签、剪贴板历史、文字片段、系统命令和终端，无需为每项任务安装单独工具。
- **键盘优先**：按 `→` 打开操作面板，状态栏提示 `Enter` 的操作，按 `F3` 直接编辑，用 `Ctrl+1`～`Ctrl+9` 快速打开对应结果；按 `Ctrl+Enter` 可打开文件所在文件夹，或将文本粘贴到当前活动窗口。
- **便携与隐私**：免安装、不写注册表、无需管理员权限，无后台服务或驱动。数据默认保存在本机；部分剪贴板数据存于 `%LOCALAPPDATA%\ALTRun`。不收集遥测数据；联网用于更新、可选汇率换算和用户主动下载的网站图标。
- **自动更新**：新版本会在搜索窗口中提示，按 `Enter` 即可安装；更新包会校验 SHA256 并保留设置，也支持 Scoop。
- **个性化定制**：支持简体中文、繁體中文、English、日本語四种界面语言和 22 套内置主题（每套都有宽松 / 常规 / 紧凑三种密度）；可跟随 Windows 浅色 / 深色模式，也可通过 JSON 文件自定义主题和设置。
- **免费开源**：采用 GPL-3.0 许可证；每个 Pull Request 都会在 Windows 上自动运行 8,000 余项测试。

### 用 Keysharp 运行当前源码

安装或编译适合本机系统的 [Keysharp](https://github.com/keysharp-org/Keysharp)，包含解析器和编译器组件。保留 `ALTRun.ahk`、`ALTRun.Modules.ahk`、`Lib/`、`Src/`、`Resources/`，在 ALTRun 文件夹中运行：

```powershell
# Windows
& 'C:\path\to\Keysharp.exe' .\ALTRun.ahk
```

```sh
# Linux 或 macOS
/path/to/Keysharp ALTRun.ahk
```

源码移植版在 Windows、Linux 和 macOS 上使用同一套 Picture 绘制的启动器：分行显示标题与路径、圆角选中背景、图标和键盘提示，并保留原生搜索输入框。偏好设置、项目编辑器和通知跟随所选主题；Windows 和 GTK 设置控件成对设置文字与背景颜色，包括下拉列表项和禁用按钮。Windows 上先设置 ALTRun 独立的进程应用标识，再设置图标，避免与其它 Keysharp 脚本共用任务栏分组。

![Keysharp 深色主题启动器，使用虚构示例数据](docs/images/screenshots/keysharp-launcher-dark.png)

[Windows 深色设置](docs/images/screenshots/keysharp-preferences-windows-dark.png) · [Linux/GTK 深色设置](docs/images/screenshots/keysharp-preferences-linux-dark.png)

偏好设置窗口可调整大小，切换页面时保留窗口尺寸。Windows 热键框在应用控件主题后仍保留已录制的快捷键；启动时会自动修复被保存为 `Alt+Space` 等显示名称的热键。

Linux 启动器使用本机按键事件及其修饰键处理导航，双击打开选中结果。显示启动器时先请求 GTK 激活窗口，再聚焦搜索框；搜索文字选区显式使用主题颜色，让 Ctrl+A 全选与部分选择清晰可见。根据本机窗口焦点在切换应用时隐藏。Wayland 无法提供窗口几何信息时，仍可按 Escape 隐藏窗口或执行搜索结果。底部菜单命令和结果右键菜单在启动器内的操作面板中显示，避免 GTK 弹出菜单抓取输入时导致 Cinnamon 的 Wayland 会话崩溃。应用图标采用兼容 GTK 的 ICO 帧，修复托盘和文件预览中的乱码图像。

Hyprland 中，结果数量变化时搜索框的位置保持不变，窗口在其下方增高或缩小；重新打开空搜索时恢复紧凑高度。启动器位图保留渲染后的像素尺寸，无需悬停即可保持结果清晰、比例正确。Wayland 窗口尺寸与位置通过 Keysharp 的合成器集成调整。

NixOS 启动外部应用、浏览器链接和终端时，不继承 Keysharp 私有的本机库搜索路径；子 Keysharp 脚本仍保留运行时所需的库。文件夹命令保留大小写，目标不存在时显示错误：在区分大小写的文件系统中，`docs ALTRun` 和 `docs ALTRUN` 指向不同文件夹。

Wayland 上的窗口置顶需要 Keysharp 桌面代理与合成器集成正常工作。Cinnamon 会话崩溃后，可用 `systemctl --user restart keysharp-desktop.service` 重启失败的代理，再运行 `keysharp-desktop probe`，应显示 `backend=cinnamon` 且有可用操作。启动频率限制及恢复步骤见[安装与故障排查](docs/wiki/Installation-zh.md)。

支持 Linux `.desktop` 应用索引、macOS `.app` 索引、本机路径处理、已安装的终端和跨平台脚本输出捕获。标准界面已在 Windows 和 Ubuntu 24.04 的 X11/Xvfb 环境通过冒烟检查，涵盖搜索结果、操作面板、偏好设置和文件夹浏览。macOS 为实验性支持，尚未验证。全局热键、托盘、窗口切换和剪贴板自动化取决于 Keysharp 桌面后端与桌面会话。Hyprland 验证覆盖启动器几何、位图绘制及基本交互；全局输入和其它合成器集成仍需单独验证。如果窗口管理器占用了 `Alt+Space`，可在偏好设置里换一个热键。

Everything、Microsoft Store 索引、资源管理器/Total Commander 对话框快速跳转、Windows 输入法/CapsLock 集成、外壳属性/提权、Windows 开机启动和“发送到”快捷方式仍是 Windows 集成，在其它系统上会禁用。Linux/macOS 使用本地文件索引。脚本支持 `.ahk`/`.ks`、`.sh`、`.py`、`.ps1`，需要对应解释器；`.bat`/`.cmd` 仅限 Windows。通过脚本扩展启动源码脚本时，Keysharp 的编译器组件也必须保留。

当前源码不能由 AutoHotkey v2/Ahk2Exe 运行或编译。现有 Windows 发布工作流和可下载的 AutoHotkey 可执行文件不包含这个 Keysharp 移植版。用 Keysharp 运行时只检查更新，不会用这些二进制文件替换自身；请从源码更新。数据位置和平台限制见[安装与升级](docs/wiki/Installation.md)。

Linux 新增应用/文件索引递归监视、XDG 登录自启、最近文档搜索 (`recent ...`)、应用本地化名称与关键字、更多终端及异步更新/汇率请求。标准界面的设置支持剪贴板、书签、窗口搜索、密度和 Tab 行为。移入回收站需要 `gio`；有 `gdbus` 时使用 `org.freedesktop.FileManager1` 选中文件，否则打开所在文件夹。电源/会话、音量/媒体和系统工具命令按已安装工具显示，是否可执行还取决于桌面权限。

登录自启只管理 ALTRun 自己的 `$XDG_CONFIG_HOME/autostart/org.keysharp.ALTRun.desktop` (默认 `~/.config/autostart/`)。最近文档读取 `$XDG_DATA_HOME/recently-used.xbel` (默认 `~/.local/share/`)，忽略私密、已删除和远程文件。冒烟测试不会改动真实自启项或执行系统操作。自启文件遵循 [freedesktop 规范](https://specifications.freedesktop.org/autostart/latest/)。

下方上游 Windows 发布包使用 AutoHotkey；当前源码请按上面的 Keysharp 说明运行。

## 快速开始
1. [下载最新版本](https://github.com/zhugecaomao/ALTRun/releases/latest)，解压到任意文件夹，运行 `ALTRun.exe`——无需安装，也无需 AutoHotkey。
2. 按 `Alt+Space`（或 `Alt+R`），输入程序或文件名称，再按 `Enter`。
3. 输入 `?` 查看全部搜索语法和快捷键；按 `Ctrl+,` 打开偏好设置。

如果 Windows SmartScreen 拦截程序，点击 **更多信息** → **仍要运行**。杀毒软件误报请参阅[常见问题](https://github.com/zhugecaomao/ALTRun/wiki/FAQ-zh#杀毒软件报毒)。

也可以通过 Scoop 或 winget（审核收录后）安装，或使用 AutoHotkey v2 直接运行 `ALTRun.ahk`。详情请参阅[其他安装方式与升级](#其他安装方式与升级)。


## 功能
**搜索**
- **搜索窗口**：输入即搜，显示标题和路径；窗口高度随结果变化，可拖动并记住位置，多显示器时显示在鼠标所在屏幕。
- **应用**：自动索引开始菜单、桌面和 Microsoft Store 应用，新装的软件几秒后就能搜到；不需要的应用和内置命令可按 `Ctrl+Del` 隐藏，在偏好设置中恢复。
- **匹配高亮**：标题中与输入匹配的部分（连续字符、单词首字母、拼音首字母）以高亮色显示。
- **文件和文件夹**：在空白搜索框中先按 `空格` 再输入名称（或 `'报告`、`open 报告`）；Everything 运行时搜索全盘，否则使用内置索引；输入 `D:\Projects\` 这样的路径可以逐级浏览文件夹；`recent 报告` 搜最近在任何程序里打开过的文件。
- **自定义命令**：文件、文件夹、程序（可带参数）、网址，可设置关键字（可写多个，用逗号分隔）；在资源管理器中右键 → 发送到 → ALTRun 即可添加（可多选）；可检查路径已失效的命令。
- **学习排序**：记住每次输入所选的结果，常用项自动靠前。
- **置顶和最近使用**：呼出窗口还没输入时，直接列出置顶的项目和最近打开的项目。
- **使用统计**：按天、按功能统计使用次数（仅记录次数）。
- **计算器**：直接输入算式；支持单位换算（`10 km in mi`）、进制换算（`255 in hex`）、日期加减（`today + 30 days`）和可选的货币换算（`100 usd to sgd`）。
- **网页搜索**：`g 关键词`（Google）、`bd 关键词`（百度）等，可自定义搜索引擎（输入 `g` 加空格、不输入搜索词就搜索剪贴板里的文字）；无结果时提供网页搜索。
- **浏览器书签**：搜索 Chrome、Edge、Brave、Vivaldi 的书签；`bm 关键词` 仅搜索书签。
- **切换窗口**：输入窗口标题或程序名切换到已打开的窗口；`w 关键词` 仅搜索窗口，`w ` 列出全部。
- **系统命令**：锁屏、睡眠、关机、清空回收站、音量和媒体控制、Windows 工具、Windows 设置页面（显示、蓝牙、WLAN 等 40 多个）、文本转换（大小写、排序、简繁转换等）。

**效率**
- **操作面板**：选中结果后按 `→`（或右键）列出可用操作，如以管理员身份运行、打开所在位置、复制路径、在此处打开终端、属性。
- **选中内容操作**：在任意程序中选中文字、文件或网址，按 `Ctrl+Alt+\` 调出操作，如网页搜索、保存为片段、转换后替换原文。
- **直接编辑**：按 `F3` 编辑命令、片段或搜索引擎；应用和文件可一键添加为自定义命令。
- **剪贴板历史**：按 `Ctrl+Alt+C` 或输入 `clip`；同时记录文字、文件和图片；常用的可以置顶；可以粘贴为纯文本；自动忽略密码管理器复制的内容。
- **文字片段**：可按名称、关键字或正文搜索；支持 `{date}`、`{clipboard}`、`{cursor}` 等占位符；在任意程序中输入 `;关键字` 自动展开；可从 Excel / CSV 批量导入，也可导出。
- **终端**：输入 `>ipconfig /all` 直接在终端中运行。
- **大字显示**：按 `Ctrl+L` 全屏显示结果，便于查看电话号码、计算结果等（在偏好设置 → 功能里打开）。

**扩展**
- **对话框快速跳转（Quick Switch）**：在打开 / 保存对话框中按 `Ctrl+G` 跳转到最近使用的文件管理器（Total Commander、Directory Opus 或资源管理器）的当前目录；对话框旁的文件夹面板列出所有已打开和最近使用的文件夹。只有文件夹树的旧式“浏览文件夹”对话框也能用。
- **一键加日期**：重命名文件时按 `Ctrl+D`，在扩展名前添加或更新日期（`Report.docx` → `Report - 28.09.2026.docx`）。
- **自定义热键**：为任意系统命令设置热键，可限定在指定程序中生效。
- **脚本扩展**：把 `.ahk`、`.ps1`、`.bat`、`.py` 脚本放进 `Scripts\` 文件夹，就能在搜索窗口里运行，可以带参数、在后台运行并显示输出。

**结构工程师专用**
- **结构计算**（默认关闭）：计算器结果下方附带梁主筋和配筋面积计算。
- **PT 工具箱**：钢筋 / BRC 面积计算、SPF2M 后张预应力束线型计算，结果可复制到 Excel。


## 截图
| 搜索窗口 | 操作面板（`→`） |
|:---:|:---:|
| <img src="docs/images/screenshots/search.png" alt="搜索窗口"> | <img src="docs/images/screenshots/actions.png" alt="操作面板"> |
| **文件搜索（`空格` + 名称）** | **按类型搜索（`doc` + 名称）** |
| <img src="docs/images/screenshots/files.png" alt="文件搜索"> | <img src="docs/images/screenshots/filetype.png" alt="按类型搜索"> |
| **计算器** | **拼音首字母（`jsb` 找到记事本）** |
| <img src="docs/images/screenshots/calculator.png" alt="计算器"> | <img src="docs/images/screenshots/pinyin.png" alt="拼音首字母"> |
| **剪贴板历史（`clip`）** | **置顶和最近使用（空搜索框）** |
| <img src="docs/images/screenshots/clipboard.png" alt="剪贴板历史"> | <img src="docs/images/screenshots/empty.png" alt="置顶和最近使用"> |
| **浏览文件夹（输入路径）** | **网页搜索（`g` + 关键词）** |
| <img src="docs/images/screenshots/browse.png" alt="浏览文件夹"> | <img src="docs/images/screenshots/websearch.png" alt="网页搜索"> |
| **对话框快速跳转（打开 / 保存对话框下面的文件夹面板）** | **主题（偏好设置 → 外观）** |
| <img src="docs/images/screenshots/quickswitch.png" alt="对话框快速跳转"> | <img src="docs/images/screenshots/prefs-appearance.png" alt="主题"> |
| **窗口切换（`w` + 空格）** | **从资源管理器添加命令（右键 → 发送到 → ALTRun）** |
| <img src="docs/images/screenshots/windows.png" alt="窗口切换"> | <img src="docs/images/screenshots/sendto.png" alt="发送到 ALTRun"> |
| **偏好设置** | **自定义命令** |
| <img src="docs/images/screenshots/prefs-general.png" alt="偏好设置"> | <img src="docs/images/screenshots/prefs-commands.png" alt="自定义命令"> |
| **文字片段** | **脚本扩展** |
| <img src="docs/images/screenshots/prefs-snippets.png" alt="文字片段"> | <img src="docs/images/screenshots/prefs-scripts.png" alt="脚本扩展"> |

<details>
<summary><b>内置主题</b>（共 22 套，每套都有宽松 / 常规 / 紧凑三种密度，点击展开）</summary>

| Dark | Classic | Midnight |
|:---:|:---:|:---:|
| <img src="docs/images/screenshots/theme-dark.png" alt="Dark"> | <img src="docs/images/screenshots/theme-classic.png" alt="Classic"> | <img src="docs/images/screenshots/theme-midnight.png" alt="Midnight"> |
| **Frost** | **Graphite** | **Ocean** |
| <img src="docs/images/screenshots/theme-frost.png" alt="Frost"> | <img src="docs/images/screenshots/theme-graphite.png" alt="Graphite"> | <img src="docs/images/screenshots/theme-ocean.png" alt="Ocean"> |
| **Paper** | **Lavender** | **Rose** |
| <img src="docs/images/screenshots/theme-paper.png" alt="Paper"> | <img src="docs/images/screenshots/theme-lavender.png" alt="Lavender"> | <img src="docs/images/screenshots/theme-rose.png" alt="Rose"> |
| **Forest** | **Sunset** | **HighContrast** |
| <img src="docs/images/screenshots/theme-forest.png" alt="Forest"> | <img src="docs/images/screenshots/theme-sunset.png" alt="Sunset"> | <img src="docs/images/screenshots/theme-highcontrast.png" alt="HighContrast"> |
| **Dark · 紧凑** | **TokyoNight** | **Dracula** |
| <img src="docs/images/screenshots/theme-compact.png" alt="Dark · 紧凑"> | <img src="docs/images/screenshots/theme-tokyonight.png" alt="TokyoNight"> | <img src="docs/images/screenshots/theme-dracula.png" alt="Dracula"> |
| **CatppuccinMocha** | **GruvboxDark** | **SolarizedLight** |
| <img src="docs/images/screenshots/theme-catppuccinmocha.png" alt="CatppuccinMocha"> | <img src="docs/images/screenshots/theme-gruvboxdark.png" alt="GruvboxDark"> | <img src="docs/images/screenshots/theme-solarizedlight.png" alt="SolarizedLight"> |
| **DarkModern** | **LightModern** | **Monokai** |
| <img src="docs/images/screenshots/theme-darkmodern.png" alt="DarkModern"> | <img src="docs/images/screenshots/theme-lightmodern.png" alt="LightModern"> | <img src="docs/images/screenshots/theme-monokai.png" alt="Monokai"> |
| **OneDark** | |  |
| <img src="docs/images/screenshots/theme-onedark.png" alt="OneDark"> | |  |

</details>

截图由 [Tests/Screenshots](Tests/Screenshots/TakeScreenshots.ahk) 在 GitHub Actions 的 Windows 环境中自动生成。


## 快捷键
| 按键 | 功能 |
|---|---|
| `Alt+Space` | 显示 / 隐藏搜索窗口（可在设置中修改） |
| `Enter` | 打开选中项 |
| `Ctrl+Enter` | 文件 / 文件夹：打开所在位置；文字：粘贴到当前窗口 |
| `Alt+Enter` | 复制路径、网址或文字 |
| `Ctrl+1`～`Ctrl+9` | 打开第 N 项 |
| `↑` `↓` / `Ctrl+P` `Ctrl+N` | 上移 / 下移一行 |
| `PgUp` `PgDn` | 上翻 / 下翻一页 |
| `Ctrl+↑` / `Ctrl+↓` | 上一条 / 下一条搜索记录 |
| `Tab` | 自动补全；文件夹：进入浏览 (也可以设成选择下一个结果, 见 偏好设置 → 键盘) |
| `Insert` | 标记多个文件 / 文件夹，再按 `→` 一起操作 |
| `空格`（搜索框为空时，或光标在最前面时） | 进入文件搜索模式，已输入的文字保留；搜索框为空或光标在最前面时按 `Backspace` 返回 |
| `folder 名称` | 仅搜索文件夹 |
| `?` | 速查表：全部语法和快捷键 |
| `→` / 右键 | 操作面板 / 操作菜单 |
| `F3` | 编辑选中项，或将应用、文件、网址添加为自定义命令 |
| `Ctrl+Del` | 删除选中项（需确认）；应用：从结果中隐藏 |
| `Ctrl+C` / `Ctrl+L` | 复制选中项 / 大字显示 |
| `Ctrl+E` | 用编辑程序打开选中的文件（例如 .ahk 脚本） |
| `F2` 或 `Ctrl+,` / `F4` | 偏好设置 / 用记事本编辑 ALTRun.json |
| `F1` | 关于 ALTRun（版本、检查更新、项目主页） |
| `Ctrl+Alt+C` | 剪贴板历史 |
| `Esc` | 关闭操作面板 / 隐藏窗口 |

完整语法（`'文件`、`>命令`、`clip`、`snip`、网页搜索关键字等）见 Wiki：[搜索与快捷键](https://github.com/zhugecaomao/ALTRun/wiki/Usage-zh)。


## 文档
完整文档见 [Wiki](https://github.com/zhugecaomao/ALTRun/wiki)：

| 页面 | 内容 |
|---|---|
| [安装与升级](https://github.com/zhugecaomao/ALTRun/wiki/Installation-zh) | 下载、Scoop / winget、开机启动、自动更新、从 2.x 升级、卸载 |
| [搜索与快捷键](https://github.com/zhugecaomao/ALTRun/wiki/Usage-zh) | 输入语法、快捷键、操作面板、学习排序、使用统计 |
| [自定义命令](https://github.com/zhugecaomao/ALTRun/wiki/Custom-Commands-zh) | 命令类型、带参数的命令、路径变量 |
| [文字片段](https://github.com/zhugecaomao/ALTRun/wiki/Snippets-zh) | 占位符、自动展开、不展开的窗口、导入 / 导出 |
| [文件搜索](https://github.com/zhugecaomao/ALTRun/wiki/File-Search-zh) | Everything 联动、内置索引、排除规则 |
| [主题](https://github.com/zhugecaomao/ALTRun/wiki/Themes-zh) | 内置主题、自定义主题、全部可用的键 |
| [扩展功能](https://github.com/zhugecaomao/ALTRun/wiki/Extensions-zh) | 对话框快速跳转、一键加日期、自定义热键、系统命令、PT 工具箱 |
| [设置文件参考](https://github.com/zhugecaomao/ALTRun/wiki/Configuration-zh) | ALTRun.json 各项的含义和默认值 |
| [常见问题](https://github.com/zhugecaomao/ALTRun/wiki/FAQ-zh) | 热键冲突、搜索不到、杀毒软件误报等 |
| [开发指南](https://github.com/zhugecaomao/ALTRun/wiki/Development-zh) | 架构、新增搜索功能、代码规范、测试 |


## 其他安装方式与升级
**通过 [Scoop](https://scoop.sh/) 安装**（自动创建开始菜单快捷方式，升级时保留设置）：
```powershell
scoop bucket add altrun https://github.com/zhugecaomao/ALTRun
scoop install altrun
scoop update altrun    # 升级（请先退出 ALTRun）
```

winget 清单已提交，等待审核收录；收录后可使用 `winget install zhugecaomao.ALTRun` 安装。

从源码运行：安装 [AutoHotkey v2](https://www.autohotkey.com/)，然后运行 `ALTRun.ahk`。

从较早版本或 2.x 升级，请参阅[安装与升级](https://github.com/zhugecaomao/ALTRun/wiki/Installation-zh)。


## 贡献与反馈
- 报告问题：[提交 Issue](https://github.com/zhugecaomao/ALTRun/issues/new/choose)（请附上 Windows 版本和复现步骤）
- 建议与讨论：[Discussions](https://github.com/zhugecaomao/ALTRun/discussions)
- 贡献代码：请先阅读 [贡献指南](CONTRIBUTING.md#参与贡献)；项目结构、运行测试、新增搜索功能见 Wiki 的[开发指南](https://github.com/zhugecaomao/ALTRun/wiki/Development-zh)

如果 ALTRun 对你有帮助，欢迎点亮星标 ⭐


## Code signing policy
Free code signing provided by [SignPath.io](https://about.signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

- Only `ALTRun.exe` built from this repository's source by the [Release workflow](.github/workflows/release.yml) is signed.
- Committers and reviewers: [zhugecaomao](https://github.com/zhugecaomao)
- Approvers: [zhugecaomao](https://github.com/zhugecaomao)
- Privacy policy: [SECURITY.md](SECURITY.md#privacy-policy)（中文：[隐私说明](SECURITY.md#隐私说明)）


## 许可证与致谢
ALTRun 以 [GPL-3.0](LICENSE) 许可开源 © zhugecaomao

感谢这些项目：
- [ALTRun](https://github.com/etworker/ALTRun)（etworker，Delphi）：名字和最初的设计
- [RunZ](https://github.com/goreliu/runz)（goreliu，AutoHotkey）：用 AutoHotkey 写启动器的思路
- [Alfred](https://www.alfredapp.com/)：操作方式
- [Listary](https://www.listary.com/)：对话框快速跳转参考了它的 Quick Switch
- [pypinyin](https://github.com/mozillazg/python-pinyin)（Copyright (c) 2016 mozillazg, 闲耘；[MIT](https://github.com/mozillazg/python-pinyin/blob/master/LICENSE.txt)）：生僻字和繁体字的拼音首字母

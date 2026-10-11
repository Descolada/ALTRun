# 参与贡献

[English](CONTRIBUTING.md) · **中文**

感谢你愿意改进 ALTRun! 反馈问题、改进文档、补充翻译、提交代码都非常欢迎。提交之前请花几分钟看一下下面的约定。

## 反馈问题
- **Bug**: 用 [Bug 报告模板](https://github.com/zhugecaomao/ALTRun/issues/new?template=bug_report.yml), 写清操作系统、Keysharp 和 ALTRun 版本、复现步骤，最好附上截图；Linux 还请注明桌面与 X11/Wayland 会话
- **建议**: 用 [功能建议模板](https://github.com/zhugecaomao/ALTRun/issues/new?template=feature_request.yml), 或先在 [Discussions](https://github.com/zhugecaomao/ALTRun/discussions) 里讨论
- 需要更多信息时, 可以在偏好设置 → 通用里打开 "写入调试日志", 复现问题后在搜索框输入 "日志" (或 log) 打开日志文件 (`%Temp%\ALTRun.log`), 附上相关部分 (注意先去掉隐私信息)

## 开发环境

当前源码仅支持 Keysharp：AutoHotkey v2 与 Ahk2Exe 无法处理 `#Import`、平台预处理和 `#CSharp` 辅助代码。请安装包含解析器/编译器组件及桌面依赖的 [Keysharp](https://github.com/keysharp-org/Keysharp)。自行编译 Keysharp 时，按其仓库说明准备本机平台依赖，安装 .NET 10 SDK，在 Keysharp 仓库根目录运行：

```sh
dotnet build Keysharp.sln -c Debug
```

Windows 可执行文件位于 `bin/Debug/net10.0-windows/Keysharp.exe`，Linux/macOS 位于 `bin/Debug/net10.0/Keysharp`。ALTRun 源码在启动时编译；请在 `ALTRun.ahk` 旁保留 `ALTRun.Modules.ahk`、`Lib/`、`Src/` 和 `Resources/`。Windows 上在 ALTRun 文件夹中运行：

```powershell
$keysharp = 'C:\path\to\Keysharp.exe'
& $keysharp --errorstdout .\ALTRun.ahk
# 只检查编译，不运行程序
& $keysharp --errorstdout --validate .\ALTRun.ahk
# 独立的服务、设置、界面和启动检查
& $keysharp --errorstdout .\Tests\PlatformServices.ahk
& $keysharp --errorstdout .\Tests\SettingsFallback.ahk
& $keysharp --errorstdout --define:ALTRUN_PORTABLE_UI .\Tests\PortableSmoke.ahk
& $keysharp --errorstdout .\Tests\StartupSmoke.ahk
```

Linux/macOS 用 `/path/to/Keysharp ALTRun.ahk` 启动。无桌面的 Linux 需要为桌面后端提供 X11 显示，编译检查也一样：

```sh
xvfb-run -a /path/to/Keysharp --errorstdout --validate ALTRun.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/PlatformServices.ahk
# 设置保存和缓存检查不需要显示服务
/path/to/Keysharp --errorstdout Tests/SettingsFallback.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/PortableSmoke.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/StartupSmoke.ahk
```

这四个移植检查脚本使用临时数据，把错误/警告写到标准输出/错误，成功时退出码为 0。`PlatformServices` 检查进程输出捕获/取消、路径和桌面应用项。`SettingsFallback` 检查有效设置、保存时保留已存储的平台选择，以及文件/缓存身份。`PortableSmoke` 实际操作搜索、操作面板和偏好设置控件。`StartupSmoke` 检查真实程序启动、第二个进程向原实例转发参数，以及退出时保存独立数据。原 `Tests/RunTests.ahk` 仍是面向 Windows 的回归测试，可在 Windows 上用 Keysharp 运行，不是 Linux/macOS 验收测试。

标准界面已在 Windows 和 Ubuntu 24.04 的 X11/Xvfb 环境通过冒烟检查，不表示验证了原生 Wayland 或全局钩子；macOS 为实验性支持、尚未验证。无人值守测试脚本应包含 `#ErrorStdOut` 与 `#Warn All, StdOut`，避免模态提示，进程检查须设超时并清理。通过脚本扩展测试源码脚本时须保留 Keysharp 编译器。

## 代码规范
- **文件与类**: 一个文件一个类, 文件名 = 类名, PascalCase (`SearchWindow.ahk` → `class SearchWindow`)
- **文件夹**: `Lib\` 放和 ALTRun 无关、可以拿到别的项目用的通用库; ALTRun 自己的代码放 `Src\` 下对应的子文件夹
- **命名**: 类、方法、属性用 PascalCase; 局部变量用 camelCase; 内部使用的成员以 `_` 开头 (`_Layout()`、`_cache`)
- **避免重名**: AutoHotkey 的名字不区分大小写, 局部变量不要和类同名 (例如不要把变量叫 `pinyin`, 会遮住 `Pinyin` 类); 同一个类里的方法和属性也不要只差大小写
- **注释**: 每个文件开头说明用途和用法; 代码里的注释说明 "为什么", 用中文或英文都可以
- **单行输入框**: 所有 `Edit` 控件都要写明行数 (`r1 -Multi`), 否则长文字会让它自动变成多行 (有测试检查)
- **设置**: 新的设置项加到 `AppSettings.Defaults()`; 改变已有设置的结构时 `AppSettings.CurrentVersion + 1`, 并在 `SchemaMigration` 里加一个 `_FromN()`
- **界面文字**: 英文原文写在 `I18n.ahk`, 翻译写在 `Resources\Lang\` 的每个语言文件里 (`zh-CN.json`、`zh-TW.json`、`ja.json`; 测试会检查每个文件都有、占位符一致); 偏好设置里的文字较长时, 注意各种语言都不要超出页面 (`PreferencesFit` 测试会检查)
- **翻译 / 新语言**: 复制一个语言文件, 改名为语言代码 (例如 `ko.json`、`de.json`), 改 `_name` (用这种语言写的名称) 和 `_font`, 再翻译每一条; 放进 `Resources\Lang\` 后偏好设置的语言列表会自动列出它。只翻译了一部分也可以用, 没翻译的显示英文 (或 `_fallback` 指定的语言)
- **编码**: UTF-8; `ALTRun.ahk` 保持 UTF-8 BOM + CRLF, 其它文件 UTF-8 + LF

新增一个搜索功能的步骤见 Wiki 的 [开发指南](https://github.com/zhugecaomao/ALTRun/wiki/Development)。

## 提交 Pull Request
1. 从 `main` 新建分支, 一个 PR 只做一件事
2. 提交前运行相关测试与 `--validate`，说明验证的平台及尚存的警告
3. 新功能或修复请附带合适的测试 (`Tests/PlatformServices.ahk`、`Tests/SettingsFallback.ahk`、`Tests/PortableSmoke.ahk`、`Tests/StartupSmoke.ahk` 或 Windows 回归测试)
4. 涉及界面的改动请附上截图; README / Wiki 里的截图由 Screenshots workflow 生成, 用英文界面和虚构的示例数据, 不要放个人或工作相关的信息
5. 用户可见的变化请更新 README (`README.md` 英文和 `README.zh-CN.md` 中文)、`CHANGELOG.md` 的 "未发布" 部分, 必要时更新 Wiki (中文页和 `en-` 英文页都要改)

## 发布新版本

版本号使用发布日期 `YYYY.MM.DD`。下面的工作流对应原上游 AutoHotkey Windows 分发版。现有 `.github/workflows/release.yml` 使用 Ahk2Exe，不会打包此 Keysharp 移植版；在当前源码上运行它不是跨平台发布方法。Keysharp 分发版需要单独的系统/运行时打包及编译器部署。本次没有重设计发布自动化。

对于原本兼容 AutoHotkey 的上游源码：
1. 更新 `Src\Core\App.ahk` 的 `App.Version` 和 `ALTRun.ahk` 的 `;@Ahk2Exe-SetVersion` (有测试检查两者一致)
2. 在 `CHANGELOG.md` 把 "未发布" 改成 `## [YYYY.MM.DD]`, 这一节就是 Release 的说明; 文件末尾加上这个版本的链接, 并把 `[未发布]` 的比较链接改成从这个版本开始 (有测试检查)
3. 合并到 `main` 后, 在 Actions 里运行 **Release** (`.github/workflows/release.yml`): 先 `publish = false` 检查构建、测试和升级测试, 再 `publish = true` 创建 Release

Release workflow 在 Windows 上编译 `ALTRun.exe`, 并用 `Tests\Fixtures\ALTRun.v2026.08.12.ini` 验证从旧版本升级。

## 文档 (Wiki)
Wiki 的源文件在仓库的 [`docs/wiki/`](docs/wiki), 合并到 `main` 后由 GitHub Actions (`.github/workflows/wiki.yml`) 自动发布到 [Wiki](https://github.com/zhugecaomao/ALTRun/wiki)。请修改 `docs/wiki/` 里的文件, 直接在网页上修改的 Wiki 会在下次发布时被覆盖。页面之间的链接写页面名, 不带 `.md` (例如 `[主题](Themes)`; 英文页写 `[Themes](en-Themes)`)。每页有中文 (`Themes.md`) 和英文 (`en-Themes.md`) 两个文件, 改一种语言时请一起改另一种; 英文不熟悉的话可以只改中文, 在 PR 里说明, 维护者会补上。

提交代码即表示你同意以 [GPL-3.0](LICENSE) 许可发布你的贡献。

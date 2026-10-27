# Contributing

[English](#contributing) · [中文](#参与贡献)

Thank you for wanting to improve ALTRun! Bug reports, documentation improvements, translations and code are all very welcome. Issues and pull requests are welcome in English or Chinese.

## Reporting problems
- **Bugs**: use the [bug report template](https://github.com/zhugecaomao/ALTRun/issues/new?template=bug_report.yml) and include your operating system, Keysharp version, ALTRun version and steps to reproduce, ideally with a screenshot; on Linux include the desktop and X11/Wayland session
- **Ideas**: use the [feature request template](https://github.com/zhugecaomao/ALTRun/issues/new?template=feature_request.yml), or start a discussion in [Discussions](https://github.com/zhugecaomao/ALTRun/discussions) first
- When more information is needed, turn on "Write a debug log" in Preferences → General, reproduce the problem, then type "log" in the search box to open the log file (`%Temp%\ALTRun.log`) and attach the relevant part (remove anything private first)
- Security problems: please report them privately, see [SECURITY.md](SECURITY.md)

Issues and pull requests are welcome in English or Chinese.

## Development environment

This checkout is Keysharp-only: `#Import`, platform preprocessing and `#CSharp` helpers cannot be processed by AutoHotkey v2 or Ahk2Exe. Install [Keysharp](https://github.com/keysharp-org/Keysharp) with its parser/compiler components and desktop dependencies. To build Keysharp from source, follow that repository's platform prerequisites, install the .NET 10 SDK and run from its root:

```sh
dotnet build Keysharp.sln -c Debug
```

Its executable is `bin/Debug/net10.0-windows/Keysharp.exe` on Windows or `bin/Debug/net10.0/Keysharp` on Linux/macOS. ALTRun source is compiled when launched; retain `ALTRun.Modules.ahk`, `Lib/`, `Src/` and `Resources/` beside `ALTRun.ahk`. From the ALTRun folder on Windows:

```powershell
$keysharp = 'C:\path\to\Keysharp.exe'
& $keysharp --errorstdout .\ALTRun.ahk
# Compile-check without running the app
& $keysharp --errorstdout --validate .\ALTRun.ahk
# Isolated services, settings, interface and startup checks
& $keysharp --errorstdout .\Tests\PlatformServices.ahk
& $keysharp --errorstdout .\Tests\SettingsFallback.ahk
& $keysharp --errorstdout .\Tests\PortableSmoke.ahk
& $keysharp --errorstdout .\Tests\StartupSmoke.ahk
```

On Linux/macOS launch with `/path/to/Keysharp ALTRun.ahk`. On headless Linux provide an X11 display for the desktop backend, including compile checks:

```sh
xvfb-run -a /path/to/Keysharp --errorstdout --validate ALTRun.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/PlatformServices.ahk
# Settings persistence and cache checks do not need a display
/path/to/Keysharp --errorstdout Tests/SettingsFallback.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/PortableSmoke.ahk
xvfb-run -a /path/to/Keysharp --errorstdout Tests/StartupSmoke.ahk
# Real keyboard and mouse delivery on a private X11 desktop (Xvfb, xdotool, Metacity)
Tests/PortableInput.sh /path/to/Keysharp
# Native Wayland input in private nested Cinnamon (Cinnamon, Xvfb, D-Bus, xdotool)
Tests/PortableWaylandInput.sh /path/to/Keysharp
```

These four portability scripts use temporary data, redirect errors/warnings and exit with 0 on success. `PlatformServices` checks process capture/cancellation, paths and desktop entries. `SettingsFallback` checks effective settings, saving without overwriting stored platform choices, and file/cache identities. `PortableSmoke` exercises actual search, action and preferences controls. `StartupSmoke` checks real application startup, a second process forwarding arguments to the original instance, and shutdown saving isolated data. The existing `Tests/RunTests.ahk` suite remains a Windows-oriented regression suite and can be run with Keysharp on Windows; it is not a Linux/macOS acceptance test.

Additional isolated checks are `Tests/FolderWatcherSmoke.ahk`, `Tests/PortableHttp.ahk`, `Tests/LinuxDesktopEntries.ahk`, `Tests/LinuxDesktopIntegration.ahk`, `Tests/LinuxSystemCommands.ahk` and `Tests/WindowsIdentity.ahk`. Run them with the same Keysharp command above (use `xvfb-run -a` on headless Linux). The Picture interface is the default everywhere; on Windows add `--define:ALTRUN_MANAGED_WATCHER` to exercise the managed watcher backend. HTTP fixtures listen only on loopback; desktop integration fixtures use temporary configuration/data; system command fixtures inspect an inert runner and never change power, session, volume or Trash state. Platform-specific tests skip elsewhere.

`Tests/HotkeyPersistence.ahk` verifies conservative repair of saved shortcut labels, settings round trips and Windows recorder state across theme-induced native handle recreation. It uses a hidden test window and sends no keys. `PortableSmoke` checks Preferences client/outer dimensions across repeated sidebar selection and showing an existing window.

`Tests/PortableInput.sh` starts its own Xvfb display and window manager, then sends real keys and clicks through GTK. It checks typing, modifiers, Enter, action panels, query-driven resizing, repeated showing, row double-clicks and interaction with another fixture window. Pixel checks verify visible Ctrl+A and partial-selection highlights in light and dark themes. Menu checks cover rapid and slow repeated footer clicks, filtering, command callbacks, returning to the original query and opening result actions with a right-click. It uses temporary data and intercepts external launches. `Tests/PortableIcons.ahk` also compares GTK's tray/file-preview ICO pixels with the original decoded frame, catching corrupt primary images that launcher-only checks miss.

`Tests/PortableWaylandInput.sh` runs Cinnamon as a nested Wayland compositor on a private Xvfb display and D-Bus session, with temporary configuration/data and nonexistent desktop/input service sockets. It sends keys through the outer X11 window into native GTK Wayland controls. It checks modifiers, Enter execution, Escape returning from actions and hiding the actual native window, remembered-position handling without compositor geometry, and focus recovery after another fixture window is used. It requires Cinnamon, Xvfb, D-Bus and xdotool. It does not test global shortcuts, broker recovery or compositor-enforced always-on-top behavior; it deliberately leaves those desktop services unavailable. Set `ALTRUN_KEEP_WAYLAND_TEST=1` to preserve its logs after a run.

`Tests/PortableVisuals.ahk <absolute-output-folder>` captures light/dark launcher, action, Preferences, editor and notification windows with synthetic data. It also saves the actual launcher bitmap and row geometry. Use an absolute output folder because scripts start in their own directory. The fixture disables global shortcuts, autostart, persistence and network work, rejects modal prompts, and cleans up temporary data. On headless Linux run it under X11/Xvfb; set `XDG_SESSION_TYPE=x11` and `GDK_BACKEND=x11` when the host exports Wayland variables. If window capture is unavailable, the fixture renders its own GTK widget hierarchy to Cairo; the manifest identifies this fallback, and uniform images fail validation.

Validated on 2026-10-26 with the local Keysharp build: the entry point compiles on Windows and Ubuntu 24.04 under WSL/X11/Xvfb, and the Windows regression runner compiles. The isolated platform regressions pass where applicable. The shared Picture interface has targeted smoke coverage for actual rendered rows, selection, DPI-scaled footer clicks, actions, preferences, persistence, notifications, process capture and startup/handoff. `Tests/PortableIcons.ahk` checks native Windows icon sources, 1×/2× decoding, cache ownership and remote guards; `Tests/WindowsIdentity.ahk` queries the real Windows process application ID. Existing local/global-name warnings are printed. Those X11 fixtures do not establish native Wayland input or actual power/session/audio authorization.

The portable interface has passed smoke checks on Windows and Ubuntu 24.04 under X11/Xvfb. Those smoke checks alone do not establish native Wayland or global-hook coverage; macOS is experimental and unverified. Put `#ErrorStdOut` and `#Warn All, StdOut` in unattended test scripts, avoid modal prompts and give process checks a timeout with cleanup. Keep Keysharp's compiler deployed when testing source scripts through the Scripts provider.

For native Wayland debugging, distinguish launcher input from compositor services: ALTRun explicitly presents its GTK window on showing, and unavailable window geometry must not block Escape dismissal or result execution. The activation helper checks GTK's actual display backend: on X11 it uses a fresh server timestamp so activation can recover after another window was focused; on Wayland it uses GTK's native presentation request. Remembered placement and header dragging are optional geometry operations. Always-on-top behavior requires working compositor integration. After a Cinnamon crash, restart a failed session broker with `systemctl --user restart keysharp-desktop.service`, then run `keysharp-desktop probe`; expect `backend=cinnamon` and nonzero available operations. For a reported startup limit, reset the failed unit and restart it as described in [installation troubleshooting](docs/wiki/Installation.md#cinnamon-wayland-troubleshooting). A healthy system authority does not establish that the per-user broker is running. Neither input fixture validates native Wayland broker recovery or compositor-enforced always-on-top behavior.

## Code style
- **Files and classes**: one class per file, file name = class name, PascalCase (`SearchWindow.ahk` → `class SearchWindow`)
- **Folders**: `Lib\` holds general-purpose libraries with nothing ALTRun-specific that could be reused in other projects; ALTRun's own code goes in the matching subfolder of `Src\`
- **Naming**: PascalCase for classes, methods and properties; camelCase for local variables; internal members start with `_` (`_Layout()`, `_cache`)
- **Avoid name clashes**: AutoHotkey names are case-insensitive, so don't give a local variable the name of a class (for example, don't call a variable `pinyin`, it hides the `Pinyin` class); methods and properties in the same class shouldn't differ only in case either
- **Comments**: every file starts with a description of what it's for and how to use it; comments in the code explain "why", in English or Chinese
- **Single-line input boxes**: give every `Edit` control a row count (`r1 -Multi`), otherwise long text turns it into a multi-line box (a test checks this)
- **Settings**: add new settings to `AppSettings.Defaults()`; when you change the structure of existing settings, bump `AppSettings.CurrentVersion` and add a `_FromN()` to `SchemaMigration`
- **UI text**: the English original goes in `I18n.ahk`, translations go in every language file in `Resources\Lang\` (`zh-CN.json`, `zh-TW.json`, `ja.json`; a test checks that every file has every string and the same placeholders); for longer text in Preferences, make sure no language overflows the page (the `PreferencesFit` test checks this)
- **Translations / new languages**: copy a language file, rename it to the language code (for example `ko.json`, `de.json`), change `_name` (the language's name written in that language) and `_font`, then translate each entry; once it's in `Resources\Lang\`, the language list in Preferences shows it automatically. A partial translation works too: untranslated strings appear in English (or in the language given by `_fallback`)
- **Encoding**: UTF-8; `ALTRun.ahk` stays UTF-8 with BOM + CRLF, every other file UTF-8 + LF

The steps for adding a search feature are in the [Development guide](https://github.com/zhugecaomao/ALTRun/wiki/Development) in the wiki.

## Submitting a pull request
1. Create a branch from `main`; one pull request does one thing
2. Before submitting, run the relevant tests and `--validate`; describe the tested platform and any remaining warnings
3. Include tests with new features or fixes (`Tests/PlatformServices.ahk`, `Tests/SettingsFallback.ahk`, `Tests/PortableSmoke.ahk`, `Tests/StartupSmoke.ahk` or the Windows regression suite as appropriate)
4. For UI changes, attach screenshots; the screenshots in the README / wiki are generated by the Screenshots workflow with the English UI and made-up sample data; don't include anything personal or work-related
5. For user-visible changes, update the README (`README.md` in English and `README.zh-CN.md` in Chinese) and the "未发布" (Unreleased) section of `CHANGELOG.md`, and the wiki where needed (both the English page and the `-zh` Chinese page)

## Releasing a new version

Version numbers are the release date `YYYY.MM.DD`. The workflow below describes the original upstream AutoHotkey Windows distribution. The existing `.github/workflows/release.yml` uses Ahk2Exe and does not package this Keysharp source port; running it against this checkout is not a portable release procedure. A Keysharp distribution needs its own OS/runtime packaging and compiler deployment. No release automation is redesigned here.

For the original AutoHotkey-compatible upstream source:
1. Update `App.Version` in `Src\Core\App.ahk` and `;@Ahk2Exe-SetVersion` in `ALTRun.ahk` (a test checks that they match)
2. In `CHANGELOG.md`, rename "未发布" to `## [YYYY.MM.DD]`; that section becomes the release notes. Add the version's link at the end of the file and change the `[未发布]` compare link to start from this version (a test checks this)
3. After merging to `main`, run **Release** in Actions (`.github/workflows/release.yml`): first with `publish = false` to check the build, tests and upgrade test, then with `publish = true` to create the release

The Release workflow compiles `ALTRun.exe` on Windows and checks the upgrade from an old version with `Tests\Fixtures\ALTRun.v2026.08.12.ini`.

## Documentation (wiki)
The wiki sources are in [`docs/wiki/`](docs/wiki) in the repository and are published to the [wiki](https://github.com/zhugecaomao/ALTRun/wiki/Home) by GitHub Actions (`.github/workflows/wiki.yml`) after merging to `main`. Edit the files in `docs/wiki/`; changes made to the wiki on the web are overwritten by the next publish. Links between pages use the page name without `.md` (for example `[Themes](Themes)`; Chinese pages use `[主题](Themes-zh)`). Each page has a Chinese (`Themes-zh.md`) and an English (`Themes.md`) file; when you change one language, please change the other one too. If you're not comfortable with one of the languages, change just the one you know and say so in the pull request; a maintainer will add the other.

By submitting code, you agree to release your contribution under the [GPL-3.0](LICENSE) license.

---

# 参与贡献

感谢你愿意改进 ALTRun! 反馈问题、改进文档、补充翻译、提交代码都非常欢迎。Issue 和 Pull Request 用中文或英文都可以。

## 反馈问题
- **Bug**: 用 [Bug 报告模板](https://github.com/zhugecaomao/ALTRun/issues/new?template=bug_report.yml), 写清 Windows 版本、ALTRun 版本、复现步骤, 最好附上截图
- **建议**: 用 [功能建议模板](https://github.com/zhugecaomao/ALTRun/issues/new?template=feature_request.yml), 或先在 [Discussions](https://github.com/zhugecaomao/ALTRun/discussions) 里讨论
- 需要更多信息时, 可以在偏好设置 → 通用里打开 "写入调试日志", 复现问题后在搜索框输入 "日志" (或 log) 打开日志文件 (`%Temp%\ALTRun.log`), 附上相关部分 (注意先去掉隐私信息)
- 安全问题请私下报告, 见 [SECURITY.md](SECURITY.md#安全策略)

## 提交 Pull Request
1. 从 `main` 新建分支, 一个 PR 只做一件事
2. 确认单元测试全部通过、语法检查没有警告:
   ```
   Keysharp.exe --errorstdout Tests\RunTests.ahk
   Keysharp.exe --errorstdout --validate ALTRun.ahk
   ```
3. 新功能或修复请附带测试 (`Tests\RunTests.ahk`)
4. 涉及界面的改动请附上截图, 用英文界面和虚构的示例数据, 不要放个人或工作相关的信息
5. 用户可见的变化请更新 README (`README.md` 和 `README.zh-CN.md`)、`CHANGELOG.md`, 必要时更新 Wiki (`docs/wiki/`, 英文页和 `-zh` 中文页都要改)

项目结构、开发环境、代码规范、界面翻译、文档和发布流程见 Wiki 的 **[开发指南](https://github.com/zhugecaomao/ALTRun/wiki/Development-zh)**。

提交代码即表示你同意以 [GPL-3.0](LICENSE) 许可发布你的贡献。

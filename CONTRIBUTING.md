# Contributing

**English** · [中文](CONTRIBUTING.zh-CN.md)

Thank you for wanting to improve ALTRun! Bug reports, documentation improvements, translations and code are all very welcome. Please take a few minutes to read the conventions below before you submit anything.

## Reporting problems
- **Bugs**: use the [bug report template](https://github.com/zhugecaomao/ALTRun/issues/new?template=bug_report.yml) and include your operating system, Keysharp version, ALTRun version and steps to reproduce, ideally with a screenshot; on Linux include the desktop and X11/Wayland session
- **Ideas**: use the [feature request template](https://github.com/zhugecaomao/ALTRun/issues/new?template=feature_request.yml), or start a discussion in [Discussions](https://github.com/zhugecaomao/ALTRun/discussions) first
- When more information is needed, turn on "Write a debug log" in Preferences → General, reproduce the problem, then type "log" in the search box to open the log file (`%Temp%\ALTRun.log`) and attach the relevant part (remove anything private first)

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
& $keysharp --errorstdout --define:ALTRUN_PORTABLE_UI .\Tests\PortableSmoke.ahk
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
```

These four portability scripts use temporary data, redirect errors/warnings and exit with 0 on success. `PlatformServices` checks process capture/cancellation, paths and desktop entries. `SettingsFallback` checks effective settings, saving without overwriting stored platform choices, and file/cache identities. `PortableSmoke` exercises actual search, action and preferences controls. `StartupSmoke` checks real application startup, a second process forwarding arguments to the original instance, and shutdown saving isolated data. The existing `Tests/RunTests.ahk` suite remains a Windows-oriented regression suite and can be run with Keysharp on Windows; it is not a Linux/macOS acceptance test.

The portable interface has passed smoke checks on Windows and Ubuntu 24.04 under X11/Xvfb. This does not establish native Wayland or global-hook coverage; macOS is experimental and unverified. Put `#ErrorStdOut` and `#Warn All, StdOut` in unattended test scripts, avoid modal prompts and give process checks a timeout with cleanup. Keep Keysharp's compiler deployed when testing source scripts through the Scripts provider.

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

The steps for adding a search feature are in the [Development guide](https://github.com/zhugecaomao/ALTRun/wiki/en-Development) in the wiki.

## Submitting a pull request
1. Create a branch from `main`; one pull request does one thing
2. Before submitting, run the relevant tests and `--validate`; describe the tested platform and any remaining warnings
3. Include tests with new features or fixes (`Tests/PlatformServices.ahk`, `Tests/SettingsFallback.ahk`, `Tests/PortableSmoke.ahk`, `Tests/StartupSmoke.ahk` or the Windows regression suite as appropriate)
4. For UI changes, attach screenshots; the screenshots in the README / wiki are generated by the Screenshots workflow with the English UI and made-up sample data; don't include anything personal or work-related
5. For user-visible changes, update the README (`README.md` in English and `README.zh-CN.md` in Chinese) and the "未发布" (Unreleased) section of `CHANGELOG.md`, and the wiki where needed (both the Chinese page and the `en-` English page)

## Releasing a new version

Version numbers are the release date `YYYY.MM.DD`. The workflow below describes the original upstream AutoHotkey Windows distribution. The existing `.github/workflows/release.yml` uses Ahk2Exe and does not package this Keysharp source port; running it against this checkout is not a portable release procedure. A Keysharp distribution needs its own OS/runtime packaging and compiler deployment. No release automation is redesigned here.

For the original AutoHotkey-compatible upstream source:
1. Update `App.Version` in `Src\Core\App.ahk` and `;@Ahk2Exe-SetVersion` in `ALTRun.ahk` (a test checks that they match)
2. In `CHANGELOG.md`, rename "未发布" to `## [YYYY.MM.DD]`; that section becomes the release notes. Add the version's link at the end of the file and change the `[未发布]` compare link to start from this version (a test checks this)
3. After merging to `main`, run **Release** in Actions (`.github/workflows/release.yml`): first with `publish = false` to check the build, tests and upgrade test, then with `publish = true` to create the release

The Release workflow compiles `ALTRun.exe` on Windows and checks the upgrade from an old version with `Tests\Fixtures\ALTRun.v2026.08.12.ini`.

## Documentation (wiki)
The wiki sources are in [`docs/wiki/`](docs/wiki) in the repository and are published to the [wiki](https://github.com/zhugecaomao/ALTRun/wiki/en-Home) by GitHub Actions (`.github/workflows/wiki.yml`) after merging to `main`. Edit the files in `docs/wiki/`; changes made to the wiki on the web are overwritten by the next publish. Links between pages use the page name without `.md` (for example `[Themes](en-Themes)`; Chinese pages use `[主题](Themes)`). Each page has a Chinese (`Themes.md`) and an English (`en-Themes.md`) file; when you change one language, please change the other one too. If you're not comfortable with one of the languages, change just the one you know and say so in the pull request; a maintainer will add the other.

By submitting code, you agree to release your contribution under the [GPL-3.0](LICENSE) license.

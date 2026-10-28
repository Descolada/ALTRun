**English** · [中文](Installation-zh)

# Installation and upgrades

## Published Windows package requirements
- Windows 10 or Windows 11 (64-bit)
- The published executable contains AutoHotkey; no separate interpreter is needed
- No .NET, Electron or other runtime; the zip is under 1 MB and about 2 MB unpacked

## Running the Keysharp source checkout

This source checkout requires [Keysharp](https://github.com/keysharp-org/Keysharp) with its parser and compiler components. It uses `#Import`, conditional platform directives and managed helpers, so AutoHotkey v2 and Ahk2Exe cannot run or compile it. Install the Keysharp dependencies for your operating system, retain `ALTRun.ahk`, `ALTRun.Modules.ahk`, `Lib/`, `Src/` and `Resources/`, and run from the ALTRun folder:

```powershell
# Windows
& 'C:\path\to\Keysharp.exe' .\ALTRun.ahk
```

```sh
# Linux or macOS
/path/to/Keysharp ALTRun.ahk
```

Windows, Linux and macOS share a Picture-rendered launcher with a native search field and themed settings controls. On Windows, ALTRun sets its own process application identity before assigning its icon so other Keysharp scripts keep their taskbar identity. Linux discovers applications through XDG `.desktop` entries; macOS scans `.app` bundles. File browsing accepts `/absolute/paths/`, `~/` and `$HOME/`, and preserves case in Unix file identities. Installed terminals and `.sh`, `.py`, `.ps1`, `.ahk`/`.ks` scripts use platform interpreters and argument arrays; background scripts capture stdout/stderr and terminate their process tree on timeout. Captured output is decoded as UTF-8; Windows scripts invoking legacy OEM-encoded tools should convert their output to UTF-8. Keep the Keysharp compiler deployed for source scripts.

The portable interface passed smoke checks on Windows and Ubuntu 24.04 under X11/Xvfb, covering search results, action panels, preferences and folder browsing. Linux launcher keys use native events and their modifiers; native focus controls dismissal, and double-click opens results. Footer commands and result context menus use the launcher's action panel to avoid GTK popup grabs that can crash Cinnamon on Wayland. Application ICO frames use GTK-compatible DIB encoding for tray icons and file previews. A separate Xvfb input fixture checks real keys, clicks and interaction with another window. These checks do not establish native Wayland or global-hook integration. The macOS port has passed native checks on Apple silicon with macOS 26.5 and the sibling Keysharp build, including startup, instance handoff, search, preferences, icons, Unicode selection, settings persistence and launcher resizing. Global shortcuts, tray support, window enumeration/activation and clipboard automation depend on the Keysharp desktop backend and session. A window manager may reserve `Alt+Space`; choose another hotkey in Preferences.

On Linux, showing the launcher requests GTK window activation before focusing the search field; explicit theme colors keep full and partial text selections visible. Escape dismissal and result execution work even when Wayland window geometry is unavailable; remembered placement and header dragging use geometry only when it is available. Always-on-top behavior on Wayland requires a functioning Keysharp desktop broker and compositor integration.

On Hyprland, the launcher keeps its top-left corner while result counts change, growing and shrinking below the search field through Keysharp's Wayland positioner. Placement, height and focus during result changes have been checked on NixOS.

External desktop launches on NixOS (or when Keysharp itself runs from the Nix store) omit the inherited `LD_LIBRARY_PATH`, so Keysharp's GTK/native libraries cannot override another application's libraries. This includes `xdg-open`, desktop entries, direct application commands and terminals; child Keysharp scripts retain their runtime environment. Firefox's libffi/XPCOM startup failure has been checked with this isolation. Folder commands use the exact path case and report missing local folders before opening them.

On virtual machines where Nautilus exits with "Lost connection to Wayland compositor", try `GSK_RENDERER=cairo keysharp ALTRun.ahk`. The desktop opener inherits the software renderer setting; ALTRun's GTK 3 launcher does not use the GTK 4 renderer. This has been checked with Nautilus on this NixOS/Hyprland VM.

Hyprland's window animations can stretch a launcher bitmap during result resizing. For Hyprland 0.55's Lua configuration, disable animations for this window only:

```lua
hl.window_rule({
    name = "altrun-immediate-resize",
    match = { class = "^keysharp$", title = "^ALTRun$" },
    no_anim = true,
})
```

Everything, Microsoft Store indexing, Explorer/Total Commander interfaces, Windows IME modes/elevated CapsLock helpers and Windows shell elevation/shortcuts are Windows-specific. macOS supplies Finder Quick Switch, native file actions, input-source control and Spotlight alongside the local index; Linux uses its local index. Writable source folders keep `Data/` beside the program; otherwise user data uses the platform's application-data location (`$XDG_DATA_HOME/ALTRun` or `~/.local/share/ALTRun` on Linux, `~/Library/Application Support/ALTRun` on macOS). A packaged macOS app always keeps data outside its signed bundle.

The existing downloadable executables, Scoop/winget packages and release workflow are AutoHotkey Windows builds, and do not package this Keysharp port. Keysharp update checks open the release page or suggest a source update; they never replace a Keysharp executable with an AutoHotkey package. Update this checkout from source. A Keysharp release needs a separate platform-specific packaging workflow.

### macOS setup and verification

The [macOS guide](macOS.md) covers Finder actions, Quick Switch, Spotlight filters, Shortcuts, Safari imports, OCR, restored Preferences, permissions and update behavior. The [app builder](../../packaging/macos/README.md) produces a self-contained `ALTRun.app`, ZIP and DMG with a private .NET runtime and Keysharp compiler. Developer ID signing and notarization require supplied credentials; development packages are ad-hoc signed.

From this checkout, double-click `ALTRun.command` in Finder or run:

```sh
./ALTRun.command
```

The launcher finds a sibling `../Keysharp` (or `../keysharp`) Debug or Release app bundle, then `~/Applications/Keysharp.app`, `/Applications/Keysharp.app`, or `keysharp` on `PATH`. Its working directory is always the ALTRun folder. To select a different Keysharp installation, including paths with spaces:

```sh
KEYSHARP_BIN="/path/to/Keysharp.app" ./ALTRun.command
```

Keysharp must include its parser/compiler components and macOS dependencies. See the sibling Keysharp checkout's installation/build instructions if it has not been built. This port uses Keysharp directly; the Windows release downloads do not supply a macOS runtime.

The default show shortcut is **Option+Space** (`!Space` in settings); Option+R is the secondary shortcut. macOS `#` hotkeys use Command. Inside the launcher, Command+1–9 opens a result, Command+Enter performs its alternate action, Command+, opens Preferences, Command+L shows Large Type when enabled, and Command+E edits a supported item. The corresponding Control shortcuts continue to work. Native Command+A/C/X/V and Command-based cursor movement stay with the macOS text field. Shortcut hints use Command on macOS.

Keysharp needs macOS permissions for global shortcuts, snippets, pasting into other applications and window switching. Grant **Accessibility** and **Input Monitoring** to the Keysharp host you use in System Settings → Privacy & Security, then restart ALTRun. **Screen Recording** is needed for foreign window titles in Keysharp's window inventory. Terminal and Finder AppleScript actions may request **Automation** permission for those targets. These are operating-system grants; ALTRun cannot grant them itself. Apple's [Accessibility](https://support.apple.com/guide/mac-help/mh43185/mac) and [Input Monitoring](https://support.apple.com/guide/mac-help/mchl4cedafb6/mac) instructions explain the controls. Search, calculation, preferences and file browsing do not require global input automation.

Applications are scanned in `/Applications`, `/System/Applications` and `~/Applications`, including subfolders. CoreFoundation supplies localized display names and reads XML or binary `Info.plist` files. Filename and bundle ID remain searchable; background helpers and nested application contents are skipped. Custom `.app` launch arguments are forwarded through `open -a ... --args`. File reveal selects the item in Finder; editing settings uses the default text editor. Native file icons and application bundle icons are used when available.

Terminal commands open Terminal.app with the configured shell (zsh by default). Set `Features.Terminal.Terminal` to `iTerm` to use iTerm2. Paths and command text are quoted independently for AppleScript and the shell, including spaces, quotes and Unicode. Terminal receives one short launcher line. A private temporary script deletes itself before executing the command, preserving quoted paths and multiline text without interactive quote-continuation prompts. The command runs in the configured shell before it becomes interactive, so directory changes and exported variables carry through. A trailing shell comment does not discard that interactive continuation; an explicit `exit` exits normally.

**Launch ALTRun at login** is off by default on macOS. Enabling it writes `~/Library/LaunchAgents/org.keysharp.ALTRun.plist` with the current host and source path and takes effect at the next login. Disabling it removes only the entry owned by this checkout. Another checkout's or an unrelated plist is preserved. Changing this preference does not start or stop a login job in the current session. Keep both checkout and runtime at their recorded locations. The format follows Apple's [launchd agent documentation](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).

`recent ...` queries Spotlight last-used dates for local items under your home folder opened in the past 90 days. The first query returns cached results while a worker updates the list; a visible recent query refreshes when the lookup finishes. Results are cached for 60 seconds. Missing paths and duplicates are removed; applications are excluded. This is not the Apple menu's private Recent Items list: documents without Spotlight metadata, outside your home folder, or excluded from indexing are absent. ALTRun does not change Spotlight settings or read private shared-file-list archives.

System search includes screen lock (Control+Command+Q), sleep, display sleep, volume/mute, shutdown, restart, sign out, empty Trash and native tools such as System Settings, Activity Monitor, TextEdit, Finder, Disk Utility and Console when installed. Existing confirmation settings apply to shutdown, restart, sign out and empty Trash. Tool discovery does not establish permission to execute every action.

Run the bounded fixtures from the checkout to verify a macOS runtime (use your Keysharp executable path):

```sh
altrun_host="../Keysharp/bin/Debug/net10.0/Keysharp"
"$altrun_host" --validate ALTRun.ahk
for fixture in PlatformServices SettingsFallback PortableHttp FolderWatcherSmoke MacPlatform MacProviders MacDesktopIntegration PortableSmoke PortableIcons PortablePlacement MacCorners MacInput StartupSmoke; do
    "$altrun_host" "Tests/$fixture.ahk" || break
done
```

These fixtures use temporary data and do not install login jobs or run power, logout or empty-Trash commands. UI fixtures briefly show owned windows. Native input checks run only when the required permissions are already granted. They do not replace manual verification of automation against each external application. The old `Tests/RunTests.ahk` suite and Windows CI still target the legacy Windows UI and AutoHotkey executable; use the portable and macOS fixtures for this source port.

### Cinnamon Wayland troubleshooting

A Cinnamon session crash or several session changes in quick succession can leave the per-user desktop broker failed after systemd's startup limit. Restart it as your graphical user, then inspect its backend:

```sh
systemctl --user restart keysharp-desktop.service
keysharp-desktop probe
```

On Cinnamon Wayland, expect `backend=cinnamon` and nonzero `available_operations`. If systemd reports `start-limit-hit` or repeated startup requests, run `systemctl --user reset-failed keysharp-desktop.service` and repeat the restart. Inspect `systemctl --user status keysharp-desktop.service` and `journalctl --user -u keysharp-desktop.service` if it fails again. The system authority service can be healthy while this per-user broker is unavailable.

Show ALTRun again after recovery so Keysharp can reapply its window placement and always-on-top request. Basic launcher dismissal does not require the broker to expose window geometry.

### Linux desktop features

Application and file indexes monitor folder changes recursively and recover when a watched folder is removed and recreated. Desktop application search includes localized generic names and keywords, honors XDG desktop-ID precedence and hidden overrides, and resolves common raster icon themes and inherited themes. SVG/XPM-only icons use the bundled fallback. Shell and Python scripts honor shebang interpreters, and terminal discovery covers common GNOME, KDE, Xfce, MATE, Wayland and independent terminal emulators.

`recent ...` reads the desktop's `$XDG_DATA_HOME/recently-used.xbel` (default `~/.local/share/recently-used.xbel`), newest first. Private, missing and remote entries are excluded. Launch-at-login manages only `$XDG_CONFIG_HOME/autostart/org.keysharp.ALTRun.desktop` (default `~/.config/autostart/`); an unrelated entry is preserved. Autostart follows the [freedesktop specification](https://specifications.freedesktop.org/autostart/latest/).

The action panel supports file copying through the clipboard and Trash when `gio` is installed; file cutting remains Windows-only. Reveal selects files through the file manager's `org.freedesktop.FileManager1` interface when `gdbus` and a supporting session are available, otherwise it opens their containing folder. Linux system commands detect `systemctl`/`loginctl`, `wpctl`/`pactl`, `playerctl`, and GNOME/KDE/Xfce tools. Existing confirmation settings apply to power, logout and empty-Trash commands. Tool presence does not guarantee desktop authorization, an active media player or hibernation support.

Update and currency downloads run asynchronously. The shared interface exposes clipboard settings, bookmarks, window search, display density, configurable input hints and Tab navigation. Native Wayland global input and Windows-specific extensions remain outside the verified support described above.

## Installing the published Windows package
ALTRun is portable: there is nothing to install and nothing is written to the registry.

1. Download the latest version from [Releases](https://github.com/zhugecaomao/ALTRun/releases/latest) and unzip it to any folder (for example `D:\Apps\ALTRun`)
   - To run this source checkout, follow the Keysharp instructions above
2. The ALTRun icon appears in the notification area; press `Alt+Space` to open the search window
3. The first run builds the app index in the background; after a few seconds your Start menu programs can be found

If Windows SmartScreen says "Windows protected your PC" when you first run it, click **More info** → **Run anyway**; if your antivirus complains, see the [FAQ](FAQ#my-antivirus-flags-it).

Put it in a folder you can write to (for example `D:\Apps\ALTRun`): settings and data are saved in the `Data\` folder next to the program, so you can take the whole folder with you. In a folder that needs admin rights to write to (such as `C:\Program Files`), settings and data are saved in `%APPDATA%\ALTRun\` instead, but one-key updates can't replace the program files and you have to download new versions by hand.

### Installing with Scoop
[Scoop](https://scoop.sh/) is a command-line installer for Windows. The ALTRun repository is itself a Scoop bucket:

```powershell
scoop bucket add altrun https://github.com/zhugecaomao/ALTRun
scoop install altrun
```

- After installing, the Start menu has "Scoop Apps → ALTRun"; the program is in `scoop\apps\altrun\current`
- Upgrading: quit ALTRun first, then run `scoop update altrun`. Settings and data (`Data\`, including `Data\ALTRun.json`) and `Themes\` are kept
- Uninstalling: `scoop uninstall altrun`; your settings stay in `scoop\persist\altrun` and come back when you reinstall. To delete them too, use `scoop uninstall altrun --purge`
- When installed with Scoop, a new version found by "Check for Updates" tells you to upgrade with `scoop update altrun`; don't unzip over it by hand

### Installing with winget
The winget manifest is ready (`packaging\winget`). Once the [official winget repository](https://github.com/microsoft/winget-pkgs) accepts it, you can run:

```powershell
winget install zhugecaomao.ALTRun
winget upgrade zhugecaomao.ALTRun     # later upgrades (quit ALTRun first)
```

- The program is in `%LOCALAPPDATA%\Microsoft\WinGet\Packages\zhugecaomao.ALTRun_...`; type `altrun` on the command line to start it
- Upgrading and uninstalling only remove the files that came in the zip; settings and data (`Data\`, `Themes\`) are kept. Only `winget uninstall --purge` deletes them as well
- winget itself doesn't create a Start menu shortcut: after you start it once with `altrun`, ALTRun adds itself to the Start menu (Preferences → General → "Add to Start menu")
- Before uninstalling, turn off "Launch ALTRun at login", "Add to Start menu" and "Add to Explorer 'Send to' menu" in Preferences → General, otherwise those shortcuts are left behind
- The first time it runs, Windows may say it "couldn't verify the publisher" (the program was downloaded from the internet); choose "Run"
- Upgrading and uninstalling both keep your settings, `Data\` and `Themes\`; to remove everything after uninstalling, delete the folder above by hand

## Files in the program folder
| File / folder | What it is | On upgrade |
|---|---|---|
| `ALTRun.ahk` or `ALTRun.exe` | The program | Replaced |
| `Lib\` `Src\` | Program code (source version) | Replaced |
| `Resources\` | Data shipped with the program: Simplified / Traditional table, built-in themes, interface languages, icons | Overwritten |
| `Data\ALTRun.json` | All your settings, custom commands and snippets | Kept (format upgraded automatically) |
| Other files in `Data\` | App index, file index, learned ranking, clipboard history, usage statistics | Kept (rebuilt if deleted) |
| `Themes\` | Your own themes | Kept |
| `Scripts\` | Your own [scripts](Extensions#scripts) | Kept |

## Start with Windows, Start menu, "Send to"
In Preferences → General:
- **Launch ALTRun at login**: creates a shortcut in the Startup folder
- **Add to Start menu**: lets you open ALTRun from the Start menu
- **Add to Explorer 'Send to' menu**: right-click a file in Explorer → Send to → ALTRun adds it as a custom command (one file opens the edit dialog; several are all added at once)

## Upgrading
### One-key updates
ALTRun checks GitHub for new versions in the background (at startup and then every 6 hours) (Preferences → General → "Check for updates automatically"). Like Alfred, it doesn't pop up a window: once a new version is found, the empty search box shows **"Update Available: ALTRun x"** when you open the search window, with the current version and the keys on the line below (typing `update` finds it too):
- `Enter`: **Install Update**. Downloads the new version, checks its SHA256 checksum, replaces the program files and restarts automatically. `Data\` (settings and data) and `Themes\` are not touched
- `→`: **Release Notes** (opens this version's notes on GitHub) or **Skip This Version** (you'll be told again when there is a newer one)

After Windows starts, it waits 1 minute (the network may not be up yet) and checks if the last check was more than 1 hour ago, so a version released the day before is found when you start your PC; after that it looks every hour whether 6 hours have passed since the last check. The time of the last check and skipped versions are kept in `Data\Update.json`, so reloading ALTRun after changing settings doesn't check again and again. When there's no network it only writes a log entry and tries again an hour later.

To check right away: tray menu → "Check for Updates", or search for "Check for ALTRun Updates" (`CheckUpdate`). A manual check always shows the result: you're up to date, or the "ALTRun Update Available" dialog: Install Update / Release Notes / Later.

If anything goes wrong during an update (network, checksum, write permission), the old program is left as it was and you're offered the download page to update by hand. The command line `ALTRun.exe -Update` checks for and installs an update without asking.

One-key updates aren't possible in these cases; the item in the search window tells you what to do instead:
- Installed with Scoop / winget: `Enter` copies the upgrade command (`scoop update altrun` / `winget upgrade zhugecaomao.ALTRun`); quit ALTRun and run it in a terminal
- Running the source `ALTRun.ahk`: update with `git pull`, or press `Enter` to open the download page
- The program is in a folder you can't write to: `Enter` opens the download page

### Updating by hand
Copy the new version over the program folder; your settings and data are not affected. If the settings file format has changed, ALTRun upgrades it at startup and backs up the original first.

### Upgrading from 2.x (v2026.08.12 and earlier) to 3.0
1. Tray icon → quit the old version
2. Unzip the new version into your existing ALTRun folder, replacing `ALTRun.exe`
3. Run `ALTRun.exe`

On the first run, the old `ALTRun.ini` is imported automatically (settings, custom commands, hotkeys) and saved as the new `Data\ALTRun.json`. `ALTRun.ini` is left unchanged: to go back to the old version, put the old `ALTRun.exe` back. The Startup, Start menu and "Send to" shortcuts keep pointing to the same `ALTRun.exe`, so nothing needs to be set up again.

- **Kept**: the hotkey, start with Windows and other general settings; user commands (File / Dir / CMD / URL → custom commands, Clip → snippets); index folders, file types and depth; the structural calculation switch; Quick Switch; date stamp (Ctrl+D); PT Tools settings; conditional hotkeys
- **No longer kept**: the built-in command list (replaced by [system commands](Extensions#system-commands)), the old index (rebuilt), run history, usage statistics, old list appearance options

The old `Res\` folder has been renamed to `Resources\`; at startup, any files you put in `Res\` yourself are moved over automatically.

## Uninstalling
1. Tray menu → Quit
2. In Preferences → General, first turn off "Launch ALTRun at login", "Add to Start menu" and "Add to Explorer 'Send to' menu" (or delete those shortcuts by hand)
3. Delete the program folder

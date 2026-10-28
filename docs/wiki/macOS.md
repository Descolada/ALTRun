# ALTRun on macOS

ALTRun runs through Keysharp. Use `ALTRun.command` for a source checkout, or build the self-contained `ALTRun.app` with [the macOS packaging tools](../../packaging/macos/README.md). The app includes its .NET runtime, Keysharp parser/compiler and licenses. It does not require a separately installed runtime.

The default launcher shortcut is **Option+Space**. Preferences records native shortcuts and retains the existing settings syntax. Native Command-based editing works in the search field.

| Shortcut | Action |
|---|---|
| Command+1–9 | Open a numbered result |
| Command+Enter | Reveal a file in Finder, or paste a text result |
| Option+Enter | Copy the result's path, URL or text |
| Command+, | Preferences |
| Command+L | Large Type, when enabled |
| Command+E | Edit the selected file |
| Right arrow / context menu | Result actions |
| Control+G | Quick Switch in a native Open/Save dialog, when enabled |
| Control+Shift+G | Search the dialog folder panel, when enabled |

## Search

Application search understands localized names, bundle filenames and bundle IDs. Applications in `/Applications`, `/System/Applications`, CoreServices' Applications folder and `~/Applications` are included by default.

File search combines the local index with asynchronous Spotlight results. Start with a space, an apostrophe, or `file`. Local results appear immediately; Spotlight results are merged when the current request finishes. Superseded requests are cancelled and cannot replace a newer search. Spotlight does not change your indexing or privacy settings, and cannot find items that macOS has not indexed.

| Example | Meaning |
|---|---|
| `file budget` | Search names in the local index and Spotlight |
| `folder projects` | Folders only |
| `doc invoice` | The configured document extensions |
| `file kind:pdf invoice` | PDF metadata filter and name |
| `file tag:"Work Projects"` | Finder tag filter |
| `file content:"meeting notes"` | Search indexed text content |
| `file modified:2026-01-01 budget` | Modified on or after the given local date |
| `file created:2026-01-01` | Created on or after the given local date |
| `recent report` | Recent home-folder documents from Spotlight last-use metadata |
| `~/Documents/` | Browse an actual directory directly |

Spotlight searches start at two characters and are bounded. Preferences → File Search enables Spotlight and optionally includes file contents in ordinary searches. Explicit `content:` queries work without changing the ordinary-name setting. The local index remains available for unindexed folders. The Finder fallback preserves the search and folder/type filters.

Web search, the calculator, units, currencies, date arithmetic, learned ranking, pinned/recent launcher items, custom commands and snippets share their existing implementations.

## Finder and result actions

Files and folders offer native **Get Info**, **Open With**, **Quick Look**, **Share**, **Copy to Folder** and **Move to Folder** actions. When Finder's current folder is known, it is also offered as a destination. Multiple selected results can be opened, copied, moved, previewed or shared together. Copy/move checks reject self/descendant destinations and offer replace, skip or cancel for existing names. Finder retains its own transfer progress and error handling.

**Terminal Here** uses Finder's folder; the result action uses the selected result's folder. Terminal.app and iTerm are selectable in Preferences. Commands, paths and arguments are passed literally, including quotes and line breaks. Terminal commands retain an interactive shell after completion.

Quick Switch is optional in Preferences. Its explicit hotkey navigates a native Open/Save panel through Go to Folder while retaining the proposed filename. The searchable attached panel combines open Finder folders and recent destinations. Automatic switching can be enabled separately. Navigation checks the receiving application, panel and field before sending keys. Custom dialogs may require their own navigation interface.

Date Stamp is optional. It adds or updates a date in selected Finder filenames using the configured format and rejects conflicting names. The **Add Date to Finder Selection** system command is also available.

The packaged app declares **Add to ALTRun** and **Actions in ALTRun** Services for Finder files and selected text. Move the app to Applications and launch it to make it discoverable to macOS. Services pass selected content directly; they do not borrow the general clipboard.

## Shortcuts, scripts, bookmarks and images

- `shortcut name` searches Apple Shortcuts. Enter runs one; its actions can open it for editing or pass clipboard text. **Run Shortcut…** passes a selected file, folder, URL or text result as input. Nonempty command-line output is copied. Shortcuts may present their own questions or permissions.
- Scripts support `.ahk`, `.ks`, `.sh`, `.command`, `.py`, `.ps1`, `.applescript`, compiled `.scpt` and `.jxa`. Required interpreters must be installed. AppleScript `-- @altrun.title ...` metadata is recognized; compiled scripts use their filename. Window/background/output modes retain literal arguments.
- Bookmark search supports Chromium browsers and readable Safari bookmarks. Preferences → Features accepts exported bookmark HTML files or Safari ZIP exports; ZIP imports read bookmark HTML entries only. Protected Safari data needs the applicable macOS access grant. Failed reads retry while idle.
- **Extract Text from Image** uses Apple's local Vision framework on a selected image or clipboard image, then copies the recognized text. Clipboard images are staged in a private directory and removed after use or exit.

## Desktop controls and Preferences

Window results offer center, left/right half, maximize, hide application and normal quit actions. They verify the original target process before operating. macOS controls which applications permit window manipulation. The launcher uses native Spaces/fullscreen auxiliary behavior, updates after desktop changes and exposes individual result/action accessibility elements. Native appearance preferences for reduced motion/transparency are respected.

Multiple windows of one application remain separate results while sharing learned application ranking. Hidden applications can be reactivated. ALTRun's native Quit command routes through its normal settings-save and cleanup path; other applications can decline a quit request or ask about unsaved work.

System commands include power/session actions, Trash, volume, media keys, process/service lists, common utilities and installed System Settings destinations. Destructive session/Trash actions keep their confirmation setting. Settings destinations are filtered against installed extensions; some labels lead to the containing pane rather than a specific control.

All 20 Preferences pages are available on macOS, including Keyboard, Search Sources, Quick Switch, Dialog Panel, Date Stamp and Usage. Snippet CSV/TSV/paste import works on the draft configuration; Cancel leaves saved snippets unchanged. Hidden applications/commands can be restored. Advanced offers data relocation, diagnostics, log access, defaults and ranking reset. PT Tools and SPF2M use the same calculation core and reference data as Windows.

Keyboard settings can choose an enabled ASCII input source for the launcher and restore the previous source afterward. Optional Caps Lock tap/hold switches sources; Windows IME modes and its elevated helper are separate platform integrations.

## Permissions and data

Preferences → Advanced reports the existing Keysharp capability status without requesting grants. Enable permissions for the executable you actually use: the source host is Keysharp, while the packaged app is ALTRun.

| Permission | Used by |
|---|---|
| Accessibility / input control | Global automation, pasting, selection actions, Quick Switch and window control |
| Input Monitoring | Global hotkeys, hotstrings and capturing typing while the launcher opens |
| Window monitoring / Screen Recording where required by macOS | External window metadata and screenshots |
| Finder Automation | Finder folders/selection, transfers, information windows and date stamping |
| Terminal or iTerm Automation | Terminal command execution |
| Access to protected browser data | Live Safari bookmarks, where macOS requires it |

Background Finder checks do not request Automation permission. Explicit Finder actions may invoke the normal macOS consent prompt. Secure fields suppress snippet/selection automation; concealed/transient clipboard markers and configured password-manager exclusions are respected.

The source checkout keeps its portable data behavior. A packaged app stores data outside its signed bundle, normally in `~/Library/Application Support/ALTRun/Data`. Preferences can move the data folder. Packaged autostart and child scripts use the bundled launcher, so they work without a global .NET installation. Login startup remains optional and manages only ALTRun's owned LaunchAgent.

## Packages and updates

The macOS update repository defaults to `Descolada/ALTRun` and is configurable in General as `owner/name`. Matching release assets use `ALTRun_vVERSION_macos-arm64.zip` or `ALTRun_vVERSION_macos-x64.zip` and a GitHub SHA256 digest. Windows executable packages are never installed into this port.

Automatic app replacement requires an existing trusted Developer ID/notarized app and a verified replacement with the same team, bundle identifier, version and architecture. Downloading and validation run asynchronously. Replacement retains a backup and uses startup readiness checks before accepting the new app. Source checkouts and ad-hoc development packages use the release page instead.

The included builder can sign/notarize with supplied credentials. An ad-hoc development package is runnable locally but is not a notarized public release.

## Verification

Native fixtures cover Preferences, shortcut recording, clipboard text/files/images, cross-process paste and selection, snippet expansion, secure/private content, input sources, Save-panel navigation and filename retention, native action dialogs, accessible result rows, Spaces flags, fade/corner behavior, Spotlight request cancellation, Safari formats, local OCR, Services input, package independence and updater archive/rollback handling.

Power/logout actions are tested through dispatch boundaries. Finder transfers needing a missing Automation grant are skipped rather than requesting permission during tests. Physical display hotplug/mixed-DPI setups, a real logout/login and a production signed/notarized update require the corresponding environment and credentials.

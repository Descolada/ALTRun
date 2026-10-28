# macOS packages

Build a standalone `ALTRun.app` with an existing Keysharp macOS build and an installed .NET 10 runtime:

```sh
python3 packaging/macos/build.py \
  --keysharp ../Keysharp/bin/Debug/net10.0/Keysharp.app \
  --output dist/macos
python3 Tests/MacPackaging.py dist/macos/ALTRun.app \
  --archive dist/macos/ALTRun_v2026.10.26.4_macos-arm64.zip \
  --dmg dist/macos/ALTRun_v2026.10.26.4_macos-arm64.dmg
```

The builder uses Xcode Command Line Tools and the newest matching .NET 10 runtime under `/usr/local/share/dotnet`. `--dotnet-root`, `--runtime-version` and `--version` select alternatives. It produces an architecture-specific app, ZIP and compressed DMG with an Applications link. Pass `--no-dmg` to build only the app and ZIP. It replaces only an app previously produced by this builder.

The native launcher keeps the bundle identity `org.keysharp.ALTRun`, sets the bundled runtime location and executes Keysharp. ALTRun source and resources live in `Contents/Resources/ALTRun`; managed Keysharp dependencies, parser and compiler are in `Contents/Resources/Keysharp`; .NET is in `Contents/Resources/dotnet`. The native Keysharp apphost remains in `Contents/MacOS` and is rebound to its managed assembly's resource path before signing. This keeps nonexecutable manifests and licenses out of macOS code directories. No .NET installation or SDK is needed to run the resulting app or compile child Keysharp scripts.

The bundle declares Finder/text Services for **Add to ALTRun** and **Actions in ALTRun**. ALTRun registers its provider when it runs. The build and test commands do not register the app, change login items or grant permissions. The app uses a menu-bar presence and has no regular Dock icon. Settings and user scripts belong outside the signed bundle; see the main installation documentation.

Packages use ad-hoc development signatures by default. For distribution, pass `--identity 'Developer ID Application: …'` and optionally `--notary-profile NAME` for an existing `notarytool` keychain profile. The latter submits the ZIP, staples the accepted app and rebuilds its ZIP before creating the DMG. These options require your own signing credentials. Ad-hoc builds are local development artifacts; they do not have a trusted Developer ID or notarization, and the automatic updater requires a trusted matching team.

All Mach-O dependencies are signed before the outer app and verified with `codesign --deep --strict`. Entitlements permit the .NET JIT and ALTRun's user-initiated Apple Events. Licenses for ALTRun, Keysharp, .NET and bundled native libraries are included.

For host diagnostics, `ALTRun.app/Contents/MacOS/ALTRun --keysharp --validate /path/to/script.ahk` forwards the remaining arguments directly to the bundled host. Normal arguments are passed to ALTRun. The package test compiles and runs an isolated fixture with a deliberately unavailable global runtime, validates the complete bundled source without starting ALTRun, checks signatures and archive contents, and verifies the DMG without mounting it.

#!/usr/bin/env python3
"""Build an offline-capable ALTRun.app, ZIP and DMG using an existing Keysharp macOS build."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def run(*arguments, **kwargs):
    try:
        return subprocess.run([str(item) for item in arguments], check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise


def version_key(value):
    return tuple(int(part) for part in re.findall(r"\d+", value))


def mach_o(path):
    if not path.is_file() or path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in {bytes.fromhex(value) for value in ["cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cafebabf"]}


def info(version):
    return {
        "CFBundleName": "ALTRun", "CFBundleDisplayName": "ALTRun", "CFBundleIdentifier": "org.keysharp.ALTRun",
        "CFBundleExecutable": "ALTRun", "CFBundlePackageType": "APPL", "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": version, "CFBundleVersion": version, "CFBundleIconFile": "ALTRun.icns",
        "LSUIElement": True, "LSMinimumSystemVersion": "15.0", "NSPrincipalClass": "NSApplication",
        "NSHighResolutionCapable": True, "NSRequiresAquaSystemAppearance": False,
        "NSAppleEventsUsageDescription": "ALTRun uses Finder and Terminal automation to act on selected files, jump to folders and run your commands.",
        "NSInputMonitoringUsageDescription": "ALTRun uses your configured global shortcuts and optional snippet expansion.",
        "NSSystemAdministrationUsageDescription": "ALTRun requests authorization only for a system action you choose.",
        "NSServices": [
            {"NSMenuItem": {"default": "Add to ALTRun"}, "NSMessage": "addToALTRun", "NSPortName": "ALTRun",
             "NSSendTypes": ["NSFilenamesPboardType", "public.file-url"]},
            {"NSMenuItem": {"default": "Actions in ALTRun"}, "NSMessage": "actionsInALTRun", "NSPortName": "ALTRun",
             "NSSendTypes": ["NSStringPboardType", "public.utf8-plain-text", "NSFilenamesPboardType", "public.file-url"]},
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keysharp", type=Path, help="Existing Keysharp.app (default: sibling Debug or Release build)")
    parser.add_argument("--dotnet-root", type=Path, default=Path("/usr/local/share/dotnet"))
    parser.add_argument("--runtime-version", help="Installed Microsoft.NETCore.App 10 version to embed (default: newest)")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "macos")
    parser.add_argument("--version", help="Default: App.Version in Src/Core/App.ahk")
    parser.add_argument("--identity", default="-", help="codesign identity; default is ad-hoc development signing")
    parser.add_argument("--notary-profile", help="Explicit notarytool keychain profile; requires Developer ID signing")
    parser.add_argument("--no-dmg", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS and Xcode Command Line Tools are required")
    if args.notary_profile and args.identity == "-":
        parser.error("notarization requires an explicit Developer ID --identity")
    host = args.keysharp
    if host is None:
        host = next((candidate for flavor in ("Debug", "Release") for candidate in [ROOT.parent / "Keysharp" / "bin" / flavor / "net10.0" / "Keysharp.app"] if candidate.exists()), None)
    if host is None or not (host / "Contents/MacOS/Keysharp").is_file():
        parser.error("build Keysharp.app first or pass --keysharp")
    host = host.resolve()
    for component in ["parser/Keysharp.Components.Scripting.Parser.dll", "compiler/Keysharp.Components.Scripting.Compiler.dll", "compiler/Microsoft.CodeAnalysis.CSharp.dll"]:
        if not (host / "Contents/MacOS/components/scripting" / component).is_file():
            parser.error("Keysharp must include parser/compiler components: " + component)
    runtime_root = args.dotnet_root.resolve()
    candidates = [path for path in (runtime_root / "shared/Microsoft.NETCore.App").glob("10.*") if path.is_dir()]
    runtime_version = args.runtime_version or (max(candidates, key=lambda item: version_key(item.name)).name if candidates else "")
    runtime = runtime_root / "shared/Microsoft.NETCore.App" / runtime_version
    fxr = runtime_root / "host/fxr" / runtime_version
    if not runtime_version or not runtime.is_dir() or not fxr.is_dir():
        parser.error("matching .NET 10 runtime and host/fxr version are required")
    architecture = run("/usr/bin/lipo", "-archs", host / "Contents/MacOS/Keysharp", capture_output=True, text=True).stdout.strip()
    if architecture not in ("arm64", "x86_64"):
        parser.error("select a single-architecture Keysharp build (arm64 or x86_64)")
    runtime_arch = run("/usr/bin/lipo", "-archs", runtime / "libcoreclr.dylib", capture_output=True, text=True).stdout.split()
    if architecture not in runtime_arch:
        parser.error("Keysharp and embedded .NET runtime architectures differ")
    match = re.search(r'static\s+Version\s*:=\s*"([^"]+)"', (ROOT / "Src/Core/App.ahk").read_text())
    version = args.version or (match.group(1) if match else "")
    if not re.fullmatch(r"\d+(?:\.\d+){1,3}", version):
        parser.error("version must contain two to four dot-separated numbers")
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    final_app = output / "ALTRun.app"
    if final_app.exists():
        metadata = final_app / "Contents/Resources/build-info.json"
        if not metadata.is_file() or json.loads(metadata.read_text()).get("builder") != "ALTRun/packaging/macos":
            parser.error("refusing to replace an app not owned by this builder: " + str(final_app))
    suffix = "arm64" if architecture == "arm64" else "x64"
    stem = f"ALTRun_v{version}_macos-{suffix}"
    archive, disk = output / (stem + ".zip"), output / (stem + ".dmg")
    with tempfile.TemporaryDirectory(prefix=".altrun-build-", dir=output) as scratch:
        image = Path(scratch) / "image"
        app = image / "ALTRun.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        managed = resources / "Keysharp"
        shutil.copytree(host / "Contents/MacOS", managed, ignore=shutil.ignore_patterns("*.pdb"))
        (contents / "MacOS").mkdir()
        shutil.move(managed / "Keysharp", contents / "MacOS/Keysharp")
        # macOS signs everything directly in MacOS as executable code. Keep managed assemblies,
        # dependency manifests and licenses in Resources, and bind the apphost to that assembly.
        apphost = contents / "MacOS/Keysharp"
        data = apphost.read_bytes()
        marker = b"Keysharp.dll\0"
        replacement = b"../Resources/Keysharp/Keysharp.dll\0"
        if data.count(marker) != 1:
            parser.error("unsupported Keysharp apphost: expected one bound assembly path")
        offset = data.index(marker)
        if any(data[offset + len(marker):offset + len(replacement)]):
            parser.error("unsupported Keysharp apphost: assembly-path padding is unavailable")
        apphost.write_bytes(data[:offset] + replacement + data[offset + len(replacement):])
        source = resources / "ALTRun"
        source.mkdir()
        for name in ["ALTRun.ahk", "ALTRun.Modules.ahk", "LICENSE"]:
            shutil.copy2(ROOT / name, source / name)
        shutil.copy2(HERE / "PackageProbe.ahk", source / "PackageProbe.ahk")
        for name in ["Lib", "Src", "Resources"]:
            shutil.copytree(ROOT / name, source / name, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
        guides = source / "docs/wiki"
        guides.mkdir(parents=True)
        for name in ["macOS.md", "Installation.md"]:
            if (ROOT / "docs/wiki" / name).is_file():
                shutil.copy2(ROOT / "docs/wiki" / name, guides / name)
        embedded = resources / "dotnet"
        shutil.copytree(runtime, embedded / "shared/Microsoft.NETCore.App" / runtime_version)
        shutil.copytree(fxr, embedded / "host/fxr" / runtime_version)
        shutil.copy2(runtime_root / "dotnet", embedded / "dotnet")
        licenses = resources / "Licenses"
        licenses.mkdir()
        for name in ["LICENSE.txt", "ThirdPartyNotices.txt"]:
            shutil.copy2(runtime_root / name, licenses / ("dotnet-" + name))
        shutil.copy2(ROOT.parent / "Keysharp/license.txt" if (ROOT.parent / "Keysharp/license.txt").exists() else host / "Contents/Resources/license.txt", licenses / "Keysharp-license.txt")
        shutil.copy2(ROOT / "LICENSE", licenses / "ALTRun-GPL-3.0.txt")
        iconset = Path(scratch) / "ALTRun.iconset"
        iconset.mkdir()
        for points in [16, 32, 128, 256, 512]:
            for density in [1, 2]:
                pixels = points * density
                icon = iconset / f"icon_{points}x{points}{'@2x' if density == 2 else ''}.png"
                run("/usr/bin/sips", "-z", pixels, pixels, ROOT / "docs/images/logo.png", "--out", icon, stdout=subprocess.DEVNULL)
        run("/usr/bin/iconutil", "-c", "icns", iconset, "-o", resources / "ALTRun.icns")
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info(version), stream, sort_keys=False)
        revision = run("/usr/bin/git", "-C", ROOT, "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
        dirty = bool(run("/usr/bin/git", "-C", ROOT, "status", "--porcelain", capture_output=True, text=True).stdout.strip())
        (resources / "build-info.json").write_text(json.dumps({"builder": "ALTRun/packaging/macos", "version": version, "architecture": suffix,
            "runtime": runtime_version, "source_revision": revision, "source_dirty": dirty, "signing": "ad-hoc development" if args.identity == "-" else args.identity}, indent=2) + "\n")
        run("/usr/bin/xcrun", "clang", "-arch", architecture, "-mmacosx-version-min=15.0", "-O2", "-Wall", "-Wextra", HERE / "launcher.c", "-o", contents / "MacOS/ALTRun")
        run("/usr/bin/xattr", "-cr", app)
        signing = ["/usr/bin/codesign", "--force", "--sign", args.identity]
        if args.identity != "-":
            signing += ["--timestamp"]
        binaries = sorted((path for path in contents.rglob("*") if mach_o(path)), key=lambda path: len(path.parts), reverse=True)
        for binary in binaries:
            options = ["--options", "runtime", "--entitlements", HERE / "entitlements.plist"] if os.access(binary, os.X_OK) and binary.suffix != ".dylib" else []
            if binary.name != "ALTRun":
                run(*signing, *options, binary, capture_output=True, text=True)
        run(*signing, "--options", "runtime", "--entitlements", HERE / "entitlements.plist", app)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
        validation = os.environ.copy()
        validation["KEYSHARP_DAEMON"] = "0"
        run(contents / "MacOS/ALTRun", "--keysharp", "--validate", source / "ALTRun.ahk", env=validation, capture_output=True, text=True)
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        if args.notary_profile:
            run("/usr/bin/xcrun", "notarytool", "submit", archive, "--keychain-profile", args.notary_profile, "--wait")
            run("/usr/bin/xcrun", "stapler", "staple", app)
            run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        if not args.no_dmg:
            (image / "Applications").symlink_to("/Applications")
            run("/usr/bin/hdiutil", "create", "-volname", "ALTRun", "-srcfolder", image, "-format", "UDZO", "-ov", disk)
        if final_app.exists():
            shutil.rmtree(final_app)
        shutil.move(app, final_app)
    print(json.dumps({"app": str(final_app), "source": str(final_app / "Contents/Resources/ALTRun"), "archive": str(archive),
        "dmg": None if args.no_dmg else str(disk), "runtime": runtime_version, "architecture": suffix, "notarized": bool(args.notary_profile)}, indent=2))


if __name__ == "__main__":
    main()

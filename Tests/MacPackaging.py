#!/usr/bin/env python3
"""Verify a generated macOS package without starting ALTRun or registering desktop services."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile


def checked(arguments, env=None):
    result = subprocess.run([str(item) for item in arguments], env=env, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise AssertionError(f"{arguments[0]} exited {result.returncode}:\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--dmg", type=Path)
    args = parser.parse_args()
    app = args.bundle.resolve()
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "org.keysharp.ALTRun"
    assert info["CFBundleExecutable"] == "ALTRun" and info["LSUIElement"]
    assert {item["NSMessage"] for item in info["NSServices"]} == {"addToALTRun", "actionsInALTRun"}
    source = contents / "Resources/ALTRun"
    host = contents / "MacOS/Keysharp"
    launcher = contents / "MacOS/ALTRun"
    metadata = json.loads((contents / "Resources/build-info.json").read_text())
    runtime = contents / "Resources/dotnet"
    managed = contents / "Resources/Keysharp"
    assert (runtime / "shared/Microsoft.NETCore.App" / metadata["runtime"] / "libcoreclr.dylib").is_file()
    for name in ["parser/Keysharp.Components.Scripting.Parser.dll", "compiler/Keysharp.Components.Scripting.Compiler.dll", "compiler/Microsoft.CodeAnalysis.CSharp.dll"]:
        assert (managed / "components/scripting" / name).is_file(), name
    assert (contents / "Resources/Licenses/dotnet-ThirdPartyNotices.txt").is_file()
    assert (contents / "Resources/ALTRun/LICENSE").is_file()
    assert not (source / "Data").exists(), "The app contains checkout runtime data"
    checked(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    print("PASS MAC_PACKAGING bundle identity, Services, source, compiler, runtime, licenses and code signatures")

    with tempfile.TemporaryDirectory(prefix="ALTRun-MacPackaging-") as temporary:
        isolated = Path(temporary)
        environment = os.environ.copy()
        environment.update({"HOME": str(isolated), "PATH": "/usr/bin:/bin", "DOTNET_ROOT": str(isolated / "missing-runtime"),
            "DOTNET_ROOT_ARM64": str(isolated / "missing-runtime"), "DOTNET_ROOT_X64": str(isolated / "missing-runtime"),
            "DOTNET_MULTILEVEL_LOOKUP": "0", "KEYSHARP_DAEMON": "0"})
        fixture = isolated / "runtime probe 汉字.ahk"
        fixture.write_text('''#Requires AutoHotkey v2.0
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#CSharp
public static string ALTRunPackagedRuntime() => System.Environment.Version.ToString() + "|" + System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory();
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_getClass")] private static extern System.IntPtr ALTRunPackagingClass(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "sel_registerName")] private static extern System.IntPtr ALTRunPackagingSelector(string name);
[System.Runtime.InteropServices.DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")] private static extern System.IntPtr ALTRunPackagingSend(System.IntPtr target, System.IntPtr selector);
public static string ALTRunPackagedBundleId()
{
    var bundle = ALTRunPackagingSend(ALTRunPackagingClass("NSBundle"), ALTRunPackagingSelector("mainBundle"));
    var identifier = ALTRunPackagingSend(bundle, ALTRunPackagingSelector("bundleIdentifier"));
    return System.Runtime.InteropServices.Marshal.PtrToStringUTF8(ALTRunPackagingSend(identifier, ALTRunPackagingSelector("UTF8String"))) ?? "";
}
#EndCSharp
if (A_Args.Length != 2 || A_Args[1] != 'spaces " and 汉字' || A_Args[2] != "line one`nline two")
    throw Error("Packaged launcher changed literal arguments.")
if !RegExMatch("file汉字123", "^file.+[0-9]+$")
    throw Error("The packaged native regular-expression library failed.")
FileAppend("PACKAGED_RUNTIME " ALTRunPackagedRuntime() "`nHOST " A_AhkPath "`nBUNDLE " EnvGet("ALTRUN_APP_BUNDLE") "`nNATIVE_ID " ALTRunPackagedBundleId() "`n", "*")
ExitApp(0)
''')
        output = checked([launcher, "--keysharp", fixture, 'spaces " and 汉字', "line one\nline two"], environment)
        assert "PACKAGED_RUNTIME 10." in output, output
        assert str(runtime) in output, "The host used a global .NET runtime: " + output
        assert str(host) in output and str(app) in output, output
        assert "NATIVE_ID org.keysharp.ALTRun" in output, "The native host lost its application bundle identity: " + output
        output = checked([launcher, "--keysharp", source / "PackageProbe.ahk", "--child", fixture, 'spaces " and 汉字', "line one\nline two"], environment)
        report = json.JSONDecoder().raw_decode(output.split("ALTRUN_PACKAGE ", 1)[1].lstrip())[0]
        assert Path(report["Bundle"]).resolve() == app and not report["Portable"], report
        assert Path(report["Source"]).resolve() == source, report
        assert not Path(report["Data"]).is_relative_to(app), "Packaged settings would modify the signed app: " + str(report)
        assert Path(report["LoginExecutable"]).resolve() == launcher and report["LoginArguments"][0] == "--keysharp", report
        assert report["LoginArguments"][-1] == "-Startup", report
        assert "ALTRUN_CHILD PACKAGED_RUNTIME 10." in output, "Bundled ScriptHost could not run a child source script: " + output
        output = checked([launcher, "--keysharp", "--validate", source / "ALTRun.ahk"], environment)
        assert "Compilation succeeded" in output, output
        if args.archive:
            output = checked([launcher, "--keysharp", source / "PackageProbe.ahk", "--archive", args.archive.resolve()], environment)
            assert "ALTRUN_ARCHIVE ALTRun.app" in output, "The native updater rejected the generated archive: " + output
        assert not (source / "Data").exists(), "Validation wrote settings into the signed bundle"
    checked(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    print("PASS MAC_PACKAGING embedded .NET/compiler with isolated HOME, missing global runtime and literal Unicode/newline arguments")

    if args.archive:
        with zipfile.ZipFile(args.archive) as archive:
            names = archive.namelist()
            assert "ALTRun.app/Contents/Info.plist" in names
            assert not any(name.startswith("ALTRun.app/Contents/Resources/ALTRun/Data/") for name in names)
        print("PASS MAC_PACKAGING ZIP contains a clean application bundle")
    if args.dmg:
        checked(["/usr/bin/hdiutil", "verify", args.dmg])
        print("PASS MAC_PACKAGING DMG integrity without mounting or registration")


if __name__ == "__main__":
    main()

#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

#CSharp
public static string ALTRunServiceFixture(string Mode, string Value)
{
    nint Sel(string name) => ALTRunMacDesktopNative.Sel(name);
    nint board = ALTRunMacDesktopNative.Send(ALTRunMacDesktopNative.Class("NSPasteboard"), Sel("pasteboardWithUniqueName"));
    try
    {
        if (Mode == "text")
            ALTRunServicesNative.Two(board, Sel("setString:forType:"), ALTRunMacDesktopNative.Text(Value), ALTRunMacDesktopNative.Text("public.utf8-plain-text"));
        else
        {
            nint url = ALTRunMacDesktopNative.Arg(ALTRunMacDesktopNative.Class("NSURL"), Sel("fileURLWithPath:"), ALTRunMacDesktopNative.Text(Value));
            nint urls = ALTRunMacDesktopNative.Array(ALTRunMacDesktopNative.Class("NSArray"), Sel("arrayWithObjects:count:"), new[] { url }, 1);
            ALTRunMacDesktopNative.Arg(board, Sel("writeObjects:"), urls);
        }
        ALTRunServicesNative.Receive(board, Mode == "add");
        return ALTRunMacServiceNext();
    }
    finally { ALTRunMacDesktopNative.Send(board, Sel("releaseGlobally")); }
}
public static object ALTRunServiceQuitFixture()
{
    Eto.Forms.Application.Instance.Invoke(() => Eto.Forms.Application.Instance.Quit());
    return null;
}
#EndCSharp

OnError((error, mode) => (FileAppend("FAIL MAC_SERVICES " error.Message "`n" error.Stack "`n", "**"), ExitApp(1)))
if !Platform.IsMac {
    FileAppend("SKIP MAC_SERVICES requires macOS`n", "*")
    ExitApp()
}
ALTRunMacServicesInstall()
textRequest := JSON.Parse(ALTRunServiceFixture("text", "Selected text ' $() 漢字`nsecond line"))
if textRequest["Add"] || textRequest["Files"].Length || textRequest["Text"] != "Selected text ' $() 漢字`nsecond line"
    throw Error("Native text Services must preserve selected content.")
fixturePath := Platform.Join(A_Temp, "literal ' $() 漢字`nfile.txt")
fileRequest := JSON.Parse(ALTRunServiceFixture("add", fixturePath))
if !fileRequest["Add"] || fileRequest["Files"].Length != 1 || fileRequest["Files"][1] != fixturePath || fileRequest["Text"] != ""
    throw Error("Native file Services must pass literal URL paths.")
actionsRequest := JSON.Parse(ALTRunServiceFixture("files", fixturePath))
if actionsRequest["Add"] || actionsRequest["Files"][1] != fixturePath
    throw Error("File action Services must keep their action type.")
ALTRunMacObserveDesktop()
ALTRunMacObserveDesktop()
if ALTRunMacDesktopChanged()
    throw Error("Registering desktop observers must not create a change event.")
ALTRunMacStopObserving()
ALTRunMacStopObserving()
ALTRunMacInstallQuitBridge()
ALTRunServiceQuitFixture()
if !ALTRunMacQuitRequested() || ALTRunMacQuitRequested()
    throw Error("Native Quit must queue exactly one script shutdown request.")
ALTRunMacStopQuitBridge()
if Platform.AppBundle != ""
    throw Error("An external source fixture must not inherit another app's identity.")
FileAppend("PASS MAC_SERVICES native private pasteboards, literal file URLs, text selection and observer lifecycle`n", "*")
ExitApp()

; PortableHttp - local HTTP fixture checks; no Internet, desktop prompts or persistent data.
#ErrorStdOut
#Warn All, StdOut
#Warn Experimental, Off
#NoTrayIcon
#SingleInstance Off
#Include ../ALTRun.Modules.ahk

OnError((err, mode) => PortableHttp.OnError(err, mode))
OnExit((*) => PortableHttp.CleanUp())
SetTimer(() => PortableHttp.Fail("Timed out after 15 seconds."), -15000)
PortableHttp.Run()

#CSharp
private static System.Net.Sockets.TcpListener ALTRunHttpFixtureListener;
private static System.Threading.CancellationTokenSource ALTRunHttpFixtureCancellation;

public static long ALTRunHttpFixtureStart()
{
    ALTRunHttpFixtureCancellation = new();
    var token = ALTRunHttpFixtureCancellation.Token;
    ALTRunHttpFixtureListener = new(System.Net.IPAddress.Loopback, 0);
    ALTRunHttpFixtureListener.Start();
    _ = System.Threading.Tasks.Task.Run(async () =>
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                var client = await ALTRunHttpFixtureListener.AcceptTcpClientAsync(token);
                _ = ALTRunHttpFixtureRespond(client, token);
            }
        }
        catch (System.OperationCanceledException) { }
        catch (System.Net.Sockets.SocketException) when (token.IsCancellationRequested) { }
        catch (System.ObjectDisposedException) when (token.IsCancellationRequested) { }
    });
    return ((System.Net.IPEndPoint)ALTRunHttpFixtureListener.LocalEndpoint).Port;
}

private static async System.Threading.Tasks.Task ALTRunHttpFixtureRespond(System.Net.Sockets.TcpClient Client, System.Threading.CancellationToken Token)
{
    using (Client)
    {
        try
        {
            var stream = Client.GetStream();
            using var reader = new System.IO.StreamReader(stream, System.Text.Encoding.ASCII, false, 1024, leaveOpen: true);
            var first = await reader.ReadLineAsync(Token);
            while (await reader.ReadLineAsync(Token) is { Length: > 0 }) { }
            var path = first.Split(' ')[1];
            if (path == "/slow")
                await System.Threading.Tasks.Task.Delay(2000, Token);
            var body = System.Text.Encoding.UTF8.GetBytes("{\"message\":\"café 漢字\"}");
            var status = path == "/error" ? "429 Too Many Requests" : "200 OK";
            var headers = System.Text.Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\nContent-Type: application/json; charset=utf-8\r\nConnection: close\r\nContent-Length: " + body.Length + "\r\n\r\n");
            await stream.WriteAsync(headers, Token);
            await stream.WriteAsync(body, Token);
        }
        catch (System.OperationCanceledException) { }
        catch (System.IO.IOException) { }
    }
}

public static void ALTRunHttpFixtureStop()
{
    ALTRunHttpFixtureCancellation?.Cancel();
    ALTRunHttpFixtureListener?.Stop();
}
#EndCSharp

class PortableHttp {
    static Results := Map(), Heartbeats := 0

    static Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    static Run() {
        Logger.Enabled := false
        base := "http://127.0.0.1:" ALTRunHttpFixtureStart()
        HttpGet.PollMs := 10
        SetTimer(() => PortableHttp.Heartbeats += 1, 10)
        HttpGet.Start(base "/ok", (text) => PortableHttp.Success("first", text), (message) => PortableHttp.Fail(message))
        HttpGet.Start(base "/second", (text) => PortableHttp.Success("second", text), (message) => PortableHttp.Fail(message))
        HttpGet.Start(base "/error", (text) => PortableHttp.Fail("An HTTP error reached the success callback."), (message) => PortableHttp.ExpectedFailure("http", message, "^HTTP 429"))
        HttpGet.Start(base "/slow", (text) => PortableHttp.Fail("The request did not time out."), (message) => PortableHttp.ExpectedFailure("timeout", message, "^Timed out"), 100)
        HttpGet.Start(base "/callback", (text) => PortableHttp.ThrowCallback(), (message) => PortableHttp.ExpectedFailure("callback", message, "^Callback failure fixture$"))
        HttpGet.Start("file:///invalid-http-fixture", (text) => PortableHttp.Fail("A non-HTTP URL was accepted."), (message) => PortableHttp.ExpectedFailure("scheme", message, "Only HTTP and HTTPS"))
        original := HttpGet.NewRequest
        try {
            HttpGet.NewRequest := () => PortableHttpFakeRequest()
            HttpGet.Start(base "/fake", (text) => PortableHttp.FakeSuccess(text), (message) => PortableHttp.Fail(message))
        } finally {
            HttpGet.NewRequest := original
        }
        PortableHttp.Assert(HttpGet.Pending >= 5, "Requests should remain pending until the timer polls them.")
        SetTimer(() => PortableHttp.Check(), 10)
    }

    static Success(name, text) {
        PortableHttp.Assert(text == '{"message":"café 漢字"}', "UTF-8 response was changed.")
        PortableHttp.Results[name] := true
    }

    static FakeSuccess(text) {
        PortableHttp.Assert(text == "fake response", "NewRequest must remain injectable.")
        PortableHttp.Results["fake"] := true
    }

    static ExpectedFailure(name, message, expected) {
        PortableHttp.Assert(RegExMatch(message, expected), name ": unexpected failure: " message)
        PortableHttp.Results[name] := true
    }

    static ThrowCallback() {
        throw Error("Callback failure fixture")
    }

    static Check() {
        if (PortableHttp.Results.Count != 7 || HttpGet.Pending != 0)
            return
        PortableHttp.Assert(PortableHttp.Heartbeats > 0, "Script timers must continue during HTTP requests.")
        FileAppend("PASS PORTABLE_HTTP UTF-8, concurrent requests, HTTP errors, timeout, callback failures and request injection`n", "*")
        ExitApp(0)
    }

    static CleanUp() {
        try ALTRunHttpCancelAll()
        try ALTRunHttpFixtureStop()
    }

    static OnError(err, mode) {
        FileAppend("FAIL PORTABLE_HTTP " err.Message "`n" err.Stack "`n", "**")
        ExitApp(1)
        return true
    }

    static Fail(message) {
        FileAppend("FAIL PORTABLE_HTTP " message "`n", "**")
        ExitApp(1)
    }
}

class PortableHttpFakeRequest {
    ReadyState => 4
    Status => 200
    StatusText => "OK"
    ResponseText => "fake response"
    Open(args*) { }
    SetRequestHeader(args*) { }
    Send() { }
    Abort() { }
}

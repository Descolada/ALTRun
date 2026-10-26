;===============================================================================
; HttpGet.ahk - downloads web content in the background; the program keeps responding meanwhile (AutoHotkey v2)
;-------------------------------------------------------------------------------
; AHK's Download() stops the whole program until it finishes: with a slow network or a proxy timing out, hotkeys and the search window don't respond.
; HttpClient downloads run in the background. A timer checks completion and calls script callbacks
; on the script thread; background workers never enter the interpreter.
;
; Usage:
;   HttpGet.Start(url, done, fail?, timeoutMs?)
;     done(text)      called for HTTP 2xx with the response text; if done throws (e.g. bad content), fail is called instead
;     fail(message)   called for network errors, HTTP errors and timeouts (30 s by default); without fail it goes to the log
;   HttpGet.Pending   number of requests not finished yet
;===============================================================================

#CSharp
private sealed record ALTRunHttpResult(int Status, string StatusText, string Text, string Error);
private sealed record ALTRunHttpJob(System.Threading.CancellationTokenSource Cancellation, System.Threading.Tasks.Task<ALTRunHttpResult> Task);
private static readonly System.Net.Http.HttpClient ALTRunHttpClient = new() { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
private static readonly System.Collections.Concurrent.ConcurrentDictionary<long, ALTRunHttpJob> ALTRunHttpJobs = new();
private static long ALTRunHttpNextJob;

public static long ALTRunHttpStart(string Address, string Headers)
{
    var uri = new System.Uri(Address, System.UriKind.Absolute);
    if (uri.Scheme != "http" && uri.Scheme != "https")
        throw new System.ArgumentException("Only HTTP and HTTPS addresses are supported.");
    var headers = System.Text.Json.JsonSerializer.Deserialize<System.Collections.Generic.Dictionary<string, string>>(Headers);
    var cancellation = new System.Threading.CancellationTokenSource();
    async System.Threading.Tasks.Task<ALTRunHttpResult> Download()
    {
        try
        {
            using var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, uri);
            request.Headers.UserAgent.ParseAdd("ALTRun");
            foreach (var header in headers)
                request.Headers.TryAddWithoutValidation(header.Key, header.Value);
            using var response = await ALTRunHttpClient.SendAsync(request, cancellation.Token).ConfigureAwait(false);
            var text = await response.Content.ReadAsStringAsync(cancellation.Token).ConfigureAwait(false);
            return new((int)response.StatusCode, response.ReasonPhrase ?? "", text, "");
        }
        catch (System.Exception error)
        {
            return new(0, "", "", "Network error: " + error.Message);
        }
    }
    var id = System.Threading.Interlocked.Increment(ref ALTRunHttpNextJob);
    ALTRunHttpJobs[id] = new(cancellation, Download());
    return id;
}

public static bool ALTRunHttpIsFinished(long Id) => !ALTRunHttpJobs.TryGetValue(Id, out var job) || job.Task.IsCompleted;

public static string ALTRunHttpFinish(long Id)
{
    if (!ALTRunHttpJobs.TryGetValue(Id, out var pending) || !pending.Task.IsCompleted)
        throw new System.InvalidOperationException("The HTTP request has not finished.");
    if (!ALTRunHttpJobs.TryRemove(Id, out var job))
        throw new System.InvalidOperationException("The HTTP request was already released.");
    using (job.Cancellation)
        return System.Text.Json.JsonSerializer.Serialize(job.Task.GetAwaiter().GetResult());
}

public static void ALTRunHttpAbort(long Id)
{
    if (!ALTRunHttpJobs.TryRemove(Id, out var job)) return;
    job.Cancellation.Cancel();
    _ = job.Task.ContinueWith(_ => job.Cancellation.Dispose(), System.Threading.Tasks.TaskScheduler.Default);
}

public static void ALTRunHttpCancelAll()
{
    foreach (var id in ALTRunHttpJobs.Keys)
        ALTRunHttpAbort(id);
}
#EndCSharp

class HttpGet {
    static PollMs := 100, TimeoutMs := 30000
    static NewRequest := () => HttpGetRequest()                             ; replaced by a fake request in tests
    static _active := [], _timer := "", _exitRegistered := false

    static Pending => HttpGet._active.Length

    static Start(url, done, fail := "", timeoutMs := "") {
        if !HttpGet._exitRegistered {
            OnExit((*) => ALTRunHttpCancelAll())
            HttpGet._exitRegistered := true
        }
        if (timeoutMs = "")
            timeoutMs := HttpGet.TimeoutMs
        try {
            xhr := HttpGet.NewRequest.Call()
            xhr.open("GET", url, true)
            xhr.setRequestHeader("If-Modified-Since", "Sat, 01 Jan 2000 00:00:00 GMT")   ; ask the server rather than returning a cached response
            xhr.send()
        } catch as e {
            return HttpGet._Later(fail, "", e.Message)
        }
        HttpGet._active.Push({Xhr: xhr, Done: done, Fail: fail, Deadline: A_TickCount + timeoutMs, TimeoutMs: timeoutMs})
        if (HttpGet._timer = "")
            HttpGet._timer := () => HttpGet._Poll()
        SetTimer(HttpGet._timer, HttpGet.PollMs)
    }

    static _Poll() {
        i := HttpGet._active.Length
        while (i >= 1) {
            request := HttpGet._active[i]
            state := 0
            try state := request.Xhr.readyState
            if (state = 4) {
                HttpGet._active.RemoveAt(i)
                HttpGet._Finish(request)
            } else if (A_TickCount >= request.Deadline) {
                HttpGet._active.RemoveAt(i)
                try request.Xhr.abort()
                HttpGet._Later(request.Fail, "", "Timed out after " Round(request.TimeoutMs / 1000) " s")
            }
            i--
        }
        if !HttpGet._active.Length
            SetTimer(HttpGet._timer, 0)
    }

    static _Finish(request) {
        try {
            status := request.Xhr.status
            if (status >= 12000)                                            ; WinINet error number (can't connect, host not found...)
                throw Error("Network error " status)
            if (status < 200 || status >= 300)
                throw Error("HTTP " status " " request.Xhr.statusText)
            text := request.Xhr.responseText
        } catch as e {
            return HttpGet._Later(request.Fail, "", e.Message)
        }
        HttpGet._Later(request.Fail, request.Done, text)
    }

    ; The callback runs in its own thread: if it shows a dialog, the other requests are still checked
    static _Later(fail, done, value) {
        SetTimer(() => HttpGet._Call(fail, done, value), -1)
    }

    static _Call(fail, done, value) {
        if IsObject(done) {
            try {
                done.Call(value)
                return
            } catch as e {
                value := e.Message
            }
        }
        if IsObject(fail)
            fail.Call(value)
        else
            Logger.Error("HttpGet: " value)
    }
}

; The small request interface is also implemented by the upstream test fixtures.
class HttpGetRequest {
    Job := 0, Address := "", Headers := Map(), Result := ""

    Open(method, address, asynchronous := true) {
        if (method != "GET" || !asynchronous)
            throw Error("HttpGet supports asynchronous GET requests.")
        this.Address := address
    }

    SetRequestHeader(name, value) => this.Headers[name] := value

    Send() => this.Job := ALTRunHttpStart(this.Address, JSON.Stringify(this.Headers))

    ReadyState => this.Job && ALTRunHttpIsFinished(this.Job) ? 4 : 1
    Status => this._Response()["Status"]
    StatusText => this._Response()["StatusText"]
    ResponseText => this._Response()["Text"]

    _Response() {
        if !IsObject(this.Result) {
            this.Result := JSON.Parse(ALTRunHttpFinish(this.Job))
            this.Job := 0
        }
        if (this.Result["Error"] != "")
            throw Error(this.Result["Error"])
        return this.Result
    }

    Abort() {
        if this.Job
            ALTRunHttpAbort(this.Job)
        this.Job := 0
    }
}

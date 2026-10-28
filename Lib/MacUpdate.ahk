; Native updates are offered only to a notarized Developer ID application with a matching signed replacement.
class MacUpdate {
    static _identity := Map("Trusted", false, "Team", ""), _timer := "", _installing := false, _identityPending := false

    static Init() {
#if OSX
        if (Platform.AppBundle = "" || !ALTRunMacUpdateBeginIdentity(Platform.AppBundle))
            return
        MacUpdate._identityPending := true
        MacUpdate._timer := () => MacUpdate._Poll()
        SetTimer(MacUpdate._timer, 200)
#endif
    }

    static TrustedTeam() => MacUpdate._identity["Trusted"] ? MacUpdate._identity["Team"] : ""

    static CanInstall(release) {
        if (!Platform.IsMac || MacUpdate.TrustedTeam() = "" || !IsObject(release))
            return false
        return release.ZipUrl != "" && RegExMatch(release.Sha256, "i)^[0-9a-f]{64}$")
            && RegExMatch(release.Version, "^\d+(?:\.\d+)*$")
    }

    static Install(release) {
        if (MacUpdate._installing || !MacUpdate.CanInstall(release))
            return false
#if OSX
        repository := AppSettings.General.Has("UpdateRepository") ? AppSettings.General["UpdateRepository"] : "Descolada/ALTRun"
        if !ALTRunMacUpdateBeginInstall(release.ZipUrl, release.Sha256, release.Version, repository)
            return false
        MacUpdate._installing := true
        App.Notify(I18n.T("Update.Downloading", release.Version), 3000)
        if !IsObject(MacUpdate._timer)
            MacUpdate._timer := () => MacUpdate._Poll()
        SetTimer(MacUpdate._timer, 200)
        return true
#else
        return false
#endif
    }

    static _Poll() {
#if OSX
        identity := ALTRunMacUpdateIdentityPoll()
        if (identity != "") {
            MacUpdate._identity := JSON.Parse(identity)
            MacUpdate._identityPending := false
        }
        if MacUpdate._installing {
            completed := ALTRunMacUpdateInstallPoll()
            if (completed != "") {
                MacUpdate._installing := false
                result := JSON.Parse(completed)
                if result["Ready"] {
                    App.Quit()
                    return
                }
                Logger.Error("macOS update: " result["Error"])
                MsgBox(I18n.T("Update.Failed", result["Error"]), App.Name, 48)
            }
        }
        if (!MacUpdate._installing && !MacUpdate._identityPending)
            SetTimer(MacUpdate._timer, 0)
#endif
    }

    static Stop() {
        if IsObject(MacUpdate._timer)
            SetTimer(MacUpdate._timer, 0)
#if OSX
        ALTRunMacUpdateStop()
#endif
    }

    static SignalReady(marker, nonce) {
#if OSX
        return ALTRunMacUpdateSignalReady(Platform.AppBundle, App.Version, marker, nonce)
#else
        return false
#endif
    }
}

#if OSX
#CSharp
using System.Linq;
public static bool ALTRunMacUpdateBeginIdentity(string bundle) => ALTRunMacUpdater.BeginIdentity(bundle);
public static string ALTRunMacUpdateIdentityPoll() => ALTRunMacUpdater.IdentityPoll();
public static bool ALTRunMacUpdateBeginInstall(string url, string sha, string version, string repository) => ALTRunMacUpdater.BeginInstall(url, sha, version, repository);
public static string ALTRunMacUpdateInstallPoll() => ALTRunMacUpdater.InstallPoll();
public static void ALTRunMacUpdateStop() => ALTRunMacUpdater.Stop();
public static bool ALTRunMacUpdateSignalReady(string bundle, string version, string marker, string nonce)
    => ALTRunMacUpdater.SignalReady(bundle, version, marker, nonce);
public static string ALTRunMacValidateUpdateArchive(string archive)
{
    try { return ALTRunMacUpdater.ValidateArchive(archive); }
    catch (System.Exception error) { return "ERROR: " + error.Message; }
}
public static string ALTRunMacUpdateFixtureHelper(string current, string incoming, string backup, bool launchSucceeds)
    => ALTRunMacUpdater.HelperScript(current, incoming, backup, 0, launchSucceeds ? "/usr/bin/true" : "/usr/bin/false");
public static string ALTRunMacUpdateFixtureReadyHelper(string current, string incoming, string backup, string staging, string nonce)
    => ALTRunMacUpdater.HelperScript(current, incoming, backup, 0, System.IO.Path.Combine(current, "Contents", "MacOS", "Fixture"), staging, nonce);

private static class ALTRunMacUpdater
{
    private sealed record Identity(string Bundle, string BundleId, string Team, string Version, bool Trusted, string Error = "");
    private sealed record Command(int Code, string Output, string Error);
    private static System.Threading.Tasks.Task<Identity> identityJob;
    private static System.Threading.Tasks.Task<string> installJob;
    private static Identity identity;
    private static System.Threading.CancellationTokenSource cancellation;
    private static bool handedOff;
    private static string stage = "", incoming = "";
    private const long MaxArchive = 1024L * 1024 * 1024, MaxExpanded = 2L * 1024 * 1024 * 1024;
    [System.Runtime.InteropServices.DllImport("/usr/lib/libSystem.B.dylib")]
    private static extern System.IntPtr realpath([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPUTF8Str)] string path, System.IntPtr destination);
    [System.Runtime.InteropServices.DllImport("/usr/lib/libSystem.B.dylib")]
    private static extern void free(System.IntPtr value);
    private static string RealPath(string path)
    {
        var value = realpath(path, System.IntPtr.Zero);
        if (value == System.IntPtr.Zero) throw new System.IO.IOException("The update path cannot be resolved.");
        try { return System.Runtime.InteropServices.Marshal.PtrToStringUTF8(value); }
        finally { free(value); }
    }

    internal static bool BeginIdentity(string bundle)
    {
        if (identityJob != null || string.IsNullOrEmpty(bundle)) return false;
        identityJob = System.Threading.Tasks.Task.Run(() =>
        {
            try { return ReadIdentity(bundle); }
            catch (System.Exception error) { return new Identity(bundle, "", "", "", false, error.Message); }
        });
        return true;
    }

    internal static string IdentityPoll()
    {
        if (identityJob?.IsCompleted != true) return "";
        identity = identityJob.GetAwaiter().GetResult(); identityJob = null;
        return System.Text.Json.JsonSerializer.Serialize(identity);
    }

    private static Identity ReadIdentity(string bundle)
    {
        bundle = System.IO.Path.GetFullPath(bundle);
        if (!bundle.EndsWith(".app", System.StringComparison.OrdinalIgnoreCase) || new System.IO.DirectoryInfo(bundle).LinkTarget != null)
            throw new System.IO.InvalidDataException("The installed application is not a regular app bundle.");
        string id = Plist(bundle, "CFBundleIdentifier"), version = Plist(bundle, "CFBundleShortVersionString");
        if (id != "org.keysharp.ALTRun") return new Identity(bundle, id, "", version, false);
        var signature = Run("/usr/bin/codesign", ["-d", "--verbose=4", bundle]);
        string detail = signature.Output + "\n" + signature.Error;
        var match = System.Text.RegularExpressions.Regex.Match(detail, @"(?m)^TeamIdentifier=([A-Z0-9]{10})\s*$");
        if (signature.Code != 0 || !match.Success || !detail.Contains("Authority=Developer ID Application:", System.StringComparison.Ordinal))
            return new Identity(bundle, id, "", version, false);
        VerifyBundle(bundle, match.Groups[1].Value, id, version);
        return new Identity(bundle, id, match.Groups[1].Value, version, true);
    }

    private static string Plist(string bundle, string key, System.Threading.CancellationToken token = default)
    {
        var result = Run("/usr/bin/plutil", ["-extract", key, "raw", "-o", "-", System.IO.Path.Combine(bundle, "Contents", "Info.plist")], token);
        if (result.Code != 0) throw new System.IO.InvalidDataException("The app bundle has no valid " + key + ".");
        return result.Output.Trim();
    }

    private static void VerifyBundle(string bundle, string team, string id, string version, System.Threading.CancellationToken token = default)
    {
        if (Plist(bundle, "CFBundleIdentifier", token) != id || Plist(bundle, "CFBundleShortVersionString", token) != version)
            throw new System.IO.InvalidDataException("The update's bundle identifier or version does not match the release.");
        var details = Run("/usr/bin/codesign", ["-d", "--verbose=4", bundle], token);
        string text = details.Output + "\n" + details.Error;
        if (details.Code != 0 || !System.Text.RegularExpressions.Regex.IsMatch(text, @"(?m)^TeamIdentifier=" + System.Text.RegularExpressions.Regex.Escape(team) + @"\s*$")
            || !text.Contains("Authority=Developer ID Application:", System.StringComparison.Ordinal))
            throw new System.IO.InvalidDataException("The update is not signed by the installed application's Developer ID team.");
        var verify = Run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", bundle], token);
        if (verify.Code != 0) throw new System.IO.InvalidDataException("The update's code signature did not verify: " + verify.Error.Trim());
        var assess = Run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", bundle], token);
        if (assess.Code != 0 || !(assess.Output + assess.Error).Contains("source=Notarized Developer ID", System.StringComparison.Ordinal))
            throw new System.IO.InvalidDataException("Gatekeeper did not accept the app as a notarized Developer ID application.");
    }

    internal static bool BeginInstall(string url, string sha, string version, string repository)
    {
        if (identity?.Trusted != true || installJob != null || handedOff) return false;
        cancellation = new System.Threading.CancellationTokenSource(System.TimeSpan.FromMinutes(5));
        installJob = System.Threading.Tasks.Task.Run(async () =>
        {
            try
            {
                var token = cancellation.Token;
                if (!System.Text.RegularExpressions.Regex.IsMatch(repository, @"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
                    || !System.Text.RegularExpressions.Regex.IsMatch(sha, @"\A[0-9A-Fa-f]{64}\z")
                    || !System.Text.RegularExpressions.Regex.IsMatch(version, @"\A\d+(?:\.\d+)*\z"))
                    throw new System.IO.InvalidDataException("The update metadata is invalid.");
                var address = new System.Uri(url);
                if (address.Scheme != "https" || !address.IsDefaultPort || address.Host != "github.com" || address.UserInfo.Length != 0
                    || address.Query.Length != 0 || address.Fragment.Length != 0
                    || !address.AbsolutePath.StartsWith("/" + repository + "/releases/download/", System.StringComparison.Ordinal)
                    || address.AbsolutePath.Contains("..", System.StringComparison.Ordinal))
                    throw new System.IO.InvalidDataException("The update URL is outside the configured repository.");
                stage = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ALTRun-update-" + System.Guid.NewGuid().ToString("N"));
                System.IO.Directory.CreateDirectory(stage, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
                string archive = System.IO.Path.Combine(stage, "release.zip");
                await Download(address, archive, token);
                using (var stream = System.IO.File.OpenRead(archive))
                {
                    string actual = System.Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(stream, token));
                    if (!actual.Equals(sha, System.StringComparison.OrdinalIgnoreCase)) throw new System.IO.InvalidDataException("The update's SHA256 does not match the release.");
                }
                string appRoot = ValidateArchive(archive);
                string extracted = System.IO.Path.Combine(stage, "extracted"); System.IO.Directory.CreateDirectory(extracted);
                var extraction = Run("/usr/bin/ditto", ["-x", "-k", archive, extracted], token);
                if (extraction.Code != 0) throw new System.IO.InvalidDataException("The update could not be extracted: " + extraction.Error.Trim());
                string candidate = System.IO.Path.Combine(extracted, appRoot);
                ValidateExtracted(candidate);
                VerifyBundle(candidate, identity.Team, identity.BundleId, version, token);
                if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture is System.Runtime.InteropServices.Architecture.Arm64 or System.Runtime.InteropServices.Architecture.X64)
                {
                    string executable = Plist(candidate, "CFBundleExecutable", token);
                    if (executable.Contains('/') || executable.Contains('\\') || executable is "." or "..") throw new System.IO.InvalidDataException("The app executable name is invalid.");
                    string architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x86_64";
                    var slices = Run("/usr/bin/lipo", ["-verify_arch", architecture, System.IO.Path.Combine(candidate, "Contents", "MacOS", executable)], token);
                    if (slices.Code != 0) throw new System.IO.InvalidDataException("The update does not support this Mac's processor.");
                }
                string parent = System.IO.Path.GetDirectoryName(identity.Bundle);
                incoming = System.IO.Path.Combine(parent, ".ALTRun-incoming-" + System.Guid.NewGuid().ToString("N") + ".app");
                string backup = System.IO.Path.Combine(parent, ".ALTRun-backup-" + System.DateTime.UtcNow.ToString("yyyyMMddHHmmss") + "-" + System.Guid.NewGuid().ToString("N") + ".app");
                var copied = Run("/usr/bin/ditto", [candidate, incoming], token);
                if (copied.Code != 0) throw new System.IO.IOException("The application folder is not writable or the staged app could not be copied.");
                ValidateExtracted(incoming);
                VerifyBundle(incoming, identity.Team, identity.BundleId, version, token);
                VerifyBundle(identity.Bundle, identity.Team, identity.BundleId, identity.Version, token);
                token.ThrowIfCancellationRequested();
                string helper = System.IO.Path.Combine(stage, "apply-update.sh"), nonce = System.Guid.NewGuid().ToString("N");
                string executableName = Plist(incoming, "CFBundleExecutable", token);
                string launcher = System.IO.Path.Combine(identity.Bundle, "Contents", "MacOS", executableName);
                string manifest = System.IO.Path.Combine(stage, "readiness.json");
                System.IO.File.WriteAllText(manifest, System.Text.Json.JsonSerializer.Serialize(new { Bundle = identity.Bundle, Version = version, Nonce = nonce }));
                System.IO.File.SetUnixFileMode(manifest, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite);
                System.IO.File.WriteAllText(helper, HelperScript(identity.Bundle, incoming, backup, System.Environment.ProcessId, launcher, stage, nonce), new System.Text.UTF8Encoding(false));
                System.IO.File.SetUnixFileMode(helper, System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite | System.IO.UnixFileMode.UserExecute);
                var start = new System.Diagnostics.ProcessStartInfo("/bin/sh") { UseShellExecute = false };
                start.ArgumentList.Add(helper);
                using var process = System.Diagnostics.Process.Start(start) ?? throw new System.IO.IOException("The update helper did not start.");
                handedOff = true;
                return System.Text.Json.JsonSerializer.Serialize(new { Ready = true, Error = "" });
            }
            catch (System.Exception error)
            {
                CleanStaging();
                return System.Text.Json.JsonSerializer.Serialize(new { Ready = false, Error = error is System.OperationCanceledException ? "The update was cancelled or exceeded five minutes." : error.Message });
            }
        });
        return true;
    }

    private static async System.Threading.Tasks.Task Download(System.Uri address, string destination, System.Threading.CancellationToken token)
    {
        using var handler = new System.Net.Http.HttpClientHandler { AllowAutoRedirect = false };
        using var client = new System.Net.Http.HttpClient(handler) { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("ALTRun/1.0");
        for (int redirect = 0; redirect <= 5; ++redirect)
        {
            using var response = await client.GetAsync(address, System.Net.Http.HttpCompletionOption.ResponseHeadersRead, token);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                var location = response.Headers.Location ?? throw new System.IO.IOException("The download redirect has no destination.");
                address = location.IsAbsoluteUri ? location : new System.Uri(address, location);
                if (address.Scheme != "https" || !address.IsDefaultPort || address.UserInfo.Length > 0 || address.Fragment.Length > 0
                    || !(address.Host == "github.com" || address.Host.EndsWith(".githubusercontent.com", System.StringComparison.Ordinal)))
                    throw new System.IO.InvalidDataException("The download redirected outside GitHub's HTTPS asset hosts.");
                continue;
            }
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength > MaxArchive) throw new System.IO.InvalidDataException("The update archive is too large.");
            using var input = await response.Content.ReadAsStreamAsync(token);
            using var output = new System.IO.FileStream(destination, System.IO.FileMode.CreateNew, System.IO.FileAccess.Write, System.IO.FileShare.None, 81920, true);
            var buffer = new byte[81920]; long total = 0; int count;
            while ((count = await input.ReadAsync(buffer, token)) != 0)
            {
                total += count;
                if (total > MaxArchive) throw new System.IO.InvalidDataException("The update archive is too large.");
                await output.WriteAsync(buffer.AsMemory(0, count), token);
            }
            return;
        }
        throw new System.IO.IOException("The download has too many redirects.");
    }

    internal static string ValidateArchive(string archive)
    {
        using var zip = System.IO.Compression.ZipFile.OpenRead(archive);
        if (zip.Entries.Count == 0 || zip.Entries.Count > 50000 || new System.IO.FileInfo(archive).Length > MaxArchive)
            throw new System.IO.InvalidDataException("The archive's entry count or size is invalid.");
        var names = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
        var links = new System.Collections.Generic.Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);
        var regular = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
        string root = ""; long total = 0;
        foreach (var entry in zip.Entries)
        {
            string name = entry.FullName;
            if (name.Length == 0 || name.StartsWith('/') || name.Contains('\\') || name.Contains(':') || name.Any(c => char.IsControl(c)))
                throw new System.IO.InvalidDataException("An archive path is unsafe.");
            string[] parts = name.TrimEnd('/').Split('/');
            if (parts.Any(p => p.Length == 0 || p is "." or "..")) throw new System.IO.InvalidDataException("An archive path contains traversal.");
            string canonical = string.Join("/", parts).Normalize(System.Text.NormalizationForm.FormC);
            if (!names.Add(canonical)) throw new System.IO.InvalidDataException("Archive paths collide on macOS.");
            bool metadata = parts[0] == "__MACOSX";
            if (!metadata)
            {
                if (!parts[0].EndsWith(".app", System.StringComparison.OrdinalIgnoreCase)) throw new System.IO.InvalidDataException("The archive must contain one top-level application.");
                if (root.Length == 0) root = parts[0];
                if (parts[0] != root) throw new System.IO.InvalidDataException("The archive contains more than one application.");
            }
            checked { total += entry.Length; }
            if (total > MaxExpanded || entry.Length > MaxArchive || entry.Length > 1024 * 1024 && entry.Length > System.Math.Max(1, entry.CompressedLength) * 1000)
                throw new System.IO.InvalidDataException("The archive expands beyond the allowed size.");
            int kind = (entry.ExternalAttributes >> 16) & 0xF000;
            if (kind is not (0 or 0x8000 or 0x4000 or 0xA000)) throw new System.IO.InvalidDataException("The archive contains a special file.");
            if (kind == 0xA000)
            {
                if (metadata || entry.Length > 4096) throw new System.IO.InvalidDataException("The archive contains an invalid symbolic link.");
                using var reader = new System.IO.StreamReader(entry.Open(), new System.Text.UTF8Encoding(false, true));
                string target = reader.ReadToEnd();
                if (target.Length == 0 || target.StartsWith('/') || target.Contains('\\') || target.Contains(':') || target.Any(c => char.IsControl(c)))
                    throw new System.IO.InvalidDataException("A symbolic link has an unsafe target.");
                if (parts.Length == 1) throw new System.IO.InvalidDataException("The application root cannot be a symbolic link.");
                links[canonical] = target;
            }
            else if (!metadata && !name.EndsWith('/')) regular.Add(canonical);
        }
        var resolvedFiles = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
        foreach (string name in names)
        {
            string physicalName = name.StartsWith("__MACOSX/", System.StringComparison.Ordinal) ? name[9..] : name;
            string ancestor = physicalName;
            while (ancestor.LastIndexOf('/') is int separator && separator >= 0)
            {
                ancestor = ancestor[..separator];
                if (links.ContainsKey(ancestor))
                    throw new System.IO.InvalidDataException("Archive entries may not be extracted through a symbolic-link directory.");
            }
            if (name.StartsWith("__MACOSX/", System.StringComparison.Ordinal) || name == "__MACOSX") continue;
            string resolved = ResolveArchivePath(name, links, root);
            if (regular.Contains(name) && !resolvedFiles.Add(resolved))
                throw new System.IO.InvalidDataException("Archive files collide through symbolic links.");
        }
        if (root.Length == 0 || !regular.Contains(root + "/Contents/Info.plist")) throw new System.IO.InvalidDataException("The archive has no app Info.plist.");
        // A regular file may not be an ancestor of another entry. Ditto must not reinterpret it as a directory.
        foreach (string name in names)
        {
            if (name.StartsWith("__MACOSX/", System.StringComparison.Ordinal) || name == "__MACOSX") continue;
            string resolved = ResolveArchivePath(name, links, root);
            string parent = resolved;
            while (parent.LastIndexOf('/') is int slash && slash >= 0)
            {
                parent = parent[..slash];
                if (resolvedFiles.Contains(parent)) throw new System.IO.InvalidDataException("An archive file is also used as a directory.");
            }
        }
        return root;
    }

    private static string ResolveArchivePath(string name, System.Collections.Generic.Dictionary<string, string> links, string root)
    {
        // Resolve links before subsequent '..' components, exactly as pathname lookup does.
        // Lexically collapsing 'link/..' first can hide an escape from a private extraction directory.
        var pending = new System.Collections.Generic.LinkedList<string>(name.Normalize(System.Text.NormalizationForm.FormC).Split('/'));
        var parts = new System.Collections.Generic.List<string>();
        int hops = 0;
        while (pending.First != null)
        {
            string part = pending.First.Value; pending.RemoveFirst();
            if (part is "" or ".") continue;
            if (part == "..")
            {
                if (parts.Count <= 1) throw new System.IO.InvalidDataException("A symbolic link escapes the application.");
                parts.RemoveAt(parts.Count - 1);
            }
            else
            {
                parts.Add(part);
                string prefix = string.Join("/", parts);
                if (links.TryGetValue(prefix, out string target))
                {
                    if (++hops > 64) throw new System.IO.InvalidDataException("The archive contains a symbolic-link cycle or excessive nesting.");
                    parts.RemoveAt(parts.Count - 1);
                    foreach (string component in target.Normalize(System.Text.NormalizationForm.FormC).Split('/').Reverse()) pending.AddFirst(component);
                }
            }
        }
        string result = string.Join("/", parts).Normalize(System.Text.NormalizationForm.FormC);
        if (!(result == root || result.StartsWith(root + "/", System.StringComparison.OrdinalIgnoreCase))) throw new System.IO.InvalidDataException("A symbolic link escapes the application.");
        return result;
    }

    private static void ValidateExtracted(string app)
    {
        if (!System.IO.Directory.Exists(app) || new System.IO.DirectoryInfo(app).LinkTarget != null)
            throw new System.IO.InvalidDataException("The extracted application is not a regular directory.");
        string prefix = System.IO.Path.GetFullPath(app).TrimEnd('/') + "/";
        var pending = new System.Collections.Generic.Stack<string>(); pending.Push(app);
        int count = 0; long size = 0;
        while (pending.TryPop(out var directory))
            foreach (var entry in new System.IO.DirectoryInfo(directory).EnumerateFileSystemInfos())
            {
                if (++count > 50000) throw new System.IO.InvalidDataException("The extracted app has too many files.");
                if (entry.LinkTarget != null)
                {
                    var target = entry.ResolveLinkTarget(true);
                    if (target == null || !target.Exists || !target.FullName.StartsWith(prefix, System.StringComparison.Ordinal))
                        throw new System.IO.InvalidDataException("An extracted symbolic link leaves the application.");
                }
                else if (entry is System.IO.DirectoryInfo) pending.Push(entry.FullName);
                else if (entry is System.IO.FileInfo file)
                {
                    checked { size += file.Length; }
                    if (size > MaxExpanded) throw new System.IO.InvalidDataException("The extracted app is too large.");
                }
            }
    }

    internal static bool SignalReady(string bundle, string version, string marker, string nonce)
    {
        try
        {
            if (bundle.Length == 0 || !System.Text.RegularExpressions.Regex.IsMatch(nonce, @"\A[a-f0-9]{32}\z")) return false;
            marker = System.IO.Path.GetFullPath(marker);
            string folder = RealPath(System.IO.Path.GetDirectoryName(marker)), temp = RealPath(System.IO.Path.GetTempPath()).TrimEnd('/') + "/";
            marker = System.IO.Path.Combine(folder, System.IO.Path.GetFileName(marker));
            var info = new System.IO.DirectoryInfo(folder);
            if (!folder.StartsWith(temp, System.StringComparison.Ordinal) || !info.Name.StartsWith("ALTRun-update-", System.StringComparison.Ordinal)
                || info.LinkTarget != null || System.IO.Path.GetFileName(marker) != "ready"
                || (System.IO.File.GetUnixFileMode(folder) & (System.IO.UnixFileMode.GroupRead | System.IO.UnixFileMode.GroupWrite | System.IO.UnixFileMode.GroupExecute
                    | System.IO.UnixFileMode.OtherRead | System.IO.UnixFileMode.OtherWrite | System.IO.UnixFileMode.OtherExecute)) != 0)
                return false;
            string manifestPath = System.IO.Path.Combine(folder, "readiness.json");
            if (new System.IO.FileInfo(manifestPath).LinkTarget != null) return false;
            using var doc = System.Text.Json.JsonDocument.Parse(System.IO.File.ReadAllText(manifestPath));
            if (doc.RootElement.GetProperty("Nonce").GetString() != nonce || doc.RootElement.GetProperty("Version").GetString() != version
                || RealPath(doc.RootElement.GetProperty("Bundle").GetString()) != RealPath(bundle)) return false;
            string next = System.IO.Path.Combine(folder, "ready-" + nonce);
            using (var stream = new System.IO.FileStream(next, new System.IO.FileStreamOptions { Mode = System.IO.FileMode.CreateNew,
                Access = System.IO.FileAccess.Write, UnixCreateMode = System.IO.UnixFileMode.UserRead | System.IO.UnixFileMode.UserWrite }))
            {
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(nonce + " " + System.Environment.ProcessId + "\n");
                stream.Write(bytes); stream.Flush(true);
            }
            System.IO.File.Move(next, marker, false);
            return true;
        }
        catch { return false; }
    }

    internal static string HelperScript(string current, string source, string backup, int pid, string opener, string staging = "", string nonce = "")
    {
        string quote(string value) => "'" + value.Replace("'", "'\"'\"'") + "'";
        // Both app renames stay on the installation volume. Preserve the previous app after success.
        string header = "#!/bin/sh\nset -eu\numask 077\ncurrent=" + quote(current) + "\nincoming=" + quote(source) + "\nbackup=" + quote(backup)
            + "\ncount=0\n" + (pid > 0 ? "while kill -0 " + pid + " 2>/dev/null; do\n count=$((count+1))\n [ \"$count\" -le 600 ] || exit 2\n /bin/sleep 0.1\ndone\n" : "")
            + "[ -d \"$current\" ] && [ -d \"$incoming\" ] && [ ! -e \"$backup\" ] || exit 3\n"
            + "/bin/mv \"$current\" \"$backup\"\n"
            + "if ! /bin/mv \"$incoming\" \"$current\"; then /bin/mv \"$backup\" \"$current\"; "
            + (pid > 0 ? "/usr/bin/open -n \"$current\" || :; " : "") + "exit 4; fi\n";
        if (nonce.Length == 0)
            return header + "if ! " + quote(opener) + " \"$current\"; then\n /bin/mv \"$current\" \"$incoming\"\n /bin/mv \"$backup\" \"$current\"\n exit 5\nfi\n/bin/rm -f \"$0\"\n";
        string marker = System.IO.Path.Combine(staging, "ready");
        return header + "marker=" + quote(marker) + "\nnonce=" + quote(nonce) + "\n"
            + "rollback() {\n kill \"$new_pid\" 2>/dev/null || :\n /bin/sleep 0.1\n kill -9 \"$new_pid\" 2>/dev/null || :\n wait \"$new_pid\" 2>/dev/null || :\n"
            + " /bin/mv \"$current\" \"$incoming\"\n /bin/mv \"$backup\" \"$current\"\n"
            + (pid > 0 ? " /usr/bin/open -n \"$current\" || :\n" : "") + " exit 6\n}\n"
            + quote(opener) + " -MacUpdateReady \"$marker\" \"$nonce\" > " + quote(System.IO.Path.Combine(staging, "new-app.log")) + " 2>&1 &\nnew_pid=$!\ncount=0\n"
            + "while :; do\n kill -0 \"$new_pid\" 2>/dev/null || rollback\n ready_nonce=\n ready_pid=\n"
            + " if [ -f \"$marker\" ]; then IFS=' ' read -r ready_nonce ready_pid < \"$marker\" || :; fi\n"
            + " if [ \"$ready_nonce\" = \"$nonce\" ] && [ \"$ready_pid\" = \"$new_pid\" ]; then break; fi\n"
            + " count=$((count+1))\n [ \"$count\" -le 300 ] || rollback\n /bin/sleep 0.1\ndone\n"
            + "/bin/sleep 1\nkill -0 \"$new_pid\" 2>/dev/null || rollback\n"
            + "[ -d \"$backup\" ] || exit 7\n/bin/rm -rf " + quote(staging) + "\n";
    }

    internal static string InstallPoll()
    {
        if (installJob?.IsCompleted != true) return "";
        string result = installJob.GetAwaiter().GetResult(); installJob = null;
        return result;
    }

    internal static void Stop()
    {
        if (handedOff) return;
        cancellation?.Cancel();
        if (installJob != null && !installJob.IsCompleted)
            try { installJob.Wait(System.TimeSpan.FromSeconds(2)); } catch { }
        if (installJob == null || installJob.IsCompleted) CleanStaging();
    }

    private static void CleanStaging()
    {
        if (handedOff) return;
        if (!string.IsNullOrEmpty(incoming)) try { System.IO.Directory.Delete(incoming, true); } catch { }
        if (!string.IsNullOrEmpty(stage)) try { System.IO.Directory.Delete(stage, true); } catch { }
    }

    private static Command Run(string executable, string[] args, System.Threading.CancellationToken cancellation = default)
    {
        var start = new System.Diagnostics.ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string arg in args) start.ArgumentList.Add(arg);
        using var process = System.Diagnostics.Process.Start(start) ?? throw new System.IO.IOException("Could not run " + executable + ".");
        var output = process.StandardOutput.ReadToEndAsync(); var errors = process.StandardError.ReadToEndAsync();
        using var deadline = System.Threading.CancellationTokenSource.CreateLinkedTokenSource(cancellation); deadline.CancelAfter(System.TimeSpan.FromSeconds(45));
        try { process.WaitForExitAsync(deadline.Token).GetAwaiter().GetResult(); }
        catch { try { process.Kill(true); } catch { } throw; }
        return new Command(process.ExitCode, output.GetAwaiter().GetResult(), errors.GetAwaiter().GetResult());
    }
}
#EndCSharp
#endif

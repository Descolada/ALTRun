#!/bin/bash
# Run this checkout with Keysharp, including when opened from Finder.
set -euo pipefail

altrun_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'ALTRun.command requires macOS. Run Keysharp ALTRun.ahk on other platforms.' >&2
    exit 1
fi

altrun_host="${KEYSHARP_BIN:-}"
if [[ -z "$altrun_host" ]]; then
    for altrun_candidate in \
        "$altrun_root/../Keysharp/bin/Debug/net10.0/Keysharp.app" \
        "$altrun_root/../keysharp/bin/Debug/net10.0/Keysharp.app" \
        "$altrun_root/../Keysharp/bin/Release/net10.0/Keysharp.app" \
        "$altrun_root/../keysharp/bin/Release/net10.0/Keysharp.app" \
        "$HOME/Applications/Keysharp.app" \
        /Applications/Keysharp.app; do
        if [[ -x "$altrun_candidate/Contents/MacOS/Keysharp" ]]; then
            altrun_host="$altrun_candidate"
            break
        fi
    done
    if [[ -z "$altrun_host" ]]; then
        altrun_host="$(command -v keysharp || true)"
    fi
fi
if [[ -d "$altrun_host" ]]; then
    altrun_host="$altrun_host/Contents/MacOS/Keysharp"
fi
if [[ -z "$altrun_host" || ! -x "$altrun_host" ]]; then
    echo 'Keysharp was not found. Build ../Keysharp or set KEYSHARP_BIN to the Keysharp executable or .app bundle.' >&2
    exit 1
fi

cd -- "$altrun_root"
exec "$altrun_host" "$altrun_root/ALTRun.ahk" "$@"

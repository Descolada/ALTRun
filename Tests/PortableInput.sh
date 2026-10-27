#!/usr/bin/env bash
# Isolated native Linux input regression; requires Xvfb, xdotool and Metacity.
# Usage: Tests/PortableInput.sh [/path/to/Keysharp]
set -euo pipefail

fixture_dir="$(cd "$(dirname "$0")" && pwd)"
fixture_host="${1:-keysharp}"
for fixture_dependency in xvfb-run xdotool metacity; do
    command -v "$fixture_dependency" >/dev/null || { echo "Missing dependency: $fixture_dependency" >&2; exit 1; }
done

exec xvfb-run -a -s '-screen 0 1280x900x24' env -u WAYLAND_DISPLAY -u DEBUG \
    XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 ALTRUN_INPUT_TEST=isolated-xvfb \
    bash -c '
        metacity --sm-disable > /dev/null 2>&1 &
        fixture_wm=$!
        trap '\''kill "$fixture_wm" 2>/dev/null || true'\'' EXIT
        sleep 0.5
        timeout 60s "$1" --errorstdout "$2/PortableInput.ahk"
    ' bash "$fixture_host" "$fixture_dir"

#!/usr/bin/env bash
# Isolated native Wayland regression; requires Cinnamon, Xvfb, D-Bus and xdotool.
# No desktop/input authority is available inside this test.
set -euo pipefail

fixture_tests="$(cd "$(dirname "$0")" && pwd)"
fixture_host="${1:-keysharp}"
for fixture_dependency in xvfb-run dbus-run-session cinnamon xdotool xwininfo rg; do
    command -v "$fixture_dependency" >/dev/null || { echo "Missing dependency: $fixture_dependency" >&2; exit 1; }
done
fixture_host="$(command -v "$fixture_host")"
fixture_dir="$(mktemp -d /tmp/altrun-wayland-input.XXXXXX)"
fixture_cleanup() {
    fixture_result=$?
    if [[ $fixture_result != 0 || ${ALTRUN_KEEP_WAYLAND_TEST:-0} == 1 ]]; then
        if [[ $fixture_result != 0 && -f "$fixture_dir/session.log" ]]; then
            tail -40 "$fixture_dir/session.log" >&2
        fi
        echo "Wayland test evidence: $fixture_dir"
    else
        rm -rf "$fixture_dir"
    fi
}
trap fixture_cleanup EXIT
mkdir -p "$fixture_dir/runtime" "$fixture_dir/config" "$fixture_dir/data" "$fixture_dir/cache"
chmod 700 "$fixture_dir/runtime"

xvfb-run -a -s '-screen 0 1280x900x24 -nolisten tcp' \
    env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u GNOME_SETUP_DISPLAY \
    -u SESSION_MANAGER -u DESKTOP_AUTOSTART_ID -u DEBUG \
    XDG_RUNTIME_DIR="$fixture_dir/runtime" XDG_CONFIG_HOME="$fixture_dir/config" \
    XDG_DATA_HOME="$fixture_dir/data" XDG_CACHE_HOME="$fixture_dir/cache" \
    GSETTINGS_BACKEND=memory XDG_SESSION_TYPE=wayland CLUTTER_BACKEND=x11 \
    LIBGL_ALWAYS_SOFTWARE=1 KEYSHARP_DAEMON=0 \
    KEYSHARP_DESKTOP_SOCKET="$fixture_dir/runtime/no-desktop.sock" \
    KEYSHARP_INPUT_SOCKET="$fixture_dir/runtime/no-input.sock" \
    ALTRUN_WAYLAND_TEST=nested-cinnamon ALTRUN_WAYLAND_TEST_DIR="$fixture_dir" \
    dbus-run-session -- bash -s -- "$fixture_host" "$fixture_tests" "$fixture_dir" 2> "$fixture_dir/session.log" <<'SESSION'
set -euo pipefail
fixture_host=$1 fixture_tests=$2 fixture_dir=$3
cinnamon --nested --wayland --no-x11 --sm-disable > "$fixture_dir/cinnamon.log" 2>&1 &
fixture_compositor=$!
trap 'kill "$fixture_compositor" 2>/dev/null || true; wait "$fixture_compositor" 2>/dev/null || true' EXIT
for ((attempt = 0; attempt < 150; attempt++)); do
    kill -0 "$fixture_compositor" || { cat "$fixture_dir/cinnamon.log"; exit 1; }
    if [[ -S "$fixture_dir/runtime/wayland-0" ]] && rg -q 'Cinnamon took' "$fixture_dir/cinnamon.log"; then
        break
    fi
    sleep 0.1
done
[[ -S "$fixture_dir/runtime/wayland-0" ]] || { cat "$fixture_dir/cinnamon.log"; exit 1; }
printf '%s\n' "$DISPLAY" > "$fixture_dir/display"
printf '%s\n' "$XAUTHORITY" > "$fixture_dir/xauthority"
fixture_outer="$(xwininfo -root -tree | sed -n 's/^[[:space:]]*\(0x[[:xdigit:]]*\) "cinnamon".*/\1/p')"
[[ $fixture_outer =~ ^0x[[:xdigit:]]+$ ]] || { echo 'Nested Cinnamon render window was not found.'; exit 1; }
fixture_status=0
env WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland ALTRUN_WAYLAND_OUTER="$fixture_outer" \
    timeout 80s "$fixture_host" --errorstdout "$fixture_tests/PortableWaylandInput.ahk" \
    > "$fixture_dir/input.log" 2>&1 || fixture_status=$?
if [[ $fixture_status != 0 ]]; then
    tail -100 "$fixture_dir/input.log"
    exit "$fixture_status"
fi
rg '^PASS PORTABLE_WAYLAND_INPUT' "$fixture_dir/input.log"
if rg 'FAIL PORTABLE_WAYLAND_INPUT|Gdk-CRITICAL|temporary window without parent' "$fixture_dir/input.log"; then
    exit 1
fi
kill -0 "$fixture_compositor"
SESSION

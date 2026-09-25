#!/bin/bash
# One A/B leg: start a headless mutter on a private D-Bus session, drive N
# short-lived GTK clients that each set a texture cursor, and report how many
# MetaWaylandCursorSurface / MetaCursorWayland objects are still alive.
#
#   dbus-run-session -- ./run.sh <label> <nclients> [libmutter-root]
#
# libmutter-root: a dir holding an extracted libmutter-18-0 .deb (see setup.sh);
# omit it to use the system libmutter. Nothing is shown on the real desktop.
set -u
T=$(cd "$(dirname "$0")" && pwd); L=$1; N=$2; LIB=${3:-}
BIN=$T/work/mutter-bin
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET
mkdir -p "$T/work/logs"; OUT=$T/work/logs
export LP_COUNT_FILE=$OUT/count-$L.txt; rm -f "$LP_COUNT_FILE"
env ${LIB:+LD_LIBRARY_PATH=$LIB/usr/lib/x86_64-linux-gnu:$LIB/usr/lib/x86_64-linux-gnu/mutter-18} \
    LD_PRELOAD="$T/work/count.so" \
    "$BIN/usr/bin/mutter" --headless --wayland --no-x11 --virtual-monitor 1280x720 \
    --mutter-plugin="$BIN/usr/lib/x86_64-linux-gnu/mutter-18/plugins/libdefault.so" \
    --wayland-display "cursor-leak-$L" > "$OUT/mutter-$L.log" 2>&1 &
MP=$!
unset LP_COUNT_FILE
for _ in $(seq 50); do
  [ -S "$XDG_RUNTIME_DIR/cursor-leak-$L" ] &&
    gdbus introspect --session --dest org.gnome.Mutter.RemoteDesktop \
      --object-path /org/gnome/Mutter/RemoteDesktop >/dev/null 2>&1 && break
  sleep 0.2
done
echo "[$L] libmutter in use: $(grep -o '/[^ ]*libmutter-18.so.0[^ ]*' /proc/$MP/maps | sort -u)"
python3 "$T/pointer.py" > "$OUT/pointer-$L.log" 2>&1 &
PP=$!
sleep 1; echo "[$L] start: $(cat "$OUT/count-$L.txt")"
for i in $(seq "$N"); do
  env WAYLAND_DISPLAY="cursor-leak-$L" GDK_BACKEND=wayland GTK_A11Y=none NO_AT_BRIDGE=1 \
      GDK_DEBUG=no-portals timeout 10 python3 "$T/client.py" 2>>"$OUT/client-$L.log"
  [ $((i % 10)) -eq 0 ] && echo "[$L] after $i clients: $(cat "$OUT/count-$L.txt")"
done
sleep 2; echo "[$L] final, all clients gone: $(cat "$OUT/count-$L.txt")"
kill $PP $MP 2>/dev/null; wait $MP 2>/dev/null

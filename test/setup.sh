#!/bin/bash
# Fetch what the A/B test needs into test/work/:
#   mutter-bin/  the stock Ubuntu `mutter` binary + default plugin (not installed by GNOME Shell)
#   old/         the stock libmutter-18-0 50.1-0ubuntu2.2 (leaks)
#   count.so     the LD_PRELOAD object counter
# To test a patched build without installing it, extract its libmutter-18-0 .deb
# with `dpkg-deb -x <deb> work/patched` and pass work/patched to run.sh.
set -euo pipefail
T=$(cd "$(dirname "$0")" && pwd); W=$T/work; mkdir -p "$W"; cd "$W"
LP=https://launchpad.net/ubuntu/+archive/primary/+files
curl -fsSLO "$LP/mutter_50.1-0ubuntu2.4_amd64.deb"
curl -fsSLO "$LP/libmutter-18-0_50.1-0ubuntu2.2_amd64.deb"
dpkg-deb -x mutter_50.1-0ubuntu2.4_amd64.deb mutter-bin
dpkg-deb -x libmutter-18-0_50.1-0ubuntu2.2_amd64.deb old
gcc -shared -fPIC -O2 -o count.so "$T/count.c" -lpthread
echo "ready: dbus-run-session -- $T/run.sh old 30 $W/old"

#!/bin/bash
# Produce the SRU debdiff for Launchpad: the newest mutter source published for
# resolute (any pocket, including -proposed) + the fix, as the next ubuntu revision.
#   docker run --rm -v "$PWD":/work ubuntu:26.04 /work/build/debdiff.sh
# Env: BASE (e.g. 50.1-0ubuntu2.6), NEW (e.g. 50.1-0ubuntu2.7), DEBFULLNAME, DEBEMAIL
# Output: out/mutter_<NEW>.debdiff
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
P=0001-cursor-wayland-dont-hold-a-ref-on-the-surface.patch
apt-get update -q
apt-get install -yq --no-install-recommends devscripts quilt dpkg-dev ca-certificates curl python3 xz-utils
BASE=${BASE:?set BASE, e.g. 50.1-0ubuntu2.6}
NEW=${NEW:?set NEW, e.g. 50.1-0ubuntu2.7}
mkdir -p /build && cd /build
dget -u -d "https://launchpad.net/ubuntu/+archive/primary/+files/mutter_$BASE.dsc"
dpkg-source -x "mutter_$BASE.dsc" src
cd src
cp "/work/patch/$P" debian/patches/
echo "$P" >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a && QUILT_PATCHES=debian/patches quilt pop -a
rm -rf .pc
DEBFULLNAME="${DEBFULLNAME:-mutter-cursor-leak-fix}" DEBEMAIL="${DEBEMAIL:-noreply@example.invalid}" \
  dch -v "$NEW" -D resolute \
  "d/p/$P: Backport upstream 918da17b (gnome-50, MR !5097). Fixes a reference cycle that leaked every Wayland cursor surface and made the shell progressively slower over uptime (LP: #2171024)"
dpkg-buildpackage -S -d -nc -us -uc
cd ..
debdiff "mutter_$BASE.dsc" "mutter_$NEW.dsc" > "/work/out/mutter_$NEW.debdiff" || [ $? -eq 1 ]
chown -R "$(stat -c %u:%g /work)" /work/out

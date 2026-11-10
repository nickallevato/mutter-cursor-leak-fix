#!/bin/bash
# Rebuild Ubuntu 26.04's mutter with the upstream fix, inside a throwaway container.
#   docker run --rm -v "$PWD":/work ubuntu:26.04 /work/build/build.sh
# Env:
#   BASE    Ubuntu version to patch (default: the candidate in resolute-updates)
#   SUFFIX  local version suffix (default +cursorfix1). BASE+SUFFIX sorts below
#           Ubuntu's next real mutter update, so that update supersedes it --
#           and brings the leak back unless it carries the fix. Rebuild then.
# Output: out/*.deb
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
P=0001-cursor-wayland-dont-hold-a-ref-on-the-surface.patch
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update -q
apt-get install -yq --no-install-recommends devscripts equivs quilt build-essential ca-certificates dpkg-dev fakeroot
BASE=${BASE:-$(apt-cache showsrc mutter | awk '/^Version:/{print $2}' | sort -V | tail -1)}
SUFFIX=${SUFFIX:-+cursorfix1}
mkdir -p /build && cd /build
apt-get source -q "mutter=$BASE"
cd mutter-50.1
cp "/work/patch/$P" debian/patches/
echo "$P" >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a && QUILT_PATCHES=debian/patches quilt pop -a
DEBFULLNAME="${DEBFULLNAME:-mutter-cursor-leak-fix}" DEBEMAIL="${DEBEMAIL:-noreply@example.invalid}" \
  dch -v "$BASE$SUFFIX" -D resolute \
  "Backport upstream 918da17b (gnome-50, MR !5097): cursor/wayland: don't hold a ref on the surface (LP: #2171024)."
mk-build-deps -i -r -t 'apt-get -yq --no-install-recommends' debian/control
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -us -uc
mkdir -p /work/out && cp ../*.deb /work/out/
chown -R "$(stat -c %u:%g /work)" /work/out

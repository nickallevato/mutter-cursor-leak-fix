#!/bin/bash
# Rebuild Ubuntu 26.04's mutter with the upstream fix, inside a throwaway container.
#   docker run --rm -v "$PWD":/work ubuntu:26.04 /work/build/build.sh
# Output: out/*.deb, versioned 50.1-0ubuntu2.4+cursorfix1 so that Ubuntu's
# next real mutter update supersedes it automatically.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update -q
apt-get install -yq --no-install-recommends devscripts equivs quilt build-essential ca-certificates dpkg-dev fakeroot
mkdir -p /build && cd /build
apt-get source -q mutter=50.1-0ubuntu2.4
cd mutter-50.1
cp /work/patch/0001-cursor-wayland-dont-hold-a-ref-on-the-surface.patch debian/patches/
echo 0001-cursor-wayland-dont-hold-a-ref-on-the-surface.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a && QUILT_PATCHES=debian/patches quilt pop -a
DEBFULLNAME="${DEBFULLNAME:-mutter-cursor-leak-fix}" DEBEMAIL="${DEBEMAIL:-noreply@example.invalid}" \
  dch -v 50.1-0ubuntu2.4+cursorfix1 -D resolute \
  "Backport upstream 918da17b (gnome-50, MR !5097): cursor/wayland: don't hold a ref on the surface."
mk-build-deps -i -r -t 'apt-get -yq --no-install-recommends' debian/control
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -us -uc
mkdir -p /work/out && cp ../*.deb /work/out/

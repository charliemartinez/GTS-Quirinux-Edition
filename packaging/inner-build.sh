#!/bin/sh
# Runs INSIDE a clean Debian environment (container or chroot), as root.
# Usage: inner-build.sh <codename> <quirinux-suffix>   e.g. daedalus q2
# Env:   SRC (source tree, read-only), OUT (where the .deb is copied),
#        REV (upstream+rev, default 2.5.1.1), HOST_UID/HOST_GID (optional chown)
set -eu
CODENAME="$1"; QS="$2"
SRC="${SRC:-/src}"; OUT="${OUT:-/out}"; REV="${REV:-2.5.1.1}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends build-essential devscripts equivs fakeroot ca-certificates

rm -rf /tmp/gts-build && mkdir -p /tmp/gts-build
cp -a "$SRC"/. /tmp/gts-build/
cd /tmp/gts-build

# Version: <upstream>.<rev>+<q2|q3>, as in the other Quirinux packages
sed -i "1s/.*/gts-quirinux (${REV}+${QS}) ${CODENAME}; urgency=medium/" debian/changelog

mk-build-deps -ir -t "apt-get -y --no-install-recommends" debian/control
dpkg-buildpackage -us -uc -b

mkdir -p "$OUT"
cp ../gts-quirinux_*.deb "$OUT"/
[ -n "${HOST_UID:-}" ] && chown "$HOST_UID:${HOST_GID:-$HOST_UID}" "$OUT"/gts-quirinux_*.deb || true
echo "OK: $(ls "$OUT"/gts-quirinux_*+"${QS}"_*.deb)"

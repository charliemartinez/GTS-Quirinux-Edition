#!/bin/bash
# Build gts-quirinux .deb packages from the COMMITTED tree (git HEAD) inside
# clean Debian environments, so each one links against that release's libs.
#
#   ./packaging/build-debs.sh [daedalus|excalibur|all]
#
# daedalus  -> debian:bookworm  -> gts-quirinux_<ver>+q2_amd64.deb
# excalibur -> debian:trixie    -> gts-quirinux_<ver>+q3_amd64.deb
#
# ENGINE=docker (default) or ENGINE=chroot (needs root and debootstrap).
# Output goes to ./dist/
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-all}"
ENGINE="${ENGINE:-docker}"
declare -A SUITE=([daedalus]=bookworm [excalibur]=trixie)
declare -A QS=([daedalus]=q2 [excalibur]=q3)

case "$TARGET" in
  all) TARGETS=(daedalus excalibur) ;;
  daedalus|excalibur) TARGETS=("$TARGET") ;;
  *) echo "Usage: $0 [daedalus|excalibur|all]"; exit 1 ;;
esac

git diff --quiet && git diff --cached --quiet || \
  echo "WARNING: uncommitted changes are NOT included (building git HEAD)."

SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
git archive HEAD | tar -x -C "$SRC"
mkdir -p dist
OUT="$PWD/dist"

for t in "${TARGETS[@]}"; do
  suite="${SUITE[$t]}"; q="${QS[$t]}"
  echo "=== $t ($suite, +$q) via $ENGINE ==="
  if [ "$ENGINE" = docker ]; then
    docker run --rm \
      -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
      -v "$SRC":/src:ro -v "$OUT":/out \
      -v "$PWD/packaging/inner-build.sh":/inner-build.sh:ro \
      "debian:$suite" sh /inner-build.sh "$t" "$q"
  else
    root="/var/tmp/gts-chroot-$suite"
    [ -d "$root/usr" ] || debootstrap --variant=minbase "$suite" "$root" http://deb.debian.org/debian
    mkdir -p "$root/src" "$root/out"
    mount --bind "$SRC" "$root/src"; mount --bind "$OUT" "$root/out"; mount -t proc proc "$root/proc"
    cp packaging/inner-build.sh "$root/inner-build.sh"
    chroot "$root" env HOST_UID="${SUDO_UID:-0}" HOST_GID="${SUDO_GID:-0}" \
      sh /inner-build.sh "$t" "$q" || { umount "$root/proc" "$root/out" "$root/src"; exit 1; }
    umount "$root/proc" "$root/out" "$root/src"
  fi
done
ls -l dist/

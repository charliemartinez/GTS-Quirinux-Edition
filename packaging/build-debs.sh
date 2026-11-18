#!/bin/bash
# Build gts .deb packages from the COMMITTED tree (git HEAD) inside
# clean Debian environments, so each one links against that release's libs.
#
#   ./packaging/build-debs.sh [daedalus|excalibur|all]
#
# daedalus  -> debian:bookworm  -> gts_<ver>+q2_amd64.deb
# excalibur -> debian:trixie    -> gts_<ver>+q3_amd64.deb
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

SRC="$(mktemp -d)"
ROOT_CUR=""
unmount_chroot() {   # never leave bind mounts behind (they point at dist/!)
  local root="$1" m
  [ -n "$root" ] || return 0
  for m in proc out src; do
    mountpoint -q "$root/$m" 2>/dev/null && { umount "$root/$m" 2>/dev/null || umount -l "$root/$m" 2>/dev/null || true; }
  done
}
cleanup() { unmount_chroot "$ROOT_CUR"; rm -rf "$SRC"; }
trap cleanup EXIT
trap 'exit 130' INT TERM
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
    root="/var/tmp/gts-chroot-$suite"; ROOT_CUR="$root"
    unmount_chroot "$root"                 # clear stale mounts from an interrupted run
    [ -d "$root/usr" ] || debootstrap --variant=minbase "$suite" "$root" http://deb.debian.org/debian
    mkdir -p "$root/src" "$root/out" "$root/proc"
    mount --bind "$SRC" "$root/src"; mount --bind "$OUT" "$root/out"; mount -t proc proc "$root/proc"
    cp packaging/inner-build.sh "$root/inner-build.sh"
    chroot "$root" env HOST_UID="${SUDO_UID:-0}" HOST_GID="${SUDO_GID:-0}" \
      sh /inner-build.sh "$t" "$q"
    unmount_chroot "$root"; ROOT_CUR=""
  fi
done
ls -l dist/

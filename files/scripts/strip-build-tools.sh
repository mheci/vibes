#!/usr/bin/env bash
# Remove the build-time toolchains from the finished image.
#
# Every script module above this one builds software in-container: the
# CachyOS kernel devel tree plus the NVIDIA open module rebuild, the
# sched-ext schedulers (Rust), the custom mutter build (meson/ninja) and
# GNOME Boxes. None of that tooling is needed at runtime, so removing it
# here shrinks the image by several gigabytes without losing any feature.
#
# llvm-libs and clang-libs are deliberately kept: mesa and other runtime
# graphics components link against libLLVM. Only the compiler binaries are
# stripped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Stripping build-time toolchains from the image ==="

STRIP_PKGS=(
  gcc gcc-c++ g++ cpp
  clang clang-analyzer lld llvm
  cargo rust rust-std-static
  cmake ninja-build meson
  protobuf-compiler
  kernel-cachyos-devel kernel-cachyos-devel-matched kernel-devel-matched
  libbpf-devel libcap-devel libnl3-devel elfutils-libelf-devel zlib-devel
  libseccomp-devel jq-devel openssl-devel pkgconf-pkg-config
  glycin-devel graphene-devel libdisplay-info-devel libei-devel
  sysprof-capture-devel gnome-desktop4-devel colord-devel lcms2-devel
  libcanberra-devel libgudev-devel libpipewire-0.3-devel
  libvirt-devel libvirt-glib-devel libosinfo-devel spice-gtk3-devel
  gtk4-devel libadwaita-devel libxml2-devel json-glib-devel
)
for pkg in "${STRIP_PKGS[@]}"; do
  if rpm -q "${pkg}" >/dev/null 2>&1; then
    "${DNF[@]}" remove --noautoremove "${pkg}" >/dev/null 2>&1 || true
  fi
done

# Remove the kernel source/headers tree left by the devel packages.
rm -rf /usr/src/kernels

# Drop build dependencies that are no longer required by anything.
"${DNF[@]}" autoremove --skip-unavailable >/dev/null 2>&1 || true

# Guard: the kernel itself must be untouched by the cleanup.
if ! rpm -q kernel-cachyos-core >/dev/null 2>&1; then
  echo "ERROR: kernel-cachyos-core was removed; refusing to continue" >&2
  exit 1
fi

# =============================================================================
# Cleanup
# =============================================================================
echo "--- Cleaning up ---"
clean_build_artifacts
rm -rf /root/.cargo /root/.rustup /root/.cache 2>/dev/null || true

echo "=== Build toolchains stripped successfully ==="

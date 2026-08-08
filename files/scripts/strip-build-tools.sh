#!/usr/bin/env bash
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

for pattern in 'qt5-*-devel' 'qt6-*-devel' 'kf5-*-devel' 'kf6-*-devel' \
    'kdecoration*-devel' 'kwin*-devel' 'polkit-qt6-*-devel' \
    'extra-cmake-modules' 'gettext'; do
  for pkg in $(rpm -qa "${pattern}" 2>/dev/null); do
    "${DNF[@]}" remove --noautoremove "${pkg}" >/dev/null 2>&1 || true
  done
done

rm -rf /usr/src/kernels

"${DNF[@]}" autoremove --skip-unavailable >/dev/null 2>&1 || true

if ! rpm -q kernel-cachyos-core >/dev/null 2>&1; then
  echo "ERROR: kernel-cachyos-core was removed; refusing to continue" >&2
  exit 1
fi

echo "--- Cleaning up ---"
clean_build_artifacts
rm -rf /root/.cargo /root/.rustup /root/.cache 2>/dev/null || true

# Final dnf state cleanup: this is the last module that touches package
# state, so repository metadata and transaction history can go now.
"${DNF[@]}" clean all >/dev/null 2>&1 || true
rm -rf /var/lib/dnf /var/cache/dnf /run/dnf || true

# The files module copies sudoers.d entries with the repo mode (0644);
# sudo requires a readable file, but 0440 is the canonical mode for
# rules files and matches what the setup script installs.
chmod 0440 /etc/sudoers.d/* 2>/dev/null || true

echo "=== Build toolchains stripped successfully ==="

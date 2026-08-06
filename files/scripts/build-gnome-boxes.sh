#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building GNOME Boxes from upstream trunk ==="

BUILD_DIR="/tmp/gnome-boxes"
BOXES_REPO="https://gitlab.gnome.org/GNOME/gnome-boxes.git"
BOXES_TAG="50.0"
BOXES_VERSION="${BOXES_TAG}"

build_boxes() {
  echo "--- Installing GNOME Boxes build dependencies ---"
  if [[ -f /usr/bin/dnf5 ]]; then
    retry /usr/bin/dnf5 builddep --skip-unavailable -y gnome-boxes
  else
    retry /usr/bin/dnf builddep --skip-unavailable -y gnome-boxes
  fi
  install_available meson libvirt-devel libvirt-glib-devel \
    libosinfo-devel spice-gtk3-devel gtk4-devel libadwaita-devel \
    libxml2-devel json-glib-devel libei-devel

  for pkg in meson libvirt-glib-devel libosinfo-devel spice-gtk3-devel \
      gtk4-devel libadwaita-devel; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
      echo "ERROR: required GNOME Boxes build dependency missing: ${pkg}" >&2
      return 1
    fi
  done

  echo "--- Cloning GNOME Boxes (${BOXES_TAG}) ---"
  rm -rf "${BUILD_DIR}"
  git init -q "${BUILD_DIR}"
  git -C "${BUILD_DIR}" remote add origin "${BOXES_REPO}"
  retry git -C "${BUILD_DIR}" fetch -q --depth 1 origin "refs/tags/${BOXES_TAG}"
  git -C "${BUILD_DIR}" checkout -q FETCH_HEAD
  echo "Building GNOME Boxes at tag ${BOXES_TAG}"

  echo "--- Configuring and building ---"
  meson setup "${BUILD_DIR}/build" "${BUILD_DIR}" \
    --prefix /usr --libdir lib64 --buildtype release -Dinstalled_tests=false
  ninja -C "${BUILD_DIR}/build" || ninja -C "${BUILD_DIR}/build" -j 1

  echo "--- Installing ---"
  DESTDIR="${BUILD_DIR}/stage" ninja -C "${BUILD_DIR}/build" install
  cp -ra "${BUILD_DIR}/stage/usr/lib64/." /usr/lib64/
  cp -ra "${BUILD_DIR}/stage/usr/lib/." /usr/lib/ 2>/dev/null || true
  cp -ra "${BUILD_DIR}/stage/usr/libexec/." /usr/libexec/ 2>/dev/null || true
  cp -ra "${BUILD_DIR}/stage/usr/bin/." /usr/bin/
  cp -ra "${BUILD_DIR}/stage/usr/share/." /usr/share/
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
  ldconfig || true

  if [[ ! -x /usr/bin/gnome-boxes ]]; then
    echo "ERROR: gnome-boxes binary missing after install" >&2
    return 1
  fi
  return 0
}

if build_boxes; then
  echo "GNOME Boxes built from trunk (${BOXES_VERSION})"
else
  echo "WARN: GNOME Boxes trunk build failed, falling back to the Fedora package" >&2
  install_available gnome-boxes
  BOXES_VERSION="fedora"
fi

echo "=== Running GNOME Boxes smoke checks ==="
errors=0

check_boxes() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "  OK: ${path}"
  else
    echo "  FAIL: ${path} not found" >&2
    errors=$((errors + 1))
  fi
}

check_command_boxes() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  OK: $cmd"
  else
    echo "  FAIL: $cmd not found" >&2
    errors=$((errors + 1))
  fi
}

check_command_boxes gnome-boxes
check_boxes /usr/share/applications/org.gnome.Boxes.desktop

if [[ $errors -gt 0 ]]; then
  echo "ERROR: ${errors} GNOME Boxes smoke check(s) failed" >&2
  exit 1
fi

echo "--- Cleaning up ---"
rm -rf "${BUILD_DIR}"
clean_build_artifacts

echo "=== GNOME Boxes (${BOXES_VERSION}) installed successfully ==="

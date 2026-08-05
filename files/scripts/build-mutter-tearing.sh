#!/usr/bin/env bash
# Build and install mutter with GNOME MR !3797 (async page flip / tearing).
# MR: https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/3797
# Ref:  refs/merge-requests/3797/head (commit a8d56d423edde9e6d76f6b9cab663d82c65cf1a2)
# The branch is based on mutter 50.1 / libmutter_api_version 51, which matches
# the Fedora 44 (GNOME 50) base image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "=== Building mutter with MR !3797 (tearing support) ==="

MUTTER_REF="refs/merge-requests/3797/head"
BUILD_DIR="/tmp/vibes-mutter-mr3797"
PREFIX="/usr"

# Resolve the MR head commit. If the merge ref is unavailable (e.g. rewritten
# merge request), fall back to the author branch tip which shares the commit.
if git ls-remote --exit-code https://gitlab.gnome.org/GNOME/mutter.git \
    "${MUTTER_REF}" >/dev/null 2>&1; then
  MUTTER_URL="https://gitlab.gnome.org/GNOME/mutter.git"
  echo "Using merge ref ${MUTTER_REF} from ${MUTTER_URL}"
else
  echo "WARN: merge ref ${MUTTER_REF} not found, falling back to author branch" >&2
  MUTTER_URL="https://gitlab.gnome.org/naveenk2/mutter.git"
  MUTTER_REF="wip/add-tearing-support"
  echo "Using branch ${MUTTER_REF} from ${MUTTER_URL}"
fi

rm -rf "${BUILD_DIR}"
git init -q "${BUILD_DIR}/src"
git -C "${BUILD_DIR}/src" remote add origin "${MUTTER_URL}"
retry git -C "${BUILD_DIR}/src" fetch -q --depth 1 origin "${MUTTER_REF}"
git -C "${BUILD_DIR}/src" checkout -q FETCH_HEAD
echo "Building mutter at commit $(git -C "${BUILD_DIR}/src" rev-parse FETCH_HEAD)"

# Install the build dependencies for the distro-provided mutter. These match
# the same toolchain needed to build the MR branch (mutter 50.1).
if [[ -f /usr/bin/dnf5 ]]; then
  retry /usr/bin/dnf5 builddep --skip-unavailable -y mutter
else
  retry /usr/bin/dnf builddep --skip-unavailable -y mutter
fi

# Ensure the devel packages that the MR branch needs but that `dnf builddep
# mutter` may miss (e.g. glycin, a mutter 50 dependency) are present.
install_available \
  glycin-devel graphene-devel libdisplay-info-devel libei-devel \
  sysprof-capture-devel gnome-desktop4-devel colord-devel lcms2-devel \
  libcanberra-devel libgudev-devel libpipewire-0.3-devel

# Fail fast if the critical devel packages are missing: meson will otherwise
# fail much later with a less obvious error after a long build.
missing=""
for pkg in glycin-devel graphene-devel libdisplay-info-devel libei-devel; do
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    missing="${missing} ${pkg}"
  fi
done
if [[ -n "${missing}" ]]; then
  echo "ERROR: required mutter build dependencies are missing:${missing}" >&2
  echo "These are needed by mutter MR !3797 and must be resolvable from" >&2
  echo "the enabled Fedora repositories." >&2
  exit 1
fi

# Apply the same flags Fedora uses for mutter, disabling the test suites that
# are not run inside the container build anyway.
meson setup \
  --prefix "${PREFIX}" \
  --libdir lib64 \
  --buildtype release \
  -Db_ndebug=if-release \
  -Dxwayland=true \
  -Dxwayland_initfd=auto \
  -Dlibwacom=true \
  -Dremote_desktop=true \
  -Dintrospection=true \
  -Dtests=disabled \
  -Dinstalled_tests=false \
  -Ddocs=false \
  -Dmutter_tests=false \
  -Dcogl_tests=false \
  -Dclutter_tests=false \
  -Dkvm_tests=false \
  -Dtty_tests=false \
  -Dprofiler=true \
  "${BUILD_DIR}/build" \
  "${BUILD_DIR}/src"

ninja -C "${BUILD_DIR}/build" || ninja -C "${BUILD_DIR}/build" -j 1

# Replace the stock mutter with the MR build. Overwrite in place so RPM
# metadata stays consistent for future upgrades of the base image.
DESTDIR="${BUILD_DIR}/stage" ninja -C "${BUILD_DIR}/build" install
cp -ra "${BUILD_DIR}/stage/usr/lib64/." /usr/lib64/
cp -ra "${BUILD_DIR}/stage/usr/lib/." /usr/lib/ 2>/dev/null || true
cp -ra "${BUILD_DIR}/stage/usr/libexec/." /usr/libexec/ 2>/dev/null || true
cp -ra "${BUILD_DIR}/stage/usr/bin/." /usr/bin/
cp -ra "${BUILD_DIR}/stage/usr/share/." /usr/share/

# Refresh the GSettings schema database and dynamic linker cache so the new
# org.gnome.mutter schema and libmutter-51 are picked up immediately.
glib-compile-schemas /usr/share/glib-2.0/schemas || true
ldconfig || true

rm -rf "${BUILD_DIR}"

echo "=== mutter MR !3797 build complete ==="

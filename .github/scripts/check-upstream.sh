#!/usr/bin/env bash
set -euo pipefail

failures=0
warnings=0

check_url() {
  local url="$1"
  local code
  code="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 30 -I "$url")" || code="network"
  case "$code" in
    2[0-9][0-9] | 3[0-9][0-9])
      echo "  OK   (${code}): ${url}"
      ;;
    401 | 403 | 405 | 429)
      echo "  PASS (${code}, reachable): ${url}"
      warnings=$((warnings + 1))
      ;;
    *)
      echo "  FAIL (${code}): ${url}"
      failures=$((failures + 1))
      ;;
  esac
}

api_get() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" "$url"
  else
    curl -fsSL --max-time 30 -H "Accept: application/vnd.github+json" "$url"
  fi
}

github_tag_exists() {
  local repo="$1" tag="$2"
  if api_get "https://api.github.com/repos/${repo}/git/ref/tags/${tag}" >/dev/null 2>&1; then
    echo "  OK   (tag ${tag}): ${repo}"
  else
    echo "  FAIL (tag ${tag} missing): ${repo}"
    failures=$((failures + 1))
  fi
}

github_commit_exists() {
  local repo="$1" sha="$2"
  if api_get "https://api.github.com/repos/${repo}/commits/${sha}" >/dev/null 2>&1; then
    echo "  OK   (commit ${sha:0:12}): ${repo}"
  else
    echo "  FAIL (commit ${sha:0:12} missing): ${repo}"
    failures=$((failures + 1))
  fi
}

latest_asset_matches() {
  local repo="$1" pattern="$2" label="$3"
  local json name
  json="$(api_get "https://api.github.com/repos/${repo}/releases/latest")" || {
    echo "  FAIL (latest release unreachable): ${repo}"
    failures=$((failures + 1))
    return
  }
  name="$(echo "$json" | jq -r --arg p "$pattern" \
    '[(.assets // [])[].name | select(test($p))][0] // empty')"
  if [[ -n "$name" ]]; then
    echo "  OK   (asset '${name}'): ${label}"
  else
    echo "  FAIL (no asset matching ${pattern}): ${label}"
    failures=$((failures + 1))
  fi
}

gitlab_release_link() {
  local project="$1" pattern="$2" label="$3"
  local name
  name="$(curl -fsSL --max-time 30 \
    "https://gitlab.com/api/v4/projects/${project}/releases/permalink/latest" \
    | jq -r --arg p "$pattern" \
    '[(.assets.links // [])[].name | select(test($p))][0] // empty')" || {
    echo "  FAIL (gitlab latest release unreachable): ${label}"
    failures=$((failures + 1))
    return
  }
  if [[ -n "$name" ]]; then
    echo "  OK   (link '${name}'): ${label}"
  else
    echo "  FAIL (no link matching ${pattern}): ${label}"
    failures=$((failures + 1))
  fi
}

echo "== Download URLs referenced by build scripts =="
while IFS= read -r url; do
  [[ "$url" == *'$'* ]] && continue
  check_url "$url"
done < <(grep -rhoE "https://[^'\" )]+" files/scripts/*.sh | sort -u)

echo
echo "== Pinned GitHub tags =="
github_tag_exists "werman/noise-suppression-for-voice" "v1.10"
github_tag_exists "autobrr/qui" "v1.23.0"
github_tag_exists "ful1e5/apple_cursor" "v2.0.0"
github_tag_exists "CachyOS/ananicy-rules" "1.1.47"

echo
echo "== Pinned commits =="
github_commit_exists "oracle/bpftune" "4712347f2da0b7d4a5fbdb0d81d071c1704b3f20"
github_commit_exists "somepaulo/MoreWaita" "53bc2ba9c2cdc1f26ef822fcdd8a95e01cce5d58"
github_commit_exists "hakavlad/nohang" "5938a2e2249cb93ff21094dd548f770c47cc1860"
github_commit_exists "hakavlad/prelockd" "584f70ac05b403237a12193f1e70380b283d4083"

echo
echo "== Pinned GitLab tags =="
check_url "https://gitlab.gnome.org/GNOME/gnome-boxes/-/tags/50.0"

echo
echo "== Kernel and scheduler sources =="
check_url "https://download.copr.fedorainfracloud.org/results/bieszczaders/kernel-cachyos/fedora-44-x86_64/repodata/repomd.xml"
check_url "https://download.copr.fedorainfracloud.org/results/bieszczaders/kernel-cachyos/pubkey.gpg"
check_url "https://raw.githubusercontent.com/CachyOS/copr-linux-cachyos/master/sources/kernel-cachyos-bore/kernel-cachyos.spec"
copr_kernel_package() {
  if curl -fsSL --max-time 30 \
      "https://copr.fedorainfracloud.org/api_3/package/list?ownername=bieszczaders&projectname=kernel-cachyos" \
      | jq -e '.items[] | select(.name == "kernel-cachyos")' >/dev/null 2>&1; then
    echo "  OK   (COPR project publishes kernel-cachyos)"
  else
    echo "  FAIL (kernel-cachyos missing from bieszczaders/kernel-cachyos COPR)" >&2
    failures=$((failures + 1))
  fi
}
copr_kernel_package
check_url "https://github.com/NVIDIA/open-gpu-kernel-modules/releases/latest"
check_url "https://github.com/sched-ext/scx/tags.atom"

echo
echo "== Element Desktop download channel =="
latest_asset_matches "commetchat/commet" "commet-linux-portable-x64\\.tar\\.gz$" "commet"
check_url "https://gitlab.gnome.org/GNOME/gnome-boxes/-/raw/main/meson.build"

echo
echo "== Latest-release asset patterns used by scripts =="
latest_asset_matches "anomalyco/opencode" "opencode-desktop-linux-x86_64\\.rpm$" "opencode desktop RPM"
latest_asset_matches "Foundry376/Mailspring" "mailspring-.*\\.x86_64\\.rpm$" "mailspring"
latest_asset_matches "ferdium/ferdium-app" "Ferdium-linux-.*-x86_64\\.rpm$" "ferdium"
latest_asset_matches "vicinaehq/vicinae" "Vicinae-x86_64\\.AppImage$" "vicinae launcher"
latest_asset_matches "zellij-org/zellij" "zellij-x86_64-unknown-linux-musl\\.tar\\.gz$" "zellij"
latest_asset_matches "glanceapp/glance" "glance-linux-amd64\\.tar\\.gz$" "glance"
latest_asset_matches "autobrr/qui" "linux_x86_64\\.tar\\.gz$" "qui"
latest_asset_matches "pingdotgg/t3code" "T3-Code-[0-9.]+-x86_64\\.AppImage$" "t3code editor"
latest_asset_matches "oven-sh/bun" "bun-linux-x64\\.zip$" "bun runtime"
latest_asset_matches "denoland/deno" "deno-x86_64-unknown-linux-gnu\\.zip$" "deno runtime"
latest_asset_matches "githubnext/monaspace" "monaspace-static-v[0-9.]+\\.zip$" "monaspace fonts"
latest_asset_matches "rsms/inter" "Inter-[0-9.]+\\.zip$" "inter fonts"
latest_asset_matches "mishamyrt/Lilex" "Lilex\\.zip$" "lilex fonts"
latest_asset_matches "SpaceTimee/Fusion-JetBrainsMapleMono" "JetBrainsMapleMono-XX-XX-XX-XX\\.zip$" "fusion jetbrains maple mono fonts"
latest_asset_matches "CachyOS/proton-cachyos" "proton-cachyos-.*-x86_64_v3\\.tar\\.xz$" "proton-cachyos"
latest_asset_matches "CachyOS/proton-cachyos" "proton-cachyos-.*-x86_64_v3\\.sha512sum$" "proton-cachyos checksum"

echo
echo "== Flatpak-to-native conversion sources =="
latest_asset_matches "radiolamp/mangojuice" "MangoJuice-AppImagename-x86_64\\.zip$" "mangojuice"
latest_asset_matches "pkgforge-dev/Gear-Lever-AppImage" "Gear_Lever-.*-anylinux-x86_64\\.AppImage$" "gear lever"
gitlab_release_link "mission-center-devs%2Fmission-center" "AppImage.*x86_64" "mission center"

echo
echo "Failures: ${failures}  Warnings: ${warnings}"
if (( failures > 0 )); then
  exit 1
fi

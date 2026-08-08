#!/usr/bin/env bash
# shellcheck disable=SC2034

set -euo pipefail

if command -v dnf5 >/dev/null 2>&1; then
  DNF=(dnf5 -y)
else
  DNF=(dnf -y)
fi
readonly -a DNF

retry() {
  local attempts=4 delay=10 n=1
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    attempts="$1"
    shift
  fi
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    delay="$1"
    shift
  fi
  until "$@"; do
    if (( n >= attempts )); then
      echo "ERROR: command failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    echo "WARN: command failed, retrying in ${delay}s: $*" >&2
    sleep "$delay"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

install_available() {
  local pkgs=("$@") available=() pkg
  for pkg in "${pkgs[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
      echo "INFO: package already installed, skipping: $pkg" >&2
      continue
    fi
    if "${DNF[@]}" repoquery --available "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      echo "WARN: package unavailable in enabled repos, skipping: $pkg" >&2
    fi
  done
  if (( ${#available[@]} == 0 )); then
    echo "INFO: no new packages to install in this group" >&2
    return 0
  fi
  echo "INFO: installing ${#available[@]} package(s): ${available[*]}" >&2
  if ! retry "${DNF[@]}" install --skip-unavailable --skip-broken "${available[@]}"; then
    echo "WARN: batch install failed; retrying packages one-by-one with skip flags" >&2
    for pkg in "${available[@]}"; do
      "${DNF[@]}" install --skip-unavailable --skip-broken "$pkg" || echo "WARN: failed to install optional package: $pkg" >&2
    done
  fi
}

gh_latest_asset_url() {
  local repo="$1" pattern="$2"
  local effective_url="" tag="" html="" url=""
  effective_url="$(retry curl -fsIL -o /dev/null -w '%{url_effective}' \
    -H "User-Agent: vibes-bluebuild" "https://github.com/${repo}/releases/latest")"
  tag="${effective_url##*/releases/tag/}"
  if [[ -n "$tag" && "$tag" != "$effective_url" ]]; then
    html="$(retry curl -fsL -H "User-Agent: vibes-bluebuild" "https://github.com/${repo}/releases/expanded_assets/${tag}")"
    url="$(echo "$html" | grep -oE 'href="/[^"]+"' | sed 's/^href="//; s/"$//' | grep -E "${pattern}" | head -n1)"
    if [[ -n "$url" ]]; then
      echo "https://github.com${url}"
      return 0
    fi
    echo "WARN: no asset matching '${pattern}' in ${repo} release ${tag} via expanded_assets, falling back to API" >&2
  else
    echo "WARN: could not resolve latest tag for ${repo} via redirect, falling back to API" >&2
  fi
  gh_asset_url "$repo" "$pattern"
}

gh_asset_url() {
  local repo="$1" pattern="$2" tag="${3:-}"
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for gh_asset_url but not installed (repo=${repo})" >&2
    return 1
  fi
  local endpoint="releases/latest"
  if [[ -n "$tag" ]]; then
    endpoint="releases/tags/${tag}"
  fi
  local api_url="https://api.github.com/repos/${repo}/${endpoint}"
  local headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: vibes-bluebuild")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
  local response="" http_code="" attempt=1 max_attempts=3 delay=5
  while (( attempt <= max_attempts )); do
    response="$(curl -sSL -w "\n%{http_code}" "${headers[@]}" "$api_url" 2>&1)" || response=""
    if [[ -n "$response" ]]; then
      http_code="$(echo "$response" | tail -n1)"
      if [[ "$http_code" == "429" || "$http_code" =~ ^5[0-9][0-9]$ ]]; then
        echo "WARN: GitHub API returned HTTP ${http_code} for ${repo}, retrying in ${delay}s (attempt ${attempt}/${max_attempts})" >&2
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
        continue
      fi
      break
    fi
    echo "WARN: curl failed for ${api_url}, retrying in ${delay}s (attempt ${attempt}/${max_attempts})" >&2
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
  if [[ -z "$response" ]]; then
    echo "ERROR: curl failed for ${api_url} after ${max_attempts} attempts" >&2
    return 1
  fi
  http_code="$(echo "$response" | tail -n1)"
  if [[ "$http_code" == "403" ]]; then
    echo "WARN: GitHub API rate limited (HTTP 403) for ${repo}; token may be missing or exhausted" >&2
  fi
  if [[ "$http_code" -ge 400 ]]; then
    local body
    body="$(echo "$response" | sed '$d')"
    echo "ERROR: GitHub API ${api_url} returned HTTP ${http_code}: ${body:0:500}" >&2
    return 1
  fi
  local assets_json url
  assets_json="$(echo "$response" | sed '$d' | jq -c '.assets // []')"
  if [[ -z "$assets_json" || "$assets_json" == "null" ]]; then
    echo "ERROR: failed to fetch release assets for ${repo} (empty assets)" >&2
    return 1
  fi
  # shellcheck disable=SC2016
  url="$(echo "$assets_json" | jq -r --arg pattern "(?i)${pattern}" '[.[] | select(.name | test($pattern))] | first | .browser_download_url // empty')"
  if [[ -z "$url" ]]; then
    echo "ERROR: no asset matching pattern '${pattern}' in ${repo} latest release" >&2
    echo "Available assets were:" >&2
    echo "$assets_json" | jq -r '.[].name' >&2 | head -n 20
    return 1
  fi
  echo "$url"
}

clean_build_artifacts() {
  # dnf state is intentionally kept: clearing /var/lib/dnf and
  # /var/cache/dnf between every module forces later modules to re-sync
  # all repository metadata. strip-build-tools.sh performs the final
  # dnf cleanup before the image is sealed.
  rm -f /var/log/dnf5.log* /var/log/dnf.librepo.log* /var/log/hawkey.log* \
        /var/cache/ldconfig/aux-cache || true
  rm -rf /root/.cache/* /root/.npm/* /root/.cargo/* 2>/dev/null || true
  rm -rf /tmp/vibes-* /tmp/bpftune /tmp/zed* /tmp/zen* /tmp/linux-rnnoise* /tmp/qui* /tmp/nohang /tmp/prelockd 2>/dev/null || true
  rm -f /tmp/*.tar.gz /tmp/*.tar.xz /tmp/*.zip /tmp/*.rpm /tmp/opencode-install.sh 2>/dev/null || true
  find /usr -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
  pip cache purge 2>/dev/null || true
  npm cache clean --force 2>/dev/null || true
}

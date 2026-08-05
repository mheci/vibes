# Changelog

All notable changes to the Vibes OCI image are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses the `latest` image tag for distribution. Tagged releases
correspond to significant milestones.

## [Unreleased]

### Added

- Hermes Agent (Nous Research) installed system-wide: official `install.sh`
  run with a pinned upstream commit (`--commit`, recorded in
  `.hermes-bootstrap-complete`) producing the FHS layout (code in
  `/usr/local/lib/hermes-agent`, `hermes`/`hermes-agent`/`hermes-acp` shims in
  `/usr/local/bin`); Python 3.11 venv + `uv sync --extra all --locked`,
  node deps and Playwright Chromium redirected to a shared read-only
  `/usr/share/hermes/ms-playwright`; defaults seeded into `/etc/skel/.hermes`
  (config, SOUL, skills, `PLAYWRIGHT_BROWSERS_PATH`) so every new user gets a
  working agent on first login
- Initramfs for the CachyOS kernel: `setup-cachyos-kernel.sh` now generates
  `/usr/lib/modules/<kver>/initramfs.img` with `dracut --no-hostonly` (bootc
  images ship the initrd inside the container; the swap removed the stock
  kernel's initrd, so the installed system panicked with "VFS: Unable to
  mount root fs" — this fixes the nightly QEMU boot test)
- proton-cachyos (x86_64_v3 build, sha512-verified) installed system-wide in
  `/usr/share/steam/compatibilitytools.d` so Steam offers it for every game;
  direct-run instructions documented in the README
- Memory management stack: `uresourced` (active-user CPU/IO priority classes),
  `low-memory-monitor` (early D-Bus pressure warnings, configured warn-only so
  it never triggers the kernel OOM killer), **nohang** (PSI-based low-memory
  handler built from upstream - the Fedora package is orphaned/EPEL8-only -
  replacing `systemd-oomd`, which is masked via a `/dev/null` unit symlink)
  and **prelockd** (executables and shared libraries pinned in RAM, installed
  from the upstream prebuilt release because the Fedora package is
  EPEL8-only)
- NVIDIA shader disk cache raised to 1 GiB with cleanup skipped
  (`__GL_SHADER_DISK_CACHE_SIZE=1073741824`,
  `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1`) to prevent shader recompilation
  stutter in large titles
- `VKD3D_CONFIG=descriptor_heap` set globally (vkd3d-proton descriptor-heap
  allocation mode for Direct3D 12 titles under proton-cachyos)
- Persistent shader caches: NVIDIA (`__GL_SHADER_DISK_CACHE_PATH`), Mesa
  (`MESA_SHADER_CACHE_DIR`), DXVK (`DXVK_STATE_CACHE_PATH`) and Qt scene
  graph are all pinned to `$XDG_CACHE_HOME` (default `~/.cache`) so no
  toolkit cache lands in volatile locations
- Qt log silencing: `QT_LOGGING_RULES=*.debug=false;*.info=false` globally,
  so only warnings/errors/criticals from Qt apps reach the journal and
  console
- Power management: `tuned` + `tuned-ppd` enabled with the PPD
  `performance` profile remapped to tuned `latency-performance` and set as
  the default; GNOME Power Mode default is `performance` (dconf local
  default, not locked); `power-status` just recipe added
- Hardware acceleration configuration for all browsers and media players:
  managed policies + flags files for the Chromium family (VA-API with
  `VaapiOnNvidiaGPUs`/`VaapiIgnoreDriverChecks` per the CachyOS guide,
  required since Chromium blocks VA-API on NVIDIA by default), Zen Browser
  distribution policy mirroring Firefox's VA-API/WebRender policy, and mpv
  `hwdec=auto-safe`
- SELinux desktop/gaming optimization: `selinuxuser_execmod` applied at
  first boot via a one-shot `vibes-selinux.service` (setsebool cannot run
  in the build container)
- Firewall verification: the FedoraWorkstation zone (opens 1025-65535
  tcp+udp) is confirmed so Steam, GSConnect/KDE Connect (1714-1764),
  torrents and media servers are never blocked
- Package policy documented (Official Dev Repo > Git RPMs > AppImage >
  Flatpak)
- OpenQA boot test: daily headless isotovideo run (`openqa/` serial test
  distribution, `openqa.yml` workflow) asserting the image boots to a login
  prompt under QEMU TCG

### Changed

- GameMode removed from the gaming stack (buggy on this image; uresourced
  supersedes its CPU/IO priority handling); the `gamemode-status` just recipe
  was dropped

### Removed

- `CODE_OF_CONDUCT.md` (not applicable to this project)

- CachyOS BORE kernel (`kernel-cachyos`) installed from the official
  `bieszczaders/kernel-cachyos` Fedora COPR (BORE scheduler, Cachy Sauce,
  HZ=1000, x86_64-v3, PREEMPT_DYNAMIC, full tickless, sched_ext, ntsync,
  SELinux default LSM, zswap default-on) replacing the previous in-image
  source build (which took 1h+ on CI runners); the stock kernel packages are
  version-locked so updates cannot restore them; the vendored spec/config in
  `files/kernel/` were removed
- NVIDIA open kernel modules rebuilt in-container from the
  `open-gpu-kernel-modules` tag matching the base image's userspace driver
  (prebuilt ublue akmods removed); modules target the COPR kernel via
  `SYSSRC`/`SYSOUT`
- sched_ext schedulers built from the latest `sched-ext/scx` git HEAD with
  cargo (CachyOS-style workspace build), replacing the COPR `scx-scheds` /
  `scx-tools-git` packages; `scx_loader.service` unit and
  `/etc/scx_loader/config.toml` (default `scx_lavd` in Gaming mode) shipped
  and enabled
- Just command runner with a 40+ recipe collection
  (`/usr/share/vibes/justfile`, `vjust` wrapper, shell completions) grouped by
  topic: system, TPM (LUKS enrollment/PCRs), LUKS (header backup, keys),
  gaming (scheduler switching, Proton tools, NTSYNC), NVIDIA,
  Flatpak, Nix, audio and hardware
- System tuning drop-ins: systemd 20 s service timeouts (system + user),
  journal (2G / 256M caps) and coredump (journal storage) limits, sysctl
  tuning (swappiness 10, page-cluster 0, BBR3 + fq with `tcp_bbr3` autoload,
  `vm.max_map_count`, inotify limits), khugepaged defrag disabled at boot,
  HDA power-save, `uaccess` udev rules for game controllers, performance CPU
  governor udev rule, `ntsync` module autoload
- Kernel arguments `nvme_core.default_ps_max_latency_us=0`, `nowatchdog` and
  `split_lock_detect=off`/`split_lock_mitigate=off` via the bootc kargs
  module; `zram-generator-defaults` removed (the CachyOS kernel enables zswap
  with zstd by default)
- Flatpak-to-native conversions: Mission Center (GitLab AppImage release
  link), Gear Lever (pkgforge-dev AppImage) and MangoJuice (AppImage from
  upstream zip); the weekly upstream health check now also verifies the
  CachyOS kernel COPR (repo, key, spec, package listing), scx and the
  conversion sources
- Mutter build hardened: correct devel package `glycin-devel` (the Fedora
  package providing `glycin-2.pc`; `glycin-2-devel` does not exist in Fedora
  44) plus a fail-fast `rpm -q` check before meson setup so missing build
  dependencies abort the layer immediately with a clear message instead of
  failing later inside meson
- Brave Origin browser installed as a native RPM from the official Brave
  repository (`/etc/yum.repos.d/brave-browser.repo`)
- Gaming stack: Steam (`steam` + `steam-devices`), `mangohud`,
  `gamescope`, `faugus-launcher` (COPR `faugus/faugus-launcher`), and explicit
  Vulkan dependencies for NVIDIA (`vulkan-loader`,
  `vulkan-validation-layers`, `nvidia-settings`)
- Copyous clipboard history manager (GNOME extension #8834, pins/tags/SQLite
  persistence) with its RPM dependencies (`libgda`, `libgda-sqlite`, `gsound`)
- Mutter built with GNOME MR !3797 (async page flip / tearing support) via
  `build-mutter-tearing.sh`; `MUTTER_DEBUG_EXPERIMENTAL_FEATURES` set to
  `tearing,variable-refresh-rate` in `/etc/environment.d/90-vibes-desktop-env.conf`
- Native apps: Mailspring (latest GitHub release RPM), Whatsie (Qt6 source
  build; upstream-documented Fedora build), Nicotine+ (Fedora repo)
- Flatpaks: Tangram, Folio, karere, Varia, AdwSteamGtk, Pods
- GNOME-first image: default Flatpaks (Bazaar, FlameGet, Refine) installed
  with the default-flatpaks v2 module, and system-wide GNOME extensions
  (Just Perfection, Grand Theft Focus, AppIndicator and KStatusNotifierItem
  Support, ChromaLeon) via the gnome-extensions module
- Additional default Flatpaks: Mission Center (system/GPU monitoring),
  Warehouse (Flatpak manager), coppwr (PipeWire graph control),
  DistroShelf (Distrobox container manager), Lobjur (distro deployment)
- adw-gtk GTK3 theme installed as a system Flatpak (light, dark and black
  variants shipped in one package) and set as the default GTK theme via dconf
  defaults, so GTK3 apps match libadwaita
- MoreWaita icon theme (Adwaita companion with icons for third-party apps)
  installed system-wide from a pinned commit and set as the default icon
  theme; the weekly upstream health check now also verifies the pinned commit
- Full Yaru theme packs (GTK3/GTK4/shell themes plus icon & cursor theme)
  installed as native RPMs
- Fonts: Hack and Iosevka (monospace), IBM Plex Sans/Serif and Source Serif
  for display and document use, alongside the existing Nerd Fonts coverage
- Alphabetical App Grid GNOME extension added (system-wide)
- Qt applications now follow the GNOME theme:
  `QT_QPA_PLATFORMTHEME=gtk3` shipped via `/etc/environment.d/10-vibes-qt.conf`
- GSConnect installed from the system package (`gnome-shell-extension-gsconnect`
  and `nautilus-gsconnect`); the gnome-extensions module cannot install it
  because the extension is hard-coded to user/local gschema locations
- Native RPMs: mpv, GNOME Tweaks
- Daily QEMU boot test workflow: builds a disk image from the published image
  with `bootc install to-disk`, verifies the cosign signature against
  `cosign.pub` first, and boots it headlessly to the multi-user target (KVM
  when available, TCG fallback)
- Weekly reproducibility check: no-cache rebuild of the recipe to catch
  upstream breakage between daily builds, with the result reported in the job
  summary
- Weekly upstream health workflow: validates every external URL referenced by
  the build scripts, pinned GitHub tags (`v1.10`, `v1.23.0`, `v2.0.0`), the
  pinned `bpftune` commit, and the latest-release asset patterns used by
  `gh_asset_url` calls
- Release hardening: tagged releases now verify the image signature against
  `cosign.pub`, record the verified image digest in the release body, and
  attach an SPDX SBOM generated from the image
- Dependabot `pip` ecosystem tracking pinned CI dependencies via
  `.github/requirements-ci.txt` (yamllint 1.38.0, pyyaml 6.0.3), with grouped
  GitHub Actions and Python updates
- `gh_asset_url` retry loop with exponential backoff for transient GitHub API
  failures (429, 5xx, network errors) and `GH_TOKEN` fallback
- Explicit installation of `jq`, `unzip`, `rsync`, and other core utilities in
  the base package layer to guarantee `gh_asset_url` and theme installers work
  reliably regardless of base image contents
- Faugus Launcher RPM installed from its COPR (previously enabled but not
  installed) to match documented intent
- Additional WirePlumber match patterns for broader app coverage
  (vesktop, Element, lower-case variants)
- Consolidated documentation in README covering PipeWire/WirePlumber
  architecture, browser installation method, and shared shell library
- Debug listing of available GitHub release assets on gh_asset_url failure
  to aid CI diagnostics
- Nix (DeterminateSystems/nix-installer, multi-user/rootless): installed at
  build time with `--init none`, store relocated to `/var/nix` (persistent
  ostree state) with a `nix.mount` bind mount to `/nix`, systemd
  socket-activated `nix-daemon`, and a `vibes-nix-selinux.service` oneshot
  that installs the shipped `determinate-nix.pp` SELinux policy module and
  relabels `/nix` at first boot (bluefin is enforcing)
- RustConn (GTK4 SSH/RDP connection manager) installed as a Flatpak, matching
  the developer's recommended install method
- T3 Code (pingdotgg/t3code) installed from the official Linux AppImage
- Additional Flatpaks: Bottles, Flatseal, Extension Manager, Gear Lever,
  ProtonPlus, Foliate, MangoJuice, Equibop, Ente Auth, Ignition,
  LibreMenu Editor, Constrict
- Arc Menu GNOME extension added system-wide (with `gnome-menus` RPM
  dependency)
- Cloud-native/dev CLI tools: `uv` (replaces pipx for Python tooling), `helix`,
  `yt-dlp`, `gh`, `zoxide`, `bun`, `deno`
- `sudo-rs` (memory-safe sudo implementation) as the default sudo, with a
  wheel-group passwordless sudoers drop-in
  (`/etc/sudoers.d/99-vibes-wheel-nopasswd`)
- Font families: Monaspace, Inter, Lilex, Fusion JetBrainsMapleMono (GitHub
  releases), plus Adobe Source Code Pro/Sans and Liberation (Fedora RPMs)

### Changed

- **Base image**: `ghcr.io/ublue-os/bluefin-hwe-nvidia-open` ->
  `ghcr.io/ublue-os/bluefin-nvidia-open` (GNOME-first, NVIDIA open drivers,
  standard kernel); description and docs updated
- **Brave repository**: `skip_if_unavailable=True` added to
  `brave-browser.repo` so a transient S3 metadata fetch failure cannot
  silently drop packages from the build
- **README**: complete rewrite with corrected package descriptions and
  original branding for the Vibes image
- **Dependabot build failures (root cause)**: runs triggered by Dependabot or
  forks get a read-only token and no secrets, so `SIGNING_SECRET` was empty
  while `cosign.pub` was present, making blue-build fail on signing key
  lookup. The image build is now skipped whenever the signing secret is
  unavailable (PRs and pushes on Dependabot/fork branches); validation still
  runs in full. This unblocks automated action updates.
- **Validation workflow**: lint steps now fail the job on any violation
  (previously `|| true` masked yamllint and markdownlint errors); pip tools
  installed from pinned `requirements-ci.txt`; markdownlint pinned to 0.49.1;
  `.github/scripts/*.sh` included in shellcheck
- **Shell library**: `gh_asset_url` now retries transient API failures with
  backoff (was a single attempt) and falls back from `GITHUB_TOKEN` to
  `GH_TOKEN`
- **Documentation**: README badges and pipeline table updated for the new
  workflows and release process; CONTRIBUTING documents the full local
  validation suite and Dependabot/fork build behavior
- **PipeWire**: Merged RT module and RNNoise filter-chain into a single
  `20-vibes-audio-quality.conf` to avoid PipeWire conf.d override behavior
  where separate files defining `context.modules` would clobber each other.
  Removed obsolete `99-input-denoising.conf`.
- **WirePlumber**: Merged all `node.rules` definitions into a single
  `50-vibes-gaming.conf` to avoid in-file override where second definition
  overwrote the first. Removed `node.rules` from `20-vibes-policy.conf`,
  leaving only settings and monitor rules there.
- **Shell library (`lib.sh`)**:
  - Fixed critical build failure: `install_available` now skips already-installed
    packages to avoid dnf5 "already installed" transaction errors (hunspell, etc.)
  - Added `--skip-unavailable --skip-broken` to all dnf install invocations
  - Improved `gh_asset_url()`:
    - explicit `jq` availability check
    - HTTP status handling and rate-limit warnings
    - proper error extraction and token-aware headers
    - switched from `test($pattern; "i")` (jq 1.6+ required) to `(?i)` inline flag
      with `test($pattern)` for jq 1.5+ compatibility (fixes CI with older jq)
    - fixed regex double-escaping bug: patterns were `\\\\.rpm` (2 literal backslashes)
      instead of `\.rpm` (escaped dot), causing "no asset matching pattern" failures
  - Fixed critical build failure: `clean_build_artifacts()` previously did
    `rm -rf /tmp/*` which deleted BlueBuild internal `/tmp/scripts` and
    `/tmp/modules`, causing Nushell eval failure `Failed to run setup-repos-and-rpms.sh`.
    Now only cleans specific caches and preserves /tmp/scripts and /tmp/modules.
- **Workflows**: Pinned all GitHub Actions to exact patch versions for
  reproducibility and supply-chain security:
  - `actions/checkout@v6` -> `@v6.1.0` (2026-07-20)
  - `github/codeql-action` `@v4` -> `@v4.37.3` (2026-07-22)
  - `actions/upload-artifact@v4` -> `@v4.6.2` (2025-03-19)
  - `softprops/action-gh-release@v2` -> `@v2.6.2` (2026-04-12)
  - `actions/stale@v10` -> `@v10.4.0` (2026-07-10)
  - `jlumbroso/free-disk-space@v1.3.1`, `jasonn3/build-container-installer@v1.5.0`,
    `blue-build/github-action@v1.12.0` already exact
  - lint tools: shellcheck `0.10.0` -> `0.11.0` (8c3be12b), actionlint `1.7.7` -> `1.7.12` (8aca8db9)
    with updated SHA256 verification
- **Dependabot**: Removed ineffective `docker` ecosystem (no Dockerfile in repo;
  Containerfile is generated by BlueBuild and gitignored). Now tracks only
  `github-actions` with conventional commit prefix.
- **README**: Full rewrite to accurately describe:
  - Firefox RPM, Helium RPM (COPR), Zen Browser tarball (not RPM)
  - PipeWire/WirePlumber config consolidation and bug fixes
  - Shared library helpers and build stages
  - Correct `cosign verify` command with `:latest` tag
  - Exact action pins and lint tool versions
- **Build tools**: Extended from minimal gcc/clang/llvm to include `jq`,
  `unzip`, `rsync`, `file`, `which`, `tar`, `gzip`, `xz` for robustness
- **RNNoise**: Updated tag `v1.2` (non-existent, 404) -> `v1.10` (latest stable
  2024-05-18) which has valid `linux-rnnoise.zip` asset. Previous `v1.2` caused
  curl 404 and build failure at RNNoise stage.
- **qui**: Fixed asset filename - path has v prefix `/download/v1.23.0/` but
  filename is `qui_1.23.0_linux_x86_64.tar.gz` without v. Previous URL
  `qui_v1.23.0_...` caused 404 and build failure at qui stage. Now uses
  `${QUI_VERSION#v}` to strip v for filename.

### Fixed

- **Critical - Build failure at DNF stage**: `install_available` previously
  attempted to reinstall already-installed packages (e.g., hunspell-1.7.3-1.fc44),
  causing dnf5 "Package already installed" transaction resolution failure.
  Fixed by skipping already-installed packages.
- **Critical - Build failure at script module boundary**: `clean_build_artifacts`
  did `rm -rf /tmp/*` deleting BlueBuild internal `/tmp/scripts` and
  `/tmp/modules`, causing `nu::shell::eval_block_with_input` and
  `Failed to run setup-repos-and-rpms.sh`. Fixed by preserving /tmp/scripts and
  /tmp/modules and only cleaning specific caches.
- **Critical - Build failure at opencode-desktop RPM**: `gh_asset_url` regex
  patterns used double-escaped `\\\\.rpm` (4 backslashes) instead of `\.rpm`,
  causing "no asset matching pattern" for `anomalyco/opencode` asset
  `opencode-desktop-linux-x86_64.rpm`. Fixed to single-escaped `\.rpm$`.
- **Critical - Build failure at opencode-desktop RPM (jq compatibility)**: Used
  `test($pattern; "i")` which requires jq 1.6+, failing on older jq in Bazzite
  base with syntax error and empty URL. Fixed by using `(?i)` inline flag with
  `test($pattern)` for jq 1.5+ compatibility.
- **Critical - Build failure at RNNoise**: Tag `v1.2` does not exist (404),
  releases are v1.02, v1.03, v1.10 (latest stable), v1.21 (prerelease). Fixed to
  `v1.10`.
- **Critical - Build failure at qui**: Asset filename includes version without v
  prefix (`qui_1.23.0_...`) but URL used with v prefix (`qui_v1.23.0_...`) causing
  404. Fixed to strip v for filename.
- **Critical - PipeWire override bug**: `20-vibes-audio-quality.conf` (RT) and
  `99-input-denoising.conf` (RNNoise) both defined `context.modules` causing
  second file to overwrite first. Now combined into one file, 99 removed.
- **Critical - WirePlumber override bug**: `50-vibes-gaming.conf` defined
  `node.rules` twice in same file, second overwrote gaming client priorities.
  Now all three node rules (alsa_output, gaming clients, capture nodes) are in
  a single array, and 20 file only has monitor rules.
- Missing `jq` dependency for `gh_asset_url()` - added to build tools
- Obsolete COPR `faugus/faugus-launcher` enabled but not installed - now installed
- Removed internal audit artifact `AUDIT_REPORT.md`
- Made all shell scripts executable

### Removed

- **Bazzite/KDE Plasma base**: image now builds on Bluefin (NVIDIA Open)
  with GNOME; all Plasma-related packages and themes removed (dolphin,
  pcmanfm-qt, kdegraphics-thumbnailers, kio-extras, Darkly and
  Beauty-Plasma-Themes)
- ISO build workflow and all ISO documentation (distribution is OCI-only)
- `AUDIT_REPORT.md` (internal audit artifact, not production documentation)
- `files/system/etc/pipewire/pipewire.conf.d/99-input-denoising.conf`
  (merged into `20-vibes-audio-quality.conf`)
- `proton-cachyos` and its smoke check: the package is Arch-only (AUR) and is
  not built for Fedora in any of the CachyOS/bieszczaders COPRs (verified
  against F44 repository metadata and Fedora Packages, which 404s it);
  gaming remains covered by Steam's Proton plus UMU-Launcher and Faugus
- Flatpak IDs corrected to current Flathub IDs: Folio
  `com.github.toolstack.Folio` -> `com.toolstack.Folio` and Varia
  `org.giantpinkrobots.varia` -> `io.github.giantpinkrobots.varia` (the old
  IDs 404 on Flathub, which failed the default-flatpaks module)
- GitHub release asset downloads (opencode desktop/CLI, Mailspring, Vicinae)
  no longer depend on the rate-limited unauthenticated REST API: a new
  `gh_latest_asset_url` in `lib.sh` resolves the latest tag via the
  `releases/latest` redirect and the `expanded_assets` HTML page, falling
  back to the API only when needed. Fixes intermittent 403 `FAIL:` failures
  when the shared GitHub Actions egress IP exhausts the 60 req/hr anonymous
  quota
- `.github/workflows/dependency-review.yml` (not applicable - Dependency Graph
  requires package manifests, not supported for shell-based OCI image repos;
  security remains via CodeQL, Dependabot, secret scanning, cosign)

### Security

- New workflows follow least privilege: boot test and reproducibility checks
  run with read-only tokens
- The boot test refuses to boot an image whose signature does not verify
  against `cosign.pub`
- Releases now ship an SBOM and a verified digest alongside the signed image
- No new vulnerabilities. Existing mitigations retained and enhanced:
  - No `curl | bash` patterns; download-then-execute for opencode
  - Cosign signing with `cosign.pub` verification
  - CodeQL (python, actions) on every push/PR
  - Dependabot (github-actions) daily
  - Secret scanning and push protection enabled
  - Pinned actions to exact SHA/tag versions with SHA256-verified lint tools
  - `jq` compatibility fix prevents silent failures

## [0.2.0] - 2025-07-29

### Added

- Shared shell library (`files/scripts/lib.sh`) eliminating code duplication
  across all build scripts
- CodeQL analysis workflow for security scanning
- Stale issue and PR management workflow
- Release creation workflow for tagged versions
- Issue templates (bug report, feature request)
- Pull request template with validation checklist
- SECURITY.md with vulnerability disclosure policy
- CONTRIBUTING.md with contribution guidelines
- CHANGELOG.md with release history
- .editorconfig for consistent editor settings
- .markdownlint.json for Markdown consistency
- .yamllint.yaml for YAML consistency

### Changed

- **NVIDIA drivers**: Removed explicit `akmod-nvidia-open`/`nvidia-open-dkms`
  installation that could conflict with Bazzite's built-in drivers. Only
  supplementary userspace packages are now installed.
- **Environment configuration**: Consolidated from `/etc/profile.d/` and
  `/etc/environment.d/` to `/etc/environment.d/` only.
- **opencode CLI installation**: Replaced insecure `curl | bash` pattern with
  download-then-execute approach.
- **RNNoise**: Pinned to tagged release instead of floating latest (now v1.10).
- **README**: Complete rewrite in professional technical documentation style.
- **LICENSE**: Updated copyright attribution to repository maintainer.
- **ISO workflow**: Fedora version made configurable via `FEDORA_VERSION`
  environment variable.
- **Recipe validator**: Extended to check shared library sourcing and
  `set -euo pipefail` compliance.

### Fixed

- Eliminated 3x code duplication of `retry()`, DNF detection, and helper
  functions across shell scripts
- NVIDIA driver version conflicts with Bazzite base image
- Insecure shell pattern in opencode installation
- Missing security and contribution policies
- Missing issue and PR templates
- Incorrect LICENSE copyright attribution

### Removed

- Redundant `/etc/profile.d/90-vibes-desktop-env.sh` (consolidated into
  `/etc/environment.d/`)
- Explicit `akmod-nvidia-open`, `nvidia-open-dkms`, `nvidia-open-kmod`
  package installation (provided by base image)

## [0.1.0] - 2025-01-15

### Added

- Initial BlueBuild recipe based on Bazzite-nvidia-open
- RPM package layering for gaming, development, and AI workflows
- Firefox RPM with VA-API hardware acceleration
- Brave browser with uBlock Origin forced installation (later replaced by
  Helium + Zen)
- PipeWire audio configuration with RNNoise noise suppression
- WirePlumber gaming-optimized audio policy
- GPU acceleration configuration (NVIDIA, CUDA, VA-API)
- Desktop themes (Darkly, Beauty-Plasma-Themes, macOS cursors)
- System services (LACT, scx_loader, bpftune)
- COPR repositories for additional packages
- ISO build workflow
- Image signing with cosign
- Daily automated builds

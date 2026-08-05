# Vibes

<p align="center"><img src="assets/vibes-mascot.svg" width="160" alt="Vibes mascot"></p>

**Vibes** is a tuned GNOME workstation image for people who play, create, and
develop on NVIDIA hardware. Built on top of **Bluefin (NVIDIA Open)** with
BlueBuild, it replaces the stock kernel with the **CachyOS BORE kernel** from
the official Fedora COPR (with NVIDIA open modules rebuilt in-container), and
pairs a stable Fedora 44 base with a curated set of gaming-ready,
privacy-friendly, and developer-focused tools — plus a custom mutter build
that unlocks desktop tearing and variable refresh rate.

[![build](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml)
[![validate](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)
[![boot](https://github.com/mheci/vibes/actions/workflows/boot.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/boot.yml)
[![codeql](https://github.com/mheci/vibes/actions/workflows/codeql.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/codeql.yml)
[![reproducibility](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml)
[![upstream-health](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml)

**Base Image:** `ghcr.io/ublue-os/bluefin-nvidia-open:latest`
**Output Image:** `ghcr.io/mheci/vibes:latest`

---

## What's Inside

### Gaming, done right

- **A kernel that plays**: the stock kernel is removed entirely and replaced
  with the **CachyOS BORE kernel** (`kernel-cachyos`) from the official
  `bieszczaders/kernel-cachyos` Fedora COPR — BORE scheduler, Cachy Sauce
  patchset, HZ=1000, x86_64-v3, PREEMPT_DYNAMIC, full tickless (NO_HZ_FULL),
  sched_ext and ntsync enabled, SELinux as default LSM, zswap (zstd) on by
  default. The COPR tracks upstream CachyOS tags and is rebuilt on upstream
  infrastructure, so the kernel stays current without a 1h+ in-image source
  build (LTO/-O3 are compile-time-only and not available from the COPR).
  The stock kernel packages are version-locked so updates can never pull
  them back
- **NVIDIA open modules rebuilt in-container** for the new kernel, from the
  `open-gpu-kernel-modules` tag matching the base image's userspace driver —
  the prebuilt ublue `kmod-nvidia` akmods are removed
- **Steam** with the standard device rules (`steam-devices`) plus the classic
  Linux gaming duo: **Mangohud** (performance overlay) and **Gamescope**
  (steam game session compositor), with **proton-cachyos** installed
  system-wide as the default compatibility tool (x86_64_v3 build, sha512
  verified). GameMode is intentionally not shipped — it is buggy on this
  image and uresourced supersedes its CPU/IO priority handling
- **Faugus Launcher** — a Flatpak-style launcher for running Windows games
  through Wine/Proton via UMU-Launcher
- **proton-cachyos** (x86_64_v3 build, sha512-verified against upstream)
  installed system-wide under `/usr/share/steam/compatibilitytools.d` so
  Steam offers it for every game. Running it outside Steam needs the Steam
  runtime paths:

  ```bash
  STEAM_COMPAT_CLIENT_INSTALL_PATH=~/.steam/steam \
  STEAM_COMPAT_DATA_PATH=~/games/mygame \
  /usr/share/steam/compatibilitytools.d/proton-cachyos/proton run /path/to/game.exe
  ```

- Full **Vulkan stack**: `vulkan-loader`, `vulkan-validation-layers`,
  `vulkan-tools`, `mesa-vulkan-drivers`, `nvidia-settings`
- **LACT daemon** for GPU overclocking, fan and power control
- **scx_loader** with the `scx_lavd` scheduler set to **Gaming** mode —
  sched_ext schedulers are built from the latest `sched-ext/scx` upstream git
  HEAD at image build time (replacing the COPR packages) and
  **ananicy-cpp** as an auto-nice daemon for desktop responsiveness
- **Vibes-specific tearing**: a custom mutter build (GNOME MR
  [!3797](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/3797), commit
  `a8d56d42`, based on mutter 50.1) enables **async page flip (tearing)** and
  **variable refresh rate** via
  `MUTTER_DEBUG_EXPERIMENTAL_FEATURES=tearing,variable-refresh-rate`, set
  globally in `/etc/environment.d/90-vibes-desktop-env.conf`

### Browsers, for every mood

- **Firefox** (native RPM) — VA-API and WebRender enabled via policy,
  hardware video decoding forced on
- **Zen Browser** — privacy-focused Firefox fork, always the latest stable
  from GitHub releases
- **Brave Origin** — the privacy browser from the official Brave RPM repo,
  with built-in ad and tracker blocking (Shields)
- **Helium** — ungoogled-Chromium-based privacy browser from COPR
  `imput/helium`

No Flatpak browsers are installed by default.

All browsers ship hardware-acceleration configuration: Chromium-family
browsers (Helium, Brave Origin) get a managed policy plus flags files that
enforce VA-API video decoding, including on NVIDIA via `libva-nvidia-driver`
(see the [CachyOS hardware acceleration guide](https://wiki.cachyos.org/configuration/enabling_hardware_acceleration_in_google_chrome/));
Firefox and Zen get the same via their distribution policies; mpv runs with
`hwdec=auto-safe`.

### Chat and social

- **Whatsie** — native Qt6 WhatsApp desktop client, built from source
- **karere** — GTK4/Libadwaita WhatsApp Web client (Flatpak)
- **Mailspring** — cross-platform email client, latest release RPM
- **Nicotine+** — Soulseek music-sharing client (Fedora package)
- **GSConnect** (KDE Connect for GNOME) and **nautilus-gsconnect** for
  phone-to-desktop integration

### Clipboard, taken seriously

- **Copyous** — clipboard history manager GNOME extension (ID 8834) with
  pinning, tags and SQLite persistence (backed by `libgda`,
  `libgda-sqlite` and `gsound`)

### Development and AI

- **Zed** — latest stable from zed.dev
- **VS Code** — Microsoft repo RPM
- **opencode** — CLI plus desktop app, latest releases
- **T3 Code** — opinionated Electron code editor by t3.gg (official AppImage)
- **Helix** — modal editor in Rust (Fedora package)
- **Nix** — Determinate Systems installer: multi-user/rootless, store in
  persistent `/var/nix` bind-mounted to `/nix`, socket-activated `nix-daemon`,
  SELinux policy module installed and `/nix` relabeled at first boot
- **uv** — fast Python package manager (Fedora package, cloud-native choice
  over pipx; `uvx` covers pipx-style one-off tools)
- **Bun** and **Deno** — modern JavaScript/TypeScript runtimes (latest
  GitHub releases)
- **CLI essentials**: `gh` (GitHub CLI), `yt-dlp`, `zoxide`
- **RustConn** — GTK4/Wayland-native SSH and RDP connection manager (Flatpak,
  per the developer's recommendation)
- **LM Studio** — local LLM playground (official AppImage)
- **Vicinae** — Raycast-inspired launcher (AppImage)
- **Hermes Agent** — Nous Research's open-source AI agent, installed
  system-wide from the official installer pinned to an exact upstream commit
  (code in `/usr/local/lib/hermes-agent`, `hermes` command on PATH for all
  users). Python 3.11 venv with `uv`, Playwright Chromium for browser tools
  shared at `/usr/share/hermes/ms-playwright`, and defaults seeded per-user
  via `/etc/skel/.hermes`. Run `hermes` (or `hermes-agent`, `hermes-acp`)
  from any terminal; API keys are configured per user in `~/.hermes/.env`
- **bpftune** — BPF-based automatic system tuning daemon, built from a pinned
  upstream commit and enabled as a systemd service

### Under the hood

- **PipeWire / WirePlumber** tuned for gaming and voice: 48 kHz fixed rate,
  real-time scheduling (nice -11 / rtprio 88), RNNoise LADSPA noise
  suppression, A2DP high-quality Bluetooth codecs, pro-audio profile
  preservation, gaming client priorities and persistent capture nodes
- **NVIDIA acceleration**: `libva-nvidia-driver`, `nvidia-vaapi-driver`,
  `nvidia-container-toolkit`, plus environment defaults for Wayland and
  hardware video decoding (`LIBVA_DRIVER_NAME=nvidia`, `VDPAU_DRIVER=nvidia`,
  `GBM_BACKEND=nvidia-drm`, `NVD_BACKEND=direct`, `MOZ_ENABLE_WAYLAND=1`); a
  1 GiB NVIDIA shader disk cache with cleanup skipped
  (`__GL_SHADER_DISK_CACHE_SIZE`, `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP`)
  avoids shader recompilation stutter in large titles. Every toolkit's
  shader cache — NVIDIA (`__GL_SHADER_DISK_CACHE_PATH`), Mesa
  (`MESA_SHADER_CACHE_DIR`), DXVK (`DXVK_STATE_CACHE_PATH`) and Qt scene
  graph — is pinned to the persistent per-user cache dir (`$XDG_CACHE_HOME`,
  default `~/.cache`) so caches never land in volatile locations.
  `VKD3D_CONFIG=descriptor_heap` lowers Direct3D 12 descriptor churn for
  titles running through proton-cachyos
- **Full media codec stack**: ffmpeg freeworld, GStreamer plugins (base,
  good, bad/freeworld, ugly, libav, vaapi), x264/x265/SVT-AV1/rav1e/AV1,
  dav1d, HEIF, WebP, JPEG XL, raw thumbnails, `ffmpegthumbnailer`
- **Theming that just works**: **adw-gtk** GTK3 theme (light/dark/black)
  as the system default so every GTK3 app matches libadwaita; **MoreWaita**
  icon theme; **Yaru** GTK3/GTK4/shell themes plus icon theme; **macOS
  Big Sur/Monterey cursor packs**; Qt apps follow the GNOME theme via
  `QT_QPA_PLATFORMTHEME=gtk3`
- **Fonts**: Nerd Fonts (JetBrains Mono, Fira Code, Cascadia Code, Hack,
  Iosevka), IBM Plex Sans/Serif, Source Serif Pro, Adobe Source Code Pro/Sans,
  Liberation, Monaspace, Inter, Lilex and Fusion JetBrainsMapleMono, plus full
  Noto Arabic coverage, with Arabic spellcheck and hyphenation dictionaries
- **Utilities**: kitty, yazi, mpv, umu-launcher, `qui` (qBittorrent web UI),
  GNOME Tweaks
- **Security**: `sudo-rs` (memory-safe sudo) as the default sudo, with the
  wheel group configured for passwordless sudo
  (`/etc/sudoers.d/99-vibes-wheel-nopasswd`); SELinux stays enforcing with
  the `selinuxuser_execmod` boolean enabled at first boot (one-shot
  `vibes-selinux.service`) so Steam/Proton and desktop apps run without
  denial noise; the default FedoraWorkstation firewalld zone opens
  `1025-65535` tcp+udp, so Steam, GSConnect/KDE Connect (1714-1764),
  BitTorrent and media servers are never blocked out of the box
- **More GNOME extensions**: Just Perfection, Grand Theft Focus, AppIndicator
  and KStatusNotifierItem Support, ChromaLeon (wallpaper-synced accent
  colors), Alphabetical App Grid, Arc Menu (alternative application menu)
- **Handy Flatpaks**: Bazaar (app store), Refine (advanced settings),
  Warehouse (Flatpak cleanup), coppwr (PipeWire graph), DistroShelf and Lobjur
  (container/distro management), Tangram (web apps in one browser), Folio
  (markdown notebook), Varia (download manager for files, torrents and video),
  AdwSteamGtk (Steam library in libadwaita style), Pods (Podman/Docker
  containers), FlameGet (GTK4 download manager), adw-gtk GTK3 theme, Bottles
  (Windows apps), Flatseal (Flatpak permissions), Extension Manager,
  ProtonPlus (Proton/GE downloader), Foliate (ebook reader),
  Equibop (Discord client), Ente Auth (authenticator), Ignition (Flatpak
  remotes), LibreMenu Editor, Constrict (podcast recorder), RustConn
  (SSH/RDP manager)
- **Flatpak-to-native conversions**: Mission Center (GitLab AppImage), Gear
  Lever (pkgforge AppImage) and MangoJuice (AppImage from upstream zip) are
  installed as native apps instead of Flatpaks
- **System tuning** (drop-ins under `/etc/systemd/*.conf.d`, `/etc/sysctl.d`,
  `/etc/modprobe.d`, `/etc/udev/rules.d`, `/etc/tmpfiles.d`): 20 s service
  timeouts, capped journal/coredump storage, BBR + fq networking, gaming
  `vm.max_map_count` and inotify limits, low swappiness, khugepaged defrag
  off, HDA power-save, `uaccess` for game controllers, and the `ntsync`
  module autoload; kernel arguments (`nvme_core.default_ps_max_latency_us=0`,
  `nowatchdog`) are added via bootc `kargs.d`; zram-generator is removed since
  the CachyOS kernel enables zswap (zstd) by default
- **Memory management**: `uresourced` (gives the active user full CPU/IO
  priority), `low-memory-monitor` (early D-Bus pressure warnings, warn-only
  config), **nohang** (PSI-based low-memory handler with desktop config,
  replacing `systemd-oomd`, which is masked) and **prelockd** (executables
  and shared libraries pinned in RAM). GameMode is intentionally **not**
  shipped — it is buggy on this image and uresourced supersedes its CPU/IO
  priority handling
- **Power management**: **tuned + tuned-ppd** (Fedora's
  power-profiles-daemon replacement) with the PPD `performance` profile
  remapped to tuned `latency-performance` (performance governor, PM QoS
  low-latency lock, energy-perf-bias) and set as the default; GNOME's Power
  Mode default is `performance` (dconf local default, not locked).
  `vjust power-status` shows the active tuned profile and PPD mapping
- **Quiet logs**: Qt apps run with
  `QT_LOGGING_RULES=*.debug=false;*.info=false`, so only warnings, errors
  and criticals from Qt land in the journal and on the console; the journal
  is size-capped (`SystemMaxUse=2G`, `RuntimeMaxUse=256M`) and `vjust
  errors` shows the current boot's warnings and above
  (`journalctl -b -p 3`)

### Command recipes: `vjust`

**Vibes** ships the **just** command runner plus a recipe collection
(`/usr/share/vibes/justfile`, wrapper `vjust`) covering everyday and power-user
tasks — 40+ recipes grouped by topic:

- **System**: status, update, journal/errors, boot status, disk/mem, kernel
  details, firmware, service management
- **TPM**: status and PCR listing, LUKS key enrollment into the TPM,
  recovery keys
- **LUKS**: device overview, header backup, key management, TPM binding
  removal
- **Gaming**: scheduler status/selection (`scx_lavd`, `scx_bpfland`,
  `scx_rusty`, ...), memory stack and power management status
  (`memory-status`, `power-status`), gamescope version, Proton tools,
  NTSYNC status
- **NVIDIA**: driver status, kernel module info, live GPU monitoring
- **Flatpak**: update, cleanup, app listing
- **Nix**: version, store GC, channels/roots
- **Audio & hardware**: PipeWire info, sinks, battery, temperatures

```bash
vjust          # list all recipes
vjust sched-set scx_bpfland
vjust tpm-status
```

---

## Getting Started

Rebase an existing Atomic Fedora installation:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/mheci/vibes:latest
systemctl reboot
```

The `latest` tag always tracks the newest successful `main` build on
Fedora 44. No automatic major Fedora version jumps.

---

## Verify the Image

Images are signed with Sigstore cosign. The public key is `cosign.pub` in the
repository root.

```bash
cosign verify --key cosign.pub ghcr.io/mheci/vibes:latest
```

---

## Stay Up to Date

Automated builds run daily at 06:00 UTC and on every push to `main`. Because
the published image is chunked into balanced OCI layers, upgrades download only
the chunks that changed since your last version (see
[How It Is Built](#how-it-is-built)).

After installation:

```bash
rpm-ostree upgrade
# or
bootc upgrade
```

---

## Releases

Tagged releases (`v*`) are created by the
[release workflow](https://github.com/mheci/vibes/actions/workflows/release.yml).
Each release:

- Verifies the published image signature against `cosign.pub`
- Records the verified image digest
- Attaches an SPDX SBOM generated from the image

---

## How It Is Built

| Stage | Description |
| --- | --- |
| **Validate** | shellcheck (0.11.0), actionlint (1.7.12), yamllint (1.38.0), markdownlint (0.49.1), recipe structural checks |
| **Build** | BlueBuild layers repositories, RPMs, themes, upstream binaries and system configs onto Bluefin NVIDIA Open, then re-chunks the image into balanced OCI layers with `rpm-ostree compose build-chunked-oci` so updates download only the chunks that changed |
| **Lint** | `bootc container lint` runs inside the recipe |
| **Sign** | Image signed with a cosign private key stored in GitHub Secrets |
| **Push** | Published to `ghcr.io/mheci/vibes:latest` |
| **Boot** | Daily QEMU boot test: a disk image is built with `bootc install to-disk` and booted to the multi-user target; the image signature is verified with `cosign.pub` first |
| **OpenQA** | Daily headless boot test with the official os-autoinst isotovideo container: the disk image is booted under QEMU (TCG) and openQA asserts the login prompt appears on the serial console (`openqa/` test distribution, no needles) |
| **Reproducibility** | Weekly no-cache rebuild that catches upstream breakage between daily builds |
| **Upstream Health** | Weekly check that every URL, pinned tag and release-asset pattern referenced by the scripts still resolves |
| **Release** | Tagged releases verify the image signature, record the image digest and attach an SPDX SBOM |

Third-party GitHub Actions are pinned to exact patch versions and tracked via
Dependabot (grouped updates). Lint binaries and pip CI dependencies are pinned
to exact versions; lint tool binaries are SHA256-verified.

CodeQL (python, actions) runs on every push/PR. Runs triggered by Dependabot
or forks skip the image build because signing secrets are unavailable to
them; validation still runs in full.

---

## Package Policy

New software is added in the following order of preference, so contributors
and reviewers can reason about each choice:

1. **Official developer repos** — vendor RPM repos (e.g. Microsoft for VS
   Code, Brave's official repo) and COPRs maintained by the upstream project
   itself. These integrate natively with DNF, SELinux, themes and updates.
2. **Git release RPMs** — `.rpm` artifacts published by upstream on GitHub
   Releases, installed from the pinned `latest` asset with the checksum
   verified (`install_latest_rpm` in `files/scripts/install-latest-apps.sh`).
3. **AppImages** — upstream AppImages installed system-wide under
   `/usr/lib/vibes-apps` with icons and desktop entries
   (`install_latest_appimage`).
4. **Flatpaks** — last resort, only when no trusted native package exists
   (e.g. apps that ship exclusively on Flathub).
5. **Pinned upstream installers** — when upstream offers no RPM, AppImage or
   Flatpak at all (e.g. Hermes Agent): the official installer is run with the
   checkout pinned to an exact commit (`--commit`), and the recorded SHA is
   verified by the build's smoke checks, so the installed code is as
   reproducible as a pinned tag.

Rationale: native packages update through DNF, carry correct SELinux labels,
work with firewalls, theming and Wayland portals, and avoid Flatpak
sandbox/graphics limitations — while verified Flatpaks are still preferred
over unverified or unsigned binaries.

---

## Development

```bash
# Validate recipe and scripts without a full container build
python3 .github/scripts/validate_recipe.py

# Shellcheck (if installed)
cd files/scripts && shellcheck -S style *.sh

# Bash syntax
bash -n files/scripts/*.sh
```

Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md)

---

## Project Links

- **Source:** [github.com/mheci/vibes](https://github.com/mheci/vibes)
- **Issues:** [github.com/mheci/vibes/issues](https://github.com/mheci/vibes/issues)
- **Discussions:** [github.com/mheci/vibes/discussions](https://github.com/mheci/vibes/discussions)
- **Security:** [SECURITY.md](SECURITY.md)
- **Support:** [SUPPORT.md](SUPPORT.md)

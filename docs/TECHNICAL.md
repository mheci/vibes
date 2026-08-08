# vibes — Installation and Technical Reference

This document is the complete, low-level reference for the vibes image:
how to install it, how it is built, what every layer and configuration
does, and how the CI/CD pipeline keeps it production-ready.

---

## Table of Contents

1. [What vibes is](#1-what-vibes-is)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Upgrading and rollback](#4-upgrading-and-rollback)
5. [How the image is built](#5-how-the-image-is-built)
6. [Build modules in execution order](#6-build-modules-in-execution-order)
7. [Package and application inventory](#7-package-and-application-inventory)
8. [System configuration reference](#8-system-configuration-reference)
9. [The vjust command suite](#9-the-vjust-command-suite)
10. [Security architecture](#10-security-architecture)
11. [CI/CD pipeline](#11-cicd-pipeline)
12. [Boot testing infrastructure](#12-boot-testing-infrastructure)
13. [Performance tuning](#13-performance-tuning)
14. [Troubleshooting](#14-troubleshooting)
15. [Reproducing a release](#15-reproducing-a-release)

---

## 1. What vibes is

vibes is a tuned KDE Plasma workstation image for NVIDIA hardware built
with [BlueBuild](https://blue-build.org). It layers a curated set of
gaming, creation and development tools on top of
`ghcr.io/ublue-os/aurora-nvidia-open:stable` (Fedora 44, KDE Plasma 6,
NVIDIA open kernel modules) and is published as an ostree/OCI image at:

| Artifact | Location |
|---|---|
| Image | `ghcr.io/mheci/vibes` (tags `latest`, `previous`) |
| Source | `github.com/mheci/vibes` |
| Public key | `cosign.pub` (repo root and image) |

The defining properties of the image:

- **Atomic, signed, verified**: upgrades are verified against an
  embedded cosign public key (see [§10](#10-security-architecture)).
- **Gaming-first**: CachyOS kernel, sched-ext schedulers, ananicy-cpp,
  Gamescope with `CAP_SYS_NICE`, proton-cachyos, Steam shader cache
  tuned to 100 GiB.
- **Self-healing boot**: greenboot health checks with automatic
  rollback, plus a daily three-phase boot/upgrade/rollback test in CI.
- **Automatic updates OFF by design**: a weekly notification-only timer
  (`vibes-update-check.timer`, Mondays 09:00) tells you a new build is
  available; you decide when to apply it.

---

## 2. Requirements

- An NVIDIA GPU (the base image ships the NVIDIA open kernel modules;
  the image itself adds `nvidia-smi` tooling and driver state is
  handled by the base's akmods flow).
- UEFI with Secure Boot (optional but recommended; the image ships
  unified kernel images via systemd-ukify).
- A TPM 2.0 (only needed for the LUKS auto-unlock recipe, §9.3).
- 50 GiB+ free disk, 8 GiB+ RAM recommended.
- The image currently targets x86_64 (COPR chroots and binary
  downloads are x86_64-only).

---

## 3. Installation

### 3.1 First-time install (from another OS)

Boot the official [Fedora 44 KDE](https://fedoraproject.org/kde/) live
ISO (or any distro) and run:

```bash
# Install bootc
sudo dnf install -y bootc

# Rebase onto the vibes image
sudo bootc switch ghcr.io/mheci/vibes:latest

# Inspect the pending deployment before rebooting
sudo bootc status

# Reboot into vibes
sudo systemctl reboot
```

If your current system already uses rpm-ostree (Bluefin, Aurora,
Bazzite, ...):

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest
sudo systemctl reboot
```

> The `ostree-unverified-registry:` transport prefix is only needed for
> the initial rebase from a foreign image; once vibes is running, the
> embedded policy (`/etc/containers/policy.json`) enforces cosign
> signature verification for every subsequent pull.

### 3.2 Verify the image before installing

```bash
# Download the key and the image manifest
curl -fsSL -o cosign.pub https://raw.githubusercontent.com/mheci/vibes/main/cosign.pub
cosign verify --key cosign.pub ghcr.io/mheci/vibes:latest
```

`cosign verify` returns exit code 0 only if the image manifest digest
matches a payload signed with the private key whose public half is
`cosign.pub`.

### 3.3 First boot

On first boot the image self-optimizes:

1. The NVIDIA kmod from the base image is compiled against the new
   kernel by akmods (base-image behavior) and loaded via
   `modprobe.d/60-vibes-nvidia.conf`.
2. `greenboot-health-check.service` runs the greenboot health checks
   and marks the boot successful.
3. `tuned-ppd` picks the `performance` profile (config in §8.9).
4. `scx_loader.service` loads the default scheduler `scx_lavd` in
   Gaming mode (`/etc/scx_loader/config.toml`).
5. The first real user created is added to `wheel` (base-image
   behavior); the image's `sudoers.d` grants passwordless `sudo`
   (documented in §8.10).

### 3.4 Layout inside the image

```
/usr/share/vibes/justfile         # vjust recipe suite (see §9)
/usr/share/vibes/kernel-version   # installed kernel version (kver)
/usr/libexec/vibes-update-check.sh# weekly update notification
/usr/libexec/vibes-luks-tpm-encrypt.sh
/usr/libexec/vibes-dns-encrypted.sh
/usr/lib/greenboot/check/warning.d/40-systemd-failed.sh
/etc/pki/containers/vibes-cosign.pub
/usr/share/steam/compatibilitytools.d/proton-cachyos
/usr/lib/vibes-apps/             # AppImages (LM Studio, Vicinae, ...)
/var/nix                          # Nix store (persistent state)
```

---

## 4. Upgrading and rollback

### 4.1 How updates are delivered

The CI pipeline rebuilds the image on every push to `main` and
re-tags the previous `latest` as `previous` (`build.yml`, step "Save
previous image tag"). Tags are moved, so consumers always pull the
fresh build.

### 4.2 Applying an update

```bash
vjust update            # = sudo bootc upgrade + flatpak update -y
sudo systemctl reboot
```

`bootc upgrade` re-resolves the deployment's image reference, pulls
the new manifest, verifies it against the policy (`sigstoreSigned` with
the embedded key), downloads new layers, deploys and regenerates the
initramfs. Failed verifications abort the upgrade.

### 4.3 Automatic update policy

The following timers are deliberately **masked** (no automatic updates):

- `ublue-update.timer`
- `bootc-fetch-apply-updates.timer`
- `flatpak-update.timer`
- `updates-stage.timer`

Instead `vibes-update-check.timer` (weekly, Mon 09:00) runs
`vibes-update-check.sh`, which compares the running deployment with the
registry and sends a desktop notification (`notify-send`) when a newer
build exists. The service is a `oneshot`; the unit file is shipped at
`/usr/lib/systemd/system/vibes-update-check.{service,timer}` and the
timer is enabled into `timers.target.wants`.

### 4.4 Automatic rollback (greenboot)

`greenboot`, `greenboot-default-health-checks` and
`greenboot-rpm-ostree` are installed. The flow:

1. After a boot triggered by an update, `greenboot-task-runner.service`
   (sockets.target) waits for `greenboot-health-check.service`
   (multi-user.target) to complete all checks.
2. Checks live in `/usr/lib/greenboot/check/required.d` (hard failures
   ⇒ rollback) and `/warning.d` (failures ⇒ warning only).
3. Our custom check `40-systemd-failed.sh` (warning level) verifies no
   systemd unit is in `failed` state, with an allowlist:
   - `systemd-vconsole-setup.service`
   - `systemd-boot-system-token.service`
4. On required-check failure, greenboot reboots into the previous
   deployment after a configurable grace period and re-runs checks
   there.
5. Only after checks pass does `bootc status` mark the boot successful.

The greenboot unit files come from the RPM; enablement is wired in
`setup-repos-and-rpms.sh` (multi-user.target.wants for
greenboot-health-check, sockets.target.wants for greenboot-task-runner).

---

## 5. How the image is built

### 5.1 The build action

`.github/workflows/build.yml` uses
`blue-build/github-action@836161eb076426a451e6a0054f722b1153b8b3ad`
(v1.12.0, pinned by SHA) with:

| Input | Value | Why |
|---|---|---|
| `recipe` | `recipe.yml` | The build definition |
| `build_chunked_oci` | `true` | Push per-module layers so upgrades fetch only changed layers |
| `rechunk_clear_plan` | `true` | rpm-ostree's ostree-ext panics (chunking.rs:423) when re-chunking against an existing chunked image; always plan from scratch |
| `cosign_private_key` | `SIGNING_SECRET` | Signs the manifest (empty ⇒ skip signing on fork/dependabot runs) |
| `verify_install` | `true` | Runs `bootc container lint` + install verification inside the container |
| `retry_push_count` | `3` | Push retries |

### 5.2 Buildkit cache mounts

BlueBuild runs every module as a RUN step inside a buildkit container
with persistent cache mounts, including `/var/cache/apt`
(id `apt-cache-vibes-44-stage-vibes`), `/var/cache/rpm-ostree`,
`/var/cache/libdnf5`, `/var/cache/zypp`, `/var/cache/apk`,
`/var/cache/pacman`. The vibes build scripts place **build trees in
`/var/cache/apt` on purpose** — that mount survives across builds, so
rebuilds are incremental:

| Cache | Path | Used by |
|---|---|---|
| Cargo registry | `/var/cache/apt/cargo` | sched-ext workspace |
| Cargo target (scx) | `/var/cache/apt/target-scx` | sched-ext schedulers |
| Cargo target (loader) | `/var/cache/apt/target-scx-loader` | scx-loader |
| Cargo target (manager) | `/var/cache/apt/target-scx-manager` | scx-manager |
| Meson/ninja | `/var/cache/apt/boxes-build` | gnome-boxes |
| CMake | `/var/cache/apt/klassy-build` | Klassy |

Cache-mounted content never lands in the image. dnf state is kept
across modules (only the final strip module cleans it) so repository
metadata is fetched once per build, not once per module.

### 5.3 Signing and pushing

1. `cosign sign` (with the passwordless private key from
   `SIGNING_SECRET`) signs the manifest; the signature is pushed to the
   registry (Sigstore bundle, not necessarily Rekor).
2. `:latest` is pushed; `:previous` handling happens in the "Save
   previous image tag" step on `main` pushes (the old `:latest` is
   re-tagged `:previous` after the new build succeeds).
3. The push-triggered build **skips** when the same commit already has
   an open pull request ("Check for open pull request" step,
   `pull-requests: read` permission): the PR build and the push build
   would produce identical images, so the push run is redundant.

### 5.4 Module execution order

`recipe.yml` runs modules top to bottom; every `script` module runs
inside the container with `bash`, and the `files` module copies
`files/system/**` into the image **after** all scripts (files module
copy happens at its position; the recipe ends with `containerfile`
snippets running `bootc container lint`).

---

## 6. Build modules in execution order

| # | Script / module | Purpose |
|---|---|---|
| 1 | `setup-repos-and-rpms.sh` | Third-party repos (VS Code, Brave, proton-cachyos via COPR, CachyOS kernel COPRs, nerd-fonts COPR, faugus, yazi, helium, LACT, gstreamer plugins), base RPM set, NVIDIA tooling, `vibes-update-check` units, sudoers, scx config, service enablements (tuned, tuned-ppd, uresourced, nohang, prelockd, gamescope cap, ananicy, scx), env defaults (`/etc/environment.d`), greenboot enablement |
| 2 | `setup-cachyos-kernel.sh` | Installs `kernel-cachyos-core` + modules/devel from COPR, records `KVER` to `/usr/share/vibes/kernel-version`, builds the NVIDIA open-gpu-kernel-modules against that exact kernel tree (`SYSSRC`/`SYSOUT`), `depmod -a`, dracut initramfs with the ostree prepare-root hook, versionlock, `dracut.conf.d` tuning |
| 3 | `build-scx.sh` | Clones `sched-ext/scx` (master, shallow), `cargo build --release` into `/var/cache/apt/target-scx` (registry in `/var/cache/apt/cargo`), installs schedulers; clones `sched-ext/scx-loader`, builds, installs `scx_loader`, scxctl, scxtui, DBus/polkit files, enables `scx_loader.service` |
| 4 | `build-scx-manager.sh` | Builds CachyOS `scx-manager` (KDE system tray app) from master into `/var/cache/apt/target-scx-manager`, installs desktop file |
| 5 | `build-gnome-boxes.sh` | Builds `gnome-boxes` 50.0 from the GNOME GitLab tag (libvirt/devel deps) into `/var/cache/apt/boxes-build`; falls back to the distro RPM on failure |
| 6 | `build-klassy.sh` | Builds Klassy (KDE window decorations) from master into `/var/cache/apt/klassy-build`, installs the KWin plugin |
| 7 | `install-themes.sh` | Cursor: `apple_cursor` v2.0.0 (macOS Big Sur/Monterey); icon: `MoreWaita` at pinned commit; Yaru GTK/icon packs |
| 8 | `install-latest-apps.sh` | The big one — see §7. Every binary is smoke-checked (`check_command`/`check_file`), and new artifacts since this batch also verify: exec bits on libexec scripts, greenboot service presence, files-module configs, justfile, kernel-version |
| 9 | `setup-extra-themes.sh` | SteamOS KDE presets (steamdeck-kde-presets 0.30 from GitLab) + Darkly (pinned commit `11c27e2d...`, `metadata.json` generated via `sed 's/@PROJECT_VERSION@/0.5.38/'`) |
| 10 | `strip-build-tools.sh` | Removes compilers/toolchains (gcc, clang, cargo, cmake, ninja, meson, *-devel patterns), `/usr/src/kernels`, autoremoves, then the **final** dnf cache clean (`/var/lib/dnf`, `/var/cache/dnf`, `/run/dnf`), `chmod 0440 /etc/sudoers.d/*`, `clean_build_artifacts` |

`lib.sh` provides shared helpers: `retry` (4 attempts, exponential
backoff), `install_available` (dnf install with per-package fallback),
`gh_asset_url`/`gh_latest_asset_url` (GitHub release asset resolution
with 429/5xx retry and token auth), `check_command`, `check_file`,
`clean_build_artifacts`.

---

## 7. Package and application inventory

### 7.1 System packages (Fedora repos)

kitty, umu-launcher, yazi, code (VS Code repo), lact, gamescope,
ananicy-cpp, faugus-launcher, tmux, lollypop, rhythmbox, fragments,
qbittorrent, mpv, kdeconnectd, libnotify, systemd-ukify, nautilus,
gvfs + backends (mtp, smb, afp, archive, fuse, nfs, goa, gphoto2),
gnome-disk-utility, dolphin, dolphin-plugins, bat, eza, fd-find,
ripgrep, fzf, duf, nicotine+, uv, helix, yt-dlp, gh, zoxide, just,
trivy, lm_sensors, nvtop, gparted, fastfetch, sudo-rs, zram, greenboot
trio, brave-origin (Brave repo), gstreamer plugins, yaru GTK/icon
packs.

### 7.2 Pinned/downloaded applications

All downloads are TLS + GitHub-release-API resolved; each is
smoke-checked at build time:

| App | Source | Verification |
|---|---|---|
| proton-cachyos | GitHub release tarball | **sha512** against the release's `.sha512sum` |
| Scx schedulers/loader | sched-ext master builds | cargo `--locked --frozen` |
| opencode-desktop | GitHub release RPM | rpm install |
| opencode CLI | GitHub release tarball | — |
| Mailspring | GitHub release RPM | — |
| Ferdium | GitHub release RPM | — |
| Sniffnet | GitHub release RPM (v1.5.1) | — |
| LM Studio | lmstudio.ai AppImage | — |
| Vicinae | GitHub release AppImage | — |
| t3code | GitHub release | — |
| MangoJuice | GitHub release | — |
| mission-center | GitLab release | — |
| opi | GitHub release | — |
| qui | GitHub release, pinned v1.23.0 | falls back to latest on pin breakage |
| zellij | GitHub latest | — |
| glance | GitHub latest | — |
| Commet | GitHub latest | — |
| bottom | GitHub latest | — |
| Helium | GitHub latest AppImage | — |
| nix-installer | GitHub release binary, **pinned v3.21.9** | `--version` matches the pinned tag; no `curl|sh` |
| Zen Browser | GitHub tarball | extraction layout check |
| nohang / prelockd | pinned commits, `make install` | unit files present |
| fonts (Monaspace, Inter, Lilex, Fusion, JetBrains Mono, Maple Mono, Fira, Droid, Envy) | GitHub releases | fc-list checks |
| ananicy-rules | CachyOS tag 1.1.47 | rules dir checks |
| RNNoise LADSPA | GitHub release | `librnnoise_ladspa.so` check |

### 7.3 Flatpaks

Installed via the recipe's `flatpak` module (system-wide):
org.mozilla.firefox removed (replaced by a browser preference), Steam
(com.valvesoftware.Steam), Heroic Games Launcher, Bottles, OBS Studio,
Kdenlive, Audacity, LibreOffice, GIMP, qBittorrent (when not RPM),
Karere, Discord, Telegram, Element (Commet replaces), etc. — see
`recipe.yml`.

### 7.4 Nix

Determinate Systems nix-installer (pinned v3.21.9, binary verified)
installs with `--init none --no-confirm`; the store is moved to
`/var/nix` (persistent ostree state), `/nix` becomes a symlink-ish
mountpoint; SELinux policy (`determinate-nix.pp`) is installed and a
`systemd-modules-load`-style service applies `semodule --install` on
boot.

---

## 8. System configuration reference

All paths are `files/system/...` in the repo, copied verbatim
(including file modes — exec bits matter, see §11 troubleshooting).

### 8.1 KDE defaults

- `/etc/xdg/kwinrc` — `[Compositing] VrrPolicy=Always`,
  `AllowTearing=true`. With a VRR-capable monitor this enables
  adaptive-sync presents; `AllowTearing` composes with it (KWin uses
  AdaptiveAsync when both are set — not contradictory).
- `/etc/xdg/powerdevilrc` — `[AC] PowerProfile=performance`. Combined
  with tuned-ppd's `default=performance` the system runs the
  `latency-performance` tuned profile on AC power.
- `/etc/xdg/kdeglobals` — `ColorScheme=BreezeDark`,
  `Font=Inter,10,...`, fixed font JetBrains Mono; `[Icons] Theme=Breeze`.
- `/etc/fonts/local.conf` — full hinting, `lcddefault` subpixel
  rendering, font aliases mapping to the shipped families.

### 8.2 NVIDIA

- `/etc/environment.d/90-vibes-desktop-env.conf`:
  `LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`,
  `__GL_SHADER_DISK_CACHE_SIZE=107374182400` (100 GiB shader cache),
  `VK_ICD_FILENAMES` pointing at the proprietary ICDs,
  `__GLX_VENDOR_LIBRARY_NAME=nvidia`.
- `modprobe.d/60-vibes-nvidia.conf` — nvidia-drm modeset+fbdev.
- `udev/rules.d/60-vibes.rules` — `TAG+="uaccess"` on the NVIDIA
  device nodes (secure boot: no setuid helpers needed).
- Gamescope gets `setcap cap_sys_nice=eip` via
  `vibes-gamescope-cap.service`.

### 8.3 Kernel boot arguments (`recipe.yml` kargs)

- `nvme_core.default_ps_max_latency_us=0` — disable NVMe autonomous
  power-state transitions (audio/video stutter fix).
- `nowatchdog` — disable watchdog timers (latency).
- `split_lock_detect=off` — split-lock detection off (implies no
  mitigation).
- Base image adds the standard ublue set (secure boot, quiet, etc.).

### 8.4 Storage / swap / OOM

- `zram` enabled with `zram-generator` defaults tuned for gaming.
- `sysctl.d/60-vibes.conf`:
  - `net.core.default_qdisc=fq`, `net.ipv4.tcp_congestion_control=bbr3`
    (with `modules-load.d/60-vibes-bbr3.conf` autoloading `-tcp_bbr3`,
    dash-prefixed so a built-in module is a non-error).
  - `vm.swappiness`, `vm.watermark_boost_factor`,
    `vm.page-cluster`, `kernel.core_uses_pid`,
    `fs.inotify.max_user_watches/instances` raised, `fs.file-max`.
- `nohang-desktop.service` + `prelockd.service` — proactive OOM
  protection; `systemd-oomd` is masked (nohang replaces it).
- `uresourced` — desktop-first resource management (GameMode-style).

### 8.5 Audio (PipeWire / WirePlumber)

- `pipewire.conf.d/20-vibes.conf` — `default.clock.quantum=256`,
  `max-buffers`, RT scheduling (`rt.prio`), RNNoise filter chain
  loaded from `librnnoise_ladspa.so` (stereo noise suppressor).
- `wireplumber.conf.d/20-vibes-policy.conf` — default sink/source
  volume 80/75 %, ALSA pro-audio profile with auto-profile/port off
  (deterministic routing), Bluetooth: A2DP preferred,
  `bluez5.codecs=[sbc aac aptx aptx_hd ldac]`, `a2dp-sink` default.
- `wireplumber.conf.d/50-vibes-gaming.conf` — session suspend disabled
  (`session.suspend-timeout-seconds=0`), priority boosting for
  game/Chromium/Brave streams.

### 8.6 systemd tuning

- `journald.conf.d`: `SystemMaxUse=4G`, `SystemKeepFree=1G`.
- `system.conf.d`: `DefaultTasksMax=infinity`-ish desktop values,
  `RuntimeWatchdogSec` disabled (games), `HibernateDelaySec` etc.
- `coredump.conf.d`: compression enabled.
- `user.conf.d`: delegate CPU etc. for the desktop user session.

### 8.7 Containers

- `/etc/containers/policy.json`: `default` scope =
  `insecureAcceptAnything`; the `ghcr.io/mheci/vibes` scope requires
  `sigstoreSigned` with `keyPath=/etc/pki/containers/vibes-cosign.pub`
  (exact-match: the pubkey shipped in the image equals `cosign.pub` in
  the repo root). Every `bootc upgrade` therefore verifies the cosign
  signature before applying.
- `containers/registries.conf`: unqualified-search registries minimal
  set, short-name mode `enforcing`.

### 8.8 SELinux

- `SELINUX=enforcing` (base). The Nix policy module
  (`/usr/share/selinux/packages/determinate-nix.pp`) is installed at
  build time and applied at boot by the `determinate-nix-selinux`
  unit so `/var/nix` works under enforcement.

### 8.9 tuned-ppd profile

`/etc/tuned/ppd.conf` maps the power profiles to tuned profiles
(performance → latency-performance, balanced → balanced, power-saver →
powersave). `tuned-ppd.service` is enabled; KDE's power profile
widget drives it.

### 8.10 sudo

`sudoers.d/99-vibes-wheel-nopasswd`: `%wheel ALL=(ALL) NOPASSWD: ALL`.
This is a deliberate desktop convenience (games/updates/firmware
without prompt loops); it is set `0440` by both the setup script and
the final strip module (the `files` module copies 0644, so the strip
module re-chmods). `sudo-rs` is installed as the sudo implementation
(memory-safe rewrite).

### 8.11 Flatpak / remote defaults

Flatpak remotes configured via recipe; the flathub remote is
pre-configured by the base. `flatpak-update` runs inside `vjust
update`.

---

## 9. The vjust command suite

`vjust` is a wrapper (`/usr/local/bin/vjust`) around
[just](https://github.com/casey/just) executing
`/usr/share/vibes/justfile`. All recipes (74 total):

### 9.1 System
`status` (kernel, image version, bootc/flatpak state), `update`
(`sudo bootc upgrade` + `flatpak update -y`), `reboot`, `poweroff`,
`journal`, `errors`, `boot-status`, `disk`, `mem`, `kernel`,
`firmware` (fwupd), `services`, `service-status <svc>`,
`service-restart <svc>`.

### 9.2 TPM & LUKS
- `tpm-status` — cryptenroll status + PCR dump (sudo).
- `tpm-enroll <dev>` — enroll TPM key slot (PCR 0+7).
- `tpm-recovery <dev>` — generate a recovery key slot.
- `tpm-pcrs` — list PCR values.
- `luks-status` — block layout + LUKS header dump of the first NVMe
  partition.
- `luks-header-backup <dev> <file>` / `luks-add-key <dev>` /
  `luks-remove-tpm <dev>`.
- **`luks-tpm-encrypt <dev>`** — full disk encryption with automatic
  unlock:
  1. Confirms interactively from `/dev/tty` (never consumes script
     stdin).
  2. Formats with `cryptsetup luksFormat --type luks2 --cipher
     aes-xts-plain64 --key-size 512` (passphrase slot 0).
  3. Enrolls the TPM: `systemd-cryptenroll --tpm2-device=auto
     --tpm2-pcrs=0+7`.
  4. Appends `<name> UUID=<uuid> none tpm2-device=auto` to
     `/etc/crypttab` (stable name `vault-<uuid8>`), `daemon-reload`.
  5. **No dracut step**: bootc images have read-only `/usr`; the
     initramfs is regenerated automatically at the next deployment and
     the crypttab generator picks the entry up.
  - Implemented as `/usr/libexec/vibes-luks-tpm-encrypt.sh` (root, no
    stdin conflicts).

### 9.3 DNS
- **`dns-encrypted [resolver]`** — writes
  `/etc/systemd/resolved.conf.d/encrypted-dns.conf`
  (`DNS=<resolver> 1.1.1.1 1.0.0.1`, `DNSOverTLS=yes`) and restarts
  systemd-resolved. Default resolver 1.1.1.1.
- `dns-status` — `resolvectl status` + live query test.
- `dns-default` — removes the drop-in and restores defaults.

### 9.4 Gaming
`sched-status` (scx ops + scx_loader), `sched-list`, `sched-set
<sched>`, `sched-cake`/`sched-cosmos`/`sched-lavd` (write the full
`/etc/scx_loader/config.toml` with mode flags and restart the loader),
`sched-config`, `memory-status` (uresourced/low-memory-monitor/nohang/
prelockd), `power-status` (tuned), `gamescope-version`, `steam`,
`steam-dev-cfg` (creates `steam_dev.cfg` with
`unShaderBackgroundProcessingThreads 16` and
`@nClientDownloadEnableHTTP2PlatformLinux 0`), `proton-list`,
`ntsync-status`.

### 9.5 NVIDIA / Flatpak / Nix / Audio / Hardware
`nvidia-status`, `nvidia-version`, `nvidia-kmod` (module inventory),
`gpu-watch` (nvidia-smi dmon), `flatpak-update`, `flatpak-clean`,
`flatpak-apps`, `nix-version`, `nix-gc`, `nix-info`, `audio-info`,
`audio-sinks`, `battery` (first detected battery), `temps`.

---

## 10. Security architecture

| Layer | Mechanism |
|---|---|
| Image signing | cosign key pair; private key only in `SIGNING_SECRET` (passwordless, empty-file-passphrase); public key in repo + image |
| Upgrade policy | `/etc/containers/policy.json` sigstoreSigned for the vibes scope |
| CI credentials | `persist-credentials: false` on every checkout that doesn't push; least-privilege `permissions:` blocks; signing key passed via env, never echoed into logs |
| Third-party actions | All pinned to immutable SHAs with version comments (CodeQL, trivy, sbom-action, stale, blue-build, free-disk-space, cosign) |
| Releases | `release.yml`: verify signature → capture digest → SBOM (SPDX) attested with cosign → SLSA provenance attestation (in-toto Statement v0.1, slsa.dev/provenance/v0.2 predicate, builder = the workflow) → GitHub Release with assets |
| Scanning | Trivy repo scan on every push/PR (fs, medium+), weekly image scan of `:latest` (skip when image unchanged); CodeQL for actions/python |
| Secrets | GitHub masked; key material only ever in runner temp files, deleted in the same step |
| Boot integrity | UKI support (systemd-ukify), greenboot health checks, rollback |
| Supply chain | Pinned downloads where upstream publishes pins (proton-cachyos sha512, Darkly/anacony/nohang/prelockd/MoreWaita commit pins, nix-installer tag-verified binary, GitHub tag pins for qui/apple_cursor); master-based builds (scx family) intentionally latest |

---

## 11. CI/CD pipeline

### 11.1 Workflows

| Workflow | Triggers | Purpose |
|---|---|---|
| `validate.yml` | push/PR (path-filtered) | `bash -n` + shellcheck (-S style) on all scripts, actionlint on workflows, yamllint on workflows+recipes, `validate_recipe.py` (module layout, flatpak refs, pin policy) |
| `build.yml` | push/PR/schedule (daily)/dispatch | The image build (§5). PR-open skip kills duplicate push builds |
| `boot.yml` | daily + dispatch | §12 |
| `trivy.yml` | push/PR + weekly | Repository filesystem scan + image scan |
| `codeql.yml` | push/PR | CodeQL actions + python analysis |
| `reproducibility.yml` | weekly | Rebuild from scratch, no layer cache, chunked-OCI; reports local tags + **package drift diff vs :latest** |
| `upstream-health.yml` | weekly | Checks every pinned tag/commit/repo and COPR/asset URLs (§8.7 of the script) |
| `release.yml` | tag `v*` | §10 |
| `stale.yml` | daily | PR/issue staleness |

### 11.2 Concurrency

- build.yml: `group = workflow + ref + event_name` — a scheduled build
  no longer cancels an in-flight push build and vice versa.
- boot.yml: `group = workflow + ref + image_ref` — manual runs against
  different images run in parallel; identical runs cancel each other.
- Each workflow declares minimal `permissions` (contents read; build
  adds packages write + pull-requests read + id-token write; release
  adds contents write, actions read, packages read).

### 11.3 Merge discipline

`main` is protected: required status check "Shell, workflow & recipe
validation", linear history (squash merges only), force-push disabled,
administrator enforcement. Every change lands via PR; the daily build
runs against `main` after the merge.

---

## 12. Boot testing infrastructure

`boot.yml` runs three QEMU jobs against the freshly built image
(default `ghcr.io/mheci/vibes:latest`, overridable via `image_ref`):

### 12.1 Boot test (QEMU)

1. cosign-verify the image with `cosign.pub` (no pipe, no masking).
2. `bootc install to-disk --generic-image --via-loopback
   --filesystem xfs --karg console=ttyS0,115200
   --karg systemd.unit=multi-user.target` into a 32G raw disk,
   executed inside a privileged podman container of the image itself
   (`BOOTC_DIRECT_IO=on`, `/dev` and `/var/lib/containers` mounted).
3. Boots with `qemu-system-x86_64` (`-machine accel=tcg` fallback,
   KVM when available, `-nographic`, serial pipe).
4. Serial I/O via FIFO: `exec 3>ser.in` for host→guest,
   `(cat ser.out > serial.log)` for guest→host. The guest echoes
   `UP_MARK_N` markers; the host polls `serial.log` and drives the
   guest by writing commands into the pipe (autologin console). Boot
   is certified when a shell responds.

### 12.2 Upgrade path test

Installs `:previous`, boots (UP_MARK_1), captures the initial
deployment digest (`bootc status` sha256), runs `bootc upgrade --tag
latest` (explicit tag — the deployment was installed from `:previous`;
`--tag latest` guarantees the newest build is fetched), verifies the
output, reboots (UP_MARK_2), verifies `bootc status` references
`ghcr.io/<owner>/vibes:latest`, confirms the digest CHANGED, then runs
`bootc rollback`, reboots (UP_MARK_3) and verifies the digest equals
the initial one — the full forward/backward certification.

### 12.3 UEFI boot test

1. Installs `ovmf` (firmware for `qemu-system-x86_64`).
2. Builds the disk image as above, attaches the ESP via loopback
   (`losetup -P`, partition 1), asserts `systemd-bootx64.efi` exists
   and counts unified kernel images in `/EFI/Linux` (UKI support is
   required, so at least one must exist).
3. Boots with the OVMF pflash pair: read-only
   `/usr/share/OVMF/OVMF_CODE_4M.fd` + a COPIED writable
   `OVMF_VARS_4M.fd` (fallbacks `OVMF_CODE.fd`/`OVMF_VARS.fd`),
   same serial-pipe protocol, certifies the shell.
4. Uploads `uefi-serial-log` on failure for post-mortem.

Every job uploads its serial log as an artifact so failures are
debuggable byte-for-byte.

---

## 13. Performance tuning

- **Scheduler**: sched-ext (scx_lavd default, scx_cake/scx_cosmos
  switchable via `vjust sched-*`), loaded by `scx_loader`; Gamescope
  gets `CAP_SYS_NICE`.
- **CPU**: `latency-performance` tuned profile on AC; split-lock off;
  no watchdogs; `sysctl` watermark boost tuned for low-latency
  wakeups.
- **Network**: `fq` qdisc + `bbr3` congestion control; VS Code/Steam
  download flags tuned in `steam_dev.cfg` (HTTP2 off reduces TCP
  overhead on high-latency links).
- **GPU**: VRR always-on + tearing-allowed compositing, NVIDIA
  env-var stack, 100 GiB shader cache, NVMe power-state transitions
  disabled.
- **Memory**: zram, nohang (OOM with desktop-friendly kills) instead
  of systemd-oomd, prelockd (lock hot libraries), uresourced
  (GameMode-style priorities), BBR3 for throughput.
- **Audio**: RT pipewire, quantum 256, RNNoise, pro-audio routing
  (no resampling), A2DP codec priority.
- **Build**: incremental cargo/ninja/cmake caches across builds, dnf
  metadata kept between modules, single build per commit, chunked OCI
  (fast upgrades), build runs on `ubuntu-latest` with forced
  free-disk-space purge before chunking (2x image size transient).

---

## 14. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `vjust` prints nothing/parse error | Not possible in this build (justfile verified with just 1.39 in CI); older images had heredoc/attribute parse bugs — update |
| Greenboot rolls back unexpectedly | `journalctl -b -1 -u greenboot*`; check `bootc status`; the warning check allowlist covers vconsole/boot-token units |
| `vibes-update-check` never notifies | Unit is `oneshot` + timer Mon 09:00; check `systemctl --failed` (exec bit regression would fail it — smoke-checked in CI now) |
| LUKS auto-unlock fails after `luks-tpm-encrypt` | The TPM seal binds PCR 0+7; a kernel/firmware update changes PCRs → fall back to the passphrase slot and re-enroll |
| Encrypted DNS not applied | `resolvectl status` shows the DNS servers; ensure the resolver supports DoT (1.1.1.1/1.0.0.1 do) |
| Image signature check failed | Registry or key drift; `cosign verify --key cosign.pub ghcr.io/mheci/vibes:latest` locally |
| `bootc upgrade` finds no update | You are current; `:previous` is kept by the pipeline |
| Long GitHub outage cancels builds | Jobs cancelled while queued (seen once); re-run via workflow_dispatch |
| NVIDIA apps stutter after suspend | `nvme_core.default_ps_max_latency_us=0` is a karg — check `cat /proc/cmdline`; if missing, the deployment predates the karg |

---

## 15. Reproducing a release

```bash
# 1. Main build (also runs boot tests)
gh workflow run build.yml -R mheci/vibes --ref main
gh run watch

# 2. Boot certification (boot, upgrade+rollback, UEFI)
gh workflow run boot.yml -R mheci/vibes --ref main

# 3. Release (v* tag)
git tag v0.1.0
git push origin v0.1.0
# release.yml: verify -> digest -> SBOM -> SPGBOM attestation ->
# SLSA provenance attestation -> GitHub Release
```

The provenance attestation subject digest equals the digest captured
by `cosign verify -o json` (`.critical.image.docker-manifest-digest`),
linking the release to the exact signed manifest.

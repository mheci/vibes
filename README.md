# Vibes

<p align="center"><img src="assets/vibes-mascot.svg" width="160" alt="Vibes mascot"></p>

Vibes is a GNOME workstation image made for gaming, creating and developing
on NVIDIA hardware. It is built on top of Bluefin (NVIDIA Open) with
BlueBuild, and it ships the CachyOS BORE kernel with NVIDIA open drivers
rebuilt for it, plus a curated set of games, browsers, chat apps and developer
tools.

**Base image:** `ghcr.io/ublue-os/bluefin-nvidia-open:latest`
**Output image:** `ghcr.io/mheci/vibes:latest`

[![build](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml)
[![validate](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)
[![boot](https://github.com/mheci/vibes/actions/workflows/boot.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/boot.yml)
[![codeql](https://github.com/mheci/vibes/actions/workflows/codeql.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/codeql.yml)
[![trivy](https://github.com/mheci/vibes/actions/workflows/trivy.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/trivy.yml)
[![reproducibility](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml)
[![upstream-health](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml)

## What You Get

### Gaming

- CachyOS BORE kernel from the official Fedora COPR, with NVIDIA open kernel
  modules rebuilt in the image to match it.
- Steam, Gamescope and MangoHud.
- proton-cachyos installed as the system-wide Steam compatibility tool
  (sha512 verified against the upstream release).
- Faugus Launcher for running Windows games through Wine and Proton.
- LACT for GPU overclocking and fan control.
- sched-ext schedulers (scx_lavd in Gaming mode) and ananicy-cpp for smooth
  desktop response.
- A custom mutter build that adds desktop tearing and variable refresh rate.
- A 100 GiB NVIDIA shader disk cache so games do not stutter while
  recompiling shaders.

### Browsers

- Zen Browser, Brave Origin and Helium, all from official or maintained
  sources.
- Hardware video decoding is configured for every browser, including on
  NVIDIA.
- Firefox is not included.

### Chat and Social

- Ferdium, one app for WhatsApp, Telegram, Slack and more, from the official
  release RPM.
- Element for Matrix, always the newest desktop build.
- karere (WhatsApp Web, Flatpak), Mailspring and Nicotine+.
- GSConnect for phone-to-desktop integration.

### Media

- Lollypop and Rhythmbox for music.
- Fragments for torrents.
- Memento to track movies and TV shows you watched.
- mpv with hardware decode, plus the full ffmpeg and GStreamer codec stack.

### Development and AI

- Zed, VS Code, opencode CLI and desktop app, T3 Code and Helix.
- Nix (Determinate Systems installer) with the store in persistent
  `/var/nix`, a socket-activated daemon and SELinux policy at first boot.
- uv, Bun, Deno, Node.js, GitHub CLI, yt-dlp, zoxide and just.
- tmux and zellij for terminal sessions.
- LM Studio for local LLMs, plus the Vicinae launcher with its GNOME
  extension.
- bpftune, a BPF-based system tuning daemon.

### Virtualization

- GNOME Boxes, built from the newest upstream source at image build time, for
  running virtual machines.
- Pods, DistroShelf, Lobjur and RustConn as Flatpaks for containers and
  remote connections.

### Under the Hood

- PipeWire tuned for gaming and voice: fixed 48 kHz, realtime scheduling,
  RNNoise noise suppression and high-quality Bluetooth codecs.
- NVIDIA acceleration defaults for Wayland and video, and persistent cache
  paths for every toolkit.
- Memory management with uresourced, low-memory-monitor (warn only), nohang
  and prelockd.
- Power management with tuned and tuned-ppd, defaulting to the
  latency-performance profile.
- Quiet system tuning: BBR networking, gaming memory limits, capped logs.
- `vjust`, a just command runner with recipes for system, TPM, LUKS, gaming,
  NVIDIA, Flatpak, Nix and audio tasks.

```bash
vjust          # list all recipes
vjust sched-set scx_bpfland
vjust tpm-status
```

## Getting Started

Rebase an existing Atomic Fedora installation:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/mheci/vibes:latest
systemctl reboot
```

The `latest` tag always tracks the newest successful `main` build on
Fedora 44.

## Verify the Image

Images are signed with Sigstore cosign. The public key is `cosign.pub` in
the repository root.

```bash
cosign verify --key cosign.pub ghcr.io/mheci/vibes:latest
```

## Stay Up to Date

Automated builds run daily at 06:00 UTC and on every push to `main`. The
image is chunked into balanced OCI layers, so updates download only the parts
that changed since your last version.

```bash
rpm-ostree upgrade
# or
bootc upgrade
```

## Releases

Tagged releases (`v*`) are created by the
[release workflow](https://github.com/mheci/vibes/actions/workflows/release.yml).
Each release verifies the image signature, records the verified digest and
attaches an SPDX SBOM.

## How It Is Built

| Stage | Description |
| --- | --- |
| Validate | shellcheck, actionlint, yamllint, markdownlint and recipe checks |
| Build | BlueBuild layers repositories, RPMs, themes, upstream binaries and system configs onto Bluefin NVIDIA Open, then re-chunks the image into balanced OCI layers |
| Lint | `bootc container lint` runs inside the recipe |
| Sign | Image signed with a cosign private key stored in GitHub Secrets |
| Scan | Trivy scans the repository on every push and the published image weekly |
| Push | Published to `ghcr.io/mheci/vibes:latest` |
| Boot | Daily QEMU boot test boots the image to the login prompt |
| OpenQA | Daily headless boot test with os-autoinst |
| Reproducibility | Weekly no-cache rebuild that catches upstream breakage |
| Upstream Health | Weekly check that every URL and release-asset pattern used by the scripts still resolves |
| Release | Tagged releases verify the signature and attach an SBOM |

The build strips the compiler toolchains after everything is compiled, which
keeps the finished image lean. Runs triggered by Dependabot or forks skip the
image build because signing secrets are unavailable to them; validation still
runs in full.

## Package Policy

Software is added in the following order of preference:

1. Fedora repositories and official vendor RPM repos.
2. GitLab or GitHub release RPMs, with the latest asset installed through
   DNF.
3. Direct release artifacts (binaries, AppImages) installed system-wide.
4. Flatpaks, as the very last resort.

Applications that only exist in language package managers (npm, uv or pip,
crates.io, Go modules) are not baked into the image. The package managers
themselves are installed from Fedora packages, but end-user tools must ship
through the sources above so they update reliably and carry correct SELinux
labels.

## Development

```bash
python3 .github/scripts/validate_recipe.py
cd files/scripts && shellcheck -S style *.sh
bash -n files/scripts/*.sh
```

Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md)

## Project Links

- **Source:** [github.com/mheci/vibes](https://github.com/mheci/vibes)
- **Issues:** [github.com/mheci/vibes/issues](https://github.com/mheci/vibes/issues)
- **Discussions:** [github.com/mheci/vibes/discussions](https://github.com/mheci/vibes/discussions)
- **Security:** [SECURITY.md](SECURITY.md)
- **Support:** [SUPPORT.md](SUPPORT.md)

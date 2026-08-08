# Vibes

<p align="center"><img src="assets/vibes-mascot.svg" width="160" alt="Vibes mascot"></p>

Vibes is a KDE Plasma workstation image for NVIDIA hardware. It layers the
CachyOS BORE kernel with in-image NVIDIA driver builds, a curated toolset and
quiet system tuning onto Aurora, and publishes signed, chunked images that
update quickly.

**Base image:** `ghcr.io/ublue-os/aurora-nvidia-open:stable`
**Output image:** `ghcr.io/mheci/vibes:latest`

[![build](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml)
[![validate](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)
[![boot](https://github.com/mheci/vibes/actions/workflows/boot.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/boot.yml)
[![codeql](https://github.com/mheci/vibes/actions/workflows/codeql.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/codeql.yml)
[![trivy](https://github.com/mheci/vibes/actions/workflows/trivy.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/trivy.yml)
[![reproducibility](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/reproducibility.yml)
[![upstream-health](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/upstream-health.yml)

## Highlights

| Area | What the image ships |
| --- | --- |
| Kernel | CachyOS BORE kernel (COPR), NVIDIA open modules rebuilt in the image, stock kernel removed and version-locked, initramfs generated for the new kernel |
| Graphics | KDE Plasma with variable refresh rate and tearing enabled, Klassy window decorations, 100 GiB shader cache, Wayland and VA-API defaults |
| Gaming | Steam, Gamescope (with CAP_SYS_NICE), MangoHud, proton-cachyos (sha512 verified), Faugus Launcher, LACT, sched-ext schedulers with the scx-manager GUI, one-command switching between scx_cake, scx_cosmos and scx_lavd, ananicy-cpp with the CachyOS ruleset |
| Browsers | Zen Browser, Brave Origin, Helium, with hardware video decoding configured |
| Messaging | Ferdium (WhatsApp, Telegram, Slack and more), Commet for Matrix, karere, Mailspring, Nicotine+, KDE Connect |
| Media | Lollypop, Rhythmbox, Fragments, Memento, qBittorrent with the qui web UI, mpv with hardware decode, full ffmpeg and GStreamer codec stack |
| File managers | Dolphin by default, Nautilus with the full GVFS stack (MTP, SMB, AFP, archive, FUSE, NFS, GOA, gphoto2), GNOME Disks |
| Network | Sniffnet for network monitoring, Glance self-hosted dashboard, qui web UI for qBittorrent |
| Development | Zed, VS Code, opencode, T3 Code, Helix, Nix (persistent `/var/nix`), uv, Bun, Deno, Node.js, GitHub CLI, yt-dlp, tmux, zellij, bat, eza, fd, ripgrep, fzf, duf, bottom |
| AI | LM Studio, Vicinae launcher |
| Virtualization | GNOME Boxes built from the newest upstream source, Pods, DistroShelf, Lobjur (Lobsters and Hacker News client), RustConn |
| Security | cosign signing with signature-verified upgrades, Trivy scanning, sudo-rs, SELinux gaming tuning, UKI support, GitHub Actions pinned to exact SHAs |
| System | PipeWire tuned for voice and gaming, uresourced, nohang, prelockd, tuned with latency-performance, BBR networking, KDE defaults (Breeze Dark, Inter), automatic updates off with a weekly update notification, greenboot health checks with automatic rollback, `vjust` command recipes (including LUKS + TPM encryption and encrypted DNS) |

The full list of packages, Flatpaks and extensions lives in
[`recipes/recipe.yml`](recipes/recipe.yml) and the build scripts under
[`files/scripts`](files/scripts).

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

Updates are applied manually: the image does not upgrade itself. A weekly
check (Monday at 09:00) shows a desktop notification when an OS update is
available, and nothing more happens until you run:

```bash
sudo bootc upgrade
systemctl reboot
```

Every upgrade is verified against the embedded cosign public key before it
is applied. Signature verification is enforced for the vibes image itself
(`/etc/containers/policy.json`); other container images pulled on the system
fall back to the system policy defaults.

## Releases

Tagged releases (`v*`) are created by the
[release workflow](https://github.com/mheci/vibes/actions/workflows/release.yml).
Each release verifies the image signature, records the verified digest and
attaches an SPDX SBOM attested to the image with cosign.

## How It Is Built

| Stage | Description |
| --- | --- |
| Validate | shellcheck, actionlint, yamllint, markdownlint and recipe checks |
| Build | BlueBuild layers repositories, RPMs, themes, upstream binaries and system configs onto Aurora NVIDIA Open, then re-chunks the image into balanced OCI layers |
| Lint | `bootc container lint` runs inside the recipe |
| Sign | Image signed with a cosign private key stored in GitHub Secrets |
| Scan | Trivy scans the repository on every push and the published image weekly |
| Push | Published to `ghcr.io/mheci/vibes:latest` |

The complete low-level reference — installation, build architecture,
every configuration file, the vjust suite, the CI/CD pipeline, the
boot-test infrastructure and troubleshooting — lives in
[docs/TECHNICAL.md](docs/TECHNICAL.md).
| Boot | Daily QEMU boot test (BIOS and UEFI) plus an upgrade-path test that boots the previous image, applies `bootc upgrade`, reboots and certifies `bootc rollback` |
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

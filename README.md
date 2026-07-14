# vibes &nbsp; [![bluebuild build badge](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml) [![validate-image badge](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)

Personal Bazzite NVIDIA Open gaming, media, and AI workstation image built with [BlueBuild](https://blue-build.org/).

Current base: `ghcr.io/ublue-os/bazzite-nvidia-open:latest` → published as `ghcr.io/mheci/vibes`.

## What's inside

- **Base**: Bazzite NVIDIA Open (latest)
- **Browsers**: Firefox (RPM), Brave Origin (with uBlock Origin policy), Waterfox (RPM + Flatpak)
- **Development**: VS Code, Zed, opencode CLI + Desktop, Heroic Games Launcher
- **AI**: LM Studio, Vicinae launcher
- **Gaming**: Faugus Launcher, umu-launcher, LACT, MangoHud, GameScope, scx LAVD scheduler (performance mode)
- **Audio**: High-quality PipeWire + WirePlumber configs, RNNoise stereo noise suppression
- **GPU**: NVIDIA Open kernel modules, VAAPI/VDPAU/NVD acceleration defaults
- **Themes**: Darkly, Beauty-Plasma-Themes, macOS cursor packs
- **System**: bpftune enabled, comprehensive codec & thumbnail support, nerd fonts, Arabic + English spellcheck

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/mheci/vibes:latest
  ```
- Reboot again to complete the installation:
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## Validation

Every successful build triggers a comprehensive validation pipeline:

- **Static validation**: cosign signature verification, `bootc container lint`, filesystem smoke checks for critical binaries and configs
- **Security scanning**: Trivy CVE scan (CRITICAL + HIGH, unfixed only) with SARIF upload to GitHub Security tab
- **KVM boot test**: Full qcow2 conversion via `bootc-image-builder` and QEMU/KVM boot with nested virtualization
- **In-VM QA**: SSH-based health checks — kernel panics, systemd failures, GPU acceleration, audio stack, critical packages, fonts, spellcheck dictionaries

## ISO

If building on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/how-to/generate-iso/#_top). These ISOs cannot be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/mheci/vibes
```

# vibes &nbsp; [![repo-ci badge](https://github.com/mheci/vibes/actions/workflows/ci.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/ci.yml) [![bluebuild build badge](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml) [![validate-image badge](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)

Personal Bazzite NVIDIA Open gaming, media, and AI workstation image built with [BlueBuild](https://blue-build.org/).

Current base: `ghcr.io/ublue-os/bazzite-nvidia-open:latest` → published as `ghcr.io/mheci/vibes`.

## What's inside

- **Base**: Bazzite NVIDIA Open (latest)
- **Browsers**: Waterfox (RPM + Flatpak), Brave Origin (RPM with uBlock Origin policy), Firefox (RPM replacing Flatpak)
- **Development**: VS Code, Zed, opencode CLI + Desktop, Heroic Games Launcher
- **AI**: LM Studio, Vicinae launcher
- **Gaming**: Steam + steam-devices, Faugus Launcher, Heroic, Lutris, umu-launcher, MangoHud, GameScope, Proton helpers, scx LAVD scheduler (performance mode)
- **Audio**: High-quality PipeWire + WirePlumber configs, RNNoise stereo noise suppression
- **GPU**: Latest Bazzite NVIDIA Open base plus layered NVIDIA userspace / akmod tooling, VAAPI/VDPAU/NVD acceleration defaults
- **Themes**: Darkly Qt + GTK, Beauty Plasma Themes, macOsTahoeKdeTheme bundle, WhiteSur KDE, McMojave KDE, WhiteSur cursors, macOS-style cursor variants
- **System**: Terra stable + extras configured, comprehensive codec & thumbnail support, development fonts, Arabic + English spellcheck

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
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

Validated releases are promoted to `latest` and `stable` only after the full build, smoke, security, and KVM boot pipeline passes. In-progress builds publish only to the internal `candidate` tag. The image still follows the Fedora version specified in `recipes/recipe.yml`, so you won't get accidentally updated to the next major version.

## Validation

The pipeline is intentionally split into three layers so PR checks stay fast while release validation stays strict:

- **Repository CI (`repo-ci`)**: runs on pushes and pull requests to validate workflow YAML, shell syntax, and action wiring without needing signing secrets.
- **Release pipeline (`bluebuild`)**: builds a non-user-facing `candidate` image, resolves the immutable digest, runs `bootc container lint`, performs filesystem/package/theme smoke checks, runs Trivy SARIF + advisory reporting, boots the image in QEMU/KVM, executes in-VM QA, and only then promotes the exact validated digest to `stable` and `latest`.
- **Continuous revalidation (`validate-image`)**: scheduled/manual smoke + Trivy + KVM revalidation against `stable` (or any explicitly supplied image reference).

This means users never see a freshly built but untested tag, and every published update must survive container checks, security advisory generation, and a full virtual-machine boot before promotion.

## ISO

If building on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/how-to/generate-iso/#_top). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). Promoted builds are available as `stable`, `latest`, and immutable `sha-<commit>` tags. You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/mheci/vibes
```

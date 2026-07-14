# ✨ vibes

### *vibe-code your way to the perfect desktop* 🚀

[![bluebuild build badge](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml) [![iso build badge](https://github.com/mheci/vibes/actions/workflows/iso.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/iso.yml)

> **the vibe**: a buttery-smooth, gpu-accelerated, ai-ready workstation that just *feels* right.

built on [bluebuild](https://blue-build.org/) and [bazzite](https://bazzite.gg/) — because life's too short for broken configs and boot loops.

---

## 🎨 what's the vibe?

```
ghcr.io/ublue-os/bazzite-nvidia-open:latest → ghcr.io/mheci/vibes
```

### 🎮 gaming
heroic games launcher · faugus launcher · umu-launcher · lact gpu control · mangohud · gamescope · scx lavd scheduler (gaming mode, always performance)

### 💻 development
vs code · zed · opencode cli + desktop · kitty terminal

### 🤖 ai / ml
lm studio · vicinae launcher · nvidia container toolkit

### 🌐 browsing
firefox (rpm, hardware-accelerated) · brave origin (ublock origin pre-installed)

### 🎵 audio
pipewire + wireplumber tuned for low-latency · rnnoise stereo noise suppression · realtime scheduling · 48khz default · bluetooth a2dp-first

### 🖥️ desktop polish
darkly theme · beauty-plasma-themes · macos cursor packs · qt disk shader cache force-enabled · nvidia vaapi/vdpau/nvd acceleration · wayland-first

### 📦 multimedia
ffmpeg · gstreamer full suite · vaapi · h264/h265/av1/vp9 · thumbnails for everything · heif/jxl/webp/raw support

### 🔤 fonts & language
nerd fonts · jetbrains mono · fira code · cascadia code · noto arabic · hunspell en + ar spellcheck

---

## 🚀 installation

### via iso
download the latest iso from the [actions tab](https://github.com/mheci/vibes/actions/workflows/iso.yml) (click the most recent successful run → artifacts section at the bottom), flash it to a usb with [fedora media writer](https://www.fedoraproject.org/en/workstation/download) or [balena etcher](https://etcher.balena.io/), and boot it.

### via rebase
> ⚠️ **atomic rebasing is experimental** — you've been warned

rebase an existing atomic fedora install to the latest build:

```bash
# step 1: rebase to unsigned image (gets signing keys installed)
rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest

# step 2: reboot
systemctl reboot

# step 3: rebase to signed image (verifies the real deal)
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/mheci/vibes:latest

# step 4: final reboot
systemctl reboot
```

*the `latest` tag always points to the most recent build. you won't accidentally jump major versions.*

---

## 🔐 verification

images are signed with [sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign).

```bash
# grab the public key from this repo, then:
cosign verify --key cosign.pub ghcr.io/mheci/vibes
```

---

*no waterfox. no fluff. just vibes.* ✨

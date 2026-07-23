# ✨ vibes

**The perfect desktop for gaming, media, and AI workflows** 🚀

[![bluebuild build badge](https://github.com/mheci/vibes/actions/workflows/build.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/build.yml)
[![iso build badge](https://github.com/mheci/vibes/actions/workflows/iso.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/iso.yml)
[![validate badge](https://github.com/mheci/vibes/actions/workflows/validate.yml/badge.svg)](https://github.com/mheci/vibes/actions/workflows/validate.yml)

A buttery-smooth, GPU-accelerated, AI-ready workstation built on [BlueBuild](https://blue-build.org/) and [Bazzite](https://bazzite.gg/). No broken configs, no boot loops, just vibes.

**Base Image:** `ghcr.io/ublue-os/bazzite-nvidia-open:latest` → `ghcr.io/mheci/vibes`

---

## 📦 What's Included

### 🎮 Gaming
- **Heroic Games Launcher** - Epic Games, GOG, and Amazon Games
- **Faugus Launcher** - Proton launcher with advanced features
- **umu-launcher** - Universal Proton launcher
- **LACT** - GPU monitoring and overclocking tool
- **MangoHud** - Performance monitoring overlay
- **Gamescope** - Micro-compositor for gaming
- **scx LAVD Scheduler** - Gaming-focused CPU scheduler

### 💻 Development
- **VS Code** - Full-featured code editor
- **Zed** - High-performance code editor
- **OpenCode** - AI coding assistant (CLI + Desktop)
- **Kitty** - GPU-accelerated terminal emulator

### 🤖 AI / ML
- **LM Studio** - Local LLM inference
- **Vicinae** - AI-powered launcher
- **NVIDIA Container Toolkit** - GPU acceleration for containers

### 🌐 Browsing
- **Firefox** - RPM package with hardware acceleration
- **Brave Origin** - Privacy-focused browser with uBlock Origin pre-installed

### 🎵 Audio
- **PipeWire** - Low-latency audio/video routing
- **WirePlumber** - Session manager for PipeWire
- **RNNoise** - Stereo noise suppression
- **48kHz default** - Professional audio quality
- **Bluetooth A2DP** - High-quality audio streaming

### 🖥️ Desktop
- **KDE Plasma** - Wayland-first desktop environment
- **Darkly Theme** - Modern dark theme
- **Beauty Plasma Themes** - Additional theme collection
- **macOS Cursor Packs** - Polished cursor themes
- **Qt Disk Shader Cache** - Optimized desktop performance
- **NVIDIA Hardware Acceleration** - VA-API/VDPAU/NVD

### 📦 Multimedia
- **FFmpeg** - Complete codec support
- **GStreamer** - Full multimedia framework
- **Hardware Acceleration** - VA-API for video decoding
- **Codecs** - H.264/H.265/AV1/VP9
- **Thumbnailers** - HEIF/JXL/WebP/RAW support

### 🔤 Fonts & Language
- **Nerd Fonts** - Developer-friendly fonts
- **JetBrains Mono** - Coding font
- **Fira Code** - Programming font with ligatures
- **Cascadia Code** - Microsoft's coding font
- **Noto Arabic** - Complete Arabic language support
- **Spellcheck** - English and Arabic dictionaries

### 🛠️ System Utilities
- **Gear Lever** - AppImage manager
- **LACT** - GPU monitoring and overclocking
- **bpftune** - BPF-based network auto-tuning
- **scx-tools** - Scheduler ext tools

---

## 🚀 Installation

### Option 1: ISO Installation (Recommended)

> 💡 **Tip:** GitHub requires you to be signed in to download build artifacts.

1. Download the latest ISO from [GitHub Actions](https://github.com/mheci/vibes/actions/workflows/iso.yml)
2. Click the most recent successful build
3. Download the artifact from the "Artifacts" section
4. Flash to USB using [Fedora Media Writer](https://www.fedoraproject.org/en/workstation/download) or [Balena Etcher](https://etcher.balena.io/)
5. Boot from USB and install

### Option 2: Rebase Existing Atomic Fedora

> ⚠️ **Note:** Atomic rebasing is experimental. Proceed with caution.

```bash
# Step 1: Rebase to unsigned image (installs signing keys)
rpm-ostree rebase ostree-unverified-registry:ghcr.io/mheci/vibes:latest

# Step 2: Reboot
systemctl reboot

# Step 3: Rebase to signed image (verifies authenticity)
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/mheci/vibes:latest

# Step 4: Final reboot
systemctl reboot
```

The `latest` tag always points to the most recent build. You won't accidentally jump to a new major version.

---

## 🔐 Image Verification

All images are cryptographically signed with [Sigstore cosign](https://www.sigstore.dev/).

```bash
# Verify the image signature
cosign verify --key cosign.pub ghcr.io/mheci/vibes
```

---

## 🏗️ Build Pipeline

- **Daily Builds:** Automatic builds at 06:00 UTC
- **Fast Validation:** ShellCheck + actionlint + recipe structure checks gate every push/PR in seconds
- **Cosign Signing:** Every image is signed for authenticity
- **Layer Caching:** Optimized build times
- **ISO Generation:** Automated ISO creation after successful `main` branch builds
- **Pinned Tooling:** Third-party actions and lint tools are version- and checksum-pinned

---

## 📝 Notes

- Firefox is installed as an RPM (not Flatpak) for better codec support
- Brave includes uBlock Origin as a forced extension
- NVIDIA drivers are open-source (`nvidia-open-dkms`)
- All packages are verified against official repositories
- Build artifacts are cached for faster subsequent builds

---

*No bloat. No fluff. Just vibes.* ✨

# Changelog

All notable changes to the Vibes OCI image are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Base image migrated from Bluefin (GNOME) to Aurora (KDE Plasma) NVIDIA
  Open on the stable stream. GNOME-only pieces were removed: the custom
  mutter build, GNOME extensions, GSConnect (replaced by KDE Connect),
  dconf theming and GNOME power defaults.
- KDE defaults shipped: variable refresh rate and tearing enabled in KWin,
  PowerDevil on the performance profile, Breeze Dark with the Inter font.
- Automatic upgrades and automatic updates are disabled. A weekly check
  (Monday 09:00) only notifies the user when an OS update is available.
- sched-ext and scx-loader are built from their master branches again
  (the newest schedulers and tools, including scxtui).
- GNOME Boxes and the ananicy rules are pinned to their latest upstream
  release tags instead of HEAD builds.
- A system-wide fontconfig profile renders text with full hinting and LCD
  subpixel filtering for sharp, clear glyphs on 1080p and 1440p displays.
- `vjust steam-dev-cfg` writes the Steam development config
  (unShaderBackgroundProcessingThreads 16 and
  @nClientDownloadEnableHTTP2PlatformLinux 0) into
  ~/.steam/steam/steam_dev.cfg; new users get the same defaults from
  /etc/skel.
- Gamescope runs with CAP_SYS_NICE applied at build time and reapplied
  at every boot by a oneshot unit.
- scx-manager (CachyOS GUI for sched-ext schedulers) built from master.
- Klassy window decorations and themes built from master.
- Nautilus with the full GVFS backend set (MTP, SMB, AFP, archive, FUSE,
  NFS, GOA, gphoto2), GNOME Disks and Dolphin available as file managers.
- The OpenQA workflow was removed: its coverage is fully provided by the
  QEMU boot test in the boot workflow.
- bottom is installed from its official GitHub release (not packaged in
  Fedora 44).
- Images are verified against the embedded cosign public key before an
  upgrade is applied, and UKI generation is supported.
- Third-party GitHub Actions are pinned to immutable commit SHAs.
- The OpenQA boot test no longer fails on a missing needles directory.
- A QEMU upgrade-path test boots the previous image, upgrades to `:latest`
  and reboots into the new deployment.

### Added

- Ferdium messaging client from the official release RPM, replacing Whatsie.
- Commet (Matrix client), newest portable build, replacing Element.
- CachyOS ananicy rules for the ananicy-cpp daemon.
- tmux, zellij, Lollypop, Rhythmbox, Fragments, qBittorrent and the qui web
  UI, Glance and Memento.
- GNOME Boxes built from the newest upstream source at image build time.
- Trivy vulnerability scanner in the image and as CI scans.
- 100 GiB NVIDIA shader disk cache.
- Developer utilities: bat, eza, fd-find, ripgrep, fzf, duf, bottom.
- Glance ships a default dashboard config and a user service.
- Tagged releases attest the SBOM to the image with cosign.
- The `:previous` image tag is maintained for rollback and upgrade tests.

### Removed

- Whatsie, Hermes Agent, Element and Firefox (RPM and Flatpak).
- Build toolchains are stripped from the finished image after compilation.

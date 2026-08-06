# Changelog

All notable changes to the Vibes OCI image are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Base image migrated from Bluefin (GNOME) to Aurora (KDE Plasma) NVIDIA
  Open on the stable stream. GNOME-only pieces were removed: the custom
  mutter build, GNOME extensions, GSConnect (replaced by KDE Connect),
  dconf theming and GNOME power defaults.

### Added

- Ferdium messaging client from the official release RPM, replacing Whatsie.
- Commet (Matrix client), newest portable build, replacing Element.
- CachyOS ananicy rules for the ananicy-cpp daemon.
- tmux, zellij, Lollypop, Rhythmbox, Fragments, qBittorrent and the qui web
  UI, Glance and Memento.
- GNOME Boxes built from the newest upstream source at image build time.
- Trivy vulnerability scanner in the image and as CI scans.
- 100 GiB NVIDIA shader disk cache.

### Removed

- Whatsie, Hermes Agent, Element and Firefox (RPM and Flatpak).
- Build toolchains are stripped from the finished image after compilation.

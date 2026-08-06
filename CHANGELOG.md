# Changelog

All notable changes to the Vibes OCI image are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Ferdium messaging client from the official release RPM, replacing Whatsie.
- Element Desktop (Matrix client), newest official build.
- tmux, zellij, Lollypop, Rhythmbox, Fragments, Glance and Memento.
- GNOME Boxes built from the newest upstream source at image build time.
- Vicinae launcher GNOME extension, installed system-wide.
- Trivy vulnerability scanner in the image and as CI scans.
- 100 GiB NVIDIA shader disk cache.

### Removed

- Whatsie and Hermes Agent.
- Firefox (RPM and Flatpak).
- Build toolchains are stripped from the finished image after compilation.

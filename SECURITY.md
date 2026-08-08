# Security Policy

## Supported Versions

Only the latest image tagged `latest` on GitHub Container Registry receives
security updates. Older tags are not backported.

## Reporting a Vulnerability

To report a security vulnerability, do **not** open a public issue. Instead,
send a private report via the GitHub Security Advisory tab:

<https://github.com/mheci/vibes/security/advisories/new>

You should receive an acknowledgment within 72 hours. Once triaged, the
maintainer will coordinate a fix and disclosure timeline.

## Scope

This policy covers:

- The BlueBuild recipe and modules
- Shell scripts used at build time
- The container image and its layered packages
- CI/CD workflows and their permissions

Out-of-scope:

- The upstream Aurora or BlueBuild projects (report to those projects)
- Third-party RPM packages and COPR repositories (report to those maintainers)
- The base Fedora or Linux kernel (report to the respective distribution)

## Supply Chain Security

- All third-party GitHub Actions are pinned to release tags and verified.
- Lint tools (shellcheck, actionlint) are pinned to specific versions and
  checksum-verified before execution.
- Images are signed with cosign. Verification instructions are in the README.
- The daily QEMU boot test verifies the image signature with `cosign.pub`
  before booting a disk image built from it.
- Tagged releases attach an SPDX SBOM generated from the image and record the
  verified image digest.
- The weekly upstream health workflow validates that all external URLs, pinned
  tags, and release-asset patterns used by the build scripts still resolve.

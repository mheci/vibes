# Contributing

## Scope

This repository defines a BlueBuild OCI image layered on top of
Aurora (NVIDIA Open). Contributions should improve the image's
reliability, security, performance, or documentation.

## Pull Request Process

1. Ensure all existing CI checks pass (validate, build, CodeQL). The
   `Shell, workflow & recipe validation` check is required by branch
   protection.
2. Add or update smoke tests for any new application or service.
3. Update documentation (README, recipe comments, CHANGELOG) to reflect
   changes.
4. Keep shell scripts compatible with `set -euo pipefail` and shellcheck.
5. Avoid introducing new third-party repositories unless necessary. Prefer
   packages available in Fedora or well-maintained COPRs.
6. Pin any new third-party GitHub Actions to a specific release tag. When you
   reference a new external URL or pinned tag/commit in the build scripts, the
   [upstream health workflow](.github/scripts/check-upstream.sh) must still
   pass.

## Development Workflow

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/vibes.git
cd vibes

# Create a feature branch
git checkout -b feat/my-change

# Run the full local validation suite
python3 .github/scripts/validate_recipe.py          # recipe structure
python3 -m yamllint -c .yamllint.yaml .github/ recipes/
markdownlint --config .markdownlint.json ./*.md .github/
shellcheck -S style files/scripts/*.sh .github/scripts/*.sh
actionlint .github/workflows/*.yml

# Commit with conventional commit prefix:
#   feat:   new feature
#   fix:    bug fix
#   docs:   documentation
#   ci:     CI/CD changes
#   refactor: code restructuring
#   security: security fix
git commit -m "feat: add support for X"

# Push and open a PR
git push origin feat/my-change
```

Note: the image build job is skipped for runs triggered by Dependabot or forks
(PRs and pushes on their branches) because signing secrets are not available
to those runs; the validation suite still runs in full. Full image builds run
on `push` to `main`, on schedule, and on manual `workflow_dispatch`.

## Code Style

- Shell scripts: `shellcheck` clean, `set -euo pipefail`, functions documented.
- YAML: `actionlint` clean, two-space indentation.
- Documentation: Markdown with 80-character line wrapping, no emoji in
  technical content.

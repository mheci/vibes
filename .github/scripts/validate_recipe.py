#!/usr/bin/env python3
"""Structural validation for the vibes BlueBuild recipe.

Catches (in seconds, before a 30+ minute image build) the failure modes that
would otherwise only surface deep inside the container build:

- recipe.yml is not valid YAML / is missing required keys
- a script module references a script that does not exist in files/scripts/
- a files module references a source directory that does not exist in files/
- default-flatpaks entries that are not plausible Flatpak refs
- companion YAML files (workflows, dependabot) that no longer parse
"""

from __future__ import annotations

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
RECIPE = ROOT / "recipes" / "recipe.yml"
errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)
    print(f"FAIL: {msg}", file=sys.stderr)


def ok(msg: str) -> None:
    print(f"  OK: {msg}")


def load_yaml(path: pathlib.Path):
    try:
        return yaml.safe_load(path.read_text())
    except Exception as exc:  # noqa: BLE001 - report any parse failure
        fail(f"{path.relative_to(ROOT)} is not valid YAML: {exc}")
        return None


# --- recipe.yml ---------------------------------------------------------------
recipe = load_yaml(RECIPE)
if recipe is not None:
    if not isinstance(recipe, dict):
        fail("recipes/recipe.yml must be a mapping")
        recipe = None

if recipe is not None:
    for key in ("version", "name", "base-image"):
        if key not in recipe:
            fail(f"recipes/recipe.yml missing required key: {key!r}")
        else:
            ok(f"recipe has {key!r}: {recipe[key]!r}")

    modules = recipe.get("modules")
    if not isinstance(modules, list) or not modules:
        fail("recipes/recipe.yml must define a non-empty 'modules' list")
        modules = []

    ref_pattern = re.compile(r"^[a-zA-Z0-9_][a-zA-Z0-9_.-]*\.[a-zA-Z0-9_.-]+$")

    for i, module in enumerate(modules):
        if not isinstance(module, dict) or "type" not in module:
            fail(f"module #{i} has no 'type'")
            continue
        mtype = module["type"]

        if mtype == "script":
            for script in module.get("scripts", []) or []:
                path = ROOT / "files" / "scripts" / script
                if path.is_file():
                    ok(f"script module {i}: found files/scripts/{script}")
                else:
                    fail(f"script module {i}: missing files/scripts/{script}")

        elif mtype == "files":
            for entry in module.get("files", []) or []:
                source = (entry or {}).get("source")
                if source is None:
                    fail(f"files module {i}: entry missing 'source'")
                    continue
                path = ROOT / "files" / source
                if path.exists():
                    ok(f"files module {i}: found files/{source}")
                else:
                    fail(f"files module {i}: missing files/{source}")

        elif mtype == "default-flatpaks":
            for conf in module.get("configurations", []) or []:
                for ref in (conf or {}).get("install", []) or []:
                    if ref_pattern.match(str(ref)) and "." in str(ref):
                        ok(f"default-flatpaks module {i}: plausible ref {ref}")
                    else:
                        fail(f"default-flatpaks module {i}: implausible ref {ref!r}")

# --- companion YAML -----------------------------------------------------------
for extra in sorted((ROOT / ".github").rglob("*.yml")):
    if extra.name == "validate_recipe.py":
        continue
    if load_yaml(extra) is not None:
        ok(f"{extra.relative_to(ROOT)} parses")

print()
if errors:
    print(f"{len(errors)} validation error(s)", file=sys.stderr)
    sys.exit(1)
print("All recipe validations passed.")

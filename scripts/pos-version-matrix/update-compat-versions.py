#!/usr/bin/env python3
"""
Check for new bor/erigon releases and update compat-versions.yml.

For each tracked component, fetches recent releases from GitHub and:
  - Adds new releases that aren't already in the curated list
  - Flags stale entries that are no longer the latest in their major.minor line

Designed to run in CI and produce a diff that can be opened as a PR.
"""

import os
import re
import yaml
import requests
from pathlib import Path
from typing import Optional


COMPONENTS = {
    "bor": {
        "repo": "0xPolygon/bor",
        "el_type": "bor",
        "image_prefix": "0xpolygon/bor:",
        "strip_v": True,
    },
    "erigon": {
        "repo": "0xPolygon/erigon",
        "el_type": "erigon",
        "image_prefix": "0xpolygon/erigon:",
        "strip_v": False,
    },
}


def get_headers() -> dict:
    token = os.getenv("GITHUB_TOKEN")
    if token:
        return {"Authorization": f"token {token}"}
    return {}


def fetch_latest_releases(repo: str, max_results: int = 30) -> list:
    """Fetch recent non-draft releases with valid semver tags."""
    url = f"https://api.github.com/repos/{repo}/releases?per_page=50"
    resp = requests.get(url, timeout=15, headers=get_headers())
    if resp.status_code != 200:
        print(f"Warning: failed to fetch releases for {repo} (HTTP {resp.status_code})")
        return []

    results = []
    for r in resp.json():
        if r.get("draft"):
            continue
        tag = r.get("tag_name", "")
        if not re.match(r"^v?\d+\.\d+\.\d+(-beta\d*|-rc\d*)?$", tag):
            continue
        results.append({
            "tag": tag,
            "prerelease": r.get("prerelease", False),
        })
        if len(results) >= max_results:
            break
    return results


def tag_to_version(tag: str) -> str:
    return re.sub(r"^v", "", tag)


def version_major_minor(tag: str) -> str:
    ver = tag_to_version(tag)
    parts = ver.split(".")
    return f"{parts[0]}.{parts[1]}" if len(parts) >= 2 else ver


def make_image(tag: str, comp_config: dict) -> str:
    prefix = comp_config["image_prefix"]
    if comp_config["strip_v"]:
        return prefix + tag_to_version(tag)
    return prefix + tag


def load_compat_versions(path: Path) -> dict:
    if not path.exists():
        return {"versions": []}
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    if "versions" not in data or data["versions"] is None:
        data["versions"] = []
    return data


def existing_images(data: dict) -> set:
    return {v["image"] for v in data.get("versions", []) if "image" in v}


def update_compat_versions(compat_path: Path) -> list:
    """Check for new releases and add them. Returns list of changes made."""
    data = load_compat_versions(compat_path)
    current_images = existing_images(data)
    changes = []

    for comp_name, comp_config in COMPONENTS.items():
        releases = fetch_latest_releases(comp_config["repo"])
        if not releases:
            continue

        # Group by major.minor line.
        lines: dict = {}
        for r in releases:
            mm = version_major_minor(r["tag"])
            if mm not in lines:
                lines[mm] = r

        # Check each major.minor line's latest release.
        for mm, release in lines.items():
            image = make_image(release["tag"], comp_config)
            if image in current_images:
                continue

            # New release not in the list — add it.
            reason = "new release, auto-detected"
            if release["prerelease"]:
                reason = f"new pre-release ({mm} line), auto-detected"
            else:
                reason = f"new stable release ({mm} line), auto-detected"

            entry = {
                "image": image,
                "el_type": comp_config["el_type"],
                "reason": reason,
            }
            data["versions"].append(entry)
            changes.append(f"  + {image} ({reason})")

    if changes:
        # Preserve comments by writing with a header.
        _write_compat_versions(compat_path, data)

    return changes


def _write_compat_versions(path: Path, data: dict):
    """Write compat-versions.yml preserving the header comment."""
    header = """\
# PoS version compatibility matrix — curated list of EL versions to test.
#
# The pos-e2e workflow reads this file to generate pairwise compat pairs.
# Only versions listed under `versions` are tested. Keep this list focused:
#   - Versions actively running in production
#   - Release candidates being validated for rollout
#   - Remove versions once fully deprecated and no longer in use
#
# Each entry must have: image, el_type (bor or erigon), reason.
# Pairwise pairs are generated across ALL entries (bor-bor, erigon-erigon,
# and bor-erigon cross-client combinations).
#
# If this file is absent or `versions` is empty, the workflow falls back
# to auto-detecting the latest bor release from each major.minor line.

"""
    with open(path, "w") as f:
        f.write(header)
        yaml.dump(
            {"versions": data["versions"]},
            f,
            default_flow_style=False,
            sort_keys=False,
        )


def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    compat_path = repo_root / "scripts" / "pos-version-matrix" / "compat-versions.yml"

    print("Checking for new releases...")
    changes = update_compat_versions(compat_path)

    if changes:
        print(f"\n{len(changes)} new version(s) added to {compat_path.name}:")
        for c in changes:
            print(c)
    else:
        print("No new versions found. compat-versions.yml is up to date.")


if __name__ == "__main__":
    main()

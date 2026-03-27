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
        "max_lines": 3,  # Track 3 major.minor lines (e.g. 2.7, 2.6, 2.5)
    },
    "erigon": {
        "repo": "0xPolygon/erigon",
        "el_type": "erigon",
        "image_prefix": "0xpolygon/erigon:",
        "strip_v": False,
        "max_lines": 2,  # Only latest lines — used as RPC endpoint, not pairwise tested
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


def _semver_sort_key(version: str) -> tuple:
    """Return a sort key for semantic version strings (descending).

    Handles optional -beta/-rc suffixes.  Stable > rc > beta for the
    same base version.  Returns a tuple of ints suitable for
    ``sorted(..., key=..., reverse=True)``."""
    base = re.sub(r"(-beta\d*|-rc\d*)$", "", version)
    parts = base.split(".")
    major = int(parts[0]) if len(parts) > 0 and parts[0].isdigit() else 0
    minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    patch = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0

    suffix = version[len(base):]
    if not suffix:
        weight, suffix_num = 3, 0  # stable
    elif suffix.startswith("-rc"):
        weight = 2
        suffix_num = int(suffix.replace("-rc", "") or "0")
    elif suffix.startswith("-beta"):
        weight = 1
        suffix_num = int(suffix.replace("-beta", "") or "0")
    else:
        weight, suffix_num = 0, 0

    return (major, minor, patch, weight, suffix_num)


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

        # Group by major.minor line (insertion order = newest first from API).
        lines: dict = {}
        for r in releases:
            mm = version_major_minor(r["tag"])
            if mm not in lines:
                lines[mm] = r

        # Limit to the N most recent major.minor lines.
        max_lines = comp_config.get("max_lines", 3)
        tracked_lines = dict(list(lines.items())[:max_lines])

        # Check each tracked major.minor line's latest release.
        prefix = comp_config["image_prefix"]
        for mm, release in tracked_lines.items():
            image = make_image(release["tag"], comp_config)

            # Remove superseded entries from the same major.minor line.
            superseded = [
                v for v in data["versions"]
                if v.get("image", "").startswith(prefix)
                and version_major_minor(v["image"][len(prefix):].lstrip("v")) == mm
                and v["image"] != image
            ]
            for old in superseded:
                data["versions"].remove(old)
                changes.append(f"  - {old['image']} (superseded by {image})")
                # Warn if excluded_pairs references the superseded version.
                for ep in data.get("excluded_pairs", []):
                    if old["image"] in ep.get("images", []):
                        print(f"  ! excluded_pairs references superseded image "
                              f"{old['image']} — update excluded_pairs manually.")

            if image in current_images:
                continue

            # Append new entry; the final sort (below) ensures correct order.
            if release["prerelease"]:
                reason = f"new pre-release ({mm} line), auto-detected"
            else:
                reason = f"new stable release ({mm} line), auto-detected"

            data["versions"].append({
                "image": image,
                "el_type": comp_config["el_type"],
                "reason": reason,
            })
            changes.append(f"  + {image} ({reason})")

    # Sort versions: group by el_type (bor first, then erigon), then
    # descending semver within each group.  This ensures the latest
    # version of each component is first — the workflow uses index 0
    # as the "latest" for single-version baseline tests.
    el_type_order = {"bor": 0, "erigon": 1}
    prev_order = [v["image"] for v in data["versions"]]
    data["versions"].sort(
        key=lambda v: (
            el_type_order.get(v.get("el_type", ""), 99),
            tuple(-x for x in _semver_sort_key(
                v.get("image", "").split(":")[-1].lstrip("v")
            )),
        )
    )
    new_order = [v["image"] for v in data["versions"]]
    if prev_order != new_order and not changes:
        changes.append("  ~ reordered versions (latest first per component)")

    if changes:
        _write_compat_versions(compat_path, data)

    return changes


def _read_excluded_pairs_tail(path: Path) -> str:
    """Return everything from the first blank/comment line before
    ``excluded_pairs:`` to end-of-file, preserving exact formatting.

    If there is no ``excluded_pairs`` section, returns ``""``."""
    if not path.exists():
        return ""
    lines = path.read_text().splitlines(keepends=True)
    ep_idx: Optional[int] = None
    for i, line in enumerate(lines):
        if line.rstrip() == "excluded_pairs:":
            ep_idx = i
            break
    if ep_idx is None:
        return ""
    # Walk backwards to include the comment block above excluded_pairs.
    start = ep_idx
    while start > 0 and (lines[start - 1].startswith("#") or lines[start - 1].strip() == ""):
        start -= 1
    tail = "".join(lines[start:])
    # Ensure a blank line separates the yaml.dump output from the tail.
    if not tail.startswith("\n"):
        tail = "\n" + tail
    return tail


def _write_compat_versions(path: Path, data: dict):
    """Write compat-versions.yml, only touching the ``versions`` section.

    The ``excluded_pairs`` section (and its comment block) is preserved
    verbatim from the original file — it is never serialised through
    yaml.dump and must only be edited by hand."""
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
    # Capture the excluded_pairs tail before we overwrite the file.
    tail = _read_excluded_pairs_tail(path)

    with open(path, "w") as f:
        f.write(header)
        yaml.dump(
            {"versions": data["versions"]},
            f,
            default_flow_style=False,
            sort_keys=False,
        )
        if tail:
            f.write(tail)


def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    compat_path = repo_root / "scripts" / "pos-version-matrix" / "compat-versions.yml"

    print("Checking for new releases...")
    changes = update_compat_versions(compat_path)

    if changes:
        print(f"\n{len(changes)} change(s) to {compat_path.name}:")
        for c in changes:
            print(c)
    else:
        print("No changes needed. compat-versions.yml is up to date.")


if __name__ == "__main__":
    main()

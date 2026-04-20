#!/usr/bin/env python3
"""Compute PoS E2E release outputs and compat matrix in one pass.

Replaces two bash steps (~420 lines) in .github/workflows/pos-e2e.yml:
  - "Resolve bor and heimdall-v2 versions"
  - "Generate version compatibility matrix"

Reads workflow inputs from env vars (see INPUT_* block in main()), fetches
GitHub releases, parses compat-versions.yml with real yaml.safe_load, and
writes the resulting outputs to GITHUB_OUTPUT (or stdout if unset — useful
for local dry-runs).

Run the embedded smoke tests with ``python3 compute-release-outputs.py --self-test``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

import requests
import yaml

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

HV2_MIN_VERSION = "0.6.0"

# Valid semver tag shape: vX.Y.Z with optional -beta[N] or -rc[N] suffix.
# Excludes one-off experimental tags like v2.8.0-test1.
SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(-(?:beta|rc)\d*)?$")

COMPONENT_REPOS = {
    "bor": "0xPolygon/bor",
    "heimdall-v2": "0xPolygon/heimdall-v2",
    "erigon": "0xPolygon/erigon",
}

# Bor/heimdall images strip the leading "v"; erigon images retain it.
STRIP_V_PREFIX = {"bor": True, "heimdall-v2": True, "erigon": False}


# ---------------------------------------------------------------------------
# Semver helpers — pure functions, covered by --self-test
# ---------------------------------------------------------------------------

def parse_semver_key(tag: str) -> tuple[int, int, int, int, int] | None:
    """Return a descending-sortable tuple for a semver tag, or None if invalid.

    Weights: stable=3, rc=2, beta=1.  Same ordering as the existing bash
    (``sort -t. -k1,1rn ... -k5,5rn``) and update-compat-versions.py.
    """
    m = SEMVER_RE.match(tag)
    if not m:
        return None
    major, minor, patch, suffix = m.groups()
    if not suffix:
        weight, suffix_num = 3, 0
    elif suffix.startswith("-rc"):
        weight = 2
        suffix_num = int(suffix[3:] or "0")
    elif suffix.startswith("-beta"):
        weight = 1
        suffix_num = int(suffix[5:] or "0")
    else:
        weight, suffix_num = 0, 0
    return (int(major), int(minor), int(patch), weight, suffix_num)


def sort_tags_desc(tags: Iterable[str]) -> list[str]:
    """Return ``tags`` filtered to valid semver, sorted highest → lowest."""
    keyed = [(parse_semver_key(t), t) for t in tags]
    keyed = [(k, t) for k, t in keyed if k is not None]
    keyed.sort(key=lambda kt: kt[0], reverse=True)
    return [t for _, t in keyed]


def meets_min_version(tag_or_version: str, minimum: str) -> bool:
    """True iff ``tag_or_version`` >= ``minimum`` per semver key order."""
    v = parse_semver_key(tag_or_version)
    m = parse_semver_key(minimum)
    if v is None or m is None:
        return False
    return v >= m


def major_minor(tag: str) -> str:
    """Return "X.Y" extracted from a version tag (best-effort)."""
    m = SEMVER_RE.match(tag)
    return f"{m.group(1)}.{m.group(2)}" if m else tag


def short_label(image: str) -> str:
    """0xpolygon/bor:2.7.1 -> bor-2.7.1, used for pair_label segments."""
    return image.split("/")[-1].replace(":", "-")


def image_version(image: str) -> str:
    """Extract the tag portion, stripping an optional leading 'v'."""
    tag = image.split(":")[-1] if ":" in image else image
    return tag[1:] if tag.startswith("v") else tag


def make_image(component: str, tag: str) -> str:
    """Build a docker image ref for ``component`` from a semver tag."""
    prefix = f"0xpolygon/{component}:"
    if STRIP_V_PREFIX[component]:
        return prefix + (tag[1:] if tag.startswith("v") else tag)
    # erigon: retain v (e.g. 0xpolygon/erigon:v3.5.0)
    return prefix + (tag if tag.startswith("v") else f"v{tag}")


# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------

def fetch_release_tags(repo: str, per_page: int = 50, token: str | None = None) -> list[str]:
    """Return non-draft release tag_name strings, most recent API order.

    Empty list on any network/auth failure — matches the bash fallback
    behaviour where a failed ``gh api`` call degrades gracefully.
    """
    url = f"https://api.github.com/repos/{repo}/releases"
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        resp = requests.get(url, params={"per_page": per_page}, headers=headers, timeout=30)
    except requests.RequestException as exc:
        print(f"::warning::Failed to fetch {repo} releases: {exc}", file=sys.stderr)
        return []
    if resp.status_code != 200:
        print(
            f"::warning::Failed to fetch {repo} releases (HTTP {resp.status_code})",
            file=sys.stderr,
        )
        return []
    return [r.get("tag_name", "") for r in resp.json() if not r.get("draft")]


def fetch_latest_release_tag(repo: str, token: str | None = None) -> str:
    """Fetch ``repo``'s /releases/latest tag, or '' on failure."""
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        resp = requests.get(url, headers=headers, timeout=30)
        if resp.status_code == 200:
            return resp.json().get("tag_name", "")
    except requests.RequestException:
        pass
    return ""


# ---------------------------------------------------------------------------
# compat-versions.yml loading
# ---------------------------------------------------------------------------

@dataclass
class Excluded:
    a: str
    b: str
    reason: str = ""
    link: str = ""
    scope: str = "all"


@dataclass
class CompatYml:
    bor_images: list[str] = field(default_factory=list)
    erigon_images: list[str] = field(default_factory=list)
    heimdall_images: list[str] = field(default_factory=list)
    excluded: list[Excluded] = field(default_factory=list)


def load_compat_yml(path: Path) -> CompatYml:
    """Parse compat-versions.yml — replaces ~100 lines of awk/regex bash.

    Silently enforces the HV2 min version filter on heimdall-v2 entries
    (matching the existing workflow contract).
    """
    result = CompatYml()
    if not path.exists():
        return result
    with open(path) as f:
        data = yaml.safe_load(f) or {}

    for v in data.get("versions") or []:
        image = v.get("image")
        if not image:
            continue
        el_type = v.get("el_type")
        cl_type = v.get("cl_type")
        if el_type == "bor":
            result.bor_images.append(image)
        elif el_type == "erigon":
            result.erigon_images.append(image)
        elif cl_type == "heimdall-v2":
            if meets_min_version(image_version(image), HV2_MIN_VERSION):
                result.heimdall_images.append(image)
            else:
                print(f"  Skipping {image} (< v{HV2_MIN_VERSION})")

    for e in data.get("excluded_pairs") or []:
        images = e.get("images") or []
        if len(images) != 2:
            print(f"::warning::Incomplete excluded pair ({len(images)} image(s)): {images}")
            continue
        scope = str(e.get("scope") or "all")
        if scope not in ("all", "fork-transition"):
            print(
                f"::warning::Unknown exclusion scope '{scope}' for "
                f"{images[0]} <-> {images[1]}; treating as 'all'"
            )
            scope = "all"
        result.excluded.append(
            Excluded(
                a=images[0],
                b=images[1],
                reason=str(e.get("reason") or ""),
                link=str(e.get("link") or ""),
                scope=scope,
            )
        )
    return result


# ---------------------------------------------------------------------------
# Scenario generation
# ---------------------------------------------------------------------------

def generate_scenarios(
    bor_images: list[str],
    erigon_images: list[str],
    heimdall_images: list[str],
    excluded_all: set[tuple[str, str]],
) -> list[dict]:
    """Build compat-pairs list with bor_a/bor_b/erigon_rpc/heimdall_a/heimdall_b.

    * Single-version baseline: latest bor × latest erigon × latest heimdall.
    * Pairwise mixes: majority (side A) pins to latest bor + latest heimdall;
      minority (side B) rotates through bor_images[j] and heimdall_images[j]
      (clamped to last available heimdall).  Erigon is pinned to index 0 but
      rotates if excluded with either side.
    """
    scenarios: list[dict] = []
    if not bor_images:
        return scenarios

    hv_latest = heimdall_images[0] if heimdall_images else ""
    erigon_latest = erigon_images[0] if erigon_images else ""

    la = short_label(bor_images[0])
    scenarios.append(
        {
            "bor_a": bor_images[0],
            "bor_b": bor_images[0],
            "erigon_rpc": erigon_latest,
            "heimdall_a": hv_latest,
            "heimdall_b": hv_latest,
            "pair_label": f"{la}-single",
        }
    )

    va = bor_images[0]
    for j in range(1, len(bor_images)):
        vb = bor_images[j]
        if (va, vb) in excluded_all or (vb, va) in excluded_all:
            print(f"  Skipping excluded pair: {va} <-> {vb}")
            continue

        # Erigon rotation: start at index 0, rotate past any erigon excluded
        # with va or vb.  Preserves the existing workflow's off-by-one fix
        # (start at 0, not at j % N).
        if erigon_images:
            eri = erigon_images[0]
            for k in range(1, len(erigon_images)):
                if (va, eri) not in excluded_all and (vb, eri) not in excluded_all:
                    break
                eri = erigon_images[k % len(erigon_images)]
                print(f"  Rotated erigon to {eri} (excluded pair avoided for {va} or {vb})")
            if (va, eri) in excluded_all or (vb, eri) in excluded_all:
                print(
                    f"::warning::No compatible erigon for bor pair {va} <-> {vb} — "
                    "all versions excluded, skipping."
                )
                continue
        else:
            eri = erigon_latest

        hva = hv_latest
        if len(heimdall_images) > 1:
            hvb_idx = j if j < len(heimdall_images) else len(heimdall_images) - 1
            hvb = heimdall_images[hvb_idx]
        else:
            hvb = hv_latest

        lb = short_label(vb)
        if hva != hvb:
            lbl = f"{la}-vs-{lb}__{short_label(hva)}-vs-{short_label(hvb)}"
        else:
            lbl = f"{la}-vs-{lb}"

        scenarios.append(
            {
                "bor_a": va,
                "bor_b": vb,
                "erigon_rpc": eri,
                "heimdall_a": hva,
                "heimdall_b": hvb,
                "pair_label": lbl,
            }
        )
    return scenarios


def apply_fork_trans_exclusions(
    scenarios: list[dict], excluded_ft: list[Excluded]
) -> list[dict]:
    """Drop scenarios that match any fork-transition-scoped exclusion.

    Matches the bash jq filter:
      bor_a/bor_b pair OR erigon_rpc × (bor_a or bor_b) pair.
    """
    remaining = list(scenarios)
    for e in excluded_ft:
        remaining = [
            s for s in remaining
            if not (
                (s["bor_a"] == e.a and s["bor_b"] == e.b)
                or (s["bor_a"] == e.b and s["bor_b"] == e.a)
                or (s["erigon_rpc"] == e.a and (s["bor_a"] == e.b or s["bor_b"] == e.b))
                or (s["erigon_rpc"] == e.b and (s["bor_a"] == e.a or s["bor_b"] == e.a))
            )
        ]
    return remaining


# ---------------------------------------------------------------------------
# Top-level orchestration
# ---------------------------------------------------------------------------

@dataclass
class Inputs:
    """Mirror of workflow inputs, read from INPUT_* env vars."""
    event_name: str = ""
    bor_latest_image: str = ""
    bor_previous_image: str = ""
    heimdall_v2_image: str = ""
    erigon_image: str = ""
    bor_archive_image: str = ""
    bor_compat_versions: str = ""
    heimdall_compat_versions: str = ""
    github_token: str = ""
    compat_yml_path: str = "scripts/pos-version-matrix/compat-versions.yml"
    github_output: str = ""

    @classmethod
    def from_env(cls) -> "Inputs":
        return cls(
            event_name=os.environ.get("EVENT_NAME", ""),
            bor_latest_image=os.environ.get("INPUT_BOR_LATEST_IMAGE", ""),
            bor_previous_image=os.environ.get("INPUT_BOR_PREVIOUS_IMAGE", ""),
            heimdall_v2_image=os.environ.get("INPUT_HEIMDALL_V2_IMAGE", ""),
            erigon_image=os.environ.get("INPUT_ERIGON_IMAGE", ""),
            bor_archive_image=os.environ.get("INPUT_BOR_ARCHIVE_IMAGE", ""),
            bor_compat_versions=os.environ.get("INPUT_BOR_COMPAT_VERSIONS", ""),
            heimdall_compat_versions=os.environ.get("INPUT_HEIMDALL_COMPAT_VERSIONS", ""),
            github_token=os.environ.get("GITHUB_TOKEN", ""),
            compat_yml_path=os.environ.get(
                "COMPAT_YML_PATH", "scripts/pos-version-matrix/compat-versions.yml"
            ),
            github_output=os.environ.get("GITHUB_OUTPUT", ""),
        )


class OutputWriter:
    """Accumulate key=value pairs; flush to GITHUB_OUTPUT or stdout."""

    def __init__(self, path: str):
        self.path = path
        self.pairs: list[tuple[str, str]] = []

    def set(self, key: str, value: str) -> None:
        self.pairs.append((key, value))

    def flush(self) -> None:
        if not self.path:
            for k, v in self.pairs:
                print(f"[output] {k}={v}")
            return
        # Multi-line values would need heredoc syntax, but all our outputs
        # are single-line (JSON is compact).
        with open(self.path, "a") as f:
            for k, v in self.pairs:
                f.write(f"{k}={v}\n")


def _resolve_bor(inputs: Inputs, out: OutputWriter) -> str:
    """Emit bor-tag / bor-latest-image / bor-previous-image.  Returns the
    latest_tag (or '' on failure) for downstream archive-image defaulting."""
    all_tags = fetch_release_tags("0xPolygon/bor", per_page=50, token=inputs.github_token)[:50]
    if not all_tags:
        print("::warning::Failed to fetch bor releases.")
        out.set("bor-tag", "")
        return ""

    version_tags = [t for t in all_tags if SEMVER_RE.match(t)]
    if not version_tags:
        print("::warning::No valid bor version tags found, falling back to all releases.")
        version_tags = list(all_tags)

    sorted_tags = sort_tags_desc(version_tags)
    if not sorted_tags:
        out.set("bor-tag", "")
        return ""

    latest_tag = sorted_tags[0]
    print(f"Latest bor tag: {latest_tag}")
    print("Sorted tags (highest version first):")
    for t in sorted_tags[:10]:
        print(f"  {t}")

    latest_mm = major_minor(latest_tag)
    previous_tag = latest_tag
    for t in sorted_tags:
        if major_minor(t) != latest_mm:
            previous_tag = t
            break

    out.set("bor-tag", latest_tag)
    out.set("bor-latest-image", make_image("bor", latest_tag))
    out.set("bor-previous-image", make_image("bor", previous_tag))
    return latest_tag


def _resolve_component_latest(
    component: str, override: str, out_key: str, out: OutputWriter, token: str
) -> None:
    """Emit a single-version output for heimdall-v2 or erigon."""
    if override:
        out.set(out_key, override)
        return
    tag = fetch_latest_release_tag(COMPONENT_REPOS[component], token=token)
    if tag:
        out.set(out_key, make_image(component, tag))
    else:
        print(f"::warning::Failed to fetch {component} release, using 'latest'.")
        out.set(out_key, f"0xpolygon/{component}:latest")


def resolve_versions(inputs: Inputs, out: OutputWriter) -> str:
    """Emit bor/heimdall-v2/erigon/bor-archive outputs.

    Short-circuits on manual dispatch with an explicit bor-latest-image.
    Returns the resolved latest bor image (may be empty on failure) so
    downstream steps can fall back to it.
    """
    # --- Manual dispatch shortcut ---
    if inputs.event_name == "workflow_dispatch" and inputs.bor_latest_image:
        print("Manual dispatch with explicit images.")
        out.set("bor-tag", "manual")
        out.set("bor-latest-image", inputs.bor_latest_image)
        out.set("bor-previous-image", inputs.bor_previous_image)
        out.set("heimdall-v2-image", inputs.heimdall_v2_image)
        _resolve_component_latest(
            "erigon", inputs.erigon_image, "erigon-image", out, inputs.github_token
        )
        out.set(
            "bor-archive-image",
            inputs.bor_archive_image or inputs.bor_latest_image,
        )
        return inputs.bor_latest_image

    # --- Auto-detect ---
    latest_tag = _resolve_bor(inputs, out)
    _resolve_component_latest(
        "heimdall-v2", inputs.heimdall_v2_image, "heimdall-v2-image", out, inputs.github_token
    )
    _resolve_component_latest(
        "erigon", inputs.erigon_image, "erigon-image", out, inputs.github_token
    )

    if inputs.bor_archive_image:
        out.set("bor-archive-image", inputs.bor_archive_image)
    elif latest_tag:
        out.set("bor-archive-image", make_image("bor", latest_tag))
    else:
        out.set("bor-archive-image", "")

    return make_image("bor", latest_tag) if latest_tag else ""


def _collect_bor_images(yml: CompatYml, inputs: Inputs, bor_latest: str, bor_previous: str) -> list[str]:
    if inputs.bor_compat_versions:
        print("Using manual override for bor versions.")
        return [s.strip() for s in inputs.bor_compat_versions.split(",") if s.strip()]
    if yml.bor_images:
        return list(yml.bor_images)
    print("No bor versions found. Falling back to auto-detect.")
    result = []
    if bor_latest:
        result.append(bor_latest)
    if bor_previous and bor_previous != bor_latest:
        result.append(bor_previous)
    return result


def _collect_erigon_images(yml: CompatYml, inputs: Inputs, erigon_fallback: str) -> list[str]:
    if inputs.erigon_image:
        print(f"Using manual override for erigon: {inputs.erigon_image}")
        return [inputs.erigon_image]
    if yml.erigon_images:
        return list(yml.erigon_images)
    if erigon_fallback:
        print(f"No erigon versions in YAML — using auto-detected fallback: {erigon_fallback}")
        return [erigon_fallback]
    print("::warning::No erigon images found — erigon_rpc will be empty in scenarios.")
    return []


def _collect_heimdall_images(yml: CompatYml, inputs: Inputs, hv2_fallback: str) -> list[str]:
    # 1. Manual override (comma-separated list, min-version filter applied).
    if inputs.heimdall_compat_versions:
        print("Using manual override for heimdall-v2 versions.")
        result = []
        for raw in inputs.heimdall_compat_versions.split(","):
            img = raw.strip()
            if not img:
                continue
            if meets_min_version(image_version(img), HV2_MIN_VERSION):
                result.append(img)
            else:
                print(f"::warning::Skipping {img} (< v{HV2_MIN_VERSION}).")
        if result:
            return result

    # 2. compat-versions.yml (already filtered during load).
    if yml.heimdall_images:
        return list(yml.heimdall_images)

    # 3. Auto-detect from GitHub releases.
    print("No heimdall-v2 entries in YAML — auto-detecting from GitHub releases.")
    tags = fetch_release_tags("0xPolygon/heimdall-v2", per_page=30, token=inputs.github_token)
    hv2_images = []
    for tag in tags[:30]:
        if not SEMVER_RE.match(tag):
            continue
        if meets_min_version(tag, HV2_MIN_VERSION):
            hv2_images.append(make_image("heimdall-v2", tag))
    if hv2_images:
        return hv2_images

    # 4. Fallback to resolve-step single heimdall-v2 image.
    if hv2_fallback:
        ver = image_version(hv2_fallback)
        if meets_min_version(ver, HV2_MIN_VERSION):
            print(f"Using resolve-step heimdall-v2 as fallback: {hv2_fallback}")
            return [hv2_fallback]
        print(
            f"::warning::resolve-step heimdall-v2 {hv2_fallback} is below "
            f"v{HV2_MIN_VERSION} — scenarios will have empty heimdall fields."
        )
    return []


def generate_matrix(
    inputs: Inputs, out: OutputWriter, resolved: dict[str, str]
) -> None:
    """Emit compat-pairs, fork-trans-pairs, excluded-pairs."""
    yml = load_compat_yml(Path(inputs.compat_yml_path))

    bor_images = _collect_bor_images(
        yml, inputs, resolved.get("bor-latest-image", ""), resolved.get("bor-previous-image", "")
    )
    erigon_images = _collect_erigon_images(yml, inputs, resolved.get("erigon-image", ""))
    heimdall_images = _collect_heimdall_images(
        yml, inputs, resolved.get("heimdall-v2-image", "")
    )

    print(f"Bor versions ({len(bor_images)}):")
    for i in bor_images:
        print(f"  {i}")
    print(f"Erigon versions ({len(erigon_images)}):")
    for i in erigon_images:
        print(f"  {i}")
    print(f"Heimdall-v2 versions ({len(heimdall_images)}):")
    for i in heimdall_images:
        print(f"  {i}")

    excluded_all_set = set()
    excluded_ft_list: list[Excluded] = []
    for e in yml.excluded:
        if e.scope == "fork-transition":
            excluded_ft_list.append(e)
            print(f"  Excluded pair ({e.scope}): {e.a} <-> {e.b}")
        else:
            excluded_all_set.add((e.a, e.b))
            excluded_all_set.add((e.b, e.a))
            print(f"  Excluded pair: {e.a} <-> {e.b}")

    excluded_json = [
        {"a": e.a, "b": e.b, "reason": e.reason, "link": e.link, "scope": e.scope}
        for e in yml.excluded
    ]
    out.set("excluded-pairs", json.dumps(excluded_json, separators=(",", ":")))
    print(f"Loaded {len(excluded_json)} excluded pairs.")

    scenarios = generate_scenarios(bor_images, erigon_images, heimdall_images, excluded_all_set)
    out.set("compat-pairs", json.dumps(scenarios, separators=(",", ":")))
    print(f"Test scenarios ({len(scenarios)}):")
    for s in scenarios:
        print(
            f"  {s['pair_label']}  bor={s['bor_a']}/{s['bor_b']}  "
            f"heimdall={s['heimdall_a']}/{s['heimdall_b']}  erigon={s['erigon_rpc']}"
        )

    ft = apply_fork_trans_exclusions(scenarios, excluded_ft_list)
    out.set("fork-trans-pairs", json.dumps(ft, separators=(",", ":")))
    diff = len(scenarios) - len(ft)
    if diff > 0:
        print(f"Fork-transition scenarios: {len(ft)} ({diff} excluded by scope)")


def main_run() -> int:
    inputs = Inputs.from_env()
    out = OutputWriter(inputs.github_output)

    resolve_versions(inputs, out)
    # Snapshot resolved outputs for the matrix step (avoids re-reading GITHUB_OUTPUT).
    resolved = {k: v for k, v in out.pairs}
    generate_matrix(inputs, out, resolved)

    out.flush()
    return 0


# ---------------------------------------------------------------------------
# Embedded smoke tests
# ---------------------------------------------------------------------------

def _self_test() -> int:
    failures = 0

    def check(desc: str, got, want) -> None:
        nonlocal failures
        if got == want:
            print(f"  OK: {desc}")
        else:
            failures += 1
            print(f"  FAIL: {desc}\n    got:  {got!r}\n    want: {want!r}")

    print("=== semver parsing ===")
    # Compare via sort_tags_desc to exercise the public API without
    # triggering type-checker warnings on Optional-vs-Optional comparisons.
    check("stable > rc", sort_tags_desc(["v2.7.0-rc2", "v2.7.0"])[0], "v2.7.0")
    check("rc > beta", sort_tags_desc(["v2.7.0-beta3", "v2.7.0-rc1"])[0], "v2.7.0-rc1")
    check("patch bump ordering", sort_tags_desc(["v2.7.0", "v2.7.1"])[0], "v2.7.1")
    check("invalid returns None", parse_semver_key("v2.7.0-test1"), None)
    check("v-prefix tolerant", parse_semver_key("2.7.0"), parse_semver_key("v2.7.0"))

    print("\n=== sort_tags_desc ===")
    tags_in = ["v2.6.5", "v2.7.1", "v2.7.0-beta2", "v2.7.0", "v2.8.0-test1", "v2.7.0-rc1"]
    check(
        "drops invalid + sorts descending",
        sort_tags_desc(tags_in),
        ["v2.7.1", "v2.7.0", "v2.7.0-rc1", "v2.7.0-beta2", "v2.6.5"],
    )

    print("\n=== min version filter ===")
    check("0.5.9 < 0.6.0", meets_min_version("0.5.9", "0.6.0"), False)
    check("0.6.0 >= 0.6.0", meets_min_version("0.6.0", "0.6.0"), True)
    check("0.7.0-beta1 >= 0.6.0", meets_min_version("0.7.0-beta1", "0.6.0"), True)
    check("v-prefix accepted", meets_min_version("v0.6.0", "0.6.0"), True)
    # Edge: 0.6.0-beta1 IS a pre-release of 0.6.0, so semver-wise less than.
    check("0.6.0-beta1 < 0.6.0 (pre-release)", meets_min_version("0.6.0-beta1", "0.6.0"), False)

    print("\n=== image helpers ===")
    check("short_label", short_label("0xpolygon/bor:2.7.1"), "bor-2.7.1")
    check("image_version strips v", image_version("0xpolygon/erigon:v3.5.0"), "3.5.0")
    check("image_version no v", image_version("0xpolygon/bor:2.7.1"), "2.7.1")
    check("make_image bor strips v", make_image("bor", "v2.7.1"), "0xpolygon/bor:2.7.1")
    check("make_image erigon keeps v", make_image("erigon", "v3.5.0"), "0xpolygon/erigon:v3.5.0")
    check("make_image erigon adds v", make_image("erigon", "3.5.0"), "0xpolygon/erigon:v3.5.0")

    print("\n=== scenario generation ===")
    bor = ["0xpolygon/bor:2.7.1", "0xpolygon/bor:2.6.5"]
    erigon = ["0xpolygon/erigon:v3.5.0"]
    hv_single = ["0xpolygon/heimdall-v2:0.6.0"]
    hv_two = ["0xpolygon/heimdall-v2:0.6.1", "0xpolygon/heimdall-v2:0.6.0"]

    s1 = generate_scenarios(bor, erigon, hv_single, set())
    check("1-heimdall: 2 scenarios", len(s1), 2)
    check("1-heimdall: baseline label", s1[0]["pair_label"], "bor-2.7.1-single")
    check("1-heimdall: pair label has no hv suffix", s1[1]["pair_label"], "bor-2.7.1-vs-bor-2.6.5")
    check("1-heimdall: heimdall_a == heimdall_b", s1[1]["heimdall_a"] == s1[1]["heimdall_b"], True)

    s2 = generate_scenarios(bor, erigon, hv_two, set())
    check(
        "2-heimdall: pair label includes hv suffix",
        s2[1]["pair_label"],
        "bor-2.7.1-vs-bor-2.6.5__heimdall-v2-0.6.1-vs-heimdall-v2-0.6.0",
    )
    check("2-heimdall: heimdall_a is latest", s2[1]["heimdall_a"], "0xpolygon/heimdall-v2:0.6.1")
    check("2-heimdall: heimdall_b is older", s2[1]["heimdall_b"], "0xpolygon/heimdall-v2:0.6.0")

    print("\n=== empty heimdall ===")
    s0 = generate_scenarios(bor, erigon, [], set())
    check("0-heimdall: scenarios still produced", len(s0), 2)
    check("0-heimdall: heimdall fields empty", s0[1]["heimdall_a"], "")

    print("\n=== excluded pair (bor-bor) ===")
    excluded = {(bor[0], bor[1]), (bor[1], bor[0])}
    s_excl = generate_scenarios(bor, erigon, hv_single, excluded)
    check("bor-bor exclusion: only baseline remains", len(s_excl), 1)

    print("\n=== fork-transition scoped exclusion ===")
    scenarios_in = generate_scenarios(bor, erigon, hv_single, set())
    ft_excl = [Excluded(a=bor[0], b=bor[1], scope="fork-transition")]
    ft = apply_fork_trans_exclusions(scenarios_in, ft_excl)
    check("ft exclusion drops pairwise", len(ft), 1)
    check("ft exclusion keeps baseline", ft[0]["pair_label"], "bor-2.7.1-single")

    print()
    if failures == 0:
        print("All self-tests passed.")
        return 0
    print(f"{failures} self-test(s) failed.")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run embedded smoke tests and exit.",
    )
    args = parser.parse_args()
    if args.self_test:
        return _self_test()
    return main_run()


if __name__ == "__main__":
    sys.exit(main())

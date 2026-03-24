#!/usr/bin/env python3
"""
Automated version matrix extraction tool for PoS (kurtosis-pos).

Extracts version information from:
1. kurtosis-pos constants.star (IMAGES dict)
2. E2E test scenario configurations (scenarios/pos/)
3. GitHub releases/tags for latest version detection

Generates scripts/version-matrix/matrix.json with status indicators.
"""

import argparse
import os
import re
import json
import yaml
import requests
from pathlib import Path
from typing import Dict, Optional
from dataclasses import dataclass, asdict
from datetime import datetime


@dataclass
class ComponentVersion:
    """Represents a version of a component."""

    version: str
    image: str
    latest_version: Optional[str] = None
    latest_stable_version: Optional[str] = None
    version_source_url: Optional[str] = None
    latest_version_source_url: Optional[str] = None
    latest_stable_version_source_url: Optional[str] = None
    status: Optional[str] = None


@dataclass
class TestEnvironment:
    """Represents a test environment configuration."""

    type: str
    config_file_path: str
    components: Dict[str, ComponentVersion]


# PoS core components and their GitHub repos.
COMPONENT_REPOS = {
    "bor": "0xPolygon/bor",
    "heimdall-v2": "0xPolygon/heimdall-v2",
    "erigon": "0xPolygon/erigon",
}

# Mapping from constants.star keys to component names.
CONSTANTS_KEY_MAP = {
    "l2_el_bor_image": "bor",
    "l2_cl_heimdall_v2_image": "heimdall-v2",
    "l2_el_erigon_image": "erigon",
}


class VersionMatrixExtractor:
    """Extracts and manages the PoS version matrix."""

    def __init__(self, repo_root: Path, kurtosis_pos_root: Optional[Path] = None):
        self.repo_root = repo_root
        self.kurtosis_pos_root = kurtosis_pos_root
        self.constants_path = (
            kurtosis_pos_root / "src" / "config" / "constants.star"
            if kurtosis_pos_root
            else None
        )
        # E2E test environments to scan.
        self.test_files = [
            (
                "pos-upgrade",
                repo_root / "scenarios" / "pos" / "upgrade" / "params.yml",
            ),
        ]

    # ------------------------------------------------------------------
    # constants.star parsing
    # ------------------------------------------------------------------

    def extract_default_images(self) -> Dict[str, ComponentVersion]:
        """Extract default image versions from kurtosis-pos constants.star."""
        content = self._read_constants_star()
        if not content:
            return {}

        components: Dict[str, ComponentVersion] = {}

        # Match the IMAGES dict (not DEFAULT_IMAGES — kurtosis-pos uses IMAGES).
        images_match = re.search(r"IMAGES\s*=\s*\{(.*?)\}", content, re.DOTALL)
        if not images_match:
            print("Warning: IMAGES dict not found in constants.star")
            return {}

        images_content = images_match.group(1)

        for line in images_content.split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            match = re.search(r'"([^"]+)":\s*"([^"]+)"', line)
            if not match:
                continue

            key, image = match.groups()
            if key not in CONSTANTS_KEY_MAP:
                continue

            name = CONSTANTS_KEY_MAP[key]
            version = self._extract_version_from_image(image)
            latest_version, latest_stable = self._get_latest_versions(name)

            components[name] = ComponentVersion(
                version=version,
                image=image,
                latest_version=latest_version,
                latest_stable_version=latest_stable,
                version_source_url=self._get_source_url(name, version),
                latest_version_source_url=self._get_source_url(name, latest_version),
                latest_stable_version_source_url=self._get_source_url(name, latest_stable),
                status=self._determine_status(version, latest_version),
            )

        return components

    def _read_constants_star(self) -> Optional[str]:
        """Read constants.star from local path or fetch from GitHub."""
        if self.constants_path and self.constants_path.exists():
            with open(self.constants_path) as f:
                return f.read()

        # Fallback: fetch from GitHub raw.
        url = "https://raw.githubusercontent.com/0xPolygon/kurtosis-pos/main/src/config/constants.star"
        print(f"Fetching constants.star from {url} ...")
        try:
            headers = {}
            token = os.getenv("GITHUB_TOKEN")
            if token:
                headers["Authorization"] = f"token {token}"
            resp = requests.get(url, timeout=15, headers=headers)
            if resp.status_code == 200:
                return resp.text
            print(f"Warning: failed to fetch constants.star (HTTP {resp.status_code})")
        except Exception as e:
            print(f"Warning: failed to fetch constants.star: {e}")
        return None

    # ------------------------------------------------------------------
    # Test environment scanning
    # ------------------------------------------------------------------

    def extract_test_environments(self) -> Dict[str, TestEnvironment]:
        """Scan e2e scenario configs for component versions."""
        environments: Dict[str, TestEnvironment] = {}

        for env_name, yaml_path in self.test_files:
            if not yaml_path.exists():
                print(f"Warning: {yaml_path} not found, skipping {env_name}")
                continue

            with open(yaml_path) as f:
                config = yaml.safe_load(f)

            if not config:
                continue

            components = self._extract_components_from_params(config)
            rel_path = str(yaml_path.relative_to(self.repo_root))

            environments[env_name] = TestEnvironment(
                type=env_name,
                config_file_path=rel_path,
                components=components,
            )

        return environments

    def _extract_components_from_params(
        self, config: dict
    ) -> Dict[str, ComponentVersion]:
        """Extract component versions from a kurtosis-pos params.yml."""
        components: Dict[str, ComponentVersion] = {}
        participants = (
            config.get("polygon_pos_package", {}).get("participants", [])
        )

        for participant in participants:
            el_image = participant.get("el_image", "")
            cl_image = participant.get("cl_image", "")
            el_type = participant.get("el_type", "")

            if cl_image and "heimdall-v2" not in components:
                version = self._extract_version_from_image(cl_image)
                latest, latest_stable = self._get_latest_versions("heimdall-v2")
                components["heimdall-v2"] = ComponentVersion(
                    version=version,
                    image=cl_image,
                    latest_version=latest,
                    latest_stable_version=latest_stable,
                    version_source_url=self._get_source_url("heimdall-v2", version),
                    latest_version_source_url=self._get_source_url("heimdall-v2", latest),
                    latest_stable_version_source_url=self._get_source_url("heimdall-v2", latest_stable),
                    status=self._determine_status(version, latest),
                )

            if el_image:
                name = el_type if el_type in ("bor", "erigon") else self._guess_el_name(el_image)
                if name and name not in components:
                    version = self._extract_version_from_image(el_image)
                    latest, latest_stable = self._get_latest_versions(name)
                    components[name] = ComponentVersion(
                        version=version,
                        image=el_image,
                        latest_version=latest,
                        latest_stable_version=latest_stable,
                        version_source_url=self._get_source_url(name, version),
                        latest_version_source_url=self._get_source_url(name, latest),
                        latest_stable_version_source_url=self._get_source_url(name, latest_stable),
                        status=self._determine_status(version, latest),
                    )

        return components

    @staticmethod
    def _guess_el_name(image: str) -> Optional[str]:
        """Guess the EL component name from the docker image string."""
        lower = image.lower()
        if "bor" in lower:
            return "bor"
        if "erigon" in lower:
            return "erigon"
        return None

    # ------------------------------------------------------------------
    # GitHub version fetching
    # ------------------------------------------------------------------

    def _get_latest_versions(self, component: str) -> tuple:
        """Fetch both latest (including pre-release) and latest stable versions.

        Returns (latest_version, latest_stable_version).
        """
        repo = COMPONENT_REPOS.get(component)
        if not repo:
            return None, None

        headers = {}
        token = os.getenv("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"token {token}"

        try:
            return self._scan_releases(repo, headers)
        except Exception as e:
            print(f"Warning: failed to fetch versions for {component}: {e}")
        return None, None

    @staticmethod
    def _scan_releases(repo: str, headers: dict) -> tuple:
        """Scan releases for the absolute latest and latest stable semver tags.

        Returns (latest_version, latest_stable_version).
        - latest_version: first semver release (may be beta/rc)
        - latest_stable_version: first release with no pre-release suffix
        """
        url = f"https://api.github.com/repos/{repo}/releases?per_page=30"
        resp = requests.get(url, timeout=10, headers=headers)
        if resp.status_code != 200:
            print(f"Warning: failed to fetch releases for {repo} (HTTP {resp.status_code})")
            return None, None

        releases = resp.json()
        latest = None
        latest_stable = None

        for release in releases:
            if release.get("draft"):
                continue
            tag = release.get("tag_name", "")
            # Skip non-semver tags (e.g. date-based, test tags).
            if not re.match(r"^v?\d+\.\d+\.\d+", tag):
                continue
            ver = re.sub(r"^v?", "", tag)

            if latest is None:
                latest = ver

            # Stable = no pre-release suffix (no -beta, -rc, -test, etc.)
            if re.match(r"^v?\d+\.\d+\.\d+$", tag) and latest_stable is None:
                latest_stable = ver

            if latest and latest_stable:
                break

        return latest, latest_stable

    # ------------------------------------------------------------------
    # Version helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_version_from_image(image: str) -> str:
        """Extract the version string from a docker image tag."""
        if ":" not in image:
            return "latest"
        tag = image.split(":")[-1]
        if tag in ("latest", "main", "master"):
            return tag
        return re.sub(r"^v?", "", tag)

    @staticmethod
    def _get_source_url(name: str, version: Optional[str]) -> Optional[str]:
        """Build a link to the GitHub release/tag page."""
        if not version or version in ("latest", "main", "master"):
            repo = COMPONENT_REPOS.get(name)
            return f"https://github.com/{repo}/releases/latest" if repo else None
        repo = COMPONENT_REPOS.get(name)
        if not repo:
            return None
        return f"https://github.com/{repo}/releases/tag/v{version.lstrip('v')}"

    @staticmethod
    def _determine_status(version: str, latest_version: Optional[str]) -> Optional[str]:
        """Compare deployed version against latest stable."""
        if not latest_version:
            return None

        def version_to_int(v: str) -> int:
            base = v.split("-")[0]
            parts = base.split(".")
            while len(parts) < 3:
                parts.append("0")
            try:
                return (
                    int(parts[0]) * 1_000_000
                    + int(parts[1]) * 1_000
                    + int(parts[2])
                )
            except (ValueError, IndexError):
                return 0

        v_int = version_to_int(version)
        l_int = version_to_int(latest_version)

        v_suffix = version.split("-", 1)[1] if "-" in version else ""
        l_suffix = latest_version.split("-", 1)[1] if "-" in latest_version else ""

        if v_int > l_int:
            return "newer than stable"
        if v_int < l_int:
            return "behind stable"
        # Same base version — compare suffixes.
        if v_suffix == l_suffix:
            return "matches stable"
        return "newer than stable"

    # ------------------------------------------------------------------
    # Output
    # ------------------------------------------------------------------

    def build_matrix(self) -> dict:
        """Build the full version matrix dict."""
        default_images = self.extract_default_images()
        test_envs = self.extract_test_environments()

        matrix = {
            "generated_at": datetime.utcnow().isoformat(),
            "default_images": {
                name: asdict(comp) for name, comp in default_images.items()
            },
            "test_environments": {},
            "summary": {
                "total_components": len(COMPONENT_REPOS),
                "environments": len(test_envs),
            },
        }

        for env_name, env in test_envs.items():
            matrix["test_environments"][env_name] = {
                "type": env.type,
                "config_file_path": env.config_file_path,
                "components": {
                    name: asdict(comp) for name, comp in env.components.items()
                },
            }

        return matrix


def main():
    parser = argparse.ArgumentParser(
        description="Extract PoS version matrix from kurtosis-pos and e2e scenarios."
    )
    parser.add_argument(
        "--kurtosis-pos-root",
        type=Path,
        default=None,
        help="Path to kurtosis-pos checkout. If omitted, constants.star is fetched from GitHub.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output path for matrix.json (default: scripts/version-matrix/matrix.json).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    output_path = args.output or repo_root / "scripts" / "version-matrix" / "matrix.json"

    # Try common local paths for kurtosis-pos.
    kp_root = args.kurtosis_pos_root
    if kp_root is None:
        for candidate in [
            repo_root.parent / "kurtosis-pos",
            repo_root / "kurtosis-pos",
        ]:
            if (candidate / "src" / "config" / "constants.star").exists():
                kp_root = candidate
                break

    if kp_root:
        print(f"Using kurtosis-pos at: {kp_root}")
    else:
        print("No local kurtosis-pos found; will fetch constants.star from GitHub.")

    extractor = VersionMatrixExtractor(repo_root, kp_root)
    matrix = extractor.build_matrix()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(matrix, f, indent=2)

    print(f"Version matrix written to {output_path}")

    # Print summary.
    for name, comp in matrix["default_images"].items():
        status = comp.get("status", "unknown")
        latest = comp.get("latest_version", "?")
        stable = comp.get("latest_stable_version", "?")
        print(f"  {name}: {comp['version']} (latest: {latest}, stable: {stable}) [{status}]")



if __name__ == "__main__":
    main()

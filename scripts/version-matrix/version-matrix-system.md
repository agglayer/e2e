# PoS Version Matrix System

This document describes the automated version matrix system for PoS E2E testing, which tracks compatibility information for the core PoS components: **bor**, **heimdall-v2**, and **erigon**.

## Overview

The version matrix system provides:

- **Automated extraction** of version information from kurtosis-pos defaults and e2e scenario configs
- **Latest release detection** from GitHub APIs
- **Status tracking** for each version (matches stable, behind, newer)
- **Known-issue tracking** for excluding buggy versions from testing
- **Human-readable documentation** generation

## Architecture

### Data Flow

```
kurtosis-pos/constants.star ──┐
                               ├─► extract-versions.py ──► matrix.json ──► generate-markdown.py ──► VERSION_MATRIX.md
scenarios/pos/*/params.yml ───┤
                               │
GitHub APIs ──────────────────┘
```

### Components

1. **Version Extraction** (`extract-versions.py`)
   - Parses `IMAGES` dict from kurtosis-pos `constants.star`
   - Scans e2e scenario `params.yml` files for pinned versions
   - Fetches latest releases from GitHub
   - Outputs `matrix.json`

2. **Markdown Generation** (`generate-markdown.py`)
   - Creates `docs/VERSION_MATRIX.md` from `matrix.json`
   - Includes status indicators and release links

3. **Known Issues** (`known-issues.yml`)
   - Tracks versions with known bugs or incompatibilities
   - Used to exclude versions from the pairwise compatibility matrix

## Usage

```bash
# Install dependencies
pip install -r scripts/version-matrix/requirements.txt

# Set GitHub token (optional, avoids rate limits)
export GITHUB_TOKEN="..."

# Extract versions (auto-detects local kurtosis-pos or fetches from GitHub)
python3 scripts/version-matrix/extract-versions.py

# Or specify kurtosis-pos path explicitly
python3 scripts/version-matrix/extract-versions.py --kurtosis-pos-root ../kurtosis-pos

# Generate Markdown
python3 scripts/version-matrix/generate-markdown.py
```

## Tracked Components

| Component | GitHub Repository | Description |
|-----------|-------------------|-------------|
| bor | [0xPolygon/bor](https://github.com/0xPolygon/bor) | PoS execution client (go-ethereum fork) |
| heimdall-v2 | [0xPolygon/heimdall-v2](https://github.com/0xPolygon/heimdall-v2) | PoS consensus client |
| erigon | [0xPolygon/erigon](https://github.com/0xPolygon/erigon) | Alternative PoS execution client |

## Version Status System

| Status | Icon | Description |
|--------|------|-------------|
| matches stable | ✅ | Version equals the latest stable release |
| newer than stable | ⚡️ | Pre-release, RC, or beta ahead of stable |
| behind stable | 🚨 | Older than the latest stable release |

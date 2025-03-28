#!/bin/bash
set -euo pipefail

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&3
}

#!/usr/bin/env bash
# compile-evm-asm.sh — Compiles .evm assembly files using the wjmelements/evm assembler.
#
# The assembler is available at: https://github.com/wjmelements/evm
#
# Usage:
#   ./scripts/compile-evm-asm.sh                           # compile all .evm files
#   ./scripts/compile-evm-asm.sh core/contracts/foo.evm    # compile a specific file
#
# Requirements:
#   - The `evm` assembler from https://github.com/wjmelements/evm must be on PATH
#     (as `evm-asm` to avoid conflict with go-ethereum's `evm`), or set EVM_ASM= env var.
#
# Installation (wjmelements/evm):
#   git clone https://github.com/wjmelements/evm /tmp/wjmelements-evm
#   cd /tmp/wjmelements-evm && make
#   sudo cp bin/evm /usr/local/bin/evm-asm   # rename to avoid conflict with geth evm
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/core/contracts/bin"

# Find the assembler binary.  Prefer EVM_ASM env, then evm-asm, then evm.
find_assembler() {
    if [[ -n "${EVM_ASM:-}" ]] && command -v "$EVM_ASM" &>/dev/null; then
        echo "$EVM_ASM"
        return 0
    fi
    if command -v evm-asm &>/dev/null; then
        echo "evm-asm"
        return 0
    fi
    # Check if `evm` is the wjmelements assembler (not go-ethereum).
    if command -v evm &>/dev/null; then
        local help_text
        help_text=$(evm --help 2>&1 || true)
        if [[ "$help_text" != *"the evm command line interface"* ]]; then
            echo "evm"
            return 0
        fi
    fi
    return 1
}

compile_file() {
    local src="$1"
    local basename
    basename="$(basename "$src" .evm)"
    local out="${BIN_DIR}/${basename}.bin"

    echo "Compiling ${src} -> ${out}"
    "$ASM" "$src" > "$out"
    echo "  OK ($(wc -c < "$out") bytes)"
}

ASM=""
if ! ASM=$(find_assembler); then
    echo "ERROR: wjmelements/evm assembler not found." >&2
    echo "" >&2
    echo "Install it:" >&2
    echo "  git clone https://github.com/wjmelements/evm /tmp/wjmelements-evm" >&2
    echo "  cd /tmp/wjmelements-evm && make" >&2
    echo "  sudo cp bin/evm /usr/local/bin/evm-asm" >&2
    echo "" >&2
    echo "Or set EVM_ASM=/path/to/evm-assembler" >&2
    exit 1
fi

echo "Using assembler: $ASM"
mkdir -p "$BIN_DIR"

if [[ $# -gt 0 ]]; then
    for f in "$@"; do
        if [[ ! -f "$f" ]]; then
            echo "ERROR: File not found: $f" >&2
            exit 1
        fi
        if [[ "$f" != *.evm ]]; then
            echo "WARNING: $f does not have .evm extension" >&2
        fi
        compile_file "$f"
    done
else
    shopt -s nullglob
    sources=("${PROJECT_ROOT}"/core/contracts/*.evm)
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No .evm files found in core/contracts/"
        exit 0
    fi
    for f in "${sources[@]}"; do
        compile_file "$f"
    done
fi

echo "Done."

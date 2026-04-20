#!/usr/bin/env bash
# Render a GitHub Actions step-summary table of BATS tests that were
# skipped in the current job's TAP output.
#
# Usage: summarize-skipped-tests.sh <pair_label>
#
# Environment:
#   TAP_FILE              path to accumulated BATS TAP output
#                         (default: /tmp/bats-tap-output.txt).
#   GITHUB_STEP_SUMMARY   standard GitHub Actions env; required for output
#                         (the script writes the markdown summary to this
#                         path in append mode).
set -euo pipefail

PAIR_LABEL="${1:?pair_label is required}"
TAP_FILE="${TAP_FILE:-/tmp/bats-tap-output.txt}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY must be set (are you running outside GitHub Actions?)}"

{
  echo "## Skipped Tests Summary (${PAIR_LABEL})"
  echo ""
  if [[ ! -f "$TAP_FILE" ]]; then
    echo "_No BATS output captured (tests may not have run)._"
  else
    skipped=$(grep '# skip' "$TAP_FILE" || true)
    if [[ -z "$skipped" ]]; then
      echo "All tests ran — none were skipped."
    else
      echo "| Test | Skip Reason |"
      echo "|------|-------------|"
      while IFS= read -r line; do
        test_name=$(echo "$line" | sed -E 's/^ok [0-9]+ //' | sed -E 's/ # skip.*$//')
        reason=$(echo "$line" | sed -E 's/.*# skip (.*)/\1/')
        echo "| ${test_name} | ${reason} |"
      done <<< "$skipped"
      echo ""
      count=$(echo "$skipped" | wc -l)
      echo "**${count} test(s) skipped** — these represent known version incompatibilities, not failures."
    fi
  fi
} >> "$GITHUB_STEP_SUMMARY"

#!/usr/bin/env bash
# Patch kurtosis-pos' constants.star with a staggered Rio+ fork schedule,
# then emit /tmp/fork-schedule.env consumed by BATS tests.
#
# Forks supported by the minimum bor version are spaced 64 blocks apart
# starting at 256 (the bor/heimdall consensus minimum).  Forks not
# supported by the minimum are pinned to 999999999 so the newer bor in a
# mixed-version devnet does not activate them and cause a consensus split.
#
# Environment:
#   BOR_MIN_VERSION     base semver of the oldest bor in the mix (required,
#                       e.g. "2.6.5" — caller is responsible for stripping
#                       any -beta / -rc suffix).
#   CONSTANTS_PATH      path to constants.star
#                       (default: kurtosis-pos/src/config/constants.star).
#   FORK_SCHEDULE_ENV   path to write fork-schedule.env to
#                       (default: /tmp/fork-schedule.env).
set -euo pipefail

: "${BOR_MIN_VERSION:?BOR_MIN_VERSION must be set (e.g. 2.6.5)}"
CONSTANTS="${CONSTANTS_PATH:-kurtosis-pos/src/config/constants.star}"
FORK_SCHEDULE_ENV="${FORK_SCHEDULE_ENV:-/tmp/fork-schedule.env}"

if [[ ! -f "$CONSTANTS" ]]; then
  echo "::error::constants.star not found at ${CONSTANTS}" >&2
  exit 1
fi

# Helper: true iff BOR_MIN_VERSION >= required.
ver_gte() {
  [[ "$(printf '%s\n%s' "$BOR_MIN_VERSION" "$1" | sort -V | head -1)" == "$1" ]]
}

# Staggered fork schedule (64-block gaps).  Gives each fork enough blocks
# for historical-state queries, base-fee boundary tests, and the
# Lisovo→LisovoPro KZG window.
declare -A FORK_BLOCKS=(
  [rio]=256
  [madhugiri]=320
  [madhugiriPro]=384
  [dandeli]=448
  [lisovo]=512
  [lisovoPro]=576
  [giugliano]=640
)

PATCH=(rio)
ver_gte "2.5.0" && PATCH+=(madhugiri madhugiriPro)
ver_gte "2.5.6" && PATCH+=(dandeli)
ver_gte "2.6.0" && PATCH+=(lisovo lisovoPro)
ver_gte "2.7.0" && PATCH+=(giugliano)

DISABLE=()
ver_gte "2.7.0" || DISABLE+=(giugliano)
ver_gte "2.6.0" || DISABLE+=(lisovo lisovoPro)
ver_gte "2.5.6" || DISABLE+=(dandeli)
ver_gte "2.5.0" || DISABLE+=(madhugiri madhugiriPro)

echo "Patching forks for min bor version ${BOR_MIN_VERSION}: ${PATCH[*]}"
for fork in "${PATCH[@]}"; do
  block="${FORK_BLOCKS[$fork]}"
  sed -i -E '/^\s+"'"${fork}"'":/s/[0-9]+/'"${block}"'/' "$CONSTANTS"
done

if [[ ${#DISABLE[@]} -gt 0 ]]; then
  echo "Disabling unsupported forks for min bor version ${BOR_MIN_VERSION}: ${DISABLE[*]}"
  for fork in "${DISABLE[@]}"; do
    sed -i -E '/^\s+"'"${fork}"'":/s/[0-9]+/999999999/' "$CONSTANTS"
  done
fi

echo "--- Patched EL_HARD_FORK_BLOCKS ---"
grep -A 20 '^EL_HARD_FORK_BLOCKS' "$CONSTANTS"

# camelCase fork keys in constants.star map to SCREAMING_SNAKE FORK_* env
# vars used by the BATS tests (madhugiriPro -> FORK_MADHUGIRI_PRO, etc.).
declare -A FORK_ENV_MAP=(
  [rio]=FORK_RIO [madhugiri]=FORK_MADHUGIRI [madhugiriPro]=FORK_MADHUGIRI_PRO
  [dandeli]=FORK_DANDELI [lisovo]=FORK_LISOVO [lisovoPro]=FORK_LISOVO_PRO
  [giugliano]=FORK_GIUGLIANO
)
{
  echo "# Auto-generated staggered fork schedule"
  echo "FORK_JAIPUR=0"; echo "FORK_DELHI=0"; echo "FORK_INDORE=0"
  echo "FORK_AGRA=0"; echo "FORK_NAPOLI=0"; echo "FORK_AHMEDABAD=0"
  echo "FORK_BHILAI=0"
  for fork in "${PATCH[@]}"; do
    echo "${FORK_ENV_MAP[$fork]}=${FORK_BLOCKS[$fork]}"
  done
  for fork in "${DISABLE[@]}"; do
    echo "${FORK_ENV_MAP[$fork]}=999999999"
  done
} > "$FORK_SCHEDULE_ENV"

echo "--- Fork schedule written to ${FORK_SCHEDULE_ENV} ---"
cat "$FORK_SCHEDULE_ENV"

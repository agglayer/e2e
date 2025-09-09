#!/usr/bin/env bats

setup(){
  load "../../core/helpers/scripts/eventually.bash"

  HEIMDALL_GET_LATEST_HEIGHT='curl --silent "${HEIMDALURL}/status" | jq -r '.result.sync_info.latest_block_height''
  
  timeout_seconds=${TIMEOUT_SECONDS:-"300"}
  interval_seconds=${INTERVAL_SECONDS:-"10"}
}

# Convert a duration string like "75s", "1m0s", "2m3s", "1h2m3s" into seconds.
parse_duration_seconds() {
  local dur="$1"
  local h=0 m=0 s=0
  # Normalize (e.g., "60s", "1m0s", "2m3s", "1h2m3s", "1h", "2m", "45s")
  [[ "$dur" =~ ^([0-9]+)h ]] && h="${BASH_REMATCH[1]}" && dur="${dur/${BASH_REMATCH[0]}/}"
  [[ "$dur" =~ ^([0-9]+)m ]] && m="${BASH_REMATCH[1]}" && dur="${dur/${BASH_REMATCH[0]}/}"
  [[ "$dur" =~ ^([0-9]+)s?$ ]] && s="${BASH_REMATCH[1]}"

  echo $(( h*3600 + m*60 + s ))
}

get_latest_height() {
  curl --silent "${HEIMDALURL}/status" \
  | jq -r '.result.sync_info.latest_block_height'
}

# Wait until the chain height is strictly greater than L2_CL_RETAIN_BLOCKS.
wait_until_height_exceeds_retain() {
  local retain_blocks="$1"

  assert_command_eventually_gt get_latest_height $retain_blocks "${timeout_seconds}" "${interval_seconds}"
}

# Sleep for the prune interval (+ small buffer) to allow pruning to run.
sleep_for_prune_interval() {
  local prune_str="$1"
  local prune_secs
  prune_secs=$(parse_duration_seconds "$prune_str")
  # Add a small buffer to be safer than exact interval.
  local buffer=10
  local total=$(( prune_secs + buffer ))

  echo "Sleeping ${total}s to allow pruning (interval=${prune_str}) to elapse..."
  sleep "${total}"
}

# Return 0 (success) if the "height not available" error is present for height=1; else 1.
check_block_pruned() {
  local resp
  local height_to_check="$1"
  resp="$(curl --silent "${HEIMDALURL}/block?height=$height_to_check")"

  # Prefer checking the structured error fields first.
  local code message data
  code="$(jq -r '.error.code // empty' <<<"$resp")"
  message="$(jq -r '.error.message // empty' <<<"$resp")"
  data="$(jq -r '.error.data // empty' <<<"$resp")"

  echo "Block query response:"
  echo "$resp" | jq

  # Successful prune example typically has:
  #   "error": {
  #     "code": -32603,
  #     "message": "Internal error",
  #     "data": "height 1 is not available, lowest height is <N>"
  #   }
  if [[ -n "$code" && "$code" != "null" ]] && [[ "$data" == *"is not available"* ]]; then
    echo "Detected pruned block  (error ${code}: ${data})"
    return 0
  fi

  # If there's a result object, then height=1 still exists (not pruned).
  local has_result
  has_result="$(jq -r 'has("result")' <<<"$resp")"
  if [[ "$has_result" == "true" ]]; then
    echo "Block still present (not pruned)."
    return 1
  fi

  echo "Unexpected response; cannot confirm pruning."
  return 1
}

# bats file_tags=pos,hv2,prune
@test "txIndexerPrune works" {
  echo "Step 1: Get current height"
  local latest_height
  latest_height="$(get_latest_height)"
  local wait_until_block=$((latest_height + L2_CL_RETAIN_BLOCKS))

  echo "Step 2: wait until height exceed $wait_until_block"
  run wait_until_height_exceeds_retain "${wait_until_block}"
  [ "$status" -eq 0 ]

  echo "Step 3: wait for prune interval: ${L2_CL_PRUNE_INTERVAL}"
  run sleep_for_prune_interval "${L2_CL_PRUNE_INTERVAL}"
  [ "$status" -eq 0 ]

  echo "Step 4: check block #$latest_height is pruned"
  run check_block_pruned $latest_height
  if [ "$status" -ne 0 ]; then
    echo "Expected block #$latest_height to be unavailable after pruning."
    echo "Hints:"
    echo "- Verify L2_CL_PRUNE_INTERVAL is set to the actual pruning cadence."
    echo "- Verify L2_CL_RETAIN_BLOCKS is small enough relative to current height."
    echo "- Check node logs to ensure the pruner is enabled."
  fi
  [ "$status" -eq 0 ]
}
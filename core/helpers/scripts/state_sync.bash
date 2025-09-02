#!/bin/bash
set -euo pipefail

  # Helper: assert the receipts JSON contains the StateSync log w/ expected id
function  assert_statesync_in_receipts_json() {
    local json="$1"
    local where="$2"  # label for messages

    local id_hex
    id_hex="$(jq -r --arg topic "${TOPIC_STATE_SYNC}" --arg em "${EMITTER_ADDR}" '
      def rcpts:
        if type=="object" and has("result") then
          (.result | if type=="array" then . else [.] end)
        elif type=="object" and has("logs") then
          [ . ]                    # already a single receipt object
        elif type=="array" then
          .                        # already an array of receipts
        else
          []                       # unknown shape
        end;

      rcpts
      | [ .[] | .logs[]?
          | select((.address|ascii_downcase) == ($em|ascii_downcase))
          | select((.topics|length) > 1 and .topics[0] == $topic)
          | .topics[1] ] | last // empty
    ' <<< "$json")"

    if [ -z "$id_hex" ] || [ "$id_hex" = "null" ]; then
      echo "FAIL(${where}): StateSync log not found"
      return 1
    fi

    local id_dec
    id_dec="$(cast to-dec "$id_hex")"
    if [ "$id_dec" -ne "$expected_id" ]; then
      echo "FAIL(${where}): StateSync id ${id_dec} != expected ${expected_id}"
      return 1
    fi

    echo "OK(${where}): StateSync id ${id_dec}"
    return 0
  }

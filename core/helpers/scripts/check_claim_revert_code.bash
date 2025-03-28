#!/bin/bash
set -euo pipefail

function check_claim_revert_code() {
    local file_curl_response="$1"
    local response_content
    response_content=$(<"$file_curl_response")

    # 0x646cf558 -> AlreadyClaimed()
    log "💡 Check claim revert code"
    log "$response_content"

    if grep -q "0x646cf558" <<<"$response_content"; then
        log "🎉 Deposit is already claimed (revert code 0x646cf558)"
        return 0
    fi

    # 0x002f6fad -> GlobalExitRootInvalid(), meaning that the global exit root is not yet injected to the destination network
    if grep -q "0x002f6fad" <<<"$response_content"; then
        log "⏳ GlobalExitRootInvalid() (revert code 0x002f6fad)"
        return 2
    fi

    log "❌ Claim failed. response: $response_content"
    return 1
}

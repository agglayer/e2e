#!/bin/bash
set -euo pipefail

function wait_to_settled_certificate_containing_global_index() {
    local _aggkit_pp1_node_url=$1
    local _global_index=$2
    local _check_frequency=${3:-30}
    local _timeout=${4:-300}
    log "Waiting for certificate with global index $_global_index" >&3
    run_with_timeout "wait certificate settle for $_global_index" $_check_frequency $_timeout $AGGSENDER_IMPORTED_BRIDGE_PATH $_aggkit_pp1_node_url $_global_index
}

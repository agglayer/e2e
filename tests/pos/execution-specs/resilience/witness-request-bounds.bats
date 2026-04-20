#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,resilience,witness,s1

# Witness Request Bounds
# ======================
# These tests exercise Bor's `wit` devp2p capability using an external peer
# helper. Before running the oversized request, the suite first requires a
# count=1 control request to succeed against the selected target so disconnects
# from a broken probe/helper path do not register as successful "rejections".
# The secure expectation is that oversized request cardinality is rejected early
# instead of being processed into a full normal response. We intentionally send
# requests that are 256x Ethereum's 1024-item request reference limit so unsafe
# acceptance is obvious in both test output and external monitoring.

readonly ETH_REQUEST_REFERENCE_LIMIT=1024
readonly WIT_STRESS_MULTIPLIER=256

setup_file() {
    load "../../../../core/helpers/pos-setup.bash"
    pos_setup

    local helper_src helper_bin genesis_file

    helper_src="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && cd ../../../../core/golang && pwd)"
    helper_bin="${BATS_FILE_TMPDIR}/borwitprobe"
    genesis_file="${BATS_FILE_TMPDIR}/l2-genesis.json"

    if [[ -d "${helper_src}/tools/borwitprobe" ]]; then
        echo "Building borwitprobe helper..." >&3
        if (cd "${helper_src}" && go build -o "${helper_bin}" ./tools/borwitprobe/) 2>&3; then
            echo "${helper_bin}" > "${BATS_FILE_TMPDIR}/wit_helper"
        else
            echo "WARNING: borwitprobe build failed — witness bounds tests will skip." >&3
            echo "" > "${BATS_FILE_TMPDIR}/wit_helper"
        fi
    else
        echo "WARNING: borwitprobe source not found — witness bounds tests will skip." >&3
        echo "" > "${BATS_FILE_TMPDIR}/wit_helper"
    fi

    if kurtosis files inspect "${ENCLAVE_NAME}" l2-el-genesis genesis.json > "${genesis_file}" 2>/dev/null; then
        echo "${genesis_file}" > "${BATS_FILE_TMPDIR}/wit_genesis"
    else
        echo "WARNING: Could not fetch l2-el genesis.json — witness bounds tests will skip." >&3
        echo "" > "${BATS_FILE_TMPDIR}/wit_genesis"
    fi

    _discover_wit_target
}

setup() {
    load "../../../../core/helpers/pos-setup.bash"
    load "../../../../core/helpers/scripts/resilience-helpers.bash"
    pos_setup
    _require_devnet

    WIT_HELPER="$(cat "${BATS_FILE_TMPDIR}/wit_helper" 2>/dev/null || true)"
    WIT_GENESIS="$(cat "${BATS_FILE_TMPDIR}/wit_genesis" 2>/dev/null || true)"
    WIT_TARGET_SERVICE="$(cat "${BATS_FILE_TMPDIR}/wit_target_service" 2>/dev/null || true)"
    WIT_TARGET_RPC_URL="$(cat "${BATS_FILE_TMPDIR}/wit_target_rpc" 2>/dev/null || true)"
    WIT_TARGET_ENODE="$(cat "${BATS_FILE_TMPDIR}/wit_target_enode" 2>/dev/null || true)"
    WIT_TARGET_ERROR="$(cat "${BATS_FILE_TMPDIR}/wit_target_error" 2>/dev/null || true)"
    WIT_REQUEST_HASH="$(cat "${BATS_FILE_TMPDIR}/wit_request_hash" 2>/dev/null || true)"

    if [[ -z "${WIT_HELPER}" || ! -x "${WIT_HELPER}" ]]; then
        skip "borwitprobe helper is unavailable"
    fi
    if [[ -z "${WIT_GENESIS}" || ! -f "${WIT_GENESIS}" ]]; then
        skip "L2 genesis.json is unavailable"
    fi
    if [[ -n "${WIT_TARGET_ERROR}" ]]; then
        echo "${WIT_TARGET_ERROR}" >&2
        return 1
    fi
    if [[ -z "${WIT_TARGET_SERVICE}" || -z "${WIT_TARGET_RPC_URL}" || -z "${WIT_TARGET_ENODE}" ]]; then
        skip "No witness-enabled Bor node discovered; deploy a node with el_bor_produce_witness=true or set WIT_TARGET_SERVICE"
    fi
    if [[ -z "${WIT_REQUEST_HASH}" ]]; then
        echo "FAIL: witness request preflight did not select a usable block hash" >&2
        return 1
    fi

    echo "WIT oversized request target: $(( ETH_REQUEST_REFERENCE_LIMIT * WIT_STRESS_MULTIPLIER )) items (256x Ethereum's 1024-item reference limit)" >&3
}

_normalize_hostport() {
    local raw="$1"
    raw="${raw#http://}"
    raw="${raw#https://}"
    printf '%s' "${raw}"
}

_service_rpc_url() {
    local svc="$1"
    kurtosis port print "${ENCLAVE_NAME}" "${svc}" rpc 2>/dev/null
}

_service_discovery_hostport() {
    local svc="$1"
    local raw
    raw="$(kurtosis port print "${ENCLAVE_NAME}" "${svc}" discovery 2>/dev/null)" || return 1
    _normalize_hostport "${raw}"
}

_service_internal_enode() {
    local svc="$1"
    local rpc_url payload
    rpc_url="$(_service_rpc_url "${svc}")" || return 1
    payload='{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}'
    curl -s -m 10 --connect-timeout 5 -X POST "${rpc_url}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        | jq -r '.result.enode // empty'
}

_service_external_enode() {
    local svc="$1"
    local internal_enode discovery_hostport pubkey

    internal_enode="$(_service_internal_enode "${svc}")" || return 1
    [[ -n "${internal_enode}" ]] || return 1

    discovery_hostport="$(_service_discovery_hostport "${svc}")" || return 1
    [[ -n "${discovery_hostport}" ]] || return 1

    pubkey="${internal_enode#enode://}"
    pubkey="${pubkey%@*}"
    [[ -n "${pubkey}" ]] || return 1

    printf 'enode://%s@%s' "${pubkey}" "${discovery_hostport}"
}

_probe_wit_support() {
    local enode="$1"
    "${BATS_FILE_TMPDIR}/borwitprobe" --mode probe --enode "${enode}" 2>/dev/null || true
}

_service_block_hash() {
    local rpc_url="$1"
    local block_ref="$2"
    cast block "${block_ref}" --rpc-url "${rpc_url}" --json 2>/dev/null | jq -r '.hash // empty'
}

_run_wit_helper_json() {
    local mode="$1"
    local rpc_url="$2"
    local enode="$3"
    local hash="$4"
    local count="$5"
    local helper_bin genesis_file
    shift 5

    helper_bin="$(cat "${BATS_FILE_TMPDIR}/wit_helper" 2>/dev/null || true)"
    genesis_file="$(cat "${BATS_FILE_TMPDIR}/wit_genesis" 2>/dev/null || true)"
    [[ -n "${helper_bin}" && -x "${helper_bin}" && -n "${genesis_file}" && -f "${genesis_file}" ]] || return 1

    "${helper_bin}" \
        --mode "${mode}" \
        --enode "${enode}" \
        --rpc-url "${rpc_url}" \
        --genesis "${genesis_file}" \
        --count "${count}" \
        --hash "${hash}" \
        --timeout "${BOR_WIT_HELPER_TIMEOUT:-60s}" \
        "$@" 2>/dev/null
}

_response_count_for() {
    local helper_json="$1"
    jq -r '.response_count // 0' <<< "${helper_json}" 2>/dev/null || echo 0
}

_outcome_for() {
    local helper_json="$1"
    jq -r '.outcome // empty' <<< "${helper_json}" 2>/dev/null || true
}

_wit_request_path_ok() {
    local rpc_url="$1"
    local enode="$2"
    local hash="$3"
    local metadata_json witness_json metadata_outcome witness_outcome metadata_count witness_count

    metadata_json="$(_run_wit_helper_json get-witness-metadata "${rpc_url}" "${enode}" "${hash}" 1)"
    metadata_outcome="$(_outcome_for "${metadata_json}")"
    metadata_count="$(_response_count_for "${metadata_json}")"

    witness_json="$(_run_wit_helper_json get-witness "${rpc_url}" "${enode}" "${hash}" 1)"
    witness_outcome="$(_outcome_for "${witness_json}")"
    witness_count="$(_response_count_for "${witness_json}")"

    if [[ "${metadata_outcome}" == "response" && "${metadata_count}" -eq 1 &&
        "${witness_outcome}" == "response" && "${witness_count}" -eq 1 ]]; then
        printf '%s\n%s\n' "${metadata_json}" "${witness_json}" > "${BATS_FILE_TMPDIR}/wit_preflight_last"
        return 0
    fi

    {
        echo "hash=${hash}"
        echo "metadata=${metadata_json}"
        echo "witness=${witness_json}"
    } > "${BATS_FILE_TMPDIR}/wit_preflight_last"
    return 1
}

_find_usable_wit_hash() {
    local rpc_url="$1"
    local enode="$2"
    local latest_block offset candidate hash

    if [[ -n "${BOR_WIT_REQUEST_HASH:-}" ]]; then
        hash="${BOR_WIT_REQUEST_HASH}"
        if _wit_request_path_ok "${rpc_url}" "${enode}" "${hash}"; then
            printf '%s' "${hash}"
            return 0
        fi
        return 1
    fi

    latest_block="$(cast block-number --rpc-url "${rpc_url}" 2>/dev/null || true)"
    [[ "${latest_block}" =~ ^[0-9]+$ ]] || return 1

    for offset in 0 1 2 4 8 16 32; do
        candidate=$(( latest_block - offset ))
        if (( candidate < 0 )); then
            continue
        fi
        hash="$(_service_block_hash "${rpc_url}" "${candidate}")"
        [[ -n "${hash}" ]] || continue
        if _wit_request_path_ok "${rpc_url}" "${enode}" "${hash}"; then
            printf '%s' "${hash}"
            return 0
        fi
    done

    return 1
}

_discover_wit_target() {
    local helper candidate_svc candidate_rpc candidate_enode probe_json outcome explicit_svc request_hash
    local first_probe_failure=""

    helper="$(cat "${BATS_FILE_TMPDIR}/wit_helper" 2>/dev/null || true)"
    if [[ -z "${helper}" || ! -x "${helper}" ]]; then
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_service"
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_rpc"
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_enode"
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_error"
        echo "" > "${BATS_FILE_TMPDIR}/wit_request_hash"
        return 0
    fi

    : > "${BATS_FILE_TMPDIR}/wit_target_error"
    : > "${BATS_FILE_TMPDIR}/wit_request_hash"

    explicit_svc="${WIT_TARGET_SERVICE:-}"
    if [[ -n "${explicit_svc}" ]]; then
        if candidate_rpc="$(_service_rpc_url "${explicit_svc}")" &&
            candidate_enode="$(_service_external_enode "${explicit_svc}")"; then
            probe_json="$(_probe_wit_support "${candidate_enode}")"
            outcome="$(jq -r '.outcome // empty' <<< "${probe_json}" 2>/dev/null || true)"
            if [[ "${outcome}" == "probe_ok" ]]; then
                if request_hash="$(_find_usable_wit_hash "${candidate_rpc}" "${candidate_enode}")"; then
                    echo "${explicit_svc}" > "${BATS_FILE_TMPDIR}/wit_target_service"
                    echo "${candidate_rpc}" > "${BATS_FILE_TMPDIR}/wit_target_rpc"
                    echo "${candidate_enode}" > "${BATS_FILE_TMPDIR}/wit_target_enode"
                    echo "${request_hash}" > "${BATS_FILE_TMPDIR}/wit_request_hash"
                    echo "Witness target (explicit): ${explicit_svc}" >&3
                    return 0
                fi
                first_probe_failure="Explicit target ${explicit_svc} advertises wit support but failed count=1 control requests: $(tr '\n' ' ' < "${BATS_FILE_TMPDIR}/wit_preflight_last")"
            fi
        fi
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_service"
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_rpc"
        echo "" > "${BATS_FILE_TMPDIR}/wit_target_enode"
        echo "" > "${BATS_FILE_TMPDIR}/wit_request_hash"
        if [[ -n "${first_probe_failure}" ]]; then
            echo "${first_probe_failure}" > "${BATS_FILE_TMPDIR}/wit_target_error"
            echo "${first_probe_failure}" >&3
            return 0
        fi
        echo "No witness support found on explicit target ${explicit_svc}" >&3
        return 0
    fi

    for role in rpc validator archive; do
        for i in $(seq 1 12); do
            candidate_svc="l2-el-${i}-bor-heimdall-v2-${role}"
            if ! candidate_rpc="$(_service_rpc_url "${candidate_svc}")"; then
                continue
            fi
            if ! candidate_enode="$(_service_external_enode "${candidate_svc}")"; then
                continue
            fi

            probe_json="$(_probe_wit_support "${candidate_enode}")"
            outcome="$(jq -r '.outcome // empty' <<< "${probe_json}" 2>/dev/null || true)"
            if [[ "${outcome}" == "probe_ok" ]]; then
                if request_hash="$(_find_usable_wit_hash "${candidate_rpc}" "${candidate_enode}")"; then
                    echo "${candidate_svc}" > "${BATS_FILE_TMPDIR}/wit_target_service"
                    echo "${candidate_rpc}" > "${BATS_FILE_TMPDIR}/wit_target_rpc"
                    echo "${candidate_enode}" > "${BATS_FILE_TMPDIR}/wit_target_enode"
                    echo "${request_hash}" > "${BATS_FILE_TMPDIR}/wit_request_hash"
                    echo "Witness target discovered: ${candidate_svc} (hash ${request_hash})" >&3
                    return 0
                fi
                if [[ -z "${first_probe_failure}" ]]; then
                    first_probe_failure="Witness request preflight failed on ${candidate_svc}: $(tr '\n' ' ' < "${BATS_FILE_TMPDIR}/wit_preflight_last")"
                fi
            fi
        done
    done

    echo "" > "${BATS_FILE_TMPDIR}/wit_target_service"
    echo "" > "${BATS_FILE_TMPDIR}/wit_target_rpc"
    echo "" > "${BATS_FILE_TMPDIR}/wit_target_enode"
    echo "" > "${BATS_FILE_TMPDIR}/wit_request_hash"
    if [[ -n "${first_probe_failure}" ]]; then
        echo "${first_probe_failure}" > "${BATS_FILE_TMPDIR}/wit_target_error"
        echo "${first_probe_failure}" >&3
        return 0
    fi
    echo "No witness-enabled Bor node discovered in enclave ${ENCLAVE_NAME}" >&3
}

_assert_oversized_wit_rejected() {
    local label="$1"
    local want_count="$2"
    local helper_json="$3"
    local outcome response_count
    outcome="$(jq -r '.outcome // empty' <<< "${helper_json}")"
    response_count="$(jq -r '.response_count // 0' <<< "${helper_json}")"

    echo "${label}: ${helper_json}" >&3

    if [[ "${outcome}" == "response" ]]; then
        echo "FAIL: ${label} received a normal witness response for oversized request (count=${want_count}, response_count=${response_count}). Bor should reject a request this large." >&2
        return 1
    fi
    if [[ "${outcome}" == "write_error" ]]; then
        echo "FAIL: ${label} was never sent because the helper hit a local write limit. Lower the request size or raise the helper/frame limit before using this value." >&2
        return 1
    fi
    if [[ -z "${outcome}" ]]; then
        echo "FAIL: ${label} returned malformed helper output for oversized request" >&2
        return 1
    fi
    case "${outcome}" in
        disconnect|timeout)
            return 0
            ;;
        *)
            echo "FAIL: ${label} returned unexpected outcome=${outcome} for oversized request. Expected Bor to reject on the peer side, not a harness/setup failure." >&2
            return 1
            ;;
    esac
}

# bats test_tags=resilience,witness,s1,metadata
@test "WIT: oversized GetWitnessMetadata request is rejected" {
    local count start_block
    count="${BOR_WIT_METADATA_REQUEST_COUNT:-$(( ETH_REQUEST_REFERENCE_LIMIT * WIT_STRESS_MULTIPLIER ))}"
    start_block="$(cast block-number --rpc-url "${WIT_TARGET_RPC_URL}")"

    run "${WIT_HELPER}" \
        --mode get-witness-metadata \
        --enode "${WIT_TARGET_ENODE}" \
        --rpc-url "${WIT_TARGET_RPC_URL}" \
        --genesis "${WIT_GENESIS}" \
        --count "${count}" \
        --hash "${WIT_REQUEST_HASH}" \
        --timeout "${BOR_WIT_HELPER_TIMEOUT:-60s}"

    _assert_oversized_wit_rejected "GetWitnessMetadata" "${count}" "${output}"
    _assert_rpc_alive "${WIT_TARGET_RPC_URL}" "after oversized GetWitnessMetadata"
    _wait_for_block_advance "${start_block}" 3 30
}

# bats test_tags=resilience,witness,s1,pages
@test "WIT: oversized GetWitness request is rejected" {
    local count start_block
    count="${BOR_WIT_PAGES_REQUEST_COUNT:-$(( ETH_REQUEST_REFERENCE_LIMIT * WIT_STRESS_MULTIPLIER ))}"
    start_block="$(cast block-number --rpc-url "${WIT_TARGET_RPC_URL}")"

    run "${WIT_HELPER}" \
        --mode get-witness \
        --enode "${WIT_TARGET_ENODE}" \
        --rpc-url "${WIT_TARGET_RPC_URL}" \
        --genesis "${WIT_GENESIS}" \
        --count "${count}" \
        --hash "${WIT_REQUEST_HASH}" \
        --unique \
        --timeout "${BOR_WIT_HELPER_TIMEOUT:-60s}"

    _assert_oversized_wit_rejected "GetWitness" "${count}" "${output}"
    _assert_rpc_alive "${WIT_TARGET_RPC_URL}" "after oversized GetWitness"
    _wait_for_block_advance "${start_block}" 3 30
}

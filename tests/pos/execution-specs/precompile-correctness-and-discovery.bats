#!/usr/bin/env bats
# bats file_tags=pos,execution-specs,pos-precompile

# Precompile detection and verification tests for Polygon PoS (Bor).
#
# Two test categories:
#
#   1. Fuzz scan – sends JSON-RPC batch requests (N independent eth_calls per
#      HTTP body) to probe every address in 0x0001..PRECOMPILE_FUZZ_MAX.
#      Because each call targets exactly ONE address there is no cumulative gas
#      budget and no eth_call gas-cap problem.  Fails if any address returns
#      non-trivial data AND is not in the KNOWN_PRECOMPILES list below.
#      Update that list whenever a new precompile is intentionally shipped.
#
#   2. Correctness – exercises each known precompile with a concrete test vector
#      to ensure it is active and returning the expected output.
#
# Environment:
#   PRECOMPILE_FUZZ_MAX   upper bound address (decimal, default 65535 = 0xFFFF)
#   L2_RPC_URL            override Bor RPC (default: discovered via Kurtosis)

# ────────────────────────────────────────────────────────────────────────────
# Setup
# ────────────────────────────────────────────────────────────────────────────

setup() {
  load "../../../core/helpers/pos-setup.bash"
  load "../../../core/helpers/scripts/eventually.bash"
  pos_setup
}

# ────────────────────────────────────────────────────────────────────────────
# Shared helpers
# ────────────────────────────────────────────────────────────────────────────

# Call a precompile address with raw hex calldata.
# Returns the hex output string (including 0x prefix), or empty on revert/error.
function _call() {
  local addr="$1"
  local input="${2:-0x}"
  local out
  out=$(cast call --rpc-url "${L2_RPC_URL}" "${addr}" "${input}" 2>/dev/null) || out=""
  echo "${out}"
}

# Returns 0 (true) when the hex string is non-empty AND has at least one
# non-zero nibble (i.e. "0x" alone or "0x000...0" are both considered trivial).
function _is_nontrivial() {
  local data="${1#0x}"
  [[ -n "${data}" && "${data//0/}" != "" ]]
}

# ────────────────────────────────────────────────────────────────────────────
# Fuzz scan (JSON-RPC batch requests – no on-chain gas budget)
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pos-precompile,precompile-fuzz
@test "fuzz scan: no unknown precompiles in 0x0001..PRECOMPILE_FUZZ_MAX" {
  # ── Known-precompile registry ─────────────────────────────────────────────
  # Lowercase 40-char hex addresses WITHOUT 0x prefix.
  # Add entries here whenever a new precompile is intentionally shipped.
  # Known precompiles by hardfork / Bor fork name.
  # Bor maps Ethereum hardforks to its own names; only the forks active on
  # this devnet will have the corresponding precompiles enabled.
  #
  #   Frontier / Homestead : 0x01–0x04 (ecRecover, SHA-256, RIPEMD-160, identity)
  #   Byzantium            : 0x05–0x08 (modexp, bn256Add/Mul/Pairing)
  #   Istanbul             : 0x09 blake2F
  #   Cancun / Bor Lisovo  : 0x0a kzgPointEvaluation (EIP-4844)
  #   Prague / Bor Madhugiri: 0x0b–0x11 BLS12-381 suite (EIP-2537)
  #                           0x0b G1Add  0x0c G1MSM  0x0d G2Add  0x0e G2MSM
  #                           0x0f Pairing  0x10 MapFpToG1  0x11 MapFp2ToG2
  #   Cancun / Bor MadhugiriPro: 0x0100 p256Verify / secp256r1 (RIP-7212)
  local -a known_precompiles=(
    "0000000000000000000000000000000000000001"  # ecRecover       (Homestead)
    "0000000000000000000000000000000000000002"  # SHA-256          (Homestead)
    "0000000000000000000000000000000000000003"  # RIPEMD-160       (Homestead)
    "0000000000000000000000000000000000000004"  # identity         (Homestead)
    "0000000000000000000000000000000000000005"  # modexp           (Byzantium)
    "0000000000000000000000000000000000000006"  # bn256Add         (Byzantium)
    "0000000000000000000000000000000000000007"  # bn256ScalarMul   (Byzantium)
    "0000000000000000000000000000000000000008"  # bn256Pairing     (Byzantium)
    "0000000000000000000000000000000000000009"  # blake2F          (Istanbul)
    "000000000000000000000000000000000000000a"  # kzgPointEval     (Lisovo)
    "000000000000000000000000000000000000000b"  # BLS12 G1 Add     (Madhugiri)
    "000000000000000000000000000000000000000c"  # BLS12 G1 MSM     (Madhugiri)
    "000000000000000000000000000000000000000d"  # BLS12 G2 Add     (Madhugiri)
    "000000000000000000000000000000000000000e"  # BLS12 G2 MSM     (Madhugiri)
    "000000000000000000000000000000000000000f"  # BLS12 Pairing    (Madhugiri)
    "0000000000000000000000000000000000000010"  # BLS12 MapFpToG1  (Madhugiri)
    "0000000000000000000000000000000000000011"  # BLS12 MapFp2ToG2 (Madhugiri)
    "0000000000000000000000000000000000000100"  # p256Verify       (MadhugiriPro)
    # "0000000000000000000000000000000000000012" # Testing purposes - precompile doesn't exist
  )

  local -A known_set=()
  for addr in "${known_precompiles[@]}"; do
    known_set["${addr}"]=1
  done

  # ── Scan using JSON-RPC batch requests ────────────────────────────────────
  # JSON-RPC 2.0 allows an array of requests in a single HTTP body.  Each
  # element is an independent eth_call to ONE address, so there is no
  # cumulative gas budget – no eth_call gas-cap problem regardless of range.
  #
  # Two probes are sent as separate batch requests per chunk:
  #   Probe A – 32-byte non-zero value: triggers SHA-256 / RIPEMD-160 / identity
  #   Probe B – empty calldata:         triggers ecPairing (returns 0x1 for ∅)
  #
  # "Non-trivial" result: eth_call succeeded (result field present, not an
  # error/revert) AND the returned hex has at least one non-zero nibble.
  local max="${PRECOMPILE_FUZZ_MAX:-65535}"
  # Bor enforces a JSON-RPC batch limit of 100 requests per HTTP call.
  # Exceeding it returns a single error object (not an array), which silently
  # breaks detection.  Keep well under the limit.
  local batch_size=80   # addresses per JSON-RPC batch HTTP call
  echo "Scan range: 0x0001..0x$(printf '%04x' "${max}") in batches of ${batch_size}"

  local -a all_active=()
  local -a unknown=()

  for ((bstart = 1; bstart <= max; bstart += batch_size)); do
    local bend=$(( bstart + batch_size - 1 ))
    (( bend > max )) && bend=${max}
    echo "  Batch 0x$(printf '%04x' "${bstart}")..0x$(printf '%04x' "${bend}")"

    # Build two JSON-RPC batch payloads (Probe A and Probe B) in parallel.
    local pa_payload="[" pb_payload="["
    for ((i = bstart; i <= bend; i++)); do
      local a
      a=$(printf "%040x" "$i")
      [[ $i -gt $bstart ]] && { pa_payload+=","; pb_payload+=","; }
      pa_payload+="{\"jsonrpc\":\"2.0\",\"id\":${i},\"method\":\"eth_call\",\"params\":[{\"to\":\"0x${a}\",\"data\":\"0x0000000000000000000000000000000000000000000000000000000000000001\"},\"latest\"]}"
      pb_payload+="{\"jsonrpc\":\"2.0\",\"id\":${i},\"method\":\"eth_call\",\"params\":[{\"to\":\"0x${a}\",\"data\":\"0x\"},\"latest\"]}"
    done
    pa_payload+="]"; pb_payload+="]"

    local resp_a resp_b
    resp_a=$(curl -s -X POST -H "Content-Type: application/json" -d "${pa_payload}" "${L2_RPC_URL}")
    resp_b=$(curl -s -X POST -H "Content-Type: application/json" -d "${pb_payload}" "${L2_RPC_URL}")

    # Guard: if either response is not a JSON array the node rejected the batch
    # (e.g. batch-size limit exceeded).  Fail loudly rather than silently pass.
    for _resp_label in "Probe-A:${resp_a}" "Probe-B:${resp_b}"; do
      local _label="${_resp_label%%:*}" _body="${_resp_label#*:}"
      if ! echo "${_body}" | jq -e 'type == "array"' > /dev/null 2>&1; then
        local _errmsg
        _errmsg=$(echo "${_body}" | jq -r '.error.message // "non-array response"' 2>/dev/null || echo "non-array response")
        echo "ERROR: ${_label} batch rejected for 0x$(printf '%04x' "${bstart}")..0x$(printf '%04x' "${bend}"): ${_errmsg}"
        return 1
      fi
    done

    # Collect the decimal request IDs where either probe returned non-trivial
    # output.  jq processes both JSON arrays sequentially (one per line).
    local -A responding=()
    while IFS= read -r id; do
      [[ -n "${id}" ]] && responding["${id}"]=1
    done < <(
      printf '%s\n' "${resp_a}" "${resp_b}" | \
        jq -r '.[] |
                select(.result != null) |
                select(.result | ltrimstr("0x") | test("[^0]")) |
                .id | tostring'
    )

    for dec_addr in "${!responding[@]}"; do
      local hex_addr
      hex_addr=$(printf "%040x" "${dec_addr}")

      # Skip addresses with deployed bytecode – those are system contracts,
      # not EVM precompiles.
      local code
      code=$(cast code --rpc-url "${L2_RPC_URL}" "0x${hex_addr}" 2>/dev/null) || code="0x"
      if [[ "${code}" != "0x" && -n "${code}" ]]; then
        echo "    [0x${hex_addr}] has deployed bytecode – skipping (system contract)"
        continue
      fi

      all_active+=("0x${hex_addr}")
      echo "    Active: 0x${hex_addr} (decimal ${dec_addr})"

      if [[ -z "${known_set[${hex_addr}]+_}" ]]; then
        echo "    FAIL: 0x${hex_addr} is NOT in the known precompile list"
        unknown+=("0x${hex_addr}")
      fi
    done
  done

  echo ""
  echo "Summary:"
  echo "  Scan range : 0x0001..0x$(printf '%04x' "${max}")"
  echo "  Known      : ${#known_precompiles[@]}"
  echo "  Active     : ${#all_active[@]}  (${all_active[*]:-none})"
  echo "  Unknown    : ${#unknown[@]}  (${unknown[*]:-none})"

  if [[ "${#unknown[@]}" -gt 0 ]]; then
    echo ""
    echo "ERROR: The following addresses responded to probe inputs but are NOT"
    echo "in the known_precompiles list. Either register them (if intentional)"
    echo "or investigate."
    for u in "${unknown[@]}"; do
      echo "  ${u}"
    done
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Correctness tests – one per known precompile
# ────────────────────────────────────────────────────────────────────────────

# bats test_tags=execution-specs,pos-precompile
@test "0x01 ecRecover: recovers signer from a valid ECDSA signature" {
  # Standard ecRecover test vector (128-byte input: hash || v || r || s).
  # Source: https://ethereum.github.io/execution-specs/src/ethereum/cancun/vm/precompiled_contracts/ecrecover.html
  local input="0x"
  input+="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"  # msg hash
  input+="000000000000000000000000000000000000000000000000000000000000001c"  # v = 28
  input+="9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"  # r
  input+="4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"  # s

  local out
  out=$(_call "0x0000000000000000000000000000000000000001" "${input}")
  echo "ecRecover output: ${out}"

  # Non-empty, non-all-zero output indicates a valid address was recovered.
  _is_nontrivial "${out}"
}

# bats test_tags=execution-specs,pos-precompile
@test "0x02 SHA-256: hash of empty string equals known constant" {
  # sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  local out
  out=$(_call "0x0000000000000000000000000000000000000002" "0x")
  echo "sha256('') = ${out}"
  [[ "${out}" == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x03 RIPEMD-160: hash of empty string equals known constant" {
  # ripemd160("") = 9c1185a5c5e9fc54612808977ee8f548b2258d31 (20 bytes, left-padded to 32)
  local out
  out=$(_call "0x0000000000000000000000000000000000000003" "0x")
  echo "ripemd160('') = ${out}"
  [[ "${out}" == "0x0000000000000000000000009c1185a5c5e9fc54612808977ee8f548b2258d31" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x04 identity: returns input bytes unchanged" {
  local input="0xdeadbeefcafebabe0102030405060708090a0b0c0d0e0f101112131415161718"
  local out
  out=$(_call "0x0000000000000000000000000000000000000004" "${input}")
  echo "identity output: ${out}"
  [[ "${out}" == "${input}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x05 modexp: 8^9 mod 10 equals 8" {
  # 8^9 mod 10: powers of 8 mod 10 cycle as 8→4→2→6→8…, exponent 9 ≡ 1 (mod 4) → 8.
  # Input layout (EIP-198): len(B)(32) || len(E)(32) || len(M)(32) || B || E || M
  local input="0x"
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # len(B) = 1
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # len(E) = 1
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # len(M) = 1
  input+="08"   # B = 8
  input+="09"   # E = 9
  input+="0a"   # M = 10
  local out
  out=$(_call "0x0000000000000000000000000000000000000005" "${input}")
  echo "modexp(8,9,10) = ${out}"
  [[ "${out}" == "0x08" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x06 ecAdd (alt_bn128): G + G returns a valid non-zero curve point" {
  # Add the alt_bn128 generator G = (1, 2) to itself.
  # Result: 2·G = a valid 64-byte affine point (non-zero).
  local input="0x"
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # x1
  input+="0000000000000000000000000000000000000000000000000000000000000002"  # y1
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # x2
  input+="0000000000000000000000000000000000000000000000000000000000000002"  # y2
  local out
  out=$(_call "0x0000000000000000000000000000000000000006" "${input}")
  echo "ecAdd(G, G) = ${out}"
  _is_nontrivial "${out}"
}

# bats test_tags=execution-specs,pos-precompile
@test "0x07 ecMul (alt_bn128): 2·G matches ecAdd(G, G)" {
  # ecMul(G, 2) should yield the same point as ecAdd(G, G).
  local input_mul="0x"
  input_mul+="0000000000000000000000000000000000000000000000000000000000000001"  # x
  input_mul+="0000000000000000000000000000000000000000000000000000000000000002"  # y
  input_mul+="0000000000000000000000000000000000000000000000000000000000000002"  # k = 2

  local input_add="0x"
  input_add+="0000000000000000000000000000000000000000000000000000000000000001"
  input_add+="0000000000000000000000000000000000000000000000000000000000000002"
  input_add+="0000000000000000000000000000000000000000000000000000000000000001"
  input_add+="0000000000000000000000000000000000000000000000000000000000000002"

  local out_mul out_add
  out_mul=$(_call "0x0000000000000000000000000000000000000007" "${input_mul}")
  out_add=$(_call "0x0000000000000000000000000000000000000006" "${input_add}")

  echo "ecMul(G, 2) = ${out_mul}"
  echo "ecAdd(G, G) = ${out_add}"

  _is_nontrivial "${out_mul}"
  [[ "${out_mul}" == "${out_add}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x08 ecPairing (alt_bn128): empty input returns 1 (trivial pairing check)" {
  # An empty pairing set is defined to be true (e(∅) = 1).
  local out
  out=$(_call "0x0000000000000000000000000000000000000008" "0x")
  echo "ecPairing([]) = ${out}"
  [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x09 blake2F: EIP-152 test vector 5 (12 rounds, 'abc' message)" {
  # Reference: https://eips.ethereum.org/EIPS/eip-152 – Example 5
  # Input layout (213 bytes): rounds(4) || h(64) || m(128) || t0(8) || t1(8) || f(1)
  #
  # rounds = 12 (big-endian uint32)
  local rounds="0000000c"

  # h – BLAKE2b-512 initial hash state (IV XOR parameter block), little-endian uint64 words
  local h="48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5"
  h+="d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b"

  # m – message block: "abc" (0x616263) followed by 125 zero bytes, little-endian uint64 words
  local m="6162630000000000000000000000000000000000000000000000000000000000"  # bytes  0-31
  m+="0000000000000000000000000000000000000000000000000000000000000000"           # bytes 32-63
  m+="0000000000000000000000000000000000000000000000000000000000000000"           # bytes 64-95
  m+="0000000000000000000000000000000000000000000000000000000000000000"           # bytes 96-127

  # t[0] = 3 (length of "abc") as little-endian uint64; t[1] = 0
  local t0="0300000000000000"
  local t1="0000000000000000"

  # f – final block flag = true
  local f="01"

  local input="0x${rounds}${h}${m}${t0}${t1}${f}"
  local out
  out=$(_call "0x0000000000000000000000000000000000000009" "${input}")
  echo "blake2F output: ${out}"

  # Expected output: go-ethereum's (and thus Bor's) blake2F result for this input (64 bytes).
  # Note: the EIP-152 document lists a different value for "example 5"; the canonical
  # reference is the go-ethereum test suite which Bor inherits.
  local expected="0xba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
  expected+="7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
  [[ "${out}" == "${expected}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0a KZG point evaluation: active on Cancun+ (rejects invalid input)" {
  # EIP-4844: input must be exactly 192 bytes (versioned_hash || z || y || commitment || proof).
  # Calling with empty data should revert on an active precompile.
  # An inactive address (pre-Cancun chain) returns "0x" (success with empty output).
  local out
  out=$(_call "0x000000000000000000000000000000000000000a" "0x")
  echo "KZG with empty input: '${out}'"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0a returned empty success – precompile not active (pre-Cancun chain)"
  fi
  # Active precompile must revert on invalid-length input → empty output from _call.
  [[ -z "${out}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0b BLS12-381 G1 Add: identity + G equals G (Prague+)" {
  # EIP-2537: G1Add(∞, G) = G.
  # G1 point encoding (128 bytes): [16-byte pad || 48-byte x || 16-byte pad || 48-byte y]
  # BLS12-381 G1 generator coordinates (standard):
  #   x = 0x17f1d3a7...adb22c6bb  y = 0x08b3f481...c5e7e1
  local pad="00000000000000000000000000000000"
  local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
  local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
  local G1="${pad}${g1x}${pad}${g1y}"             # 256 hex = 128 bytes
  local inf                                        # 128-byte G1 point at infinity = all zeros
  inf=$(printf '%0256s' '' | tr ' ' '0')
  local out
  out=$(_call "0x000000000000000000000000000000000000000b" "0x${inf}${G1}")
  echo "G1Add(∞, G) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0b returned empty success – precompile not active (pre-Prague chain)"
  fi
  [[ "${out}" == "0x${G1}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0c BLS12-381 G1 MSM: scalar-1 times G equals G (Prague+)" {
  # EIP-2537: G1MSM([G], [1]) = G.
  # Input: [G1 point (128 bytes)][scalar (32 bytes)] = 160 bytes total.
  local pad="00000000000000000000000000000000"
  local g1x="17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"
  local g1y="08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
  local G1="${pad}${g1x}${pad}${g1y}"
  local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
  local out
  out=$(_call "0x000000000000000000000000000000000000000c" "0x${G1}${scalar1}")
  echo "G1MSM([G], [1]) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0c returned empty success – precompile not active (pre-Prague chain)"
  fi
  [[ "${out}" == "0x${G1}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0d BLS12-381 G2 Add: identity + G2 equals G2 (Prague+)" {
  # EIP-2537: G2Add(∞, G2) = G2.
  # G2 point encoding (256 bytes): four 64-byte fields each [16-byte pad || 48-byte Fp element].
  # NOTE: Bor encodes G2 as [X.c0][X.c1][Y.c0][Y.c1] (c0-first), which differs from the
  # EIP-2537 spec that specifies [X.c1][X.c0][Y.c1][Y.c0] (c1-first).
  # BLS12-381 G2 generator:  X = x0 + x1*u  Y = y0 + y1*u
  local pad="00000000000000000000000000000000"
  local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
  local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
  local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
  local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
  local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"  # 512 hex = 256 bytes (Bor c0-first order)
  local inf                                                  # 256-byte G2 point at infinity = all zeros
  inf=$(printf '%0512s' '' | tr ' ' '0')
  local out
  out=$(_call "0x000000000000000000000000000000000000000d" "0x${inf}${G2}")
  echo "G2Add(∞, G2) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0d returned empty success – precompile not active (pre-Prague chain)"
  fi
  [[ "${out}" == "0x${G2}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0e BLS12-381 G2 MSM: scalar-1 times G2 equals G2 (Prague+)" {
  # EIP-2537: G2MSM([G2], [1]) = G2.
  # Input: [G2 point (256 bytes)][scalar (32 bytes)] = 288 bytes total.
  # Uses Bor's c0-first G2 encoding (see 0x0d test for details).
  local pad="00000000000000000000000000000000"
  local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
  local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
  local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
  local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
  local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
  local scalar1="0000000000000000000000000000000000000000000000000000000000000001"
  local out
  out=$(_call "0x000000000000000000000000000000000000000e" "0x${G2}${scalar1}")
  echo "G2MSM([G2], [1]) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0e returned empty success – precompile not active (pre-Prague chain)"
  fi
  [[ "${out}" == "0x${G2}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0f BLS12-381 Pairing: e(G1_infinity, G2) returns 1 (Prague+)" {
  # EIP-2537: e(∞, P2) = 1 for any P2 (the point at infinity contributes nothing).
  # NOTE: Bor v2.6.0 rejects empty input with "invalid input length" (non-conformance
  # with EIP-2537 which requires empty input to return 1).  Use a single pair with
  # G1 = point at infinity instead, which is universally valid and returns 1.
  local pad="00000000000000000000000000000000"
  local x0="024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8"
  local x1="13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e"
  local y0="0ce5d527727d6e118cc9cdc6da2e351aadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801"
  local y1="0606c4a02ea734cc32acd2b02bc28b99cb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be"
  local G2="${pad}${x0}${pad}${x1}${pad}${y0}${pad}${y1}"
  local g1_inf
  g1_inf=$(printf '%0256s' '' | tr ' ' '0')  # G1 point at infinity = 128 zero bytes
  local out
  out=$(_call "0x000000000000000000000000000000000000000f" "0x${g1_inf}${G2}")
  echo "BLS12Pairing(G1_inf, G2) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0f returned empty success – precompile not active (pre-Prague chain)"
  fi
  [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x10 BLS12-381 MapFpToG1: Fp element 1 maps to a non-trivial G1 point (Prague+)" {
  # EIP-2537: MapFpToG1 applies the hash-to-curve Fp→G1 mapping.
  # Input: 64 bytes = [16-byte pad || 48-byte Fp element].
  # For Fp = 1 (valid field element) the output must be a non-trivial 128-byte G1 point.
  local pad="00000000000000000000000000000000"
  local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
  local out
  out=$(_call "0x0000000000000000000000000000000000000010" "0x${pad}${fp1}")
  echo "MapFpToG1(1) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x10 returned empty success – precompile not active (pre-Prague chain)"
  fi
  # Must return a 128-byte (256 hex char) non-trivial G1 point.
  local data="${out#0x}"
  [[ "${#data}" -eq 256 ]]
  _is_nontrivial "${out}"
}

# bats test_tags=execution-specs,pos-precompile
@test "0x11 BLS12-381 MapFp2ToG2: Fp2 element (0,1) maps to a non-trivial G2 point (Prague+)" {
  # EIP-2537: MapFp2ToG2 applies the hash-to-curve Fp2→G2 mapping.
  # Input: 128 bytes = [64-byte c1 field || 64-byte c0 field], each [16-byte pad || 48-byte Fp].
  # For Fp2 = (c1=0, c0=1) the output must be a non-trivial 256-byte G2 point.
  local pad="00000000000000000000000000000000"
  local fp0="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"  # 0
  local fp1="000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"  # 1
  # c1 = 0, c0 = 1  (EIP-2537 encodes c1 first)
  local out
  out=$(_call "0x0000000000000000000000000000000000000011" "0x${pad}${fp0}${pad}${fp1}")
  echo "MapFp2ToG2(0,1) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x11 returned empty success – precompile not active (pre-Prague chain)"
  fi
  # Must return a 256-byte (512 hex char) non-trivial G2 point.
  local data="${out#0x}"
  [[ "${#data}" -eq 512 ]]
  _is_nontrivial "${out}"
}

# bats test_tags=execution-specs,pos-precompile
@test "0x0100 p256Verify (secp256r1): Wycheproof test vector returns 1 (MadhugiriPro+)" {
  # RIP-7212: verifies a P-256 / secp256r1 ECDSA signature.
  # Input (160 bytes): hash(32) || r(32) || s(32) || x(32) || y(32)
  # Source: Bor p256Verify.json (Wycheproof ecdsa_secp256r1_sha256_p1363 #1).
  local input="0x"
  input+="4cee90eb86eaa050036147a12d49004b6b9c72bd725d39d4785011fe190f0b4d"  # hash
  input+="a73bd4903f0ce3b639bbbf6e8e80d16931ff4bcf5993d58468e8fb19086e8cac"  # r
  input+="36dbcd03009df8c59286b162af3bd7fcc0450c9aa81be5d10d312af6c66b1d60"  # s
  input+="4aebd3099c618202fcfe16ae7770b0c49ab5eadf74b754204a3bb6060e44eff3"  # x
  input+="7618b065f9832de4ca6ca971a7a1adc826d0f7c00181a5fb2ddf79ae00b4e10e"  # y
  local out
  out=$(_call "0x0000000000000000000000000000000000000100" "${input}")
  echo "p256Verify(Wycheproof-#1) = ${out}"
  if [[ "${out}" == "0x" ]]; then
    skip "0x0100 returned empty success – precompile not active (pre-MadhugiriPro chain)"
  fi
  [[ "${out}" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x04 identity: 256-byte patterned data round-trip" {
  # Send 256 bytes of patterned data (0x00..0xFF) to the identity precompile.
  local input="0x"
  for i in $(seq 0 255); do
    input+=$(printf '%02x' "$i")
  done

  local out
  out=$(_call "0x0000000000000000000000000000000000000004" "${input}")
  echo "identity(256 bytes) output length: $(( (${#out} - 2) / 2 )) bytes"

  [[ "${out}" == "${input}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x02 SHA-256: 'abc' matches NIST vector" {
  # sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  # "abc" = 0x616263
  local out
  out=$(_call "0x0000000000000000000000000000000000000002" "0x616263")
  echo "sha256('abc') = ${out}"
  [[ "${out}" == "0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x01 ecRecover: recovered address matches known signer" {
  # Test vector from the Ethereum Yellow Paper / execution specs.
  # Message hash, v=28, r, s → recovered address = 0x7156526fbd7a3c72969b54f64e42c10fbb768c8a
  local input="0x"
  input+="456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"  # msg hash
  input+="000000000000000000000000000000000000000000000000000000000000001c"  # v = 28
  input+="9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"  # r
  input+="4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada"  # s

  local out
  out=$(_call "0x0000000000000000000000000000000000000001" "${input}")
  echo "ecRecover output: ${out}"

  # Output is a 32-byte word with the address left-padded with zeros.
  # Extract the last 40 hex chars as the address.
  local recovered_addr
  recovered_addr=$(echo "${out}" | sed 's/0x//' | tail -c 41)
  recovered_addr=$(echo "${recovered_addr}" | tr '[:upper:]' '[:lower:]')

  local expected="7156526fbd7a3c72969b54f64e42c10fbb768c8a"
  [[ "${recovered_addr}" == "${expected}" ]]
}

# bats test_tags=execution-specs,pos-precompile
@test "0x05 modexp: 2^256 mod 13 equals 3" {
  # Large exponent test: modexp(base=2, exp=256, mod=13) = 3.
  # 2^256 mod 13: cycle length=12, 256 mod 12 = 4, 2^4 mod 13 = 16 mod 13 = 3.
  # Input layout (EIP-198): len(B)(32) || len(E)(32) || len(M)(32) || B || E || M
  local input="0x"
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # len(B) = 1
  input+="0000000000000000000000000000000000000000000000000000000000000002"  # len(E) = 2 (256 = 0x0100)
  input+="0000000000000000000000000000000000000000000000000000000000000001"  # len(M) = 1
  input+="02"     # B = 2
  input+="0100"   # E = 256 (big-endian)
  input+="0d"     # M = 13

  local out
  out=$(_call "0x0000000000000000000000000000000000000005" "${input}")
  echo "modexp(2, 256, 13) = ${out}"
  [[ "${out}" == "0x03" ]]
}

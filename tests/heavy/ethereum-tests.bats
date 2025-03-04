# This test leverages test data that's derived from the core ethereum
# test suite. We're leveraging this data as a stress test rather than
# a functional test. I.e. we don't check for the correct execution of
# the tests since in many cases it's impossible. The test suite is
# still a great source of test data for stressing out the EVM.
setup() {
    rpc_url=${RPC_URL:-"$(kurtosis port print cdk cdk-erigon-rpc-001 rpc)"}
    master_private_key=${PRIVATE_KEY:-"0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"}
    master_address=$(cast wallet address --private-key "$master_private_key")
    ethereum_testdata=${ETHEREUM_TESTDATA:-"core/testdata/ethereum-tests-afed83bf2a097cba688a60246429f3a051fe03f6.zst"}
    parallel_job_limit=${PARALLEL_JOB_LIMIT:-"128"}
    main_log_file=${LOG_FILE:-"/tmp/evm-test.log"}
    legacy_flag=${LEGACY_FLAG:-""}
    clean_up="true"
    cast_timeout="20"
    export RPC_TIMEOUT="$cast_timeout"
    test_fund_amount=$(cast to-wei 0.01)
    master_nonce_file=$(mktemp -p /tmp master-nonce-XXXXXXXXXXXX)
}

function print_warning() {
    >&2 echo -e "\e[41m\e[97m$1\e[0m"
}

function normalize_address() {
    sed 's/0x//' |
        tr '[:upper:]' '[:lower:]'
}

function hex_to_dec() {
    hex_in=$(sed 's/0x//' | tr '[:lower:]' '[:upper:]')
    dec_val=$(bc <<< "ibase=16; $hex_in")
    echo "$dec_val"
}

function increment_nonce() {
    # Lock the file, update the nonce, and unlock
    nonce_file=$1

    nonce=$(flock "$nonce_file" -c "nonce=\$(cat $nonce_file); echo \$((nonce + 1)) > $nonce_file; echo \$nonce")
    echo "$nonce"
}

function process_test_item() {
    local testfile
    local tmp_dir
    local nonce
    local count
    local test_counter
    local test_name

    testfile=$1
    test_counter=$2
    wallet_file=$3

    tmp_dir=$(mktemp -p /tmp -d retest-work-XXXXXXXXXXXX)
    pushd "$tmp_dir" &> /dev/null || exit 1

    test_name=$(jq -r '.testCases[0].name' "$testfile")
    printf "Test Number: %d %s is running in %s\n" "$test_counter" "$test_name" "$tmp_dir"

    private_key=$(jq -r '.private_key' "$wallet_file")
    eth_address=$(cast wallet address --private-key "$private_key")

    echo "0" > tmp.nonce

    count=0
    jq -c '.dependencies[]' "$testfile" | while read -r pre ; do
        local reference_address
        local code_to_deploy

        count=$((count+1))
        echo "$pre" | jq '.' > "dep-$count.json"
        code_to_deploy=$(jq -r '.code' "dep-$count.json")
        reference_address=$(jq -r '.addr' "dep-$count.json" | normalize_address)
        >&2 echo "deploying dependency $count for $reference_address"

        nonce="$(increment_nonce tmp.nonce)"
        # shellcheck disable=SC2086
        cast send --json $legacy_flag --timeout "$cast_timeout" --nonce "$nonce" --rpc-url "$rpc_url" --private-key "$private_key" --create "$code_to_deploy" | jq -r '.transactionHash' | tee "$reference_address.txhash"
        cast compute-address --nonce "$nonce" "$eth_address" | sed 's/^.*0x/0x/' > "$reference_address.actual"

        # this particular call is not part of the typical retest execution. But since we're not entirely accurate, i think it makes sense to do some heavy calls to the dependencies with random inputs
        echo "Calling dependency"
        # shellcheck disable=SC2086
        cast send $legacy_flag --timeout "$cast_timeout" --nonce "$(increment_nonce tmp.nonce)" --rpc-url "$rpc_url" --value 10 --gas-limit 2000000 --private-key "$private_key" "$(sed 's/0x//' < "$reference_address.actual")"
    done


    count=0
    jq -c '.testCases[]' "$testfile" | while read -r "test_case" ; do
        local name
        local addr
        local gas
        local val

        count=$((count+1))
        echo "$test_case" | jq '.' > "test_case_$count.json"
        tx_input=$(jq -r '.input' test_case_$count.json)
        name=$(jq -r '.name' test_case_$count.json)
        addr=$(jq -r '.to' test_case_$count.json | normalize_address)
        gas=$(jq -r '.gas' test_case_$count.json) # this value can be obscenely high in the test cases
        val=$(jq -r '.value' test_case_$count.json)
        val_arg=""
        if [[ $val != "0x0" ]] ; then
            dec_val=$(echo "$val" | hex_to_dec)
            val_arg=" --value $dec_val "
        fi

        gas_arg=""
        if [[ $gas != "" ]] ; then
            dec_val=$(echo "$gas" | hex_to_dec)
            valid_gas=$(bc <<< "$dec_val < 30000000 && $dec_val > 0")
            if [[ $valid_gas == "1" ]] ; then
                gas_arg=" --gas-limit $dec_val "
            else
                # gas_arg=" --gas-limit $gas_limit "
                # in the case where the test defined gas limit is too big, we'll do an estimate
                gas_arg=""
            fi
        fi

        local to_addr_arg=""
        if [[ $addr == "0x0000000000000000000000000000000000000000" || $addr == "" || $addr == "0000000000000000000000000000000000000000" ]] ; then
            if [[ $tx_input == "" ]]; then
                print_warning "The test $name case $count seems to have a create with an empty data... skiping"
                continue
            fi
            to_addr_arg=" --create "
        else
            if [[ ! -e $addr.actual ]]; then
                print_warning "the test file $addr.actual does not seem to exist... skipping"
                continue
            fi
            resolved_address=$(cat "$addr.actual")
            contract_code=$(cast code --rpc-url "$rpc_url" "$resolved_address")
            if [[ $contract_code == "0x" ]]; then
                print_warning "The test #$count for $name to alias of $addr ($resolved_address) doesn't have any code"
            fi
            to_addr_arg=" $resolved_address "
        fi

        >&2 echo "executing tx $count for $name to alias of $addr"

        # shellcheck disable=SC2086
        cast send $legacy_flag --timeout "$cast_timeout" --nonce "$(increment_nonce tmp.nonce)" --rpc-url "$rpc_url" --private-key "$private_key" $gas_arg $val_arg $to_addr_arg $tx_input | tee "tx-$count-out.json"
        ret_code=$?
        if [[ $ret_code -ne 0 ]]; then
            print_warning "it looks like this request timed out.. it might be worth checking?!"
        fi
    done

    balance=$(cast balance --rpc-url "$rpc_url" "$eth_address")
    if [[ $balance -eq 0 ]]; then
        print_warning "it looks like $tmp_address was not funded or happend to have spent all of it's funds?!"
        return
    else
        gas_price=$(cast gas-price --rpc-url "$rpc_url")
        fudge_factor=100000000000
        value_to_send=$(bc <<< "$balance - $fudge_factor - ($gas_price * 21000)")
        >&2 echo "Clawing back $value_to_send from $tmp_address"

        if ! cast send --legacy --nonce "$(increment_nonce tmp.nonce)" --gas-price "$gas_price" --rpc-url "$rpc_url" --value "$value_to_send" --private-key "$private_key" "$master_address" ; then
            print_warning "Clawback failed. Retrying with the pending nonce"
            cast send --legacy --gas-price "$gas_price" --rpc-url "$rpc_url" --value "$value_to_send" --private-key "$private_key" "$master_address"
        fi
    fi

    popd &> /dev/null || exit 1

    if [[ $clean_up == "true" ]] ; then
        rm -rf "$tmp_dir"
        rm "$testfile"
    fi
}

function fund_new_wallet() {
    wallet_info=$(cast wallet new --json | jq -c '.[]')
    tmp_address=$(echo "$wallet_info" | jq -r '.address')
    nonce=$(increment_nonce "$master_nonce_file")
    cast send --legacy --rpc-url "$rpc_url" --nonce "$nonce" --value "$test_fund_amount" --private-key "$master_private_key" "$tmp_address" > /dev/null
    echo "$wallet_info"
}

# bats test_tags=evm,stress
@test "execute ethereum test cases and ensure liveness" {
    wallet_address=$(cast wallet address --private-key "$master_private_key")
    wallet_nonce=$(cast nonce --rpc-url "$rpc_url" "$wallet_address")
    counter_file="$(mktemp -p /tmp retest-counter-XXXXXXXX)"
    main_lock="$(mktemp -p /tmp retest-lock-XXXXXXXX)"


    echo "$wallet_nonce" > "$master_nonce_file"

    test_counter=0
    if [[ ! -e "$ethereum_testdata" ]]; then
        echo "Test datafile $ethereum_testdata seems to be missing"
        exit 1
    fi

    # Break down each test into different files
    zstd -d -c "$ethereum_testdata" | jq -c '.[]' | shuf | while read -r test_item ; do
        testfile=$(mktemp -p /tmp retest-item-jq-XXXXXXXXXXXX)
        echo "$test_item" > "$testfile"
        test_counter=$((test_counter+1))

        # Increment a counter to keep track of how many tasks are running in parallel
        flock "$counter_file" -c "counter=\$(cat $counter_file); echo \$((counter + 1)) > $counter_file"

        # Run the test in the background and redirect its output to the log file
        (
            log_file="$(mktemp -p /tmp retest-log-XXXXXXXX)"
            wallet_file="$(mktemp -p /tmp retest-wallet-XXXXXXXX)"

            fund_new_wallet > "$wallet_file"

            wallet_info="$(cat "$wallet_file")"
            start=$(date +%s)
            process_test_item "$testfile" "$test_counter" "$wallet_file" &> "$log_file"
            end=$(date +%s)
            duration=$((end - start))
            pretty_duration=$(date -u -d @"$duration" +"%Hh %Mm %Ss")
            dt=$(date -Is)

            exec 201>"$main_lock"
            flock 201
            awk -v pid="$$" -v dt="$dt" '{print dt "\t" pid "\t" $0}' "$log_file" >> "$main_log_file"
            printf "The test completeted in %s \n\n" "$pretty_duration" >> "$main_log_file"
            flock -u 201

            rm "$log_file"
            # if there are left overs in each account, we could do something  with the wallet files
            # rm $wallet_file

            # Now that the job is done, we can decrement the counter
            flock "$counter_file" -c "counter=\$(cat $counter_file); echo \$((counter - 1)) > $counter_file"
        ) &

        # we will check the value of the counter and if we're greater or equal to the number of our limit, we'll sleep
        current_jobs=$(flock "$counter_file" -c "counter=\$(cat $counter_file); echo \$counter")
        while [[ "$current_jobs" -ge "$parallel_job_limit" ]]; do
            echo "it looks like there are $current_jobs jobs running.. pausing briefly"
            sleep 2
            current_jobs=$(flock "$counter_file" -c "counter=\$(cat $counter_file); echo \$counter")
        done
    done

    nonce=$(increment_nonce "$master_nonce_file")
    if ! cast send --legacy --rpc-url "$rpc_url" --nonce "$nonce" --value "$test_fund_amount" --private-key "$master_private_key" "$master_address" ; then
        echo "unable to send a transaction at the end of the ethereum test suit. something has probably gone wrong with the RPC"
        exit 1
    fi
}

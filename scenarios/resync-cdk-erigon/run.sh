#!/bin/env bash

set -euo pipefail

source ../common/load-env.sh
load_env

# Spin up the enclave
kurtosis run --enclave "$ENCLAVE_NAME" "$KURTOSIS_PACKAGE_SELECTOR"

# Get the RPC url of the rpc node
rpc_url=$(kurtosis port print "$ENCLAVE_NAME" cdk-erigon-rpc-001 rpc)
sequencer_url=$(kurtosis port print "$ENCLAVE_NAME" cdk-erigon-sequencer-001 rpc)


# Wait a few blocks, just to make sure things are running properly
until [[ $(cast block-number --rpc-url "$rpc_url") -gt 50 ]]; do
    rpc_bn=$(cast block-number --rpc-url "$rpc_url")
    seq_bn=$(cast block-number --rpc-url "$sequencer_url")
    printf "The RPC block number is %d and the sequencer block number is %d. Waiting...\n" "$rpc_bn" "$seq_bn"
    sleep 5
done

# Kill the erigon process but keep the container running
kurtosis service exec "$ENCLAVE_NAME" cdk-erigon-rpc-001 'kill -TRAP $(pidof proc-runner.sh)'

# Delete the entire data directory for erigon
kurtosis service exec "$ENCLAVE_NAME" cdk-erigon-rpc-001 'rm -rf data/dynamic-kurtosis-sequencer/*'

# Stop the service
kurtosis service stop "$ENCLAVE_NAME" cdk-erigon-rpc-001

# Start it back up
kurtosis service start "$ENCLAVE_NAME" cdk-erigon-rpc-001

# Wait until the RPC is back working again
rpc_url=$(kurtosis port print "$ENCLAVE_NAME" cdk-erigon-rpc-001 rpc)
set +e
until [[ $(cast block-number --rpc-url "$rpc_url") -gt 50 ]]; do
    rpc_bn=$(cast block-number --rpc-url "$rpc_url")
    seq_bn=$(cast block-number --rpc-url "$sequencer_url")
    printf "The RPC block number is %d and the sequencer block number is %d. Waiting...\n" "$rpc_bn" "$seq_bn"
    sleep 5
done
set -e

printf "The RPC block number is %d and the sequencer block number is %d\n" "$rpc_bn" "$seq_bn"

# This test has finished. Let's stop the enclave
kurtosis enclave stop "$ENCLAVE_NAME"

# The enclave have stopped, let's clean it up
kurtosis clean

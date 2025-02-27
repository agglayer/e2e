#!/usr/bin/env bash

function extract_tx_hash() {
    local cast_output="$1"
    echo "$cast_output" | grep 'transactionHash' | awk '{print $2}' | tail -n 1
}
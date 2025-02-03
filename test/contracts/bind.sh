#!/bin/sh

set -e

gen() {
    local package=$1

    docker run --rm --platform=linux/amd64 -v $(pwd):/contracts ethereum/client-go:alltools-latest abigen --bin /contracts/bin/${package}.bin --abi /contracts/abi/${package}.abi --pkg=${package} --out=/contracts/${package}/${package}.go
}

gen verifybatchesmock
gen claimmock
gen claimmockcaller
gen claimmocktest
gen zkcounters
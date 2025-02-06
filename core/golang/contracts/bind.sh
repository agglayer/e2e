#!/bin/sh

# script used to generate go code from compiled SCs in the contracts directory

set -e

gen() {
    local package=$1

    mkdir -p ${package}
    docker run --rm --platform=linux/amd64 -v $(pwd)/../../contracts/:/source -v $(pwd):/contracts ethereum/client-go:alltools-latest abigen --bin /source/bin/${package}.bin --abi /source/abi/${package}.abi --pkg=${package} --out=/contracts/${package}/${package}.go
}

gen verifybatchesmock
gen claimmock
gen claimmockcaller
gen claimmocktest
gen zkcounters
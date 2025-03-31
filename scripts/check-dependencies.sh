#!/usr/bin/env bash

function pad_command() {
    cmd="$1"
    cmd_len=$(echo -n "$cmd" | wc -m)
    pad_len=$((15 - cmd_len))
    printf "%s %.*s " "$cmd" "$pad_len" "..............."
}

deps=(
    yq
    jq
    polycli
    cast
)

echo "Checking for dependencies"
success=1

for dep in "${deps[@]}"; do
    pad_command "$dep"
    if ! command -v "$dep" > /dev/null ; then
        echo "NOT INSTALLED"
        success=0
    else
        echo "OK"
    fi
done

if [[ $success -eq 0 ]]; then
    echo "1 or more dependencies is not installed"
    exit 1
fi

echo "All dependencies are installed"

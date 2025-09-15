#!/bin/bash

function _log_file_descriptor() {
    local file_descriptor=$1
    local log_output=$2

    # Create the log message
    log_message="[$(date '+%Y-%m-%d %H:%M:%S')]: $log_output"

    # Output based on file descriptor
    # File descriptor 1 (stdout)
    # File descriptor 2 (stderr)
    # File descriptor 3 (and higher)
    if [[ "$file_descriptor" == "1" ]]; then
        echo "$log_message" >&1
    elif [[ "$file_descriptor" == "2" ]]; then
        echo "$log_message" >&2
    else
        echo "$log_message" >&3
    fi
}
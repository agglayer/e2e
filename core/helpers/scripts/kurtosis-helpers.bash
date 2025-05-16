#!/usr/bin/env bash

function kurtosis_download_file_exec_method() {
    local _enclave="$1"
    local _service="$2"
    local _file_path="$3"
    if [ -z $_file_path ]; then
        echo "Error: file_path parameter is not set." >&2
        return 1
    fi
   kurtosis service exec "$_enclave" "$_service" "cat $_file_path" | kurtosis_filer_exec_method
}

function kurtosis_filer_exec_method() {
    local _kurtosis_version=$(kurtosis version | cut -d ':'  -f 2 | head -n 1)
    # versions previous 1.7.0 first line in stdout is
    # "The command was successfully executed and returned '0'."
    # After this version this line is output in stderr
    # So if kurtosis version is <1.7.0 need tail -n +2, if not just same output
    dpkg --compare-versions "$_kurtosis_version" "ge" "1.7.0" && cat || tail -n +2
}
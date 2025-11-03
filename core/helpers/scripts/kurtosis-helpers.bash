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
    local _kurtosis_version
    _kurtosis_version=$(kurtosis version | cut -d ':' -f 2 | head -n 1)
    # versions previous 1.7.0 first line in stdout is
    # "The command was successfully executed and returned '0'."
    # After this version this line is output in stderr
    # So if kurtosis version is <1.7.0 need tail -n +2, if not just same output
    dpkg --compare-versions "$_kurtosis_version" "ge" "1.7.0" && cat || tail -n +2
}

function update_kurtosis_service_state() {
    local service="$1"
    local action="$2"  # start or stop

    if [[ "$action" == "stop" ]]; then
        if docker ps | grep "$service"; then
            echo "Stopping $service..." >&3
            kurtosis service stop "$ENCLAVE_NAME" "$service" || {
                echo "Error: Failed to stop $service" >&3
                return 1
            }
            echo "$service stopped." >&3
        else
            echo "Error: $service does not exist in enclave $ENCLAVE_NAME" >&3
            return 1
        fi
    elif [[ "$action" == "start" ]]; then
        echo "Starting $service..." >&3
        kurtosis service start "$ENCLAVE_NAME" "$service" || {
            echo "Error: Failed to start $service" >&3
            return 1
        }
        echo "$service started." >&3
    fi
}

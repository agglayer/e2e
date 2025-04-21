#!/bin/env bash

load_env() {
    if [[ -f ".env" ]]; then
        set -a
        source ".env"
        set +a
        echo "Loaded .env" >&2
    elif [[ -f "env.example" ]]; then
        set -a
        source "env.example"
        set +a
        echo "Loaded env.example" >&2
    else
        echo "no environment variables were loaded" >&2
    fi
}



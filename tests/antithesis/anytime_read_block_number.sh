#!/usr/bin/env bash

kurtosis service exec pos test-runner \
  "cast block-number --rpc-url ${L2_RPC_URL}"

#!/usr/bin/env/bash

kurtosis service exec pos test-runner \
  "cast call --rpc-url ${L2_RPC_URL} ${L2_STATE_RECEIVER_ADDRESS} "lastStateId()(uint)"

#!/usr/bin/env bash

kurtosis service exec pos test-runner \
  "cast send --rpc-url ${L2_RPC_URL} --legacy --private-key ${PRIVATE_KEY} --value 0.001ether $(cast address-zero)"

#!/usr/bin/env/bash

kurtosis service exec pos test-runner \
  "bats --filter-tags pos,bridge,matic,pol --recursive tests/"

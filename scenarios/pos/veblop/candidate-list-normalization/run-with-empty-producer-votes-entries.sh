#!/bin/env bash

heimdallv2_tag="82ead2c" # develop - 2025/09/05

echo "Starting heimdall-v2 with empty entries in producer votes list"
producer_votes="1,1,1,,,,,,2,3,4,5,5,,,6,7,8,8,9,,10,,"
output=$(docker run --rm --entrypoint sh "local/heimdall-v2:$heimdallv2_tag" -c \ "heimdalld init 1 > /dev/null 2>&1 \
  && echo 'producer_votes=\"$producer_votes\"' >> /var/lib/heimdall/config/app.toml \
  && heimdalld start --all --bridge --rest-server" 2>&1)
exit_code=$?
echo "Output: $output"
echo "Exit code: $exit_code"

if [[ $exit_code -ne 0 ]]; then
  if grep -q "Empty producer ID found in producer votes list" <<< "$output"; then
    echo "Command failed as expected with the expected error message"
  else
    echo "Command failed as expected but with an unexpected error message"
    exit 1
  fi
else
  echo "Command succeeded unexpectedly"
  exit 1
fi

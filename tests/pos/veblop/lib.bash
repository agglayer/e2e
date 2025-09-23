function is_veblop_enabled() {
  local block_number
  block_number=$(cast block-number --rpc-url "${L2_RPC_URL}")
  [[ $block_number -gt 270 ]]
}

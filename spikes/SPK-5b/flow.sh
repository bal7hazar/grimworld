#!/usr/bin/env bash
# SPK-5b: declare, deploy, invoke and call the throwaway contract with sncast against the local
# node, read the event from the receipt, then decode it from TypeScript with starknet.js. Meant to
# run under the node of scripts/with-node.sh, from the repository root:
#   scripts/with-node.sh spikes/SPK-5b/flow.sh
# Needs the artifacts of `spikes/SPK-5b/locked.sh scarb build` and `pnpm install` in spikes/SPK-5b.
# The environment comes from with-node.sh: NODE_URL, NODE_ACCOUNT_ADDRESS, NODE_ACCOUNT_PRIVATE_KEY.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

: "${NODE_URL:?run under scripts/with-node.sh}"
accounts=${WITH_NODE_LOG_DIR:-$PWD/.with-node}/accounts.json
rm -f "$accounts"
value=${1:-42}

# sncast reads the package from the working directory: run it from the package's folder.
snc() { (cd spikes/SPK-5b && sncast --accounts-file "$accounts" "$@"); }
# The line "<label>: <value>" of sncast's output.
field() { sed -n "s/^$1:[[:space:]]*//p" | head -n 1; }

snc account import --url "$NODE_URL" --name dev --type oz \
  --address "$NODE_ACCOUNT_ADDRESS" --private-key "$NODE_ACCOUNT_PRIVATE_KEY"

out=$(snc --account dev declare --url "$NODE_URL" --contract-name Mark)
echo "$out"
class_hash=$(field 'Class Hash' <<< "$out")
[ -n "$class_hash" ] || { echo "flow: no class hash in the declare output" >&2; exit 1; }

out=$(snc --account dev deploy --url "$NODE_URL" --class-hash "$class_hash")
echo "$out"
address=$(field 'Contract Address' <<< "$out")
[ -n "$address" ] || { echo "flow: no contract address in the deploy output" >&2; exit 1; }

out=$(snc --account dev invoke --url "$NODE_URL" --contract-address "$address" --function mark --calldata "$value")
echo "$out"
tx=$(field 'Transaction Hash' <<< "$out")
[ -n "$tx" ] || { echo "flow: no transaction hash in the invoke output" >&2; exit 1; }

out=$(snc call --url "$NODE_URL" --contract-address "$address" --function get)
echo "$out"

echo "receipt of $tx:"
curl -sf -X POST -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"starknet_getTransactionReceipt\",\"params\":{\"transaction_hash\":\"$tx\"}}" \
  "$NODE_URL"
echo

node spikes/SPK-5b/read.ts "$address" "$tx" "$value"

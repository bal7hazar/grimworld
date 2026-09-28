#!/usr/bin/env bash
# SPK-11: scripts/with-node.sh with the node's full state archive, which `devnet_abortBlocks` (the
# simulated reorg) requires. starknet-devnet reads the option from its environment
# (STATE_ARCHIVE_CAPACITY, `starknet-devnet --help`), and with-node.sh passes its environment to the
# node, so nothing in with-node.sh changes. Run from the repository root:
#   spikes/SPK-11/with-archive.sh <command> [args...]
set -euo pipefail
export STATE_ARCHIVE_CAPACITY=full
exec scripts/with-node.sh "$@"

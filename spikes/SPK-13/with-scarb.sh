#!/usr/bin/env bash
# SPK-13: runs a command with another installed Scarb selected through asdf's per-command variable
# (ASDF_SCARB_VERSION), so that no .tool-versions file is written anywhere. Installs nothing.
#
#   spikes/SPK-13/with-scarb.sh <version> <command> [args...]
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: with-scarb.sh <version> <command> [args...]" >&2; exit 2; }
export ASDF_SCARB_VERSION=$1
shift
exec "$@"

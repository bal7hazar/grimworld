#!/usr/bin/env bash
# Installs snforge and universal-sierra-compiler from their official GitHub release archives, with
# the SHA-256 of each archive pinned below and verified BEFORE extraction. Used instead of
# foundry-rs/setup-snfoundry, which calls software-mansion/setup-universal-sierra-compiler@v1, a
# mutable tag: every executed action of the workflow stays pinned by SHA, transitively.
#
# Usage: SNFORGE=<x.y.z> install-snforge.sh   (the version comes from a validated .tool-versions)
# A snforge version without a pinned hash is refused: when .tool-versions moves, add its hash here
# (sha256sum of the release archive, cross-checked with the `digest` GitHub shows for the asset).
set -euo pipefail

: "${SNFORGE:?SNFORGE is not set}"
: "${RUNNER_TEMP:?RUNNER_TEMP is not set}"

case "$SNFORGE" in
  0.61.0) snforge_sha=fdd3b5d9b5a927a31ca45088b1c9a820519f8b2d2cc93193d790bcd5ece9359b ;;
  0.51.2) snforge_sha=9a8f9bdf69dd2e3a501949182520dccc77067c2c05d2a9ba835ec28234d4028a ;;
  *)
    echo "no pinned SHA-256 for snforge $SNFORGE: add it to .github/ci/install-snforge.sh" >&2
    exit 1
    ;;
esac

# The same compiler serves both snforge versions (CI ran them with it).
usc=2.10.1
usc_sha=8f6d9faf2ce644faa99e2acee7e855e3fbeb7919b99ec13d29f57c08089f2fb9

dest="$RUNNER_TEMP/cairo-tools"
mkdir -p "$dest"

# fetch_and_extract <name> <url> <sha256>
fetch_and_extract() {
  local archive="$dest/$1.tar.gz"
  curl --fail --silent --show-error --location --retry 3 --retry-delay 5 --proto '=https' --tlsv1.2 --output "$archive" "$2"
  echo "$3  $archive" | sha256sum --check --strict -
  tar --extract --gzip --strip-components=1 --file "$archive" --directory "$dest"
}

fetch_and_extract snforge \
  "https://github.com/foundry-rs/starknet-foundry/releases/download/v$SNFORGE/starknet-foundry-v$SNFORGE-x86_64-unknown-linux-gnu.tar.gz" \
  "$snforge_sha"
fetch_and_extract universal-sierra-compiler \
  "https://github.com/software-mansion/universal-sierra-compiler/releases/download/v$usc/universal-sierra-compiler-v$usc-x86_64-unknown-linux-gnu.tar.gz" \
  "$usc_sha"

echo "$dest/bin" >> "$GITHUB_PATH"
"$dest/bin/snforge" --version
"$dest/bin/universal-sierra-compiler" --version

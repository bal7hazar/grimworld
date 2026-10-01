#!/usr/bin/env bash
# SPK-12: build stwo-cairo's `run_and_prove` and `verify` inside the spike, as slingfall does
# (github.com/bal7hazar/slingfall at d401cf2, tools/prove/setup.sh and docs/proving.md): the same
# rev, the same two patches (copied verbatim into this folder), the same binaries.
#
#   spikes/SPK-12/prove/setup.sh [--native]   # clone, patch, build (idempotent); prints the binaries' dir
#
# The clone lives in spikes/SPK-12/prove/vendor/ (git-ignored). The clone's rust-toolchain.toml selects
# nightly-2025-06-23, already installed on the Mac. STWO_JOBS=N sets cargo's jobs (default 8).
set -euo pipefail

REV=467d5c6
REPO=https://github.com/starkware-libs/stwo-cairo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/vendor/stwo-cairo"
PATCHES=("$HERE/vm_utils-standalone-context.patch" "$HERE/verify-proof-format.patch")
PROVER="$SRC/stwo_cairo_prover"
BIN="$PROVER/target/release"
JOBS="${STWO_JOBS:-8}"

flags=""
[ "${1:-}" = --native ] && flags="-C target-cpu=native"
stamp="rev=$REV patches=$(cat "${PATCHES[@]}" | shasum -a 256 | cut -c1-16) flags=$flags"

if [ -f "$BIN/.spk12-stamp" ] && [ "$(cat "$BIN/.spk12-stamp")" = "$stamp" ] \
  && [ -x "$BIN/run_and_prove" ] && [ -x "$BIN/verify" ]; then
  echo "$BIN"
  exit 0
fi

mkdir -p "$HERE/vendor"
[ -d "$SRC/.git" ] || git clone --quiet "$REPO" "$SRC" >&2
git -C "$SRC" checkout --quiet --force "$REV" >&2
git -C "$SRC" checkout --quiet -- . >&2
for p in "${PATCHES[@]}"; do
  git -C "$SRC" apply "$p"
done

(
  cd "$PROVER"
  RUSTFLAGS="$flags" cargo build --release -j "$JOBS" -p stwo-cairo-dev-utils \
    --bin run_and_prove --bin verify >&2
)
echo "$stamp" > "$BIN/.spk12-stamp"
echo "$BIN"

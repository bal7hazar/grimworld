#!/usr/bin/env bash
# Installs the toolchain of Grim World on a clean machine, without root, and prints each version.
# Idempotent: what is already installed is left alone. Nothing global is touched: asdf versions are
# read from the repository's .tool-versions only (never `asdf set -u`), and the release binaries go
# under $GRIMWORLD_TOOLS (default ~/.grimworld/tools/<tool>/<version>/), linked into
# $GRIMWORLD_BIN_DIR (default ~/.cargo/bin, which is on the PATH of the machine and of the agents).
#
#   asdf (.tool-versions):   scarb, starknet-foundry, nodejs, pnpm
#   release binaries:        sozo, katana, torii   (the asdf `dojo` plugin cannot install Dojo 1.8:
#                                                   torii has its own repository since 1.8.x)
#
# Pins of the release binaries live here, next to their sha256; the asdf pins live in .tool-versions.
# The reasons and the compatibility constraints are in docs/research/SPK-5-toolchain.md.
set -euo pipefail

SOZO_VERSION=1.8.7
KATANA_VERSION=1.7.1
TORII_VERSION=1.8.16

# sha256 of the release archives, from the GitHub release assets (digest field): <tool> <arch>.
sha256_of() {
  case "$1:$2" in
    sozo:amd64) echo f26287bd3a0d70e7c716363d59e0a6df74cf7a610e7b0ba485bfd8f96fbb398a ;;
    sozo:arm64) echo bcf48677378546b6b3452ffd65f011182c1fdc7b1e1a28117118c331f15cb7ea ;;
    katana:amd64) echo 34632a9640b4572fb46a227deb645334addf1ca88431613da47ea8e7c70992e1 ;;
    katana:arm64) echo 39ae18295bdbbec910a76b8897b588127b1ef58e72e736e339af8aa7041c8a14 ;;
    torii:amd64) echo ab25b4667c6a91ca73efdbd3fec62440acdf7212b5b91b0e1333c6a92c573219 ;;
    torii:arm64) echo aa0b3a66fc393c2269a264d0eb965704f9be1ee6114b8a5d8ff4b029c59d9005 ;;
  esac
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools=${GRIMWORLD_TOOLS:-$HOME/.grimworld/tools}
bin_dir=${GRIMWORLD_BIN_DIR:-$HOME/.cargo/bin}

log() { echo "setup-toolchain: $*"; }
die() { echo "setup-toolchain: $*" >&2; exit 1; }

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) arch=amd64 ;;
  Linux:aarch64 | Linux:arm64) arch=arm64 ;;
  *) die "unsupported platform $(uname -s) $(uname -m) (Linux amd64 and arm64 only)" ;;
esac

command -v asdf > /dev/null || die "asdf is not installed (https://asdf-vm.com/guide/getting-started.html)"
command -v curl > /dev/null || die "curl is required"
command -v sha256sum > /dev/null || die "sha256sum is required"

# --- asdf tools, from the repository's .tool-versions -------------------------------------------
cd "$root"
[ -f .tool-versions ] || die "no .tool-versions at $root"
plugins=$(asdf plugin list 2> /dev/null || true)
while read -r name _; do
  case "$name" in '' | '#'*) continue ;; esac
  if ! grep -qx "$name" <<< "$plugins"; then
    log "asdf plugin add $name"
    asdf plugin add "$name"
  fi
done < .tool-versions

# The pnpm plugin reports a failed download step on a clean machine although pnpm 12 works
# afterwards (its shim fetches the binary on first use): the final check below is what decides.
asdf install || log "asdf install returned $?; the version check below decides"

# --- release binaries ---------------------------------------------------------------------------
install_release() { # <tool> <version> <sha256> <url>
  local tool=$1 version=$2 sha=$3 url=$4 dir tmp
  dir=$tools/$tool/$version
  if [ ! -x "$dir/$tool" ]; then
    log "installing $tool $version from $url"
    mkdir -p "$dir"
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "$tmp/archive.tar.gz"
    echo "$sha  $tmp/archive.tar.gz" | sha256sum -c --quiet - || die "sha256 mismatch for $url"
    tar xzf "$tmp/archive.tar.gz" -C "$tmp"
    [ -f "$tmp/$tool" ] || die "$url does not contain $tool"
    install -m 0755 "$tmp/$tool" "$dir/$tool"
    rm -rf "$tmp"
  fi
  mkdir -p "$bin_dir"
  local link=$bin_dir/$tool
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "$link exists and is not a symlink: not replacing it"
  fi
  if [ "$(readlink "$link" 2> /dev/null || true)" != "$dir/$tool" ]; then
    ln -sfn "$dir/$tool" "$link"
  fi
}

# The archives hold the bare binary (sozo, katana, torii) at their root.
install_release sozo "$SOZO_VERSION" "$(sha256_of sozo "$arch")" \
  "https://github.com/dojoengine/dojo/releases/download/sozo/v$SOZO_VERSION/sozo_v${SOZO_VERSION}_linux_$arch.tar.gz"
install_release katana "$KATANA_VERSION" "$(sha256_of katana "$arch")" \
  "https://github.com/dojoengine/katana/releases/download/v$KATANA_VERSION/katana_v${KATANA_VERSION}_linux_$arch.tar.gz"
install_release torii "$TORII_VERSION" "$(sha256_of torii "$arch")" \
  "https://github.com/dojoengine/torii/releases/download/v$TORII_VERSION/torii_v${TORII_VERSION}_linux_$arch.tar.gz"

# --- report and check ---------------------------------------------------------------------------
status=0
check() { # <label> <expected version> <command…>
  local label=$1 want=$2 got
  shift 2
  # pnpm 12 announces its first-use download on a line of its own before the version.
  got=$("$@" 2>&1 | grep -v '^Downloading' | head -n 1) || true
  if [[ $got == *"$want"* ]]; then
    printf '%-18s %s\n' "$label" "$got"
  else
    printf '%-18s MISMATCH: expected %s, got: %s\n' "$label" "$want" "$got" >&2
    status=1
  fi
}

pinned() { awk -v n="$1" '$1 == n { print $2 }' .tool-versions; }
export PATH="$bin_dir:$PATH"

check scarb "$(pinned scarb)" scarb --version
check snforge "$(pinned starknet-foundry)" snforge --version
check node "$(pinned nodejs)" node --version
check pnpm "$(pinned pnpm)" pnpm --version
check sozo "$SOZO_VERSION" "$tools/sozo/$SOZO_VERSION/sozo" --version
check katana "$KATANA_VERSION" "$tools/katana/$KATANA_VERSION/katana" --version
check torii "$TORII_VERSION" "$tools/torii/$TORII_VERSION/torii" --version

for t in sozo katana torii; do
  [ "$(command -v "$t" || true)" = "$bin_dir/$t" ] || {
    echo "setup-toolchain: '$t' on the PATH is not $bin_dir/$t; put $bin_dir first on the PATH" >&2
    status=1
  }
done
exit "$status"

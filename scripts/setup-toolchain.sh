#!/usr/bin/env bash
# Installs the toolchain of Grim World on a clean machine, without root, and checks it.
# Idempotent: what is installed is left alone. Nothing global is touched: the versions come from
# the repository's .tool-versions (never `asdf set -u`, never ~/.tool-versions), and nothing is
# written outside asdf's own directory.
#
#   .tool-versions   scarb, starknet-foundry, nodejs, pnpm, and sozo, katana, torii (the separate
#                    plugins github.com/dojoengine/asdf-{sozo,katana,torii}; the combined `dojo`
#                    plugin cannot install Dojo 1.8, see docs/research/SPK-5-toolchain.md)
#
# Adding an asdf plugin creates machine-wide shims (~/.asdf/shims/<tool>) that come before the
# system binaries on the PATH: see docs/reports/INC-2026-09-28-asdf-node-shims.md. This script
# therefore checks at its end that node and pnpm still work outside a pinned directory, and
# warns when they do not; it never edits ~/.tool-versions.
#
# The sha256 of the extracted sozo, katana and torii binaries are pinned below and verified on
# every run, whichever plugin version installed them. Reasons and constraints: the research file.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Where an earlier version of this script linked release binaries; only its own links are removed.
legacy_tools=${GRIMWORLD_TOOLS:-$HOME/.grimworld/tools}
legacy_bin_dir=${GRIMWORLD_BIN_DIR:-$HOME/.cargo/bin}

log() { echo "setup-toolchain: $*"; }
die() { echo "setup-toolchain: $*" >&2; exit 1; }

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) arch=amd64 ;;
  Linux:aarch64 | Linux:arm64) arch=arm64 ;;
  *) die "unsupported platform $(uname -s) $(uname -m) (Linux amd64 and arm64 only)" ;;
esac

# sha256 of the binary inside the release archive: <tool> <version> <arch>. Update it together
# with .tool-versions; a version without a pinned hash is refused.
binary_sha256() {
  case "$1:$2:$3" in
    sozo:1.8.7:amd64) echo f76a5a49b6ef6401595eae43859f936621799204d7ff52781c0be854f735ae63 ;;
    sozo:1.8.7:arm64) echo 2b728fe055fe2471ab10875eec73330beb793097e5e7d127b60d49f4a80ab022 ;;
    katana:1.7.1:amd64) echo 7ccdcbacd0de309d476470ba40bda832edc650daeacab0c672bc5f09c15c6b71 ;;
    katana:1.7.1:arm64) echo 6ccc8f0f7f1a7623b445ba6243c1301528591bbf8e51748db9b11a0fa0cdc4b3 ;;
    torii:1.8.16:amd64) echo cbf88d6b23bd742508f9d6b74c27b78375532ce6bb57f8e5b0fbd3ed91ff14b6 ;;
    torii:1.8.16:arm64) echo 4a6451a33d1404738b3914a8b01245b74d0f0fa5012ac8c5146ac186a9c3d109 ;;
  esac
}

# Where an asdf plugin lives when it is not in asdf's registry.
plugin_source() {
  case "$1" in
    sozo | katana | torii) echo "https://github.com/dojoengine/asdf-$1.git" ;;
  esac
}

command -v asdf > /dev/null || die "asdf is not installed (https://asdf-vm.com/guide/getting-started.html)"
command -v sha256sum > /dev/null || die "sha256sum is required"

cd "$root"
[ -f .tool-versions ] || die "no .tool-versions at $root"
pinned() { awk -v n="$1" '$1 == n { print $2 }' .tool-versions; }

# --- an earlier version of this script linked the binaries into ~/.cargo/bin -----------------
# The asdf shims replace them. Remove a link only if it points inside our own tools directory.
for tool in sozo katana torii; do
  link=$legacy_bin_dir/$tool
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in
    "$legacy_tools"/*)
      log "removing $link (linked by an earlier version of this script)"
      rm -f "$link"
      ;;
    *) log "$link points elsewhere ($(readlink "$link")): not ours, left alone" ;;
  esac
done

# --- asdf plugins and versions, from .tool-versions ------------------------------------------
plugins=$(asdf plugin list 2> /dev/null || true)
while read -r name _; do
  case "$name" in '' | '#'*) continue ;; esac
  if ! grep -qx "$name" <<< "$plugins"; then
    log "asdf plugin add $name"
    source=$(plugin_source "$name")
    if [ -n "$source" ]; then asdf plugin add "$name" "$source"; else asdf plugin add "$name"; fi
  fi
done < .tool-versions

# The pnpm plugin may report a failed download step on a first install although pnpm 12 works
# afterwards (its shim fetches the binary on first use): the checks below decide.
asdf install || log "asdf install returned $?; the checks below decide"

# --- checks -----------------------------------------------------------------------------------
status=0
fail() { echo "setup-toolchain: $*" >&2; status=1; }

# The command must succeed and its first version-shaped word must be exactly the pinned version.
check_version() { # <label> <expected version> <command…>
  local label=$1 want=$2 out rc line word got=''
  shift 2
  out=$("$@" 2>&1) && rc=0 || rc=$?
  # pnpm 12 announces its first-use download on a line of its own before the version.
  line=$(grep -v '^Downloading' <<< "$out" | head -n 1 || true)
  for word in $line; do
    if [[ $word =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      got=${BASH_REMATCH[1]}
      break
    fi
  done
  if [ "$rc" = 0 ] && [ "$got" = "$want" ]; then
    printf '%-18s %s\n' "$label" "$line"
  else
    fail "$label: expected version $want, exit $rc, output: ${line:-<none>}"
  fi
}

check_hash() { # <tool> <version>
  local tool=$1 version=$2 want dir got
  want=$(binary_sha256 "$tool" "$version" "$arch")
  [ -n "$want" ] || { fail "$tool $version: no sha256 pinned for this version on $arch (update binary_sha256)"; return; }
  dir=$(asdf where "$tool" "$version" 2> /dev/null) || { fail "$tool $version: not installed"; return; }
  got=$(sha256sum "$dir/bin/$tool" | awk '{ print $1 }')
  if [ "$got" = "$want" ]; then
    printf '%-18s sha256 %s\n' "$tool" "$got"
  else
    fail "$tool $version: sha256 of $dir/bin/$tool is $got, expected $want"
  fi
}

check_version scarb "$(pinned scarb)" scarb --version
check_version snforge "$(pinned starknet-foundry)" snforge --version
check_version node "$(pinned nodejs)" node --version
check_version pnpm "$(pinned pnpm)" pnpm --version
for tool in sozo katana torii; do
  version=$(pinned "$tool")
  [ -n "$version" ] || { fail "$tool is not pinned in .tool-versions"; continue; }
  check_version "$tool" "$version" "$tool" --version
  check_hash "$tool" "$version"
done

# --- node and pnpm outside a pinned directory (incident INC-2026-09-28) ------------------------
# The shims of the nodejs and pnpm plugins answer "No version is set" where no .tool-versions
# names them, instead of falling through to the system binaries. Only a warning: the remedy
# (`nodejs system` and `pnpm system` in the global ~/.tool-versions) is the owner's decision and
# this script never edits that file.
for tool in node pnpm; do
  if ! (cd /tmp && "$tool" --version > /dev/null 2>&1); then
    echo "setup-toolchain: WARNING: '$tool --version' fails in /tmp, outside a pinned directory." >&2
    echo "setup-toolchain: the asdf shim hides the system $tool (docs/reports/INC-2026-09-28-asdf-node-shims.md)." >&2
    echo "setup-toolchain: pending remedy of that incident, an owner decision: add 'nodejs system' and" >&2
    echo "setup-toolchain: 'pnpm system' to ~/.tool-versions. This script does not edit that file." >&2
  fi
done

exit "$status"

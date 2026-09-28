#!/usr/bin/env bash
# Installs the toolchain of Grim World on a clean machine, without root, and checks it.
# Idempotent: what is installed is left alone. Nothing global is touched: the versions come from
# the repository's .tool-versions (never `asdf set -u`, never ~/.tool-versions, which is only
# READ, below), and no plugin is ever removed.
#
#   .tool-versions   scarb, starknet-foundry (which brings snforge and sncast), starknet-devnet (the
#                    local node, NS-1: docs/research/SPK-5b-toolchain-native.md), nodejs, pnpm.
#                    A native Starknet game on Cairo 2.19 (ADR-0007): no sozo, katana or torii.
#                    The Dojo spikes pin their own set in spikes/*/.tool-versions and are not
#                    installed by this script.
#
# WHAT IS WRITTEN OUTSIDE asdf's data directory (~/.asdf, or $ASDF_DATA_DIR): nothing by this
# script. Side effects of the third-party plugins, not of this script: node-build logs in /tmp
# (nodejs), and `curl | sh` of universal-sierra-compiler's installer by the starknet-foundry
# plugin, which puts `universal-sierra-compiler` in ~/.local/bin (already there on this machine,
# dated before this task, unchanged).
#
# EVERY PINNED TOOL comes first from the system. Adding an asdf plugin creates shims that hide the
# system binary of that tool everywhere (docs/reports/INC-2026-09-28-asdf-node-shims.md). So, per
# tool (nodejs, pnpm, scarb, starknet-foundry, starknet-devnet), in this order:
#   1. the plugin is already added: the pinned version is installed (the repository's pin selects
#      it through the shim, so it must exist), nothing is added;
#   2. else the binaries (found on the PATH outside asdf's shims directory) already have exactly
#      the pinned version (and, where a sha256 is pinned below, that hash): they are used and the
#      plugin is NOT added;
#   3. else, if the system has the tool at another version, the plugin is added only if the global
#      ~/.tool-versions (read-only check) already has `<tool> system`; if not, the script stops
#      with the remedy of the incident file;
#   4. else (no such binary anywhere) the plugin is added: it hides nothing.
# An existing plugin is never removed. The repository's .tool-versions keeps every pin either
# way: where the plugins are already added (this machine), that local pin is what makes the tools
# work in the worktrees.
#
# INTEGRITY, tool by tool (sources read on 2026-09-28, see the research file §1):
#   starknet-devnet      asdf-starknet-devnet (ptisserand/asdf-starknet-devnet, a plugin
#                        generated from asdf's template): the release tarball of 0xSpaceShard/starknet-devnet over
#                        HTTPS by curl, no checksum. The sha256 of the extracted binary is pinned
#                        below (it comes from the release tarball, whose sha256 GitHub publishes as
#                        the asset digest) and verified BEFORE the binary is run, on every run.
#   scarb              asdf-scarb (software-mansion/asdf-scarb, bin/download, lib/utils.bash):
#                        release tarball from github.com over HTTPS by curl; no checksum, no
#                        signature. Not pinned here: the archive holds ~9 binaries per arch.
#   snforge, sncast      asdf-starknet-foundry (foundry-rs/asdf-starknet-foundry): the same, and it
#                        pipes universal-sierra-compiler's install.sh to `sh`; no checksum.
#   node                 system package; or asdf-nodejs, which delegates to node-build: node-build
#                        keeps a sha256 per release in its definitions and verifies the download
#                        (asdf-nodejs README, "integrity"), the definitions being updated from
#                        github.com at install time.
#   pnpm                 system package; or asdf-pnpm: tarball from the npm registry over HTTPS by
#                        curl, no checksum (bin/download); pnpm 12 then downloads its platform
#                        binary itself at first use.
#   For these, HTTPS to github.com, the npm registry and nodejs.org is the whole guarantee, and the
#   version check runs the binary: they are trusted, not verified. Reasons and constraints: the
#   research file.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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
    starknet-devnet:0.10.0:amd64) echo 4e2e6479fa9502f2952ed26740d5cc8ebeb3695c16e752edcc560f6e736b167c ;;
    starknet-devnet:0.10.0:arm64) echo fe08fbe940e4e2efde9af3a199b6902e926822efb53207c79c81eb5b6b050111 ;;
  esac
}

# The first executable called <binary> on the PATH outside asdf's shims directory, or nothing.
system_binary() { # <binary>
  local shims=${ASDF_DATA_DIR:-$HOME/.asdf}/shims dir dirs
  IFS=: read -ra dirs <<< "$PATH"
  for dir in "${dirs[@]}"; do
    if [ -z "$dir" ] || [ "$dir" = "$shims" ]; then continue; fi
    if [ -x "$dir/$1" ] && [ ! -d "$dir/$1" ]; then
      echo "$dir/$1"
      return
    fi
  done
}

# First version-shaped word of the first line of the output of a version command.
version_of() { # <command…>
  local out line word
  out=$("$@" 2>&1) || return 1
  line=$(grep -v '^Downloading' <<< "$out" | head -n 1 || true)
  for word in $line; do
    if [[ $word =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]}"
      return
    fi
  done
  return 1
}

# Read-only: does the global ~/.tool-versions already say `<tool> system`?
global_system_fallback() { # <asdf tool name>
  local file=$HOME/${ASDF_DEFAULT_TOOL_VERSIONS_FILENAME:-.tool-versions}
  [ -r "$file" ] && grep -Eq "^[[:space:]]*$1[[:space:]]+system([[:space:]]|\$)" "$file"
}

command -v asdf > /dev/null || die "asdf is not installed (https://asdf-vm.com/guide/getting-started.html)"
command -v sha256sum > /dev/null || die "sha256sum is required"

cd "$root"
[ -f .tool-versions ] || die "no .tool-versions at $root"
pinned() { awk -v n="$1" '$1 == n { print $2 }' .tool-versions; }

# --- every pinned tool: the system first -----------------------------------------------------
sha256_of() { sha256sum "$1" | awk '{ print $1 }'; }

system_served=' '   # asdf names served by the system binaries, e.g. ' nodejs pnpm '
declare -A system_path   # asdf name -> the system binary named like the tool, for the hash check
plugins=$(asdf plugin list 2> /dev/null || true)
# <asdf name>:<binaries the tool brings, comma separated>
for pair in nodejs:node pnpm:pnpm scarb:scarb starknet-foundry:snforge,sncast starknet-devnet:starknet-devnet; do
  name=${pair%%:*} binaries=${pair##*:}
  want=$(pinned "$name")
  [ -n "$want" ] || continue
  if grep -qx "$name" <<< "$plugins"; then
    log "$name $want: the asdf plugin is already added, installing the pin"
    continue
  fi
  # Do the system binaries have exactly the pinned version (and pinned hash, when there is one)?
  match=1 seen='' candidate='' hash_want=$(binary_sha256 "$name" "$want" "$arch")
  for binary in ${binaries//,/ }; do
    sys=$(system_binary "$binary")
    if [ -z "$sys" ]; then
      match=0
      continue
    fi
    got=''
    # The hash is checked before the binary is run at all.
    if [ "$binary" = "$name" ] && [ -n "$hash_want" ] && [ "$(sha256_of "$sys")" != "$hash_want" ]; then
      got='another build'
    else
      got=$(version_of "$sys" --version || true)
    fi
    seen="$seen $binary:${got:-unknown}"
    [ "$got" = "$want" ] || match=0
    [ "$binary" != "$name" ] || candidate=$sys
  done
  if [ "$match" = 1 ]; then
    log "$name $want: using the system binaries (exactly the pinned version); asdf plugin not needed"
    system_served="$system_served$name "
    # Recorded only now that the system binary is the one selected: check_hash reads this path,
    # and a tool installed by asdf must be hashed where asdf put it.
    [ -z "$candidate" ] || system_path[$name]=$candidate
  elif [ -z "$seen" ]; then
    log "$name $want: no system binary outside asdf's shims; adding the plugin hides nothing"
  elif global_system_fallback "$name"; then
    log "$name $want: system has$seen; ~/.tool-versions has '$name system', adding the plugin is safe"
  else
    {
      echo "setup-toolchain: $name $want is pinned but the system has$seen."
      echo "setup-toolchain: adding the asdf plugin '$name' would hide the system binaries everywhere"
      echo "setup-toolchain: (docs/reports/INC-2026-09-28-asdf-node-shims.md). Refusing. Remedy of that incident,"
      echo "setup-toolchain: an owner decision: add the line '$name system' to ~/.tool-versions"
      echo "setup-toolchain: (backup first), then run this script again. This script does not edit that file."
    } >&2
    exit 1
  fi
done

# --- asdf plugins and versions, from .tool-versions ------------------------------------------
while read -r name version _ <&3; do
  case "$name" in '' | '#'*) continue ;; esac
  case "$system_served" in *" $name "*) continue ;; esac
  if ! grep -qx "$name" <<< "$plugins"; then
    log "asdf plugin add $name"
    asdf plugin add "$name"
  fi
  # The pnpm plugin may report a failed download step on a first install although pnpm 12 works
  # afterwards (its shim fetches the binary on first use): the checks below decide.
  asdf install "$name" "$version" || log "asdf install $name $version returned $?; the checks below decide"
done 3< .tool-versions

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

check_hash() { # <tool> <version>: the system binary when it serves the tool, else asdf's
  local tool=$1 version=$2 want file got
  want=$(binary_sha256 "$tool" "$version" "$arch")
  [ -n "$want" ] || { fail "$tool $version: no sha256 pinned for this version on $arch (update binary_sha256)"; return 1; }
  file=${system_path[$tool]:-}
  if [ -z "$file" ]; then
    file=$(asdf where "$tool" "$version" 2> /dev/null) || { fail "$tool $version: not installed"; return 1; }
    file=$file/bin/$tool
  fi
  got=$(sha256_of "$file")
  if [ "$got" = "$want" ]; then
    printf '%-18s sha256 %s\n' "$tool" "$got"
  else
    fail "$tool $version: sha256 of $file is $got, expected $want"
    return 1
  fi
}

check_version scarb "$(pinned scarb)" scarb --version
check_version snforge "$(pinned starknet-foundry)" snforge --version
check_version sncast "$(pinned starknet-foundry)" sncast --version
check_version node "$(pinned nodejs)" node --version
check_version pnpm "$(pinned pnpm)" pnpm --version
# starknet-devnet: the pinned sha256 is verified BEFORE the binary is run at all.
devnet_version=$(pinned starknet-devnet)
if [ -z "$devnet_version" ]; then
  fail "starknet-devnet is not pinned in .tool-versions"
elif check_hash starknet-devnet "$devnet_version"; then
  check_version starknet-devnet "$devnet_version" starknet-devnet --version
else
  echo "setup-toolchain: starknet-devnet not run: its hash was not verified" >&2
fi

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

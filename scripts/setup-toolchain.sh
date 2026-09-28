#!/usr/bin/env bash
# Installs the toolchain of Grim World on a clean machine, without root, and checks it.
# Idempotent: what is installed is left alone. Nothing global is touched: the versions come from
# the repository's .tool-versions (never `asdf set -u`, never ~/.tool-versions, which is only
# READ, below), and no plugin is ever removed.
#
#   .tool-versions   scarb, starknet-foundry, nodejs, pnpm, and sozo, katana, torii (the separate
#                    plugins github.com/dojoengine/asdf-{sozo,katana,torii}; the combined `dojo`
#                    plugin cannot install Dojo 1.8, see docs/research/SPK-5-toolchain.md)
#
# WHAT IS WRITTEN OUTSIDE asdf's data directory (~/.asdf, or $ASDF_DATA_DIR):
#   1. Exception of this script, one-time: it removes the symlinks ~/.cargo/bin/sozo,
#      ~/.cargo/bin/katana and ~/.cargo/bin/torii that a first version of this task created, and
#      only if each points into ~/.grimworld/tools/ (else it is left alone). On a machine where
#      they are gone, nothing happens. (~/.cargo/bin is $GRIMWORLD_BIN_DIR, ~/.grimworld/tools is
#      $GRIMWORLD_TOOLS.) The directory ~/.grimworld/tools itself is not touched.
#   2. Side effects of the third-party plugins, not of this script: node-build logs in /tmp
#      (nodejs), and `curl | sh` of universal-sierra-compiler's installer by the starknet-foundry
#      plugin, which puts `universal-sierra-compiler` in ~/.local/bin (already there on this
#      machine, dated before this task, unchanged).
#
# NODE AND PNPM come first from the system. Adding the asdf plugins nodejs and pnpm creates
# shims that hide the system node and pnpm everywhere (docs/reports/INC-2026-09-28-asdf-node-shims.md).
# So, per tool: if the system binary (found on the PATH outside asdf's shims directory) already
# has exactly the pinned version, it is used and the plugin is NOT added. Otherwise the plugin is
# added only if the global ~/.tool-versions (read-only check) already has `<tool> system`; if it
# has not, the script stops with the remedy of the incident file. An existing plugin is never
# removed. The repository's .tool-versions keeps nodejs and pnpm either way: where the plugins are
# already added (this machine), that local pin is what makes node work in the worktrees.
#
# INTEGRITY, tool by tool (sources read on 2026-09-28, see the research file §1):
#   sozo, katana, torii  sha256 of the extracted binary pinned below, verified BEFORE the binary is
#                        run, on every run (the plugins themselves check nothing).
#   scarb                asdf-scarb (software-mansion/asdf-scarb, bin/download, lib/utils.bash):
#                        release tarball from github.com over HTTPS by curl; no checksum, no
#                        signature. Not pinned here: the archive holds ~9 binaries per arch.
#   snforge              asdf-starknet-foundry (foundry-rs/asdf-starknet-foundry): the same, and it
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

# --- node and pnpm: the system first ---------------------------------------------------------
system_served=' '   # asdf names served by the system binary, e.g. ' nodejs pnpm '
plugins=$(asdf plugin list 2> /dev/null || true)
for pair in nodejs:node pnpm:pnpm; do
  name=${pair%%:*} binary=${pair##*:}
  want=$(pinned "$name")
  [ -n "$want" ] || continue
  sys=$(system_binary "$binary")
  got=''
  [ -z "$sys" ] || got=$(version_of "$sys" --version || true)
  if [ -n "$sys" ] && [ "$got" = "$want" ]; then
    log "$name $want: using the system $sys (exactly the pinned version); asdf plugin not needed"
    system_served="$system_served$name "
  elif grep -qx "$name" <<< "$plugins"; then
    log "$name $want: system ${got:-none} differs; the asdf plugin is already added, installing the pin"
  elif global_system_fallback "$name"; then
    log "$name $want: system ${got:-none} differs; ~/.tool-versions has '$name system', adding the plugin is safe"
  else
    {
      echo "setup-toolchain: $name $want is pinned but the system has ${got:-no $binary}."
      echo "setup-toolchain: adding the asdf plugin '$name' would hide the system $binary everywhere"
      echo "setup-toolchain: (docs/reports/INC-2026-09-28-asdf-node-shims.md). Refusing. Remedy of that incident,"
      echo "setup-toolchain: an owner decision: add the lines 'nodejs system' and 'pnpm system' to ~/.tool-versions"
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
    source=$(plugin_source "$name")
    if [ -n "$source" ]; then asdf plugin add "$name" "$source"; else asdf plugin add "$name"; fi
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

check_hash() { # <tool> <version>
  local tool=$1 version=$2 want dir got
  want=$(binary_sha256 "$tool" "$version" "$arch")
  [ -n "$want" ] || { fail "$tool $version: no sha256 pinned for this version on $arch (update binary_sha256)"; return 1; }
  dir=$(asdf where "$tool" "$version" 2> /dev/null) || { fail "$tool $version: not installed"; return 1; }
  got=$(sha256sum "$dir/bin/$tool" | awk '{ print $1 }')
  if [ "$got" = "$want" ]; then
    printf '%-18s sha256 %s\n' "$tool" "$got"
  else
    fail "$tool $version: sha256 of $dir/bin/$tool is $got, expected $want"
    return 1
  fi
}

check_version scarb "$(pinned scarb)" scarb --version
check_version snforge "$(pinned starknet-foundry)" snforge --version
check_version node "$(pinned nodejs)" node --version
check_version pnpm "$(pinned pnpm)" pnpm --version
# sozo, katana and torii: the pinned sha256 is verified BEFORE the binary is run at all.
for tool in sozo katana torii; do
  version=$(pinned "$tool")
  [ -n "$version" ] || { fail "$tool is not pinned in .tool-versions"; continue; }
  check_hash "$tool" "$version" || { echo "setup-toolchain: $tool not run: its hash was not verified" >&2; continue; }
  check_version "$tool" "$version" "$tool" --version
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

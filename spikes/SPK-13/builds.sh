#!/usr/bin/env bash
# SPK-13: builds the same sources N times from a clean state and records, per build, every Sierra
# class and every compiled test file (sha256, Sierra size, withdraw_gas statements, CASM felts and
# sha256, class hash), with the environment. Run from anywhere; every path is relative to the
# worktree. Heavy builds go through scripts/lock.sh when `flock` exists (the VPS); on a machine
# without it (macOS) Scarb runs directly and the environment block says so.
#
#   spikes/SPK-13/builds.sh [--target consumer|consumer-dev|hexx|contracts|minimal|all] [--n N]
#                           [--series clean,fresh-cache,one-thread] [--threads T]
#                           [--from K] [--out DIR] [--library-commit C]
#
# Targets (the library is cloned by fetch-library.sh into the spike's ignored .work/):
#   consumer   the library's crates/consumer, `build -p consumer` in the release profile (what the library's
#              scripts/bytecode_size.py measures: HexxGenerators and eight more classes)
#   consumer-dev  the same in the dev profile, `build -p consumer` (its classes carry debug names)
#   hexx       the library's crates/hexx tests, `build --test -p hexx` (the compiled test files of
#              snforge: ~4 minutes and a 228 MB file per build on the Mac)
#   contracts  the game's contracts/ at this branch's base commit, `build --workspace` then
#              `build --test --workspace` (what CI's `build` and `test` steps compile)
#   minimal    spikes/SPK-13/minimal, `build` (the minimal program)
# Series (each build starts from `scarb clean`):
#   clean        the Scarb cache of the machine
#   fresh-cache  SCARB_CACHE pointed at a new folder under --out for every build (deleted after)
#   one-thread   RAYON_NUM_THREADS=1: the compiler's parallel warm-up off (the control)
# --from K numbers the builds K..K+N-1 (to continue a series in several runs: rows are appended).
# --threads T sets RAYON_NUM_THREADS for the clean and fresh-cache series (otherwise: what the
# environment gives; scripts/lock.sh defaults it to 4, rayon itself to the number of CPUs).
#
# Output, under --out (default spikes/SPK-13/.work/out): rows.tsv (one row per artefact and
# build, appended across runs), env.txt, kept/ (one copy of every distinct program of an artefact),
# builds.txt (the table of every run so far: commit it as builds-<machine>.txt).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)
cd "$root"
rel_here=spikes/SPK-13

target=all n=10 from=1 series=clean,fresh-cache,one-thread threads="" out="$rel_here/.work/out"
library_commit=310b5f1
usage() { sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --target) target=$2; shift 2 ;;
    --n) n=$2; shift 2 ;;
    --from) from=$2; shift 2 ;;
    --series) series=$2; shift 2 ;;
    --threads) threads=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --library-commit) library_commit=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "builds.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$n$from" in '' | *[!0-9]*) echo "builds.sh: --n and --from need numbers" >&2; exit 2 ;; esac
[ "$target" = all ] && target=consumer,hexx,contracts
mkdir -p "$out"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
ncpu() { getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu; }
tilde() { sed "s#$HOME#~#g"; }
if command -v flock >/dev/null; then lock=1; else lock=0; fi

# Scarb with the build lock when the machine has one. Its arguments: manifest, then subcommand...
scarb_run() {
  local manifest=$1; shift
  if [ "$lock" = 1 ]; then
    scripts/lock.sh scarb --manifest-path "$manifest" "$@"
  else
    scarb --manifest-path "$manifest" "$@"
  fi
}

library="$rel_here/.work/hexx-cairo"
need_library() {
  if [ ! -d "$library/.git" ] || [ "$(git -C "$library" rev-parse --short=7 HEAD)" != "${library_commit:0:7}" ]; then
    "$here/fetch-library.sh" "$library_commit" >/dev/null
  fi
}

# target -> manifest, profile dir, build commands (one per line)
manifest_of() {
  case "$1" in
    consumer | consumer-dev | hexx) echo "$library/Scarb.toml" ;;
    contracts) echo contracts/Scarb.toml ;;
    minimal) echo "$rel_here/minimal/Scarb.toml" ;;
    *) echo "builds.sh: unknown target $1" >&2; exit 2 ;;
  esac
}
profile_dir_of() {
  case "$1" in
    consumer) echo "$library/target/release" ;;
    consumer-dev | hexx) echo "$library/target/dev" ;;
    contracts) echo contracts/target/dev ;;
    minimal) echo "$rel_here/minimal/target/dev" ;;
  esac
}
build_target() { # target manifest
  case "$1" in
    # The release profile through Scarb's variable: `--release` is a global option, which
    # scripts/lock.sh does not let sit before the subcommand.
    consumer) SCARB_PROFILE=release scarb_run "$2" build -p consumer ;;
    consumer-dev) scarb_run "$2" build -p consumer ;;
    hexx) scarb_run "$2" build --test -p hexx ;;
    contracts) scarb_run "$2" build --workspace && scarb_run "$2" build --test --workspace ;;
    minimal) scarb_run "$2" build ;;
  esac
}

threads_note() { # series
  local t=$threads
  [ "$1" = one-thread ] && t=1
  if [ -n "$t" ]; then echo "$t"
  elif [ -n "${RAYON_NUM_THREADS:-}" ]; then echo "$RAYON_NUM_THREADS"
  elif [ "$lock" = 1 ]; then echo "4 (scripts/lock.sh default)"
  else echo "unset (rayon: $(ncpu) CPUs)"
  fi
}

write_env() {
  local scarb_bin
  scarb_bin=$( (cd "$root" && asdf which scarb 2>/dev/null) || command -v scarb)
  {
    echo "## Environment: $(hostname -s 2>/dev/null || hostname), $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo '```'
    echo "uname -a: $(uname -a)"
    echo "scarb --version:"; scarb --version | sed 's/^/  /'
    echo "scarb on PATH: $(command -v scarb)"
    echo "scarb binary: $scarb_bin"
    echo "scarb binary sha256: $(sha256 "$scarb_bin")"
    echo "scarb cache path (default): $(scarb cache path 2>/dev/null || echo '?')"
    echo "CPUs: $(ncpu)"
    echo "RAYON_NUM_THREADS in the environment: ${RAYON_NUM_THREADS:-unset}; --threads of the last run: ${threads:-none} (each row records its own threads)"
    if [ "$lock" = 1 ]; then echo "build lock: scripts/lock.sh (flock: $(command -v flock))"
    else echo "build lock: none (no flock on this machine); scarb runs directly"; fi
    echo "starkli: $(starkli --version 2>/dev/null || echo 'absent (class hashes by class_hash.py)')"
    echo "spike commit: $(git rev-parse --short HEAD)"
    echo '```'
  } | tilde > "$out/env.txt"
}

target_env() { # target manifest
  {
    echo "### Target $1"
    echo
    echo '```'
    case "$1" in
      consumer | consumer-dev | hexx) echo "library: bal7hazar/hexx-cairo at $(git -C "$library" rev-parse HEAD)" ;;
      contracts)
        base=$(git merge-base HEAD origin/main)
        if git diff --quiet "$base" -- contracts; then same=identical; else same=DIFFERENT; fi
        echo "game contracts/ at base commit $base (working tree: $same)" ;;
      minimal) echo "minimal program: $rel_here/minimal at $(git rev-parse --short HEAD)" ;;
    esac
    lockfile="$(dirname "$2")/Scarb.lock"
    if [ -f "$lockfile" ]; then echo "Scarb.lock sha256: $(sha256 "$lockfile")"; else echo "Scarb.lock: absent"; fi
    echo '```'
  } | tilde > "$out/env-$1.txt"
}

write_env
IFS=, read -r -a targets <<< "$target"
IFS=, read -r -a serieses <<< "$series"
for t in "${targets[@]}"; do
  case "$t" in consumer | consumer-dev | hexx) need_library ;; esac
  manifest=$(manifest_of "$t")
  target_env "$t" "$manifest"
  for s in "${serieses[@]}"; do
    case "$s" in clean | fresh-cache | one-thread) ;; *) echo "builds.sh: unknown series $s" >&2; exit 2 ;; esac
    note=$(threads_note "$s")
    for i in $(seq "$from" $((from + n - 1))); do
      echo "builds.sh: $t / $s / build $i (threads: $note)" >&2
      # `scarb clean` is light (it removes the target folder): not a build, not under the lock.
      scarb --manifest-path "$manifest" clean
      cache=""
      (
        if [ "$s" = fresh-cache ]; then
          cache="$out/scarb-cache-$t-$i"
          rm -rf "$cache"; mkdir -p "$cache"
          SCARB_CACHE=$(cd "$cache" && pwd); export SCARB_CACHE
        fi
        if [ "$s" = one-thread ]; then export RAYON_NUM_THREADS=1
        elif [ -n "$threads" ]; then export RAYON_NUM_THREADS=$threads; fi
        build_target "$t" "$manifest" > "$out/last-build.log" 2>&1 ||
          { tail -40 "$out/last-build.log" >&2; exit 1; }
        python3 "$here/collect.py" rows "$(profile_dir_of "$t")" "$out/rows.tsv" "$t" "$s" "$i" \
          "$note" --keep "$out/kept"
        [ -z "$cache" ] || rm -rf "$cache"
      )
    done
  done
done
envs=("$out/env.txt")
for e in "$out"/env-*.txt; do [ -f "$e" ] && envs+=("$e"); done
python3 "$here/collect.py" table "$out/rows.tsv" "${envs[@]}" | tilde > "$out/builds.txt"
echo "builds.sh: table in $out/builds.txt" >&2

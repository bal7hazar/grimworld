#!/usr/bin/env bash
# Publishes the client of origin/main for the owner's reviews (grimworld.bal7hazar.com, served by Caddy
# from $SITE_ROOT/current). Run every 5 minutes by tools/site/grimworld-site.timer; safe to run by hand.
#
# Git only: it fetches origin main in its OWN clone ($SITE_SRC, never the shared checkout the threads use)
# and does nothing when the commit is the one already deployed. No GitHub API call. It builds the client
# only (pnpm, no Cairo, so no build lock), at `nice`, copies dist/ to $SITE_ROOT/releases/<sha>/ and
# switches $SITE_ROOT/current to it atomically. A failed build leaves `current` untouched.
#
# The art (D-73) is NOT in the build by default: the client then draws shapes. GRIMWORLD_SITE_ART=1
# builds the atlas from the pack on this machine ($GRIMWORLD_ASSETS) and copies it to <release>/art/,
# where the client loads it (src/render/atlas.ts ART_BASE). Leave it unset until the owner allows it.
#
# Files in $SITE_ROOT: current -> releases/<sha>; deployed (the sha and art flag of `current`);
# failed (the sha of the last failed build, retried after 30 minutes); deploy.log (one line per run).
set -euo pipefail

SITE_ROOT=${GRIMWORLD_SITE_ROOT:-$HOME/site/grimworld}
SITE_SRC=${GRIMWORLD_SITE_SRC:-$HOME/site/grimworld-src}
REPO=${GRIMWORLD_SITE_REPO:-git@github.com:bal7hazar/grimworld.git}
ASSETS=${GRIMWORLD_ASSETS:-$HOME/projects/assets}
ART=${GRIMWORLD_SITE_ART:-0}
KEEP=3
RETRY_MIN=30

[ "$ART" = 0 ] || [ "$ART" = 1 ] || { echo "GRIMWORLD_SITE_ART must be 0 or 1" >&2; exit 2; }
mkdir -p "$SITE_ROOT/releases"
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$SITE_ROOT/deploy.log"; }

# One run at a time (a build can outlast the timer's interval).
exec 9>"$SITE_ROOT/deploy.lock"
flock -n 9 || { log "skip: another run holds the lock"; exit 0; }

start=$(date +%s)
sha=-
step=start
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "$sha" >"$SITE_ROOT/failed"; log "sha=$sha art=$ART result=FAILED(step=$step,rc=$rc) duration=$(($(date +%s) - start))s"; fi' EXIT

t() { # t <label> <command...>: run one step and log its duration (visible in the journal)
  local label=$1 s
  shift
  step=$label
  s=$(date +%s)
  "$@"
  echo "step $label: $(($(date +%s) - s)) s"
}

if [ ! -d "$SITE_SRC/.git" ]; then
  step=clone
  mkdir -p "$(dirname "$SITE_SRC")"
  git clone --quiet --no-checkout "$REPO" "$SITE_SRC"
fi
cd "$SITE_SRC"
step=fetch
git fetch --quiet origin main
sha=$(git rev-parse FETCH_HEAD)

if [ "$(cat "$SITE_ROOT/deployed" 2>/dev/null)" = "$sha art=$ART" ] && [ -d "$SITE_ROOT/releases/$sha" ]; then
  echo "up to date at $sha"
  trap - EXIT
  exit 0
fi
if [ "$(cat "$SITE_ROOT/failed" 2>/dev/null)" = "$sha" ] && [ -n "$(find "$SITE_ROOT/failed" -mmin "-$RETRY_MIN")" ]; then
  echo "$sha failed less than $RETRY_MIN min ago: not retried yet"
  trap - EXIT
  exit 0
fi

t checkout git checkout --quiet --detach --force "$sha"
git clean -fdq
if [ "$ART" = 1 ]; then
  # An untracked symlink in place of the empty submodule directory, as the threads do; removed after.
  [ -d "$ASSETS" ] || { echo "no art pack at $ASSETS" >&2; exit 1; }
  rmdir assets 2>/dev/null || rm -f assets
  ln -s "$ASSETS" assets
  t art nice -n 10 tools/art/build.py
  rm -f assets
  mkdir -p assets
fi
t install nice -n 10 pnpm --filter @grimworld/app... install --frozen-lockfile
t build nice -n 10 pnpm --filter @grimworld/app build
dist=$SITE_SRC/client/app/dist
[ -f "$dist/index.html" ] || { echo "no $dist/index.html" >&2; exit 1; }

step=publish
rel=$SITE_ROOT/releases/$sha
rm -rf "$rel.tmp"
cp -r "$dist" "$rel.tmp"
if [ "$ART" = 1 ]; then
  mkdir -p "$rel.tmp/art"
  cp -r "$SITE_SRC/tools/art/out/." "$rel.tmp/art/"
fi
chmod -R a+rX "$rel.tmp"
rm -rf "$rel"
mv -T "$rel.tmp" "$rel"
ln -sfn "releases/$sha" "$SITE_ROOT/current.tmp"
mv -T "$SITE_ROOT/current.tmp" "$SITE_ROOT/current"
echo "$sha art=$ART" >"$SITE_ROOT/deployed"
rm -f "$SITE_ROOT/failed"

# Keep the newest $KEEP releases (a release is a directory named by a 40-hex sha, made here).
step=prune
(cd "$SITE_ROOT/releases" && ls -1t | grep -E '^[0-9a-f]{40}$' | tail -n +$((KEEP + 1)) | while read -r old; do
  [ "$old" = "$sha" ] || rm -rf "$SITE_ROOT/releases/$old"
done)

trap - EXIT
log "sha=$sha art=$ART result=ok duration=$(($(date +%s) - start))s"

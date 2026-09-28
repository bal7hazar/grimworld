#!/usr/bin/env bash
# Runs a command against a local Katana (and optionally Torii) that live only as long as the
# command: start the node(s), wait until they answer, run the command in the foreground, stop
# them, exit with the command's status. This is how an agent runs anything that needs a node
# without a background command (docs/briefs/COMMON.md §2).
#
#   scripts/with-katana.sh [--torii] [--world <address>] <command> [args...]
#
#   --torii            also start Torii, indexing the world at <address>
#   --world <address>  the world Torii indexes (default: $DOJO_WORLD_ADDRESS); required with --torii.
#                      The address is deterministic (dojo_dev.toml of the world, or `sozo migrate`
#                      output), so Torii can start before the world is migrated.
#
# Ports are picked free at each run, so parallel agents never collide. The command gets:
#   KATANA_URL       http://127.0.0.1:<port>          (JSON-RPC; also RPC_URL and STARKNET_RPC_URL,
#                                                      which sozo reads: no --rpc-url needed)
#   TORII_URL        http://127.0.0.1:<port>          (HTTP, GraphQL, SQL)
#   TORII_GRPC_URL   http://127.0.0.1:<port>          (gRPC, what dojo.js reads)
# Katana runs in dev mode: seed 0, ten pre-funded accounts (printed in the log).
# Logs: $WITH_KATANA_LOG_DIR (default ./.with-katana/) katana.log and torii.log, overwritten each run.
# Torii's database is in memory: nothing outlives the run.
# The functions below are called by the trap and through wait_for: shellcheck 0.9 reports them as
# unreachable (SC2317), 0.10 and later as never invoked (SC2329).
# shellcheck disable=SC2317,SC2329
set -uo pipefail

usage() {
  echo "usage: scripts/with-katana.sh [--torii] [--world <address>] <command> [args...]" >&2
  exit 2
}

torii=0
world=${DOJO_WORLD_ADDRESS:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --torii) torii=1 ;;
    --world)
      [ $# -ge 2 ] || usage
      world=$2
      shift
      ;;
    --) shift; break ;;
    -*) echo "with-katana: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 1 ] || usage
if [ "$torii" = 1 ] && [ -z "$world" ]; then
  echo "with-katana: --torii needs the world address (--world <address> or DOJO_WORLD_ADDRESS)" >&2
  exit 2
fi
command -v katana > /dev/null || { echo "with-katana: katana not found (scripts/setup-toolchain.sh)" >&2; exit 127; }
if [ "$torii" = 1 ]; then
  command -v torii > /dev/null || { echo "with-katana: torii not found (scripts/setup-toolchain.sh)" >&2; exit 127; }
fi

log_dir=${WITH_KATANA_LOG_DIR:-$PWD/.with-katana}
mkdir -p "$log_dir"

katana_pid='' torii_pid='' cmd_pid=''

# A port nobody listens on, not handed out earlier in this run.
taken=" "
free_port() {
  local p
  while :; do
    p=$((RANDOM % 20000 + 20000))
    case "$taken" in *" $p "*) continue ;; esac
    if ! (exec 3<> "/dev/tcp/127.0.0.1/$p") 2> /dev/null; then
      taken="$taken$p "
      echo "$p"
      return
    fi
  done
}

stop() { # <pid> [group]: TERM, then KILL after five seconds; with "group", the whole process group
  local pid=$1 target=$1
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null || return 0
  [ "${2:-}" = group ] && target=-$pid
  kill -- "$target" 2> /dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.5
  done
  kill -9 -- "$target" 2> /dev/null
  wait "$pid" 2> /dev/null
  return 0
}

cleanup() {
  trap '' EXIT INT TERM HUP
  stop "$cmd_pid" group
  stop "$torii_pid"
  stop "$katana_pid"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

wait_for() { # <label> <pid> <log> <probe command…>
  local label=$1 pid=$2 log=$3
  shift 3
  for _ in $(seq 1 120); do
    if ! kill -0 "$pid" 2> /dev/null; then
      echo "with-katana: $label exited during startup; see $log" >&2
      tail -n 20 "$log" >&2
      return 1
    fi
    if "$@" > /dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  echo "with-katana: $label did not answer within 60 s; see $log" >&2
  return 1
}

katana_port=$(free_port)
katana --dev --http.port "$katana_port" > "$log_dir/katana.log" 2>&1 &
katana_pid=$!
katana_url=http://127.0.0.1:$katana_port
probe_katana() {
  curl -sf -X POST -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"starknet_chainId","params":[]}' "$katana_url"
}
wait_for katana "$katana_pid" "$log_dir/katana.log" probe_katana || exit 1
export KATANA_URL=$katana_url RPC_URL=$katana_url STARKNET_RPC_URL=$katana_url

if [ "$torii" = 1 ]; then
  torii_port=$(free_port) grpc_port=$(free_port)
  relay_port=$(free_port) relay_webrtc_port=$(free_port) relay_ws_port=$(free_port)
  torii --world "$world" --rpc "$katana_url" \
    --http.port "$torii_port" --grpc.port "$grpc_port" \
    --relay.port "$relay_port" --relay.webrtc_port "$relay_webrtc_port" \
    --relay.websocket_port "$relay_ws_port" \
    > "$log_dir/torii.log" 2>&1 &
  torii_pid=$!
  probe_torii() { curl -s -o /dev/null "http://127.0.0.1:$torii_port/"; }
  wait_for torii "$torii_pid" "$log_dir/torii.log" probe_torii || exit 1
  export TORII_URL=http://127.0.0.1:$torii_port TORII_GRPC_URL=http://127.0.0.1:$grpc_port
  export DOJO_WORLD_ADDRESS=$world
fi

# In its own session, so that stopping it stops what it started (sozo, node…) too.
setsid "$@" <&0 &
cmd_pid=$!
wait "$cmd_pid"
status=$?
cmd_pid=''
exit "$status"

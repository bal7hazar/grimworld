#!/usr/bin/env bash
# COPY of spikes/SPK-5/with-katana.sh, itself a copy of scripts/with-katana.sh as it was on origin/main before SPK-5b removed it (ADR-0007: the game
# runs on starknet-devnet through scripts/with-node.sh). It belongs to the Dojo baseline spike, which
# keeps its own toolchain in spikes/SPK-2/.tool-versions. Changed from the original: only the paths,
# and the `cd` below, which makes asdf resolve that .tool-versions (katana, torii, sozo, scarb 2.13)
# wherever the script is called from. The command therefore runs from spikes/SPK-2/ (write
# `bash run.sh`, not `bash spikes/SPK-2/run.sh`).
# Runs a command against a local Katana (and optionally Torii) that live only as long as the
# command: start the node(s), wait until they answer, run the command in the foreground, stop
# them, exit with the command's status. This is how an agent runs anything that needs a node
# without a background command (docs/briefs/COMMON.md §2).
#
#   spikes/SPK-2/with-katana.sh [--torii] [--world <address>] <command> [args...]
#
#   --torii            also start Torii, indexing the world at <address>
#   --world <address>  the world Torii indexes (default: $DOJO_WORLD_ADDRESS); required with --torii.
#                      The address is deterministic (dojo_dev.toml of the world, or `sozo migrate`
#                      output), so Torii can start before the world is migrated.
#
# Ports are picked free at each run, so parallel agents never collide; a node that fails to bind
# (another process took the port in between) is restarted on new ports, up to five times, and a
# node counts as started only when its own log says it serves the port and the port answers.
# The command gets:
#   KATANA_URL       http://127.0.0.1:<port>          (JSON-RPC; also RPC_URL and STARKNET_RPC_URL,
#                                                      which sozo reads: no --rpc-url needed)
#   TORII_URL        http://127.0.0.1:<port>          (HTTP, GraphQL, SQL)
#   TORII_GRPC_URL   http://127.0.0.1:<port>          (gRPC, what dojo.js reads)
# The command runs in its own process group. On every way out (the command ends, fails, or this
# script is interrupted) the whole group is stopped, so nothing the command started survives it,
# even when the command itself exited first; then Torii, then Katana.
# Katana runs in dev mode: seed 0, ten pre-funded accounts (printed in the log).
# Logs: $WITH_KATANA_LOG_DIR (default ./.with-katana/) katana.log and torii.log, overwritten each run.
# Torii's database is in memory: nothing outlives the run.
#
# A process group id cannot be handed to another group while a member is alive, so signalling the
# group is safe as long as the command's leader has been reaped by this script (it has: `wait`).
# The functions below are called by the trap and through wait_for: shellcheck 0.9 reports them as
# unreachable (SC2317), 0.10 and later as never invoked (SC2329).
# shellcheck disable=SC2317,SC2329
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

usage() {
  echo "usage: spikes/SPK-2/with-katana.sh [--torii] [--world <address>] <command> [args...]" >&2
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
command -v katana > /dev/null || { echo "with-katana: katana not found (spikes/SPK-2/.tool-versions: asdf install)" >&2; exit 127; }
if [ "$torii" = 1 ]; then
  command -v torii > /dev/null || { echo "with-katana: torii not found (spikes/SPK-2/.tool-versions: asdf install)" >&2; exit 127; }
fi

log_dir=${WITH_KATANA_LOG_DIR:-$PWD/.with-katana}
mkdir -p "$log_dir"

katana_pid='' torii_pid='' cmd_pgid=''

# --- ports ---------------------------------------------------------------------------------------
# pick_port sets PORT (never runs in a command substitution: `taken` must live in this shell): a
# port nobody listens on, not handed out earlier in this run.
taken=" "
PORT=''
pick_port() {
  local p
  while :; do
    p=$((RANDOM % 20000 + 20000))
    case "$taken" in *" $p "*) continue ;; esac
    if ! (exec 3<> "/dev/tcp/127.0.0.1/$p") 2> /dev/null; then
      taken="$taken$p "
      PORT=$p
      return
    fi
  done
}

# --- stopping ------------------------------------------------------------------------------------
stop() { # <pid>: TERM, then KILL after five seconds
  local pid=$1
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null || return 0
  kill "$pid" 2> /dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.5
  done
  kill -9 "$pid" 2> /dev/null
  wait "$pid" 2> /dev/null
  return 0
}

group_alive() { kill -0 -- "-$1" 2> /dev/null; }

stop_group() { # <pgid>: TERM the whole group, then KILL after five seconds, whoever is left in it
  local pgid=$1
  group_alive "$pgid" || return 0
  kill -TERM -- "-$pgid" 2> /dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    group_alive "$pgid" || return 0
    sleep 0.5
  done
  kill -KILL -- "-$pgid" 2> /dev/null
  return 0
}

cleanup() {
  trap '' EXIT INT TERM HUP
  [ -z "$cmd_pgid" ] || stop_group "$cmd_pgid"
  stop "$torii_pid"
  stop "$katana_pid"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# --- starting nodes ------------------------------------------------------------------------------
# wait_for <label> <pid> <log> <ready function>: 0 when ready; 1 when the process died (a bind
# failure is retried by the caller); 2 when it neither died nor became ready within 60 s.
wait_for() {
  local label=$1 pid=$2 log=$3 ready=$4
  for _ in $(seq 1 120); do
    if ! kill -0 "$pid" 2> /dev/null; then
      echo "with-katana: $label exited during startup; see $log" >&2
      tail -n 5 "$log" >&2
      return 1
    fi
    if "$ready" > /dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  echo "with-katana: $label did not answer within 60 s; see $log" >&2
  return 2
}

# Ready = the node's own log says it serves the port AND the port answers: a stranger that took
# the port after the probe cannot pass for the node.
katana_ready() {
  grep -q "RPC server started.*127\.0\.0\.1:$katana_port" "$log_dir/katana.log" &&
    curl -sf -X POST -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"starknet_chainId","params":[]}' "http://127.0.0.1:$katana_port"
}

torii_ready() {
  grep -q "Starting torii endpoint.*127\.0\.0\.1:$torii_port" "$log_dir/torii.log" &&
    grep -q "Serving gRPC endpoint.*127\.0\.0\.1:$grpc_port" "$log_dir/torii.log" &&
    curl -s -o /dev/null "http://127.0.0.1:$torii_port/" &&
    (exec 3<> "/dev/tcp/127.0.0.1/$grpc_port")
}

start_katana() {
  local attempt status
  for attempt in 1 2 3 4 5; do
    pick_port
    katana_port=$PORT
    katana --dev --http.port "$katana_port" > "$log_dir/katana.log" 2>&1 &
    katana_pid=$!
    wait_for katana "$katana_pid" "$log_dir/katana.log" katana_ready
    status=$?
    [ "$status" = 0 ] && return 0
    stop "$katana_pid"
    katana_pid=''
    [ "$status" = 1 ] || return 1
    echo "with-katana: katana attempt $attempt failed, trying other ports" >&2
  done
  return 1
}

start_torii() {
  local attempt status relay_port relay_webrtc_port relay_ws_port
  for attempt in 1 2 3 4 5; do
    pick_port; torii_port=$PORT
    pick_port; grpc_port=$PORT
    pick_port; relay_port=$PORT
    pick_port; relay_webrtc_port=$PORT
    pick_port; relay_ws_port=$PORT
    torii --world "$world" --rpc "$katana_url" \
      --http.port "$torii_port" --grpc.port "$grpc_port" \
      --relay.port "$relay_port" --relay.webrtc_port "$relay_webrtc_port" \
      --relay.websocket_port "$relay_ws_port" \
      > "$log_dir/torii.log" 2>&1 &
    torii_pid=$!
    wait_for torii "$torii_pid" "$log_dir/torii.log" torii_ready
    status=$?
    [ "$status" = 0 ] && return 0
    stop "$torii_pid"
    torii_pid=''
    [ "$status" = 1 ] || return 1
    echo "with-katana: torii attempt $attempt failed, trying other ports" >&2
  done
  return 1
}

katana_port='' torii_port='' grpc_port=''
start_katana || { echo "with-katana: katana did not start" >&2; exit 1; }
katana_url=http://127.0.0.1:$katana_port
export KATANA_URL=$katana_url RPC_URL=$katana_url STARKNET_RPC_URL=$katana_url

if [ "$torii" = 1 ]; then
  start_torii || { echo "with-katana: torii did not start" >&2; exit 1; }
  export TORII_URL=http://127.0.0.1:$torii_port TORII_GRPC_URL=http://127.0.0.1:$grpc_port
  export DOJO_WORLD_ADDRESS=$world
fi

# In its own session, hence its own process group (setsid execs: this shell's background job is
# never a group leader), so that the group id is the pid and stays known after the leader exits.
setsid "$@" <&0 &
cmd_pgid=$!
wait "$cmd_pgid"
exit $?

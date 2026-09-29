# The funding service (FND-08)

Deploys and funds a player's burner account on request, with the funding key held here and never
in the client (ADR-0005 stage A, D-137). The client reaches it through `createServiceFunder` in
`client/app/src/account/funder.ts`. Hosting it is OPS-01's; nothing here is deployed.

## Endpoint

`POST /v1/burners`, body `{ "publicKey": "0x…", "address": "0x…" }` (the address is optional; when
given it must be the key's):

| Code | Body                                                       | Meaning                                                                         |
| ---- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 200  | `{ address, status: "succeeded", transaction?, repeated }` | The account exists and is funded; `repeated`: nothing was sent for this request |
| 202  | `{ address, status: "pending", transaction, repeated }`    | Sent, not settled yet: ask again                                                |
| 400  | `{ error: "invalid" }`                                     | Not a key on the curve, or an address that is not the key's                     |
| 403  | `{ error: "refused" }`                                     | The network is mainnet or not configured: nothing was signed                    |
| 429  | `{ error: "limited" }`                                     | This client's rate                                                              |
| 503  | `{ error: "exhausted" }` / `{ error: "unavailable" }`      | The day's budget / the chain cannot be reached, or the fee is above its cap     |
| 502  | `{ error: "failed", address, transaction }`                | The funding reverted; the key may ask again                                     |

## Configuration (environment, by name)

| Variable                     | Required | Default           |                                                                                                              |
| ---------------------------- | -------- | ----------------- | ------------------------------------------------------------------------------------------------------------ |
| `FUNDER_RPC_URL`             | yes      |                   | The node's JSON-RPC endpoint                                                                                 |
| `FUNDER_ACCOUNT_ADDRESS`     | yes      |                   | The funding account                                                                                          |
| `FUNDER_PRIVATE_KEY`         | yes      |                   | Its key: never printed, logged or written; removed from the environment once read                            |
| `FUNDER_ACCOUNT_CLASS`       | yes      |                   | The burner's class: on Sepolia, D-137's `0x01d1777db36cdd06dd62cfde77b1b6ae06412af95d57a13dc40ac77b8a702381` |
| `FUNDER_NETWORKS`            | yes      |                   | Chain ids allowed, by name or hex (`SN_SEPOLIA`); `SN_MAIN` is refused                                       |
| `FUNDER_AMOUNT`              |          | 2 STRK            | Given to each burner, in fri                                                                                 |
| `FUNDER_MAX_FEE`             |          | 0.5 STRK          | The most a funding may cost in fees, in fri                                                                  |
| `FUNDER_DAILY_BUDGET`        |          | 50                | New burners per day (UTC), all clients                                                                       |
| `FUNDER_CLIENT_RATE`         |          | 3                 | New burners per client (IPv4 address or IPv6 /64) per hour                                                   |
| `FUNDER_STATE_FILE`          | yes      |                   | The ledger: fundings, the day's spending, clients' rates, the held nonce; one service per file and account   |
| `FUNDER_EPHEMERAL`           |          | off               | `1`, instead of a state file, for development only: a restart forgets everything                             |
| `FUNDER_HOST`, `FUNDER_PORT` |          | `127.0.0.1`, 8787 | `0` picks a free port                                                                                        |
| `FUNDER_TRUST_PROXY`         |          | off               | `1`: the client is the last `X-Forwarded-For` hop                                                            |
| `FUNDER_ORIGIN`              |          | `*`               | `Access-Control-Allow-Origin`                                                                                |

## One execution per nonce

A funding is signed, kept in the state file with its nonce, and only then handed to the node. The
next funding waits until that nonce is consumed on the chain; while the node does not know the
kept execution, the service hands the same one again.

If a kept execution can never be included (the node refuses it for good), fundings stop and
answer `unavailable`: the operator consumes that nonce by sending any transaction from the funding
account, and the service goes on by itself.

## One service per state file and per funding account

At start the service creates `<state file>.lock` exclusively (`O_CREAT | O_EXCL`): of any number
of starts at the same time, the kernel lets one succeed. A lock that exists is **never taken
over**, even when the service that made it has stopped: the service refuses to start with
`the state file is locked by another service, or by one that stopped without closing it`. A
service removes its lock whenever it exits (a stop, a signal, an error); only a kill (`SIGKILL`,
the OOM killer) or a power loss leaves one.

**The operator's step after a kill:** make sure no funder service runs on the host (the lock holds
the pid of the one that made it: `ps -p <pid>` shows nothing, and no other funder process runs),
then remove `<state file>.lock` and start the service.

**What the deployment must guarantee (OPS-01)**; the code relies on it and cannot check it:

1. **One host.** The service, its state file and its lock are on one machine; no second host ever
   runs the service for the same funding account.
2. **The state file on a local disk** (not NFS, SMB or any storage shared between machines): the
   exclusive creation is atomic on a local file system only, and the pid in the lock means
   something on that host only.
3. **One state file per funding account, and one funding account per state file.** Two services
   with two state files on one account would each hand executions with the account's nonce.
4. **No automatic removal of the lock** (by a supervisor, a start script or a clean-up job): a
   supervisor may restart the service, which then refuses until the operator's step above.

## Run and test

```
pnpm --filter @grimworld/funder start                            # with the variables above
pnpm --filter @grimworld/funder test                             # offline
scripts/with-node.sh pnpm --filter @grimworld/funder test:node   # on the local node
```

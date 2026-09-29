# [Opus 5.5] FND-08 — The burner's funder on a public network

## Summary
The game now has a **funding service**, `services/funder/` (`@grimworld/funder`, TypeScript on Node 24, starknet.js 10.8.0 as FND-05 uses it). It deploys and funds a player's burner on request. The funding key stays on the server. The service sits behind FND-05's `Funder` port. On the client, `createServiceFunder` in `client/app/src/account/funder.ts` calls it; it holds no key and exports no vendor type. `createFunder({ kind: "service" | "node", … })` picks the funder from configuration, and `createNodeFunder` stays for the local node. It was tested on the local node only; nothing was deployed and no Sepolia transaction was sent.

Pull request: https://github.com/bal7hazar/grimworld/pull/141. Every CI check completed green (client, tooling, discover, all cairo jobs).

The model named in the brief (Opus 5.5) is the model this session runs as.

### The endpoint
`POST /v1/burners`, body `{ "publicKey": "0x…", "address": "0x…" }`. The address is optional; when given, it must be the address this key derives.

| Code | Body | When |
|---|---|---|
| 200 | `{ address, status: "succeeded", transaction?, repeated }` | The account exists and is funded. `repeated: true` means this request sent nothing |
| 202 | `{ address, status: "pending", transaction, repeated }` | Sent but not settled within 60 s. The client asks again; the retry checks the recorded execution and sends nothing new |
| 400 | `invalid` | The public key is not on the curve, or the address is not the key's; also bad JSON |
| 413 | `invalid` | The body is over 1 KB |
| 403 | `refused` | The network is mainnet or not configured; nothing was signed |
| 429 | `limited` | This client's hourly rate is used up |
| 503 | `exhausted` / `unavailable` | The day's budget is used up / the chain cannot be read, or the fee bound is above its cap |
| 502 | `failed` (+ address, transaction) | The funding reverted; the key may ask again |

The deployment (through the universal deployer, salt = the public key, class from configuration: D-137's `AccountUpgradeable` on Sepolia) and the STRK transfer go out as **one execution** from the funding account. Executions are sent one at a time, so the funding account's nonce never races.

## Files changed
- `pnpm-workspace.yaml`: adds `services/*`.
- `pnpm-lock.yaml`: the new package's importer (starknet 10.8.0, @types/node 26.6.3 and vitest 5.0.2, all already in the lock).
- `services/funder/package.json`, `tsconfig.json`, `eslint.config.js`, `.prettierrc.json`, `.gitignore`, `README.md`: the package, its checks, and its configuration table.
- `services/funder/src/config.ts`: reads the environment by variable name. Refuses `SN_MAIN` and caps that are not whole numbers. Error messages name the variable, never its value.
- `services/funder/src/secret.ts`: the key's wrapper, which prints as `[secret]` whichever way it is turned into text; `forms()` lists the ways it could be written, for the logger to scrub.
- `services/funder/src/chain.ts`: the only module that imports starknet.js and the only one that can send. It checks the chain id, then signs bound to that id, applies the fee cap, sends the deployment and the transfer together, and reads status.
- `services/funder/src/ledger.ts`: remembers the grant for each key and each day's spending, in memory or in a state file.
- `services/funder/src/service.ts`: the guards, independent of HTTP and chain.
- `services/funder/src/http.ts`: the endpoint, how a request's client is identified, CORS, and the scrubbing logger.
- `services/funder/src/main.ts`: the entry point (`node src/main.ts`); it deletes the key from `process.env` once read.
- `services/funder/src/{config,chain,service,http}.test.ts`: offline unit tests.
- `services/funder/src/funder.node.test.ts`: the integration test on the local node.
- `client/app/src/account/funder.ts`: `createServiceFunder` and `createFunder`.
- `client/app/src/account/funder.test.ts`: its offline tests.
- `client/app/src/account/index.ts`: exports the new functions and their configuration types.

## Commands run
```
$ pnpm -r test
client/sim test:  Test Files  2 passed (2)        Tests  8 passed (8)
services/funder test:  Test Files  4 passed | 1 skipped (5)    Tests  73 passed | 1 skipped (74)
client/app test:  Test Files  6 passed | 1 skipped (7)         Tests  58 passed | 1 skipped (59)
$ pnpm -r lint        -> client/sim, client/app, services/funder: Done (the service's lint includes prettier --check)
$ pnpm -r typecheck   -> client/sim, services/funder, client/app: Done
$ pnpm exec prettier --check client  -> All matched files use Prettier code style!
$ scripts/with-node.sh pnpm --filter @grimworld/funder test:node
 Test Files  1 passed (1)      Tests  1 passed (1)     Duration  3.97s
$ scripts/with-node.sh pnpm --filter @grimworld/app test:node     (FND-05's, unchanged, still passes)
 Test Files  1 passed (1)      Tests  1 passed (1)     Duration  3.88s
$ gh pr checks 141 --watch   -> every check pass
```
The skipped test in each package is its local-node test, which runs only under `scripts/with-node.sh`.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | No Cairo in this task |

## Threat model
*As first submitted. Where the audits found it wrong (the moment the caps are taken, the nonce, the rates across a restart, the default state), the sections "Fix loop 1" and then "Fix loop 2" below supersede it.*

**What is at stake.** The funding account's test STRK on Sepolia. It is not money (D-137 §1), but it is the owner's balance and it must last. Mainnet is never touched.

**The attacker.** Anyone who can reach the endpoint. They can make as many keys as they like, and each key's burner is theirs, so they can move its STRK anywhere (D-137's condition for reversal). They can script requests and use many IP addresses.

| Guard | Number | Why | Test |
|---|---|---|---|
| Network check before every send: chain id asked of the RPC at each funding (not cached); `SN_MAIN` refused; any id not in `FUNDER_NETWORKS` refused; the signer built only afterwards and bound to the checked id, so the signed execution is invalid on any other chain | — | OPERATIONS §7, COMMON §4 | `chain.test.ts` (spies on `Signer` and `Account`; mainnet; unconfigured; no answer; a node that turns into mainnet between two fundings; the signer's id is the one checked); `config.test.ts` (mainnet refused in configuration, by name and hex); node test step 5 (403, nonce unchanged, account not deployed) |
| One funding per key: a key with a grant gets the recorded answer and nothing is sent; concurrent requests for a key share one funding; an existing account is never funded; deployment and transfer are one execution, so a second funding of a deployed key reverts on the chain whatever the ledger says | 1 per key | ADR-0005 stage A | `service.test.ts` "a key is funded once" (7 tests); node test step 2 (200 `repeated`, funding account's nonce unchanged) |
| Client rate: new burners per client per hour, where a client is an IPv4 address or an IPv6 /64 (`X-Forwarded-For` only with `FUNDER_TRUST_PROXY=1`, and then its last hop). Repeats of funded keys are not counted | **3 per hour** | A player needs one burner per device; 3 covers a reinstall and a second device, and slows a script on one address to 7.5 STRK an hour | `service.test.ts` "the client rate" (sequential and concurrent); `http.test.ts` (client identification) |
| Daily budget: new burners per UTC day, all clients together; reserved synchronously before any await, so concurrent requests cannot overshoot; persisted with `FUNDER_STATE_FILE`, so a restart does not reset it | **50 per day** | A few dozen playtesters before M2. It is the cap that bounds a many-address attacker | `service.test.ts` "the day's budget" (sequential, concurrent 10→2, next day, restart with state file); node test steps 3 and 4 (third key 503, not deployed, still 503 after a restart) |
| Amount per burner | **2 STRK** (`FUNDER_AMOUNT`) | About 50 of the burner's own executions at SPK-1b's 0.0373 STRK per `leave`: several expeditions batched by 10 (D-137 §3) | Configuration: `config.test.ts` |
| Fee cap per funding: the estimate's resource bounds (with the library's margin) define the most the execution can be charged; above the cap nothing is sent. Tip fixed at 0 | **0.5 STRK** (`FUNDER_MAX_FEE`) | SPK-1b measured 0.0627 STRK for this multicall; 8× room for price spikes, and it stops a gas-price surge from multiplying the drain | `chain.test.ts` (FeeRefused, `execute` never called); `service.test.ts` (caps given back) |
| Caps given back only when nothing was signed for sending (network or fee refused, account already exists, chain unreadable); a failure after sending leaves them spent | — | Errs on the side of spending less | `service.test.ts` "a refusal before signing gives the caps back…" (4 tests) |
| Request validation: a public key on the curve (not zero, below 2^251, with a point); the address, if given, is the key's; body ≤ 1 KB | — | A value that is no one's key would burn the budget on an account nobody can use | `service.test.ts`, `chain.test.ts`, `http.test.ts` |

**Worst drain.** Whatever the attacker does, one day costs at most `dailyBudget × (amount + maxFee)` = 50 × (2 + 0.5) = **125 test STRK**. At the measured fee it is 50 × 2.0627 ≈ 103 STRK. One address alone gets at most 3 × 2.5 = 7.5 STRK per hour. Emptying the day's budget takes 17 addresses (or /64s) within an hour, or fewer over the day. With the state file off, a restart would reset the day's count: with `FUNDER_STATE_FILE` set, it does not. Repeats and refusals send nothing and cost nothing. What bounds it is the daily budget; the client rate only makes a single-address script slower.

**Proof of key (a signature over a challenge): not required.** It would only stop a third party from asking funding for **someone else's** public key. That gains the attacker nothing: the funds go to an account only the key's holder controls, and the key's owner gets one funding either way. It does **not** limit a drain, because an attacker generates fresh keys and proves each one at no cost. The caps are what bound the drain. A proof would cost a round-trip and a nonce store for no reduction in the worst case. If the service ever funds something other than the holder's own account, this should be reconsidered.

**What remains possible.** Draining the daily budget with many addresses (bounded above). An account deployed by someone else is never funded, so a player whose key's account already exists gets `200 repeated` with no funds (only possible if they deployed it themselves). The rate counters live in memory and reset on restart; the budget does not reset if the state file is on.

## How the key is kept out of every output
- It is read from `FUNDER_PRIVATE_KEY` **by name**, wrapped in a `Secret` at once, and **deleted from `process.env`** once read. It is not `STARKNET_PRIVATE_KEY`: the owner's account is never read by the service.
- `Secret` prints as `[secret]` through templates, `String`, `JSON.stringify` and `util.inspect` (including `showHidden`). Only `chain.ts` calls `reveal()`, to build its signer.
- Configuration errors name the variable and never its value (`config.test.ts`: "names the variable of a bad key, never its value").
- Log events carry public values only: addresses, execution ids, and error *names*, never messages from the library. As a second lock, the logger removes every form of the key (with and without prefix, 64-digit padded, decimal, upper and lower case) from each line (`http.test.ts` "the log").
- Responses are built field by field from public values. The state file holds public keys, addresses and counts only.
- **AC-2 on the real node:** `funder.node.test.ts` starts the service as a child process with an environment written in full (only `PATH` inherited, so no `STARKNET_*`). It collects all of its stdout and stderr, every response body, and the state file, then asserts that none of the key's forms appears, case-insensitively. It also asserts that a `funded` event was logged, so the check is not vacuous.
- The client never holds a funding key: `createServiceFunder` sends `{ publicKey, address }` and nothing else (`funder.test.ts`).

## Acceptance criteria
- [x] **AC-1**: `scripts/with-node.sh pnpm --filter @grimworld/funder test:node`. The service is started with one of the node's published keys. FND-05's `createBurnerProvider` with `createFunder({ kind: "service" })` creates a burner, which is deployed and executes an `approve` that succeeds. A second funding of the same key returns 200 `repeated` with the funding account's nonce unchanged. A second new burner uses up the budget of 2; a third is refused with 503 `exhausted`, not deployed, and the nonce is unchanged; this survives a restart. Idempotence of retries (pending, concurrent, reverted) is covered in `service.test.ts`.
- [x] **AC-2**: the same test greps output, responses and state file for the key; `config.test.ts` and `http.test.ts` as above.
- [x] **AC-3**: `chain.test.ts` with spies on `Signer.prototype.sign*`, `Account.prototype.execute` and `estimateInvokeFee`, as in FND-05. Mainnet and unconfigured networks are refused before any of them is reached. `config.test.ts` refuses mainnet in configuration. Node test step 5 shows an unconfigured network gets 403 and nothing is sent.
- [x] **AC-4**: the threat model above, with its numbers and the worst drain; each guard is listed with its test.
- [x] **AC-5**: the client only ever shows `AccountError`'s neutral messages (`funder.test.ts` checks every failure's message against a list of chain words). `vendor.test.ts` passes: `funder.ts` does not import starknet.js and no export reaches a vendor type. CI is green; `pnpm -r test`, lint and typecheck pass.

## Deviations from the brief
- **"A second funding of the same key refused"** is implemented as an **idempotent answer with nothing sent**: 200 `{ repeated: true }` with the recorded address. It is not an error status, because the brief also asks for idempotent retries, and the client's burner treats that answer as success. No second funding ever happens: the ledger answers first, and the chain would revert a second deployment together with its transfer.
- **COMMON §4, "sending … ends with the task"**: the service's sending module (`services/funder/src/chain.ts`) **is not removed or turned into a refusal**, because sending is what the service is for. It follows the rest of the rule: sending lives in that one module; nothing it exports can send (no account, signer or provider); it refuses unless the RPC's chain id is configured, and always refuses mainnet. This task sent nothing to Sepolia.
- The integration test lives in `services/funder/` and imports the client's account module by relative path, so the service's tsconfig adds the `DOM` library (the burner's `localStorage` default). Putting the test in `client/app` instead would have needed Node types in the app's tsconfig, which is outside the allowlist.
- The root `format` script and CI's `prettier --check client` cover `client/` only. The service checks its own formatting inside its `lint` script, so CI gates it without a change to `.github/`.

## Escalations
- **The caps' numbers are my choice, for the project manager to confirm**: 2 STRK per burner, a 0.5 STRK fee cap, 50 burners per day, 3 per client per hour, which gives a worst drain of 125 test STRK per day. All are environment variables.
- **Hosting (OPS-01)** must set `FUNDER_STATE_FILE`; otherwise a restart resets the day's budget. It must also set `FUNDER_TRUST_PROXY=1` only behind a proxy of our own, and `FUNDER_ORIGIN` to the game's web origin (the default is `*`). The service listens on `127.0.0.1` by default. Using it on Sepolia needs OPERATIONS §7's grant for a funding account. That account must be **a dedicated one** holding only what the budget needs, not the owner's `STARKNET_*` account.
- **D-137's reversal condition** ("a playtest opened to strangers, where a funded burner can be emptied by its holder") is exactly the drain bounded above. A public playtest should revisit the budget, or move to a paymaster (version 1).

## Open questions
- **Top-ups**: a burner that runs out after about 50 executions has no way to be refilled. The service funds each key once, and D-137 does not say how often the game funds. That needs a design decision.
- **A local node that restarts while the service keeps its state file**: the ledger would say `succeeded` for an account the reset node no longer has. On the local node the game uses `createNodeFunder`, which re-checks the chain, so this only matters if someone points the service at a node that gets reset.

## Fix loop 1
This fixes findings F-1 to F-4 of the `[GPT-6-Astra]` audit of PR 141 at `1f915f6` (`logs/AUD-141-audit1.md`, FAIL: three majors and a minor). The audit found no key disclosure and no mainnet bypass.
- A merge of `origin/main` (`e28b5ab`): it brought only documents, briefs and contracts, and nothing in this task's files.
- The fix commit: `b6b7feb fix(services): fix loop 1 of FND-08's audit, findings 1 to 4`. CI for it completed with every check green (run 36567338848: client, tooling, discover, all cairo jobs).

### F-1 (major): the funding account's nonce is now serialised, not just the submission
- **The fix.** A funding now holds the funding account from its signature until that nonce is used up on chain, or is known never to be. That covers pending executions, lost answers and restarts. The nonce is managed explicitly. Inside the one-at-a-time queue, the service first waits for the previous hold to end (`released()` in `service.ts`). It then reads the account's nonce at `latest`, records the hold (`{ nonce, transaction?, at }`) in the ledger **before signing**, and passes that nonce to both the fee estimate and the execution (`chain.fund(publicKey, address, nonce)`).
- **When a hold ends.**
  - When the account's nonce at `latest` is above the held one. This is the normal case, and it also covers a reverted execution, which still uses up its nonce.
  - When nothing shows for `holdMs` (5 minutes): the node does not know the execution, or the send failed without an answer. If a lost execution lands after that anyway, it and the next funding share one nonce, so only one of them can execute.
  - **Never**, while the node still reports the execution as pending.
- **A request that would wait longer than 60 s** for the hold answers `unavailable`, having taken nothing and sent nothing.
- **The hold is kept in the state file**, so a restarted service waits for the nonce of the funding it had in flight.
- **Tests** (`service.test.ts`, "the funding account's nonce", 8 tests), against a fake node that refuses a nonce that is not the next or that is already used:
  - four fundings at once sign with nonces 0, 1, 2 and 3;
  - the audit's race: two burners while the first is pending give nonces `[0]` and then `unavailable`, never `[0, 0]`;
  - after the first is included, the next signs with nonce 1;
  - a lost answer whose execution later shows up keeps the nonce held, and the next funding signs after it;
  - a lost answer whose execution never reached the node frees the nonce after `holdMs`, not before;
  - an execution the node dropped frees its nonce after `holdMs`;
  - a pending execution holds its nonce even after 10 hours;
  - a held nonce survives a restart with the state file.
- **On the real node** (`funder.node.test.ts`, step 1): two players are created **at the same time**. Both accounts are deployed, and the funding account's nonce rises by exactly 2.
- `chain.ts`: a failure before the execution reaches the node is now a `NotSent`. Network and fee refusals are subclasses of it. A failure of the execution itself is not a `NotSent`, because it may have been sent. Tested in `chain.test.ts`, which also checks that the held nonce is what the estimate and the execution receive.

### F-2 (major): the stated maximum drain is now enforced
- **The fix.** The client rate and the day's budget are checked and taken **at the moment of signing**, inside the queue, after the nonce's hold and on the clock at signing. They are given back only when nothing was sent: a `NotSent` (network refused, fee above the cap, preparation failed) or an unreadable nonce. A failure after the execution may have reached the node leaves them spent. Before a request queues, the same check runs again but takes nothing, so a request that is bound to be refused does not wait.
- **The exact worst drain, restated.**
  - **At most `dailyBudget` fundings are signed per UTC day**, counted by the clock at signing, in one process per state file and funding account. Each funding moves at most `amount + maxFee`. So **the fundings signed in one UTC day move at most 50 × (2 + 0.5) = 125 test STRK**; at SPK-1b's measured fee, 50 × 2.0627 ≈ 103 STRK.
  - Counted by the day the executions are **included** instead, at most one funding signed on the previous day can still be outstanding, because the nonce hold allows only one at a time. The bound is then 51 × 2.5 = **127.5 test STRK**.
  - A single client is capped at 3 × 2.5 = 7.5 STRK in any rolling hour.
  - The audit's case of 250 STRK in one day is no longer possible.
- **Tests** (`service.test.ts`, "the day's budget"):
  - **The audit's midnight case.** With a budget of 2, two requests are admitted before midnight but their deployment checks end after it, and two fresh requests arrive on the new day. Result: exactly 2 are sent and 2 answer `exhausted`; the old day records 0 and the new day 2.
  - **At the boundary, concurrently.** With a budget of 3 and 1 already spent, 10 requests at once give 2 `provided` and 8 `exhausted`, with 3 sent in total.
  - **The worst drain.** Over 24 hours, 40 fresh clients with fresh keys per hour (960 requests) sign exactly 50 fundings on each UTC day, 100 in total.
  - Refusals give everything back: spent, the client's rate times, the hold.
- **On the real node:** the third key is refused with 503 and the funding account's nonce is unchanged, both before and after a restart.

### F-3 (major): the hourly client limit now survives a restart, and the default fails closed
- **The fix.** The rolling window of each client's signing times is now kept **in the ledger** (`times`, `addTime`, `removeTime`), and entries older than the window are pruned at each lookup. With a state file, both the rate and the budget survive a restart.
- **Fails closed.** `FUNDER_STATE_FILE` is now **required**. Without it the service refuses to start, with the message `FUNDER_STATE_FILE is not set (FUNDER_EPHEMERAL=1 for development only)`. `FUNDER_EPHEMERAL=1` is the explicit development mode, in which a restart forgets everything. Setting both is refused.
- **Tests:**
  - the audit's case (`service.test.ts`): with a rate of 1, the second request is `limited`; after a restart half an hour later with the same state file and a fresh key from the same client, it is still `limited`, and it is `provided` once the hour has passed;
  - `config.test.ts` checks the fail-closed configuration;
  - the integration test's step 5 now starts its throwaway service with `FUNDER_EPHEMERAL=1`.
- **Two things for hosting.** The state file now holds client IP addresses (IPv4, or IPv6 /64) for one hour. And nothing coordinates two processes sharing one file or one funding account: run one service per state file and per funding account (this is in the README).

### F-4 (minor): the key scan now covers every answer
- The integration test gives `createFunder({ kind: "service" })` a **recording fetch**. It clones each response the client's funder receives and adds the body to the scan.
- The test asserts that every recorded answer is in the scanned text. It also asserts that the two first fundings' answers (`"repeated":false`) were recorded.
- The scan still covers the service's stdout and stderr and the state file. It finds none of the key's forms.

### Commands run
```
$ git merge origin/main                   -> e28b5ab, no file of this task touched
$ pnpm -r test
client/sim test:       Tests  8 passed (8)
services/funder test:  Tests  87 passed | 1 skipped (88)
client/app test:       Tests  58 passed | 1 skipped (59)
$ pnpm -r lint         -> Done ×3 (the service's includes prettier --check)
$ pnpm -r typecheck    -> Done ×3
$ pnpm exec prettier --check client  -> All matched files use Prettier code style!
$ scripts/with-node.sh pnpm --filter @grimworld/funder test:node  -> Tests  1 passed (1)
$ scripts/with-node.sh pnpm --filter @grimworld/app test:node     -> Tests  1 passed (1)
$ gh pr checks 141 --watch   -> every check pass
```
The skipped test in each package is its local-node test, which runs only under `scripts/with-node.sh`.

### Files changed in this loop
- `services/funder/src/service.ts`: the nonce hold, and the caps taken at signing.
- `services/funder/src/chain.ts`: the explicit nonce, `nonce()`, and `NotSent`.
- `services/funder/src/ledger.ts`: client times and the hold, persisted.
- `services/funder/src/config.ts`: fails closed, with `FUNDER_EPHEMERAL`.
- `services/funder/src/main.ts`: `holdMs`.
- `services/funder/src/service.test.ts`, `chain.test.ts`, `config.test.ts`, `funder.node.test.ts`: the tests above.
- `services/funder/README.md`: the configuration table.

### Remaining, unchanged
The audit also noted, without making a finding of it, that `FUNDER_TRUST_PROXY=1` trusts the last `X-Forwarded-For` hop without checking the socket peer. Hosting must put the service behind a proxy of our own that sets that header, and nothing else may reach the service directly. This was already in the escalations.

## Fix loop 2
This fixes F-1 and F-2 of the `[GPT-6-Astra]` re-audit of PR 141 at `b6b7feb` (`logs/AUD-141-audit2.md`, FAIL: F-1 and F-2 still open on two boundary cases; F-3 and F-4 closed).
- A merge of `origin/main` (`2861683`). One conflict, in `pnpm-workspace.yaml`: main added `indexer`, and both entries are kept. For `pnpm-lock.yaml` I took main's version and ran `pnpm install`; the lock then differs from main by the `services/funder` importer only, and `--frozen-lockfile` passes.
- The fix commit: `29fb237 fix(services): fix loop 2 of FND-08's audit, F-1 and F-2 at their boundaries`. CI for it completed with every check green (run 36570398528: client, tooling, discover, all cairo jobs; `indexer-node`, a job main added, skipped by its own condition).

### The tests that fail at b6b7feb and pass now
`services/funder/src/boundary.test.ts` (new) uses a fake node that records **every execution handed to it**: its nonce, its id, the moment it is handed and whose it is. The invariants are checked on that record, not on the service's own counts:
- (a) no nonce is ever handed with two different executions;
- (b) no UTC day has more new executions handed than the budget;
- (c) no client has more new executions handed than its rate within any hour.

It holds three F-1 cases, three F-2 cases and a seeded search over both families.

**The failing run, against the service at b6b7feb.** I ran it after writing the tests and before changing any code. For that run the fake also had the b6b7feb interface (a `fund` that prepares and hands in one call) and the fix-loop-1 `holdMs` of 5 minutes. Both were removed once the fix was in.
```
$ pnpm --filter @grimworld/funder exec vitest run src/boundary.test.ts        (service at b6b7feb)
 FAIL  F-1 … the audit's case: an answer lost, the execution still pending past five minutes
AssertionError: expected [ '0: 0x71, 0x72' ] to deeply equal []
 FAIL  F-1 … the audit's case across a restart with the same ledger
AssertionError: expected [ '0: 0x71, 0x72' ] to deeply equal []
 FAIL  F-1 … an execution the node answers `unknown` for past five minutes is sent again, never replaced
AssertionError: expected [ '0: 0x71, 0x72' ] to deeply equal []
 FAIL  F-2 … the audit's case: a nonce answer that ends after midnight
AssertionError: expected 3 to be less than or equal to 2
 FAIL  F-2 … the audit's case: a rate of one, a slow nonce, a second funding an hour after the first was taken
AssertionError: expected 3598001 to be greater than or equal to 3600000
 FAIL  F-2 … a slow preparation across midnight, with requests of the new day waiting
AssertionError: expected 3 to be less than or equal to 2
 FAIL  a seeded search of the same families > seed 2 … seed 40   (26 of 40 seeds)
AssertionError: expected [ '2: 0x73, 0x74', … ] to deeply equal []        (and "expected 4 to be ≤ 3")
      Tests  32 failed | 14 passed (46)
```
These are the audit's own figures: nonce 0 handed with two executions (`[0, 0]`), three sends on the new day with a budget of 2, and two sends 3,598,001 ms apart with a rate of one.

**After the fix:**
```
$ pnpm --filter @grimworld/funder exec vitest run src/boundary.test.ts        (200 seeds, as in CI)
      Tests  206 passed (206)
$ (the same with the seed count at 5000, run once)
      Tests  5006 passed (5006)     Duration  4.00s
```

### F-1: a nonce carries one execution, ever
**The fix.**
- `chain.ts` now **signs without sending**. `prepare` checks the network and the fee cap, then signs with `Account.getSignedTransaction` at the nonce the service holds. It computes the execution's id and returns it with the signed form (`Signed { transaction, payload }`). Nothing reaches the node there, and every failure is a `NotSent`.
- `submit(payload)` makes the `starknet_addInvokeTransaction` request **during the call itself**. It accepts the node's answer only if the node's id equals the one computed. The node's duplicate answer (code 59) means that id.
- `verify(payload)` re-checks the node's chain id before any handing again.
- In `service.ts`, the ledger keeps the **hold before the execution is handed**: `{ nonce, transaction, payload, client, at }`.
- A hold ends **only when the funding account's nonce on chain moves past it** (`released()`). The time-out of fix loop 1 is gone, and an `unknown` status proves nothing either. While the node does not know the kept execution, the service hands **the same signed execution** again (`handAgain`).
- A request that would wait more than 60 s answers `unavailable`, having taken nothing and sent nothing.
- A lost answer now leaves the key's grant as `pending` with that execution's id, so the key's next request asks about that execution first.
- `ledger.ts` takes `<state file>.lock` (the process id, created exclusively). A second service on the same file refuses to start. A lock left by a process that has stopped is taken over.

**Tests.**
- `boundary.test.ts`, the audit's case: an answer lost, the execution pending beyond 300,001 ms; then the same across a restart with the retained ledger; then an execution the node answers `unknown` for beyond five minutes. Each gives no reused nonce, and the dropped one is handed again as `0x71`, never replaced.
- `service.test.ts`, three rewritten: the handing that never reached the node, the dropped execution, and a handing again refused by full caps.
- `service.test.ts` also tests the lock (refused while open, given after close, a stale lock taken over).
- `chain.test.ts` tests the split: nothing handed in `prepare`, the request made before `submit` returns, the id mismatch, the duplicate answer, and `verify` refusing a changed network. A signature for another nonce than the held one is never kept.
- On the real node (`funder.node.test.ts`), each funding is accepted only if the node's id equals the one computed before sending, and the test passes with them equal. A second service on the same state file exits with `the state file is open in another process`.

**Why no other path of this family remains.** Two executions can share a nonce only if the service signs a second one while the first's nonce is unconsumed and the first could still execute. The service signs in exactly one place, `send()`, which runs in the one-at-a-time queue, after `released()`, with the nonce read after it. Each way a second signing could come about:
- **A lost answer, a dropped execution, an `unknown` status, a timeout, a stop before the answer.** The hold was written before the handing, with the signed execution. Only `nonce on chain > held nonce` removes it, and that is proof the nonce is consumed: by this execution or, if an operator sent one, by another. Nothing else in the code removes a hold.
- **A crash after signing but before the hold is written.** Nothing was handed: `submit` is only called after `setHold`, synchronously. So a signature that was never kept was never sent.
- **Handing again.** It sends the kept bytes, whose id is fixed, so the same nonce still carries only that one execution.
- **Concurrent requests.** One queue per process, and one process per state file, enforced by the lock.

What is **not** enforced by code: two services on one funding account with **two different state files**. That is stated in the README and in the escalations as a hosting rule.

The price is a stall. If a kept execution can never be included (the node refuses it for good), fundings stop and answer `unavailable` until its nonce is consumed. An operator can do that by sending any transaction from the funding account; the service then continues by itself (README). This fails closed, and it cannot spend.

### F-2: the caps count the moment of handing
**The fix.**
- `send()` now does every awaited step **before** the caps: the hold's release, the deployment check, the nonce, the preparation (chain id, fee, signature).
- Then, **with no await in between**, it reads the clock, checks both caps, takes them, writes the hold and calls `submit`, which makes the request during the call. So the UTC day and the rolling hour that count an execution are those of the moment it is handed to the node, to within the synchronous code between those lines.
- If the caps are full at that moment, the signed execution is dropped, never handed. Its nonce was never held.
- **The seeded search found one more path of this family,** beyond the audit's two. An execution whose first handing never reached the node (connection refused) is counted at that attempt. It could then arrive on a later day or hour through a handing again, uncounted there. Now **every handing again is counted like a first handing**, at its own moment, under the same no-await rule (`handAgain`: `verify` first, then the caps, then `submit`). It waits while the caps are full. When the first handing did arrive, it is counted twice, which only ever over-counts.
- Once taken, the caps are never given back: from the handing on, the execution may be on the chain. A refusal before the handing takes nothing.

**Tests.**
- `boundary.test.ts`: the audit's midnight case (the nonce's answer ends after midnight: at most 2 handed on the new day, and the ledger's count equals the node's); the audit's rolling hour (a rate of one and a 2 s slow nonce: the second funding is `limited` until an hour after the first **was handed**, then allowed); and a slow preparation across midnight with five requests waiting.
- `service.test.ts`: a handing again waits while the client's hour is full.

**Why no other path of this family remains.** An execution reaches the node only through `submit`. `submit` is called in two places, `send()` and `handAgain()`. In both, the caps are checked and taken immediately before it, with no await between the clock read and the call, inside the one queue. So every execution handed to the node is counted on the UTC day and in the hour of its handing, and the checks run in the order of handing.

**The bounds, restated precisely.**
- **At most `dailyBudget` executions handed to the node per UTC day** (counted by first handings; repeats of the same execution are over-counted). Each moves at most `amount + maxFee`, so **at most 50 × (2 + 0.5) = 125 test STRK per UTC day by moment of handing**.
- **At most `clientRate` new executions handed per client in any rolling hour**, so 3 × 2.5 = 7.5 STRK.
- Counted by the day an execution is **included**, the one-execution-per-nonce rule allows at most one execution handed on the previous day to land on the next: **51 × 2.5 = 127.5 test STRK**.

The seeded search checks (b) and (c) on what the node receives, over 5000 runs.

### Commands run
```
$ git merge origin/main   -> conflict in pnpm-workspace.yaml (kept both), lock re-derived; 2861683
$ pnpm -r test
client/sim test:       Tests  8 passed (8)
services/funder test:  Tests  301 passed | 1 skipped (302)
client/app test:       Tests  141 passed | 1 skipped (142)
indexer test:          Tests  66 passed (66)
$ pnpm -r lint        -> Done ×4 (the service's includes prettier --check)
$ pnpm -r typecheck   -> Done ×4
$ pnpm exec prettier --check client  -> All matched files use Prettier code style!
$ scripts/with-node.sh pnpm --filter @grimworld/funder test:node  -> Tests  1 passed (1)
$ scripts/with-node.sh pnpm --filter @grimworld/app test:node     -> Tests  1 passed (1)
$ gh pr checks 141 --watch   -> every check pass (indexer-node skipping: main's job, by its own condition)
```
The skipped test in each package is its local-node test, which runs only under `scripts/with-node.sh`.

### Files changed in this loop
- `services/funder/src/chain.ts`: `prepare` (sign only), `submit` (hand, with the id checked), `verify`; `fund` removed.
- `services/funder/src/service.ts`: the hold with the signed execution; release only on a consumed nonce; handing again, counted; the caps taken with no await before the handing.
- `services/funder/src/ledger.ts`: the hold's execution and client; `<state file>.lock` and `close()`.
- `services/funder/src/main.ts`: the lock refusal at start, closed on exit; `holdMs` removed.
- `services/funder/src/boundary.test.ts` (new), `service.test.ts`, `chain.test.ts`, `funder.node.test.ts`: the tests above.
- `services/funder/README.md`: one execution per nonce, the lock, and what the operator does if a kept execution can never be included.

### Escalations added
- **Two services on one funding account with two state files** could still hand two executions one nonce. The code cannot see this; hosting must never do it (README).
- **A kept execution the node refuses for good stops fundings** until an operator consumes its nonce with any transaction from the funding account. This fails closed, and hosting should be told how to clear it.

## Fix loop 3
This fixes F-5, the new major of the `[GPT-6-Astra]` audit of PR 141 at `29fb237` (`logs/AUD-141-audit3.md`): two services recovering a stale state-file lock at the same time could both be admitted. That audit closes F-1 to F-4.
- A merge of `origin/main` (`77a2a84`): no conflict, and nothing in this task's files.
- The fix commit: `6270f3e fix(services): fix loop 3 of FND-08's audit, F-5: one service per state file, whatever the timing`. CI for it completed with every check green (run 36574058568: client, tooling, discover, all cairo jobs; `indexer-node`, main's job, skipped by its own condition).

### The choice: no automatic recovery of a stale lock
The lock `<state file>.lock` is now **only ever created exclusively** (`writeFileSync(…, { flag: "wx" })`, which is `O_CREAT | O_EXCL`). An existing lock is **never taken over**, even when the process named in it has stopped: the service refuses to start and leaves the lock for the operator.

Why this one, of the three the brief offers:
- **It is provably exclusive.** Acquisition is one system call, and on a local file system the kernel lets exactly one creator of a name succeed, whatever the timing. There is no window, so no interleaving of starts can admit two services.
- **Any automatic takeover reintroduces F-5.** A takeover has to find out that the holder is gone, then remove the lock, then create it. Those are three steps, and another starter can run its own three between them. That is exactly the audit's interleaving.
- **Why not an OS-level lock.** `flock`/`fcntl` would release by itself when a process dies, but Node's standard library has none; it would need a native module (a new dependency, outside the brief's allowlist) or a helper process.
- **The price** is an operator's step after a service is **killed** (`SIGKILL`, the OOM killer, a power loss). Every exit Node runs handlers for removes the lock: `process.on("exit")` now calls `ledger.close()`, in addition to the `SIGTERM`/`SIGINT` handlers. A supervisor that restarts a killed service gets a refusal until the operator acts. This fails closed.
- **A close removes only its own lock.** It holds a random mark (pid and a UUID), so if an operator removed a live lock by mistake and another service took the file, the first one's close does not remove the second one's lock.

### The test: fails on 29fb237, passes now
`services/funder/src/lock.test.ts` (new) has three tests:
1. **Two recoveries against a stale lock, forced at the audit's moment.** `node:fs` is mocked so that starter B runs its whole start at the instant starter A is about to remove the lock it found stale, which is A's window between check and act. Every service admitted then funds a key of its own on **one shared fake node**, with a day's budget of **one**.
2. **The same two starts must admit none; the lock stays.** After the operator's step (removing the lock), the same two starts admit **exactly one**.
3. **Eight real processes started at the same time.** With no lock present, exactly 1 is admitted and 7 refused, and the admitted one removes its lock on close. Against a stale lock, 0 are admitted.

**The failing run against `ledger.ts` at `29fb237`**, taken before the fix, with the test file as committed except that the first test's two checks were in the other order:
```
$ pnpm --filter @grimworld/funder exec vitest run src/lock.test.ts      (ledger at 29fb237)
 × admit at most one service, and so at most the day's budget
AssertionError: expected [ '0x71@0', '0x72@1' ] to have a length of 1 but got 2
 × admit none: a lock is never taken over, the operator removes it
AssertionError: expected false to be true
 × one is admitted when no lock is there; none when a stopped service left one
AssertionError: expected [ 'admitted' ] to have a length of +0 but got 1
      Tests  3 failed (3)
```
- The first failure is the audit's: both starters were admitted (an earlier run of the same test reported `expected 2 to be less than or equal to 1` on the admission count), and the node received **two fundings against a budget of one**.
- In the process race, the first half (no lock: 1 of 8 admitted) passed at `29fb237` too. The second half failed: against a stale lock one process took it over.

**After the fix:**
```
$ pnpm --filter @grimworld/funder exec vitest run src/lock.test.ts
      Tests  3 passed (3)
```
`service.test.ts` has one test changed to match (a stale lock is refused and kept) and one added (a close removes only the lock this ledger took). In the integration test on the node, a second service on the same file now exits with `the state file is locked by another service, …`.

### Why exclusivity now holds whatever the timing
A service owns the ledger only by returning from `fileLedger`, and that happens only after its own exclusive creation of `<state file>.lock` succeeds. The code has exactly one other operation on the lock: the owner's close, which removes the lock only if it holds that owner's own mark. So at any moment at most one living process has created the lock that exists.

The lock can disappear only through its owner's close, or through the operator's step. So a second service can be admitted only when the owner has closed (and so no longer uses the ledger), or when the operator removes a live lock against the README. Timing plays no part: there is no check-then-act anywhere in acquisition.

### What the deployment must guarantee (OPS-01)
This is written in `services/funder/README.md`, section "One service per state file and per funding account". The code relies on it and cannot check it:
1. **One host.** The service, its state file and its lock are on one machine. No second host ever runs the service for the same funding account.
2. **The state file on a local disk**, not NFS, SMB or any storage shared between machines. The exclusive creation is atomic on a local file system only, and the pid in the lock means something on that host only.
3. **One state file per funding account, and one funding account per state file.** Two services with two files on one account would each use the account's nonce.
4. **No automatic removal of the lock** by a supervisor, a start script or a clean-up job.
5. **The operator's step after a kill:** make sure no funder service runs on the host (`ps -p <pid from the lock>` shows nothing, and no other funder process runs), then remove `<state file>.lock` and start the service.

The budget and nonce guarantees of fix loops 1 and 2 (125 test STRK per UTC day of handing, 127.5 per day of inclusion, 7.5 per client-hour, one execution per nonce) hold for that single owner. They therefore hold deployment-wide under guarantees 1 to 4.

### Commands run
```
$ git merge origin/main   -> 77a2a84, no conflict
$ pnpm -r test
client/sim test:       Tests  8 passed (8)
client/app test:       Tests  141 passed | 1 skipped (142)
services/funder test:  Tests  305 passed | 1 skipped (306)
indexer test:          Tests  66 passed (66)
$ pnpm -r lint        -> Done ×4 (the service's includes prettier --check)
$ pnpm -r typecheck   -> Done ×4
$ pnpm exec prettier --check client  -> All matched files use Prettier code style!
$ scripts/with-node.sh pnpm --filter @grimworld/funder test:node  -> Tests  1 passed (1)
$ scripts/with-node.sh pnpm --filter @grimworld/app test:node     -> Tests  1 passed (1)
$ gh pr checks 141 --watch   -> every check pass (indexer-node skipping: main's job, by its own condition)
```
The skipped test in each package is its local-node test, which runs only under `scripts/with-node.sh`.

### Files changed in this loop
- `services/funder/src/ledger.ts`: exclusive creation only, no takeover, a close that removes only its own mark, and an operator-facing refusal message.
- `services/funder/src/main.ts`: the lock is removed on every exit Node handles.
- `services/funder/src/lock.test.ts` (new), `service.test.ts`, `funder.node.test.ts`: the tests above.
- `services/funder/README.md`: the lock, the operator's step, and the deployment's guarantees.

### For the project manager
- **The operator's step after a kill is a new operational duty**, the price of provable exclusivity without a native dependency. If OPS-01 wants restarts after a kill with no operator, the way is a kernel lock (`flock`) through a native module or a supervising helper. That is a dependency decision outside this brief.
- Guarantees 1 to 4 above belong in OPS-01's brief.

# [GPT-6-Astra] Audit — PR 141 (FND-08) — security, quality

## Verdict

**PASS WITH FINDINGS** at `6270f3ec2ac4fe8ef0a20d5bf65fc7d533e2a6a2`.

F-1 through F-5 are closed. No open major or minor finding. One operational note remains for the project manager and OPS-01.

F-5’s automatic recovery race is removed: acquisition uses exclusive creation, and **every existing lock causes refusal**, including stale, empty and malformed locks. Concurrent starters cannot delete another starter’s lock. This guarantees one owner under the documented deployment constraints; manual removal requires coordinated recovery.

## Findings

Original severities are retained for closed findings.

| # | Severity | Location | Finding / final status | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| F-1 | major | `services/funder/src/service.ts:115`, `boundary.test.ts:172` | **Closed — nonce ownership survives pending executions, retries and restarts.** | Signed execution and nonce are persisted before submission. Unknown transactions are retransmitted unchanged; elapsed time does not release ownership. Release requires observing a consumed nonce. Boundary regressions pass; implementation unchanged since fix loop 2. | None. |
| F-2 | major | `services/funder/src/service.ts:143`, `service.ts:168`, `boundary.test.ts:222` | **Closed — budget and rate charged at submission.** | Both submission paths check and persist charges after asynchronous preparation/verification, without an intervening await before submission. Retransmission is charged too. Refusal before this point takes nothing; ambiguous sends retain charges. Midnight, delayed preparation and rolling-hour regressions pass. | None. |
| F-3 | major | `services/funder/src/ledger.ts:59`, `config.ts:143` | **Closed — persistent limits and fail-closed defaults retained.** | Client timestamps and daily spending remain in the ledger. Missing persistent storage is refused unless development explicitly selects `FUNDER_EPHEMERAL=1`. Configuration tests pass; persistence implementation unchanged. | None. |
| F-4 | minor | `services/funder/src/funder.node.test.ts:87`, `:131`, `:214` | **Closed — leak-test capture retained.** | Child stdout/stderr, direct HTTP response bodies, responses received through the client funder, and persisted state feed the secret-form scan. The initial client responses are explicitly included and asserted present. | None. |
| F-5 | major | `services/funder/src/ledger.ts:146`, `lock.test.ts:113` | **Closed — concurrent automatic stale-lock recovery eliminated.** | Independently reproduced the old interleaving: **two owners, two fundings, persisted spending one**, with budget one. Current code admits **zero** against the same stale lock and preserves it. After quiescent removal, exactly one owner is admitted. | None in service acquisition. Preserve the deployment prerequisites. |
| N-1 | note | `services/funder/README.md:60` | **Open — coordinate manual recovery in OPS-01.** | Two operators can both observe no running service; one removes the stale lock and starts a service, then the other removes its new lock using the earlier observation. A PID check alone does not serialize recovery. Automatic recovery is now safe because it refuses altogether. | OPS-01 should require one recovery operator/coordinator and prevent competing starts and removals during cleanup. Carry this operational requirement to the project manager. |

## Coverage

**F-5 verification.** Reviewed the exclusive-create acquisition, owner token, idempotent close, shutdown handling and all three new lock tests. The deterministic test exercises the original check/remove interleaving and checks its funding-budget consequence.

Using the actual old and current ledger implementations with an in-memory filesystem, independently obtained:

| Scenario | Owners admitted | Fundings submitted |
|---|---:|---:|
| `29fb237`, forced concurrent stale recovery | 2 | 2 despite budget 1 |
| `6270f3e`, identical interleaving | 0 | 0 |
| `6270f3e`, starts after quiescent cleanup | 1 | 1 |

Empty, malformed, live-owner and dead-owner lock contents all remained untouched and caused refusal.

**Deployment guarantees.** The README explicitly assigns OPS-01 one host, local storage, one state file per funding account and the inverse, and no automatic lock removal. These are necessary: this lock cannot coordinate different state paths or hosts using the same account. Stale locks deliberately trade availability for safety. N-1 records the coordination needed for manual cleanup.

**Earlier security coverage stands.** No changes undermine the previous conclusions concerning:

- Credentials read by name, secret handling/redaction, neutral errors and absence of the funding key from client interfaces and persisted transactions.
- Mainnet and unconfigured-network refusal before signing, including the frozen configuration snapshot.
- Per-key idempotence, pending executions, same-key concurrency and serialized account use.
- Fee bounds, curve validation, address derivation and body limits.
- HTTP methods, default `*` CORS, client identity, forwarding-header handling and default-disabled `FUNDER_TRUST_PROXY`.
- Client funder abstraction without exported vendor types.

The stated default bounds remain **125 test STRK per UTC submission day**, **127.5 per inclusion day** allowing one carried execution, and **7.5 per client rolling hour**, under the stated single-owner deployment assumptions. An IP-based client limit is not a per-person limit; the global budget supplies the aggregate bound.

**Validation performed:** 285 offline tests passed: 239 configuration/chain/boundary tests, 39 service tests and seven HTTP identity/logging tests. Dependencies came from the implementer checkout after verifying its relevant source matched the audited commit.

Disk-writing tests, the real-process lock race and local-node integration were inspected but not rerun under the read-only restriction. Their reported passing runs are implementer evidence, not independently observed runs. The before/after race reproduction above required no disk writes. No files were changed.
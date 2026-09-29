# FND-08 — The burner's funder on a public network

> D-150: the game's second slot while the engine chain waits. FND-05's escalation: its funder signs
> with the local node's published key only; on a public network the key must never ship in the
> client. Needed before any play on Sepolia, so before M2.

## Agent
Title: `[Opus 5.5] FND-08 funder service` · Profile: implement · Branch: `feat/fnd-08-funder-service`

## Goal
After this task the game has a **funding service**: a small server process that deploys and funds a
player's burner account on request, holding the funding key server-side, behind FND-05's `Funder`
port, so that the client's burner works on a public network without any key in the client. It is
**tested on the local node**; nothing is deployed to Sepolia by this task.

## Context
- **FND-05** (`client/app/src/account/`: the `AccountProvider`, the burner, the `Funder` port,
  `createNodeFunder` and its local-node boundary; report `docs/reports/FND-05-providers.md`, its
  escalation on the funder, and its audit `docs/reports/FND-05-audit-gpt-6-astra.md`: the frozen
  configuration snapshot, the refusal paths).
- **ADR-0005** (§2 stage A: a burner generated on the device, an account deployed by the game;
  §3 what a burner is not), **D-137** (the burner sends directly; no paymaster before version 1;
  the game funds it), design/11 (no blockchain word reaches the player), OPERATIONS §7 (Sepolia:
  credentials by name only, never printed or written; chain id checked before sending; **no
  mainnet**), **COMMON §4** (sending lives in one module and ends with the task; the shared machine).
- The machine's rules (COMMON): the service's key comes from an environment variable **by name**;
  it is never logged, printed, written to a file, a report or a test fixture. Tests use the local
  node's published keys only.

## Scope
- In:
  - **The service** (a new workspace package, for example `services/funder/`, TypeScript on Node,
    starknet.js as FND-05 uses it): one endpoint that takes a burner's public key (and what else the
    design needs), deploys its account (the class of D-137, as configuration) and funds it with a
    fixed amount, once per key; answers with the account's address and the transaction's status;
    idempotent on retries.
  - **Its guards, stated as a threat model**: the service moves test tokens on Sepolia only (a
    chain-id check before every send: **refuse `SN_MAIN`**, and refuse any network not in its
    configuration); per-key once; a global budget per day and a rate per client, with their numbers
    and why; what an attacker can drain at worst, and what bounds it. Whether a burner must prove it
    holds its key (a signature over a challenge) and what it would and would not prevent: say so.
  - **The client side**: a `Funder` implementation in `client/app/src/account/` that calls the
    service (no key, no vendor type exported, neutral errors as FND-05's), selected by
    configuration; `createNodeFunder` stays for the local node.
  - **Tests**: unit tests of the service's guards (offline, a fake chain), and one integration test
    through `scripts/with-node.sh`: the service on the local node with a published key, a burner
    created, funded, executing a call, a second funding of the same key refused, the day's budget
    reached and refused.
- Out: deploying or hosting the service (OPS-01 and the project manager's decision, with OPERATIONS
  §7's grant for anything on Sepolia); a paymaster (version 1); mainnet (never).
- Allowlist: the new package's directory, its line in `pnpm-workspace.yaml`, `client/app/src/account/**`,
  `package.json` files and the root `pnpm-lock.yaml` for the dependencies this needs, and a CI job or
  step for the new package if `pnpm -r test` does not already run it. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 The service deploys and funds a burner on the local node, once per key, idempotent; the
      client's burner works through it (the integration test).
- [ ] AC-2 The key is read by name from the environment and never reaches a log, a response, a file
      or the client (shown by a test that greps the service's output and responses for it).
- [ ] AC-3 `SN_MAIN` and any unconfigured network are refused before signing (tested, as FND-05's
      spies on signing and execution).
- [ ] AC-4 The threat model is written in the report with the numbers of its caps and the worst
      drain; each guard has a test.
- [ ] AC-5 No blockchain word in anything a player can see; no vendor type exported; CI green;
      `pnpm -r test`, lint, typecheck.

## Audits
Security (it moves funds, test tokens only) and quality: **`[GPT-6-Astra]`**.

## Verification
From the worktree root:
```
pnpm -r test && pnpm -r lint && pnpm -r typecheck
scripts/with-node.sh <the command that runs the service's integration test>
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the endpoint, the threat model and its caps, the
refusals and their tests, how the key is kept out of every output.

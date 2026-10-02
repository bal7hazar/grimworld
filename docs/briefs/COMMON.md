# Common rules of every task brief

Every brief in `docs/briefs/` inherits these rules. The orchestrator launches an agent with a
one-line prompt, `Read docs/briefs/<ID>-<slug>.md and docs/briefs/COMMON.md, then execute the
task.`, through `scripts/agent.sh`, in the task's own worktree. When a brief and this file
disagree, the brief wins for its task, and says so.

## 1. Read first

1. The brief, then this file.
2. [CONTEXT.md](../../CONTEXT.md): pillars, stack, the **glossary** (§5, the only words to use
   in code and prose), the constraints that are easy to forget (§8).
3. The design documents and ADRs the brief names.
4. **Every Cairo task: [docs/CAIRO.md](../CAIRO.md), in full.** Test-driven, a gas budget on
   every test, execution cost first, arithmetic then bitwise then loops, no `u256` without a
   written reason, `felt252` bitmaps through `hexx`'s `Bits` (D-174). The game is native Starknet on Cairo 2.20
   ([ADR-0007](../architecture/ADR-0007-native-starknet.md)): no Dojo.

## 2. How you work

- **Foreground only.** Never run a command in the background (`&`, `run_in_background`,
  `nohup`) and never end your turn waiting for one: in headless mode that ends the session. A
  command may run for up to one hour in the foreground. A process that must live during a
  test (the local Starknet node) is started and stopped **inside one foreground command**, by
  `scripts/with-node.sh <command>` (SPK-5b). Your turn ends when `REPORT.md` is
  written.
- **Work autonomously, do not ask questions, do not widen the scope.** Nobody answers
  during your run. What the brief does not ask for is out of scope, however tempting.
- **Ambiguity stops you.** If the design does not say what the code must do, you do not
  invent a rule: you stop that part, and you write the question under *Escalations* in the
  report, with the documents you read.
- **Your allowlist is the brief's.** Write only the files and folders it lists. Anything
  else, including the shared files below, is an escalation in your report, not an edit.
- **Shared files belong to the orchestrator**: `CONTEXT.md`, `OPERATIONS.md`, `PLAN.md`,
  `STATUS.md`, `README.md`, `docs/decisions/`, `docs/briefs/`, `docs/reports/`, `.github/`,
  `scripts/agent.sh`, `scripts/lock.sh`, `scripts/profiles/`, the root `Scarb.toml` and
  workspace manifests, unless the brief lists one of them.
- **Your permissions** come from the profile of your launch (`scripts/profiles/`):
  `research`, `audit` or `implement`. A refused command is not an obstacle to work around:
  use an allowed command, or report what you needed. Run commands from the worktree root
  and call the project's scripts as `scripts/…` (`scripts/lock.sh`, not
  `../../scripts/lock.sh`), with `--manifest-path` for a package in a subfolder: rules match
  the start of a command. Delete files with relative paths inside your worktree.
- **Commit early.** Coherent intermediate states in small commits, so that an interruption
  loses nothing; you may be resumed with `claude --continue`.

## 3. The machine

The VPS (8 vCPU, 31 GB) is shared with the owner's other programmes and with other agents.

- **Every heavy command goes through the build lock**:
  `scripts/lock.sh scarb --manifest-path <package>/Scarb.toml build` (Scarb 2.19 and later: the option
  comes before the subcommand), `cd <package> && snforge test <filter>` (the machine's
  `snforge` shim takes the heavy lock), `scripts/lock.sh pnpm build`. It waits silently, sometimes for
  minutes, while another build runs: that is normal. A workspace-wide run adds `--heavy`.
  `scarb` and `snforge` on your PATH are also the machine's shims, which take the shared
  heavy lock by themselves.
- **Local checks are package-scoped**: the tests of what you touched and of what depends on
  it. Never the whole workspace locally; the pull-request CI is the full gate. Push early and
  fix from CI.
- A build killed with signal 9, or exit code 137, is the OOM killer, not your code: wait a
  minute and run it again.
- Do not install or upgrade anything the brief does not ask for. Never change the machine's
  toolchain globally (`asdf set -u`, `asdf uninstall`): other programmes use it.
- **An asdf plugin changes the whole machine**: adding one creates shims in `~/.asdf/shims`,
  ahead of the system binaries on every PATH, for every programme. Never add a plugin for a
  tool the system already provides at the pinned version; after adding any plugin, check that
  the same command still works from a directory without `.tool-versions` (`cd /tmp`), and stop
  and escalate if it does not (docs/reports/INC-2026-09-28-asdf-node-shims.md).
- **The machine is shared** (OPERATIONS §3): delete and kill only what you created, named
  exactly: a path you made yourself (`mktemp -d` under your worktree, never directly under
  `/tmp`), a process whose pid you recorded. Never a wildcard outside your own worktree (`rm -rf
  /tmp/tmp.*`), never a kill by pattern (`pkill`, `killall`), never a `git clean` or a
  `git worktree prune` outside your worktree. Your profile refuses the typed forms.
- `npm`, `npx` and `corepack` print `No version is set for nodejs; please run asdf set …` on
  stderr on this machine: a harmless warning, not a failure.

## 4. Rules of the game's code

- **Multiplayer door**, constraints M-1…M-6 of
  [design/08](../design/08-multiplayer.md#what-v1-must-do-to-keep-the-door-open), on every
  task: instance state keyed by instance id, never by adventurer id; time is a field of the
  instance, durations and recharges are instance-clock deadlines; goblin target selection
  takes a list of adventurers; loot and quest credit take the set of contributors;
  ally-targeted skills target an entity id; the permission model does not assume the instance
  creator is the only writer.
- **Determinism.** Combat, movement and goblin AI are fully deterministic (D-40). No rule
  inside an instance reads the block number, the block timestamp or the transaction hash.
  Iteration and tie-break orders are fixed: lowest entity id, then lowest tile index, never a
  random draw. Randomness is obtained only through the randomness provider, `fate(domain)`
  (ADR-0002); never read the transaction hash directly.
- **Game results are API.** A change to the outcome of an action for the same state and input
  moves the shared test vectors, and says so in the report.
- **Two domains, never mixed** (ADR-0001): **persistent** (adventurer, inventory, progress,
  registries) and **ephemeral** (instance state). No model holds fields of both. The
  ephemeral domain reads a snapshot of the adventurer taken at entry and writes to the
  persistent one only through the results interface.
- **Bounded execution.** Every loop in a contract has a bound stated in the design.
- **Content is data** (pillar 6): core systems read registries and never hard-code a content
  id.
- **The chain is invisible** (D-100): no fee, wallet, signature, transaction or token reaches
  the player's screen or text.
- **Test networks only.** Nothing is deployed anywhere but the local node unless the brief
  says so; mainnet is never touched.
- **Sepolia, when a brief grants it** (launched with `--with-sepolia`; OPERATIONS §7): the account
  comes as variables used **by name only** (`STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`,
  `STARKNET_PRIVATE_KEY`, `STARKNET_NETWORK`): never print, log, echo or write a value. Every
  script that sends a transaction first asks the RPC for its chain id and stops unless it is
  `SN_SEPOLIA`; set a usual `User-Agent` header (the endpoint refuses requests without one). The
  balance is the owner's money: measure, do not loop, and report how many transactions were sent
  and their total cost. Without `--with-sepolia` these variables are empty in your environment.
- **Sending lives in one module, and ends with the task** (project manager, after SPK-1b's
  audits): the ability to send a transaction is in a single module of the task, which refuses
  unless the RPC's chain id is `SN_SEPOLIA` and the task's brief grants the account; nothing else
  exports a way to send (no account object, no provider that can submit, no raw RPC outside an
  explicit list of read methods). **In the same pull request that reports the measurements, that
  module is removed or turned into a refusal**, with an offline test that every path refuses.
- **You never publish** (D-132): no `scarb publish`, no package, release or tag to any registry,
  whatever the brief or a document says. Publications on scarbs.xyz are decided by the project
  manager in the owner's name and made by an orchestrator after a go that names package, version
  and commit (OPERATIONS §7).

## 5. Assets (D-73)

The *Tiny Swords* pack and everything derived from it live in the private repository
`tiny-swords`, attached as the submodule `assets`. Its licence forbids redistribution, even
modified.

- **Nothing from `assets/`, and nothing derived from it** (an atlas, a cleaned sprite, a
  thumbnail, a palette extracted from it) **is ever committed to this repository.** Generated
  art goes to an ignored folder the brief names.
- Never commit in the submodule, never move its pointer, never `git add assets`. The
  submodule is initialised by the launcher only for tasks that need the art.
- Names from the manga in the pack's folders never reach the game or the repository: sprites
  are renamed after our castes.

## 6. Branch, commits, pull request

- Your worktree is on the branch the orchestrator created, `<type>/<task-id>-<slug>`, cut
  from `origin/main`. Stay on it; never touch `main`, another branch or another worktree.
- **Conventional commits** (`feat(contracts): …`, `fix(client): …`, `chore(tooling): …`,
  `docs(design): …`), each ending with the trailer naming the model that did the work:
  `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` (or `Claude Opus 5.5`,
  `Claude Fable 5.1`).
- Never force-push, never rebase a pushed branch (merge `origin/main` into it instead),
  never skip hooks, never commit a secret.
- Push with exactly `git push -u origin HEAD` the first time and `git push` afterwards
  (the only two forms your profile allows). Open the pull request yourself with
  `gh pr create --base main`, title `[<Model>] <TASK-ID> <short description>`, body with the
  summary, the acceptance criteria ticked, the gas table for a Cairo task, and a last line
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Wait for the CI in the foreground (`gh pr checks <n> --watch --interval 30`) and fix until
  it is green. **Never merge**; the orchestrator does.
- A design change the code needs goes in `docs/design/*` **in the same pull request**, and
  only if the brief allows it; otherwise it is an escalation.

## 7. REPORT.md

Written at the root of your worktree, **not committed** (it is ignored by git). The
orchestrator reads it and the log, never your transcript.

The header's `[<Model>]` is **the model you read from your own session** (the model your
system prompt says you are running as), not the one the brief names; if they differ, say so
in the summary. The launcher also records the model the CLI actually ran (`model=` in the
log, `scripts/agent.sh status`), and the orchestrator checks the two agree.

```markdown
# [<Model>] <TASK-ID> — <title>

## Summary
What exists now that did not before. Pull request URL.

## Files changed
One line each.

## Commands run
Each with its real output, trimmed to what matters. No figure that was not measured.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
Every test and benchmark the lot touched (Cairo tasks), printed by
`python3 scripts/gas_budgets.py --report` from the worktree root (FND-06; `origin/main` fetched).
A raised budget shows `raised: <reason>` in the Note column: the orchestrator agrees or refuses
it at review (docs/CAIRO.md §2). "—" for a task without Cairo.

## Acceptance criteria
Each criterion of the brief, with the test or command that shows it.

## Deviations from the brief
## Escalations
Shared files that need a change, design ambiguities, blockers.
## Open questions
```

An auditor writes the audit report of [OPERATIONS.md §6](../../OPERATIONS.md#6-audits) instead,
in the same file.

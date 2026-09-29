# ENG-01b — ENG-01's cost accounting completed, and the content version

> D-141: ENG-01 (#81) was merged with three accounting findings of its final audit open; they are
> this task. Runs beside FND-05. ENG-07 depends on it.

## Agent
Title: `[Sonnet 5.5] ENG-01b accounting` · Profile: implement · Branch: `feat/eng-01b-accounting`

## Goal
After this task, ENG-01's budget tables cover every reachable branch of every entrypoint, and the
frozen interfaces carry the **content version** of D-141 (E-5). No game logic is written.

## Context
- **`docs/architecture/ENG-01-interfaces.md`** in full, above all §2.1 (reuse and generations),
  §9 (slots per entrypoint), §10 (budgets) and §11 (escalations).
- **`contracts/tools/budget_table.py`**: every write a physical key with an identity and a rule
  (`first`, `new`, `old`, `warm`); a branch is the deduplicated union of its parts' keys; counts,
  calldata (5,120 L2 gas a felt) and events (priced from their shapes, labelled E) derive from the
  sets. Its two outputs, `contracts/tools/budget-output.txt` and `budget-keys-output.txt`, are
  committed and copied into §9.3 and §10.
- **The audit to answer**: `docs/reports/ENG-01-audit-gpt-6-astra.md` (F-2, F-3, F-4; every other
  finding is resolved and must stay so). ENG-01's report: `docs/reports/ENG-01-core-interfaces.md`.
- **D-141**: `docs/decisions/2026-09-29-eng-01-escalations.md`, section *Decision*; design/02
  (*Size*, *The chain's answer*: the content version), cost-budget.md (*Per-branch budgets*).
- docs/CAIRO.md, COMMON.md.

## Scope
- In, the accounting (`budget_table.py`, its two outputs, §9–§10 of the document):
  - **F-3**: a standalone action whose ticks can complete an objective (a burning or poisoned Rift
    Heart dying while the adventurer mines or opens a chest; a dungeon cleared) unions the
    objective's keys and events with its completion, interruption and defeat branches, where
    reachable. `barter`'s refusal on price is its own branch, with its `Hub.barter` call, apart
    from an interruption before the exchange. E-8 recomputed.
  - **F-4**: `enter_rift` gains the branch of an adventurer's first entry (first instance slot,
    `I.next_slot`); the selector's cold maximum is the larger of the two branches, the later-entry
    figure kept apart.
  - **F-2**: revealed chunks and chunks a tick updates share physical identities (a chunk's feature
    word is one key whether a reveal or a tick writes it), with correct classifications at the
    transaction's start; the reveal branch gains its objective and defeat unions; the slot bound of
    §10.1 is derived from the key sets, independently of the gas maximum, and the text says the
    bound that results. §9.2's sentence on E-1 (b) is qualified (it does not remove the 47.33M
    initialised case).
  - D-141's rules in the tables where they bind: the goblin cap of 16 (E-16), the first-record
    weight (E-1), the class bound of an unsplittable action, 58M cold (E-21), the belt credited back
    on defeat (E-15), nothing carried through a gate but the belt (E-20; the four member words stay
    written at a gate).
- In, the content version (D-141, E-5), **interfaces only**:
  - The registry's content carries a version, returned by `IRegistryRead.bundle` (the call every
    invocation already makes); `play` takes the version its batch was computed under; a different
    version refuses the batch whole, before any action runs (a `Stop` value, like a sequence
    mismatch); `BatchPlayed` says so.
  - Freeze the fields and their types in the code (stubs still revert), the document (§4, §5, §9, §10
    with one more felt of calldata and one compared value) and the layout tests. Say in the report
    which frozen signatures changed. Whether the Fate and gate actions carry the version too is a
    question to raise, not to decide: they read the same content.
  - The cost is measured by ENG-03, not here.
- Out: any game logic; `TxHashFate`, `set_contracts`, `set_admin` (FND-05); the launcher; design
  documents (the orchestrator's).
- Allowlist: `contracts/tools/budget_table.py` and its two outputs, `docs/architecture/ENG-01-interfaces.md`,
  `contracts/logic/src/{interface,content,actions,types}.cairo`, the `play` signature and the
  `BatchPlayed` event in `contracts/ephemeral/src/{systems/instances,events}.cairo`, the
  `bundle` in `contracts/persistent/src/systems/registry.cairo`, the tests of those files, `GAS.md`
  and `docs/BUDGETS.md` as generated. Anything else is an escalation. FND-05 edits
  `set_contracts` and `set_admin` in `instances.cairo` and `hub.cairo` at the same time: do not
  touch those functions.

## Acceptance criteria
- [ ] AC-1 F-2, F-3 and F-4 of the audit are answered: every branch the audit names is in the key
      sets, and both outputs regenerate byte for byte (`cmp` shown).
- [ ] AC-2 The slot bound of §10.1 is derived from the key sets and stated as it is.
- [ ] AC-3 The content version is frozen in code, events, document and tests; every signature that
      changed is listed in the report.
- [ ] AC-4 F-1 and F-5 to F-14 stay resolved (the generation isolation of §2.1 above all).
- [ ] AC-5 CI green; `python3 scripts/gas_budgets.py --check` passes; `class_sizes.py` passes.

## Audits
Quality and cost (PLAN: C), and **`[GPT-6-Astra]`**, resuming ENG-01's audit.

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
cd contracts/logic && snforge test && cd - ; cd contracts/ephemeral && snforge test && cd - ; cd contracts/persistent && snforge test && cd -
cmp <(python3 -B contracts/tools/budget_table.py) contracts/tools/budget-output.txt
cmp <(python3 -B contracts/tools/budget_table.py --keys) contracts/tools/budget-keys-output.txt
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: each finding and where it is answered, the figures
that moved (before and after), the signatures that changed, the gas table of every test.

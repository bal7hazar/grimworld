# ENG-04 — Adventurer creation and ownership

> Phase 1, on ENG-01's frozen interfaces (#81, D-141). Runs beside ENG-01b; the allowlists do not
> overlap.

## Agent
Title: `[Opus 5.5] ENG-04 adventurers` · Profile: implement · Branch: `feat/eng-04-adventurers`

## Goal
After this task a player can **register an account, create and delete adventurers, and hand the
account to another owner**, on `Hub`, exactly as ENG-01 froze them, within ENG-01's budgets; and
every later `Hub` entrypoint has one tested helper for "the caller owns this adventurer, and it is
in a hub".

## Context
- **`docs/architecture/ENG-01-interfaces.md`**: §1.2 (who may call whom: `register` and
  `set_account_owner` are the player's; `set_account_owner` by the current owner, A-7; the call to
  `Instances.set_controller` when an adventurer is inside), §3.1 (packing, `LIVE`), §3.3 (`Hub`
  storage: `account_of`, `accounts`, `account_adventurers`, `adventurers`, `AccountRecord`,
  `AdventurerCore`, `AdventurerPlace`, `pack_lanes`), §4.3 and §4.5 (entrypoints, bounds), §5
  (events: add none), §7 (accounts, A-7), §9.3 and §10 (the write set and the budget of each of the
  four entrypoints), §11 E-19 (`account_of` of the old owner zeroed).
- **design/03** *Creation* (D-32: a name and a primary profession only), *Slots and vault* (D-33:
  3 slots, deleting frees the slot, the inventory emptied into the vault first), the professions of
  the MVP. ADR-0005 (accounts behind a provider; an account id owns the adventurers), ADR-0007
  *Access control*. docs/CAIRO.md, COMMON.md.
- `contracts/persistent/src/systems/hub.cairo` and `models/{account,adventurer}.cairo`: the frozen
  layouts and the stubs you implement. FND-05 implemented `set_contracts` and `set_admin` there:
  keep them.

## Scope
- In, `Hub`:
  - `register() -> u32`: one account per owner address (a second `register` by the same address is
    refused); the account's record with its 3 adventurer slots (D-33; the slots field of
    `AccountRecord`).
  - `create_adventurer(name, profession) -> u32`: the caller's account, a free slot, a valid
    primary profession (the MVP's professions as constants in `grimworld_logic`; say which ids and
    from where; Q-12, the Arcanist or the Cleric, is open: escalate if it decides an id), a name
    that is not empty; the adventurer placed in the region's town hub (say where the hub id comes
    from before ENG-03's registries exist: a constant or configuration, escalated).
  - `delete_adventurer(adventurer_id)`: the owner only, in a hub, its pack empty (balances by
    `pack_lanes`, equipment pages, equipped items, gold: say what "inventory emptied" covers and
    how each is checked without scanning, from §3.3), the slot freed, the adventurer's record never
    zeroed (§2.1's rule for reused keys applies to `Hub` too: say how deletion is marked).
  - `set_account_owner(account_id, owner)`: the current owner only; the new owner holds no account;
    `account_of` moved (E-19: the old entry zeroed). **An adventurer inside an instance**: `Hub`
    calls `Instances.set_controller` for it (§1.2); `Instances.set_controller` itself is ENG-06's,
    so test this branch with a test double deployed in its place.
  - Views `account_of`, `account`, `adventurer` as frozen.
  - **One internal helper** for every later entrypoint that names an adventurer: the caller owns
    the adventurer's account, the adventurer exists and is not deleted, and it is in a hub (not
    inside); with a refusal message per case.
- Out: `set_build`, travel, `enter` (ENG-06), services, quests, the vault's `stow`, events (none
  is frozen for these four), `Instances` (ENG-01b edits it now).
- Allowlist: `contracts/persistent/src/systems/hub.cairo` (the four entrypoints, the three views,
  the helper, their constants), `contracts/persistent/src/models/{account,adventurer}.cairo` (helpers
  only: no layout change), `contracts/logic/src/types.cairo` or a new `contracts/logic/src/professions.cairo`
  (the profession ids, and its `mod` line), `contracts/persistent/tests/`, `GAS.md` and
  `docs/BUDGETS.md` as generated. A frozen signature, layout or event that must change is an
  escalation, not an edit.

## Acceptance criteria
- [ ] AC-1 The four entrypoints and three views work as frozen; each refusal (wrong caller, second
      account, no free slot, bad profession, empty name, not in a hub, pack not empty, new owner
      already has an account) has a test.
- [ ] AC-2 Each entrypoint's storage writes match ENG-01 §9.3 (count the keys a test changes, new and
      overwritten), and its gas is within §10's budget (the report compares both).
- [ ] AC-3 No record is ever zeroed except `account_of` of the old owner (E-19); a deleted
      adventurer's slot is reusable and the deleted record stays marked.
- [ ] AC-4 The ownership helper is tested for every case, and `set_account_owner` moves the
      control of an adventurer inside (through the test double).
- [ ] AC-5 CI green; `python3 scripts/gas_budgets.py --check`; `class_sizes.py`.

## Audits
Security (access control and ownership) and quality: **`[GPT-6-Astra]`** (OPERATIONS §2).

## Verification
From the worktree root:
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
for p in logic persistent ephemeral; do (cd contracts/$p && snforge test); done
python3 scripts/gas_budgets.py --check && python3 contracts/tools/class_sizes.py
```

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: each entrypoint's writes against §9.3 and its gas
against §10, the refusals, the escalations, the gas table of every test.

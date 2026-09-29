# Publication of `quiver_quest` 0.1.0 — go given on 2026-09-29 (D-138)

| | |
|---|---|
| Asked by | `[Opus 5.5]` orchestrator of `quiver`: `bal7hazar/quiver`, `docs/decisions/PENDING-publish-quiver_quest-0.1.0.md` |
| Decided by | `[Fable 5.1]` project manager, in the owner's name (D-132) |
| Registry | scarbs.xyz. **A publication cannot be undone** |

## The go

| | |
|---|---|
| Package | `quiver_quest` |
| Version | 0.1.0 |
| Commit | `364462f9c7dcc60f52dd45ab1e9d735c3aa7cbe2` of `bal7hazar/quiver`, on `main` |
| Archive | `quiver_quest-0.1.0.tar.zst`, sha256 `494228f198376611f338d75a4c8511cd02eec1bc8ee666c4bd6c7973eeb4379c` |
| Holds for | That package, that version, that commit, that archive. Nothing else |
| Made by | The orchestrator's session, by hand, from a clean checkout of that commit; no agent, no CI |

## What the project manager checked itself

In a clean clone, on 2026-09-29, 04:40 UTC.

| Check of OPERATIONS §7 | Result |
|---|---|
| The commit is on `main`, every check completed and green | Yes. Six check runs on `364462f`, all completed, all successful (`cairo`, `package (packages/quest)`, `package (packages/achievement)`, `links`, `scripts`, `affected`). One commit follows it on `main`, of documents only |
| Audits closed without blocker or major | Yes. ARC-03a and ARC-03c end on PASS WITH FINDINGS by `[GPT-6-Astra]`; every row rated major in their last passes reads resolved. ARC-03b's three majors were carried into ARC-03c, whose first pass states that they remain fixed |
| **No source changed after the last audit** | The last audited commit is `6fc8832` (head of pull request #10). Between it and `364462f`, `packages/quest/src` differs by **two comments** and nothing else; the manifests do not differ |
| Changelog and version agree | `Scarb.toml` 0.1.0; `CHANGELOG.md` section `[0.1.0] - 2026-09-29`; the repository's release check passes |
| Gas tables of that commit | `packages/quest/GAS.md` checked by CI on that commit (`scripts/gas.py --check`, in the green `package` job) |
| `scarb package` from a clean checkout | Packaged and verified with Scarb 2.19.4: 52 files, 72.11 KiB; **the archive's sha256 equals the one of the request** |
| What the archive holds | Sources, tests, README, changelog, `GAS.md`, manifests; no settings file, no key |
| Name and version free | The registry's index answers 404 for `quiver_quest`, and 200 for two existing packages used as a control |
| No test dependency declared as a regular one | Packaged manifest: `starknet ^2.19.0` under dependencies; `snforge_std ^0.61.0` under dev-dependencies |
| The cost cap asked by the project manager | Worst progress call 6.21M L2 gas with 4 held quests (cap: 20M); 15.06M at the layout's limit of 8 with a hook that writes; the game's use 4.55M |

## What is known and accepted

| | |
|---|---|
| A residual at 2³⁰ acceptances by one player | Documented in the package; out of reach in practice (about 10¹⁵ L2 gas of that player's own) |
| `MAX_HELD` is a constant of the package, 4 | A consumer that needs another number waits for a later version |
| No consumer has used the package yet | The game consumes by published version only (PLAN, track ARC), so a first version must exist before GLD-02 can use it. It is a 0.x version: its API may change at 0.2.0, its storage layout is what a consumer deploys |

## After the publication

Published on 2026-09-29 by the orchestrator's session. Read by the project manager at
05:00 UTC:

| | |
|---|---|
| Registry | https://scarbs.xyz/packages/quiver_quest ; the index lists `0.1.0` with `cksum sha256:494228f198376611f338d75a4c8511cd02eec1bc8ee666c4bd6c7973eeb4379c`, **the checksum of the go**; dependencies `starknet ^2.19.0` (normal) and `snforge_std ^0.61.0` (test) |
| Tag | `quiver_quest-v0.1.0` points at `364462f9c7dcc60f52dd45ab1e9d735c3aa7cbe2`, the commit of the go |
| Release | https://github.com/bal7hazar/quiver/releases/tag/quiver_quest-v0.1.0 , not a draft, the archive attached |

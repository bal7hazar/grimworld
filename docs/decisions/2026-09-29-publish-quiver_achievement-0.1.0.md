# Publication of `quiver_achievement` 0.1.0 — go given on 2026-09-29 (D-142)

| | |
|---|---|
| Asked by | `[Opus 5.5]` orchestrator of `quiver`: `bal7hazar/quiver`, `docs/decisions/PENDING-publish-quiver_achievement-0.1.0.md` |
| Decided by | `[Fable 5.1]` project manager, in the owner's name (D-132) |
| Registry | scarbs.xyz. **A publication cannot be undone** |

## The go

| | |
|---|---|
| Package | `quiver_achievement` |
| Version | 0.1.0 |
| Commit | `50017e7576fd7d8228016a450f6ccdfac5044f1d` of `bal7hazar/quiver`, on `main` |
| Archive | `quiver_achievement-0.1.0.tar.zst`, sha256 `1473a07fcbe1298a9ba85ef07b1b5afc63816c1fcbe3c5c10151908ae7a4d9d9` |
| Holds for | That package, that version, that commit, that archive. Nothing else |
| Made by | The orchestrator's session, by hand, from a clean checkout of that commit; no agent, no CI |

## What the project manager checked itself

In a clean clone, on 2026-09-29.

| Check of OPERATIONS §7 | Result |
|---|---|
| The commit is on `main`, every check completed and green | Yes. Six check runs on `50017e7`, all completed, all successful. One commit follows it on `main`, of documents only |
| Audits closed without blocker or major | Yes. ARC-04, `[GPT-6-Astra]`, one pass at `33f674c`: PASS WITH FINDINGS, no blocker, no major, no access-control bypass, no unintended storage path; two minors, both fixed since |
| No source changed after the audit | Between `33f674c` and `50017e7`, `packages/achievement/src` does not differ. The manifest's description changed (the audit's second minor) and one test (its first) |
| What the audit could not verify | It states that it could not run the tests nor read CI. Both are verified here: CI green on the commit, and the package builds |
| Changelog and version agree | `Scarb.toml` 0.1.0; `CHANGELOG.md` section `[0.1.0] - 2026-09-29`; the repository's release check passes |
| `scarb package` from a clean checkout | Packaged and verified with Scarb 2.19.4: 32 files, 26.53 KiB; **the archive's sha256 equals the one of the request** |
| What the archive holds | Sources, tests, README, changelog, `GAS.md`, manifests; no settings file, no key |
| Name and version free | The registry's index answers 404 for `quiver_achievement`, and 200 for `quiver_quest`, used as a control |
| No test dependency declared as a regular one | `starknet ^2.19.0` under dependencies; `snforge_std ^0.61.0` under dev-dependencies |

## The conditions of D-139

| Condition | Result |
|---|---|
| The storage mode is absent, not refused at run time | No `Mode` type, no per-player storage, no claim in the sources; the interface says so |
| The README says that a storage design comes later and that 0.1.0 reserves nothing for it | Yes |
| The worst call is measured, with the game's use as a benchmark, under 20M | Worst `progress_many` **1.82M L2 gas**, read as the test minus its baseline (60,255,793 − 58,439,180), 9 % of the cap; the game's results call 0.83M, 1.25M with 16 tasks |
| Reporters' access control audited | By `[GPT-6-Astra]`, no bypass found |

## After the publication

Published on 2026-09-29 by the orchestrator's session. Read by the project manager:

| | |
|---|---|
| Registry | https://scarbs.xyz/packages/quiver_achievement ; the index lists `0.1.0` with `cksum sha256:1473a07fcbe1298a9ba85ef07b1b5afc63816c1fcbe3c5c10151908ae7a4d9d9`, **the checksum of the go**; dependencies `starknet ^2.19.0` (normal) and `snforge_std ^0.61.0` (test) |
| Tag | `quiver_achievement-v0.1.0` points at `50017e7576fd7d8228016a450f6ccdfac5044f1d`, the commit of the go |
| Release | https://github.com/bal7hazar/quiver/releases/tag/quiver_achievement-v0.1.0 , not a draft, the archive attached |
| Consumed | A fresh project depending on `quiver_achievement = "0.1.0"` and `quiver_quest = "0.1.0"` together builds with Scarb 2.19.4; its lock file records both from `registry+https://scarbs.xyz/` with the checksums of the two goes |

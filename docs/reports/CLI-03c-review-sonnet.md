> Archived by the orchestrator of track CV on 2026-10-01 from `nexus report grimworld/review-cli-03c` (the VPS, account claude-b7r, model claude-sonnet-5-5: the fallback while Codex has no quota). Verdict PASS WITH FINDINGS, three notes, none blocking; #270 merged on it. No audit (D-177).

# [sonnet] Review — CLI-03c hubs and transitions on fixed data

## Verdict
PASS WITH FINDINGS

## Revision
475662af0e75cf408166d8bb90d8be97ffbac0ad, compared with origin/main. The merge base was not printed, so I used the three-dot `git diff origin/main...HEAD`.

## Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | note | `client/app/src/sandbox/imports.test.ts` (the `sameTile…anchor` loop) | The "no tile is compared to an anchor" guard is a single-line regex, so it cannot catch a comparison split over two lines. | The pattern `/\b(anchor\|entry)_(chunk\|tile)\b.*sameTile\|sameTile.*anchor/` has no `s` flag, so it matches only within one line. The `readers` allow-list (`InstanceScreen`, `Loop`, `screens`) is the stronger check and holds. | Optional: drop the regex, or anchor the check on `hubGateAt` and `sameTile` imports. |
| 2 | note | `tools/art/build.py`, `artpipe/atlas.py` | No test pins that the existing strips' atlas output is unchanged now that stills are added. | Stills are appended after the strips and `pack` is first-fit in list order, so the strips' frame placements cannot move. The last existing page can grow if a still lands on it, which changes that page's PNG and JSON bytes, and `sprites.json` gains entries. `clean.cut_strip`, `register` and `place` are untouched (the `clean.py` change adds `still()` and edits the docstring). I did not run the build. | Optional: before merge, compare `build.py --fingerprint` of the strips before and after on the Mac, or add a test with synthetic strips plus a still that checks the strips' frames are identical. |
| 3 | note | `client/app/src/sandbox/loop/InstanceScreen.tsx`, `Sandbox.tsx` | The offer to leave depends on the `listenToWalk` callback calling `adventurerTile()`. If the entry tile is itself a hub gate's anchor, no walk happens and the offer would not show. | For the seed, gate 2's anchor is not entry tile 105, so there is no failing case today. The room opens at `entry`, and `tile` is set to `entry` by the machine, so a gate-on-entry case would still be offered. | None needed. |

## Mandate §6
- **No rule outside `placeholders.ts`:** the new rules `hubGateAt`, `entryThrough` and `hubAfter` are in `placeholders.ts`, each marked "PLACEHOLDER until CLI-02". `machine.ts` is the only non-test importer besides `wiring.ts`, and the imports test asserts both lists.
- **Taps yield intents only:** `hubTaps.ts` returns `LoopIntent` values via `targetIntent` and `figureIntent`. `intent.ts` types them in one module. The imports test checks that `hubView`, `hubRenderer` and `hubTaps` import nothing from the sandbox.
- **The machine decides nothing:** it only looks up fixtures and placeholders. Leaving by a gate is accepted only on a hub gate's anchor (D-148), the other two ways out are always accepted, and the hub reached comes from `hubAfter`. Defeat and travel back are asked or debug-labelled in the UI, and leave and travel back have a confirmation (I-5).
- **On demand:** `hubRenderer.test.ts` shows that after one view there is one render and the host is quiet for 60 s, and that a view, a size or an atlas each cost exactly one frame. It also shows nothing is drawn while the page is hidden. There is no `requestAnimationFrame` or `setInterval` in the new code.
- **No randomness or clock:** the imports test forbids `Math.random`, `Date.`, `performance.now` and `crypto.` in `machine.ts` and the three fixture files. The entry screen's one-shot `setTimeout` is a UI delay that reads no clock, and it is cleaned up on unmount.
- **The imports test enforces the above:** yes, apart from the weak regex in finding 1.

## Other requested checks
- **`region.test.ts` and the seed:** it reads `contracts/seed/test-region.json`. It checks every copied field of the region, locations 1–2, gates 1–2, and each zone outline row against the seed's `<kind>_fields`. It also checks that the outpost's location and gate ids collide with no seed record, and pins `globalTile` to the README's chunk 0 / tile 105 example.
- **design/11:** the diff is one 11-line addition inside *Hubs*, before `## Desktop`. It has five rows, each marked "proposed, the owner's eye", and nothing else changed.
- **`tools/art` still role:** it is additive (`still()`, `still_problems`, `still_sprite`, a `[[still]]` manifest block). `still()` reuses `register` and leaves `cut_strip` untouched. The synthetic-image tests cover the thin-pole base, native size and a single frame. Finding 2 is the one gap.
- **Art pack not committed (D-73):** the diff and `git ls-files` show no png, jpg, gif, webp or atlas file. The manifest lists pack paths only. The diff touches no package files, so no dependency was added.
- **Scope:** every changed path is under `client/app` (not `account/` or `chain.ts`), `tools/art` or design/11. `client/sim` and `contracts/` are untouched.

## Coverage
I read the diff in full for `placeholders.ts`, `imports.test.ts`, `region.test.ts`, `machine.ts`, `hubTaps.ts`, `intent.ts`, `params.ts`, `controller.ts`, `Sandbox.tsx`, `Loop.tsx`, `screens.tsx` and `InstanceScreen.tsx`. I also read the `hubRenderer` test, the art pipeline changes, the manifest, the art tests and README, and design/11.

I did not read `hubRenderer.ts`, `hubView.ts`, `fixtures/hubs.ts`, `region.ts` or `HubScreen.tsx` line by line. I ran nothing: no tests, no art build, no Playwright. Two `cd`-prefixed commands were denied by the sandbox, and I repeated them with absolute paths instead. AC-9 (the visual check on the Mac) and CI status are outside this review.

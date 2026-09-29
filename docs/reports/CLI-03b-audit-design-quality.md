<!-- Archived by the orchestrator of track CV, 2026-09-29. Design and quality audit of CLI-03b by [Opus 5.5], second and last pass: PASS. First pass (PASS WITH FINDINGS): an inspect during a walk playing the next step; stop conditions outside placeholders.ts; the window ring not treated as wall; notes. All fixed. -->

# [Opus 5.5] Audit — CLI-03b — design and quality (second pass)

Pull request 163. Scope: the diff since the first pass, commit `bdd1752`
("fix(client): CLI-03b fix loop 1, audits of #163"), 6 files, +324 −25, in `client/app/src/sandbox/`.

## Verdict

**PASS**

All seven accepted findings are fixed, and each fix has a test that would fail on the code before
it: my F-1 to F-6, and [GPT-6-Sol] 1, the walk while the page is hidden. The fix commit introduces
no new defect. GPT-6-Sol's finding 2 was not accepted. The new idle-cadence test pins what the
orchestrator decided instead (after a walk, only the idle cadence remains), and it holds.

## Findings

No new findings.

## Accepted findings, checked

| Finding | Fixed | How | Test |
|---|---|---|---|
| F-1 (Medium): an inspect during a walk played a step | Yes | `SandboxSession.apply` handles an `inspect` first: it applies it, shows the result and returns, without `stopTimer` or `walkOn`. `applyIntent`'s inspect branch still changes only `said`. | `session.test.ts`, "an inspect during a walk plays no step and keeps the walk's pace". It inspects every 50 ms and expects steps at exactly 180, 360, 540, 720 and 900 ms. The first-pass code would have stepped on each inspect (my scratch test showed it). |
| F-2 (Low): stop conditions evaluated in the wiring | Yes | `stopsAfterStep(before, after)` in `placeholders.ts` is marked `PLACEHOLDER until CLI-02` and cites design/02. It returns the goblins that entered sight (lowest id first), and whether a chunk was revealed, detected as a tile unrevealed before and not after. It lists the conditions it does not cover. `walkStep` only turns its result into the one line. | `placeholders.test.ts`, `stopsAfterStep`: goblins entering sight, leaving sight being no stop, a reveal and no reveal. The existing session stop tests still pass through it. The imports test requires `stopsAfterStep(` in the wiring and forbids a sight diff there. |
| F-3 (Low): the window's ring was walkable | Yes | `insideRing` is the window less its first and last columns and rows: 6 columns on each side, rows `top+1` to `top+14`. `findPath`'s `free` uses it, so no path ends on the ring or passes through it. The doc comment cites D-120 and SPK-7 §4. | The window bound test is rewritten: the ring is 58 tiles for both row parities (2 × 15 + 2 × 14, correct), the column and row limits are checked for an even and an odd centre, and a wall whose only gap is on the ring gives null. |
| F-4 (Info): tie rule unverified against the library | Yes | The `findPath` doc says the tie rule is "a reading" of "lowest tile index", that the map library may break ties differently, and that CLI-02's finder is the rule. | Documentation only. The existing tie test still applies. |
| F-5 (Info): a walk ended by a map tap had no reason | Yes | `CANCELLED = "walk cancelled"`. The counter's cancel and a map tap that ends a walk both set it as `stopped`. A tap that starts a new walk clears it; a new preview keeps it. Cancelling a preview still sets no reason. | `session.test.ts`: the counter-cancel test now expects `"walk cancelled"`, and "a tap on the map that ends a walk says so; one that starts another walk does not" covers the map tap. |
| F-6 (Info): the AC-4 guard relied on regexes | Yes | A new imports test lists the 12 hex rules of `placeholders.ts`. It checks that `wiring.ts` is the only module importing any of them, that no other module exports one, and that the wiring uses none of the grid geometry (`neighbour`, `distance`, `inWindow`, `insideRing`). | `imports.test.ts`, "the hex rules are imported by the wiring only, and copied nowhere (F-6)". |
| GPT-6-Sol 1: the walk continued while the page was hidden | Yes | `WalkTimers` gains `hidden()` and `onVisibilityChange`, which `browserHost()` and `FakeHost` already provide. When the page is hidden, the session clears the step timer and keeps the plan. When it shows again with a walk in progress and no timer, the next step is scheduled `stepMs` later. `walkOn` also returns without stepping if a timer fires while hidden. `destroy` unsubscribes. | `session.test.ts`, "no step is played while the page is hidden; the walk resumes when it shows". It runs 60 s hidden with no step, no render and nothing scheduled, then after showing expects a step at exactly `STEP_MS` and the rest at the same pace, and ends quiet. |

## What the diff adds, checked

- **Pause and resume on visibility.** There is no double scheduling: resuming requires
  `timer === null`, and `walkOn` clears the timer before rescheduling. Hiding the page during a
  preview does nothing. A timer firing at the moment the page hides steps nothing, and the next
  visibility change reschedules it. Resuming instead of stopping is justified in the class
  comment: nothing happens while hidden (D-40), and each resumed step evaluates the stops again.
  The renderer's scheduler already pauses on the same event. The controller passes a separate
  `browserHost()` object to the session, which is harmless because each subscription is its own.
- **`stopsAfterStep`.** It is equivalent to the first-pass inline logic. Detecting a reveal by
  comparing tiles no longer depends on `revealInSight` returning the same object, which is more
  robust. Sorting by id only makes the order of names in the line deterministic.
- **`insideRing`.** It uses the same row origin as `inWindow` and one tile of margin on each side.
  The adventurer (local row 7 or 8, column 7) is always inside the ring. Correct.
- **The cancel line.** It is consistent across the counter and the map. The preview-mode case
  (the old walk's line stays under the new preview) is deliberate and commented.
- **The imports test.** It is a real strengthening. The `import {…} from` parser handles `type`
  and `as` aliases. A namespace import (`import * as`) would slip past it. That is acceptable,
  since the earlier call-site test still catches `findPath(`, `stepToward(` and `neighbour(`.
- **The idle-cadence test** for the rejected GPT-6-Sol 2. It uses the edge fixture with idle
  animations on, and compares renders and wake-ups over 10 s before and after a walk and its
  fade: they are equal, at 15 fps or less. This matches D-151 and ADR-0003.

## Coverage

- Read: `git log` and the whole of `bdd1752` (code and tests), plus `scheduler.ts` and
  `fakeHost.ts` for the visibility interface.
- Ran at the new head: `pnpm install --frozen-lockfile` (ok). `pnpm test`: client/app
  172 passed, 1 skipped (165 in the first pass, 7 new); client/sim 8; indexer 66; funder
  305 passed, 1 skipped. `pnpm lint` (ok). `pnpm typecheck` (ok). `pnpm build` (ok).
- Not run: the root-level `prettier --check client indexer` (not approved in the first pass;
  the per-package lint includes Prettier). Nothing was checked in a browser.
- Outside the diff: I saw no blocker or major finding.

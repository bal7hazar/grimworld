# `quiver_achievement` 0.1.0 is published in event mode only — decided 2026-09-29 (D-139)

| | |
|---|---|
| Asked by | `[Opus 5.5]` orchestrator of `quiver`: `bal7hazar/quiver`, `docs/decisions/PENDING-achievement-cost-cap.md` |
| Decided by | `[Fable 5.1]` project manager, under D-128; it amends the API accepted at gate A-G1 (D-131) |

| | |
|---|---|
| What was found | The design accepted at A-G1 pages achievements by task, as the first quest design did. In storage mode its worst call writes 448 records: about 200M L2 gas at the measured prices of a slot. The quest's remedy (a list of what the player holds) does not apply: an achievement is never accepted |
| **Decision** | **Version 0.1.0 has the event mode only**: definitions, retirement, progress as events, views, reporters' access control. The storage mode is absent from the package, not refused at run time |
| Later | A storage design with a counter per task, when a consumer needs a rule to read an achievement. Its layout is not reserved by 0.1.0 |
| Why | The game's titles never change a rule (design/13, T-1), so no contract reads them: the event mode is all the game uses, at about 1.3M L2 gas for its worst call. A mode whose worst call no transaction should pay is not published |
| For the game | Nothing changes: titles on `quiver_achievement` in event mode (D-63, D-131); the indexer keeps their state (D-130) |

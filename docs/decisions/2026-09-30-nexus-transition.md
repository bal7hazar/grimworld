# D-162: the transition to the standard roles of Nexus

| | |
|---|---|
| Asked by | The owner, 2026-09-30, through the transition text of Nexus (`nexus session project-manager --project grimworld --transition`) |
| Recorded by | `[Fable 5.1]` project manager (the session moved from Opus 5.5 to Fable 5.1 by the owner the same day) |

## Decided (the owner)

1. The organisation keeps its standard in Nexus: the roles of the Overseer, of the project managers,
   of the orchestrators and of the agents of tasks, and their skills. `OPERATIONS.md` holds only what
   is specific to Grim World and never restates the standard; where it contradicts it, the standard
   wins.
2. **Every pull request is reviewed by Codex before it is merged** (`nexus review`); the standard's
   two exceptions apply and are recorded (`Codex review: none — <reason>`).
3. Reviews, audits and work for the Mac go through `nexus`; the implementers of the VPS tracks are
   still started by `scripts/agent.sh` until `OPERATIONS.md` names `nexus` for their track.
4. The project manager's report is the standard's table; `nexus progress` and `nexus accounts` are
   read at each check-in.

## What follows in the project (the project manager)

- `OPERATIONS.md` rewritten (the pull request of this decision says what was removed, kept, added,
  and where the standard won).
- **Track CV**: its agents are started with `nexus run --require browser`; the macOS launcher of
  CV-01 (#121, #129) is retired, its budget of 5 and its thresholds kept and enforced by Nexus. The
  mandate `ORCH-client-visual.md` §3 says so.
- The audit lenses *quality* and *cost* run on Codex, as the project's registry in Nexus names them.

## What would reverse it

A change of the standard, decided by the owner in `bal7hazar/nexus`.

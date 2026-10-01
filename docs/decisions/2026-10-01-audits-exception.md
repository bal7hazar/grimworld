# D-177: an audit is the exception, not the routine

| | |
|---|---|
| Decided by | The owner, 2026-10-01, relayed by the Overseer; recorded by the `[Fable 5.1]` project manager |
| Measured | 67 audits of grimworld since 2026-09-30 against 53 reviews, 15 queued or blocked on Codex |

**The review of every pull request (its checks and `nexus review`) is the routine gate and is enough
for a lot. An audit is run sparingly**: when a large feature or a large refactoring lands, and when
the tests alone do not give the confidence needed to validate the changes.

In the project:
1. OPERATIONS §6 names the kinds of tasks that require an audit and the lens of each (value, access
   control, randomness and the reveal, a published interface, a cost or determinism only a
   measurement proves, a large refactoring, a lot the owner asked to see); no lens per lot any more.
2. Every pull request says in one line why an audit was asked, or that none was needed.
3. Each orchestrator stops its queued audits that do not meet the rule (`nexus stop`, its own agents)
   and says so in its status; design-conformance audits on every lot stop unless the owner asked to
   see the lot. The project manager reports to the Overseer how many were stopped.

The project manager's reading of the lots in flight: ENG-R1a keeps one organisation audit (a large
refactoring, and the owner reads it); ARC-07b keeps its organisation and cost audits once, before
the 0.2.0 publication (a published interface); CBT-04, CBT-03a, ENG-02, SPK-15, M1-T5, M1-T7, ARC-07c,
SPK-12 and SPK-13 need none: their review, their tests and, for the spikes, their measurements.

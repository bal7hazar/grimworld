# GATE-1: the Phase 1 gate on Sepolia (D-308)

The gate (PLAN.md, Overview): "Create adventurer → enter zone → cross rooms → reach a hub, on Sepolia".

It is **met** by run 2, on the deployment `2026-10-16-cf6ddbb`, played by `scripts/sepolia_play.py` at commit `44373774e7ff8ae19f80584565f86c794709d38b`. Records: `GATE-1-sepolia-play-2026-10-17-2026-10-16-cf6ddbb-run2.json` and `GATE-1-sepolia-play-2026-10-17-2026-10-16-cf6ddbb-run2.md`.

Run 1 stopped: goblins blocked the way back to gate 2 for 8 batches of Waits, and the adventurer was left inside an instance (records `GATE-1-sepolia-play-2026-10-17-2026-10-16-cf6ddbb.json` and `.md`). That stop was 1 draw in 9 on the devnet. A rerun creates a new adventurer.

Total fee of both runs: 31476276130155500189 + 13925479201207006588 FRI.

The gate table is GATE-MAP's, in the body of PR #543, rows P1-1 to P1-4.

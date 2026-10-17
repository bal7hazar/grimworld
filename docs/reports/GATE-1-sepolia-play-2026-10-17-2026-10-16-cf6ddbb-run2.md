# GATE-1: the Phase 1 path on Starknet Sepolia (2026-10-17)

The Phase 1 gate (PLAN.md, Overview): create an adventurer, enter a zone, cross rooms, reach a hub: reached. Played by `scripts/sepolia_play.py` at commit `4437377` on the deployment `2026-10-16-cf6ddbb` (commit `cf6ddbb`).

- Adventurer: 2
- Entered: instance 8589934593, by gate 1 (location 1 to 2)
- Chunks crossed, in order: 15 (at (7, 15)), 16 (at (15, 19)), 1 (at (19, 14)), 0 (at (14, 6))
- Final location: in the hub, location 1
- Hits taken (the script never attacks): 3; at (15, 19), health 100 to 99; at (19, 16), health 99 to 98; at (8, 3), health 98 to 97
- Transactions: 12, total fee 13925479201207006588 FRI
- Time: 2026-10-17T11:32:51+00:00 to 2026-10-17T11:35:49+00:00 (178 s)

| # | Transaction | Hash | Fee |
|---|---|---|---|
| 1 | create_adventurer | `0x07907406d8c472021fef25d8944d61d0e09fcf066e510cfbc991a11b58c7a097` | 59110584540237915 FRI |
| 2 | set_build | `0x02ad9556668120ce4ca2b450140ad94dda369f67822cb140bdd2bf0d323ae79e` | 55728804284575236 FRI |
| 3 | enter (gate 1) | `0x069503e455451d1f0823a00c6cdc84cf504b8eeb4ca52b813520d1e13ffaba98` | 188077219345086480 FRI |
| 4 | play (batch 1, 10 Moves) | `0x02f43dcaf77ee2b542567c1e18adeee4ae82f6fc27612b3293f3ebb63c6ee2da` | 550243356548473026 FRI |
| 5 | play (batch 2, 4 Moves) | `0x00c87a1ed98c6e38dfbc0dbbf2c1b14649e407ba21c9511911d912d53ba74a08` | 662381569345465362 FRI |
| 6 | play (batch 3, 10 Moves) | `0x047e766881d94c7b42144f272cc0f036fb6e50f69c74e3313c6acba353ff9301` | 1510104911518595657 FRI |
| 7 | play (batch 4, 5 Moves) | `0x0716c7c613eeb3e572a25e06061265387f00e0206c6320a43dd859d22b218092` | 1251516336073827847 FRI |
| 8 | play (batch 5, 10 Moves) | `0x03410fe4f74e392d96df2150afb5a9b4181e4eb658670c658b984a88562a4261` | 2027138729563234423 FRI |
| 9 | play (batch 6, 10 Moves) | `0x05b8d38871a9aab7c68ebadeb87e4f43fbf61a9c1654049ed50fb16a7fc593e9` | 3303236000557006954 FRI |
| 10 | play (batch 7, 10 Moves) | `0x0496a33fde62ada217fd3b5c04a21fce475ad8dbe70110366017ac7b65742735` | 2296175968559778685 FRI |
| 11 | play (batch 8, 10 Moves) | `0x013fe4d85d5c63a4261509f3baf5d6e4d5ffe1f95868ceeb6ead0e814d174664` | 1988244120243849779 FRI |
| 12 | leave (gate 2) | `0x078ef2ee840a2c49c3a57a631dfebab6afb04ddc3d3163c416e40f1c737e69af` | 33521600626875224 FRI |

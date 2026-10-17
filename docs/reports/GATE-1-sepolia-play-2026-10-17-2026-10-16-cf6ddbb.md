# GATE-1: the Phase 1 path on Starknet Sepolia (2026-10-17)

The Phase 1 gate (PLAN.md, Overview): create an adventurer, enter a zone, cross rooms, reach a hub: **not reached**. Played by `scripts/sepolia_play.py` at commit `4437377` on the deployment `2026-10-16-cf6ddbb` (commit `cf6ddbb`).

- Adventurer: 1
- Entered: instance 4294967297, by gate 1 (location 1 to 2)
- Chunks crossed, in order: 15 (at (13, 15)), 16 (at (15, 22)), 15 (at (14, 22)), 16 (at (15, 17)), 1 (at (21, 14))
- Final location: left inside instance 4294967297
- Hits taken (the script never attacks): 12; at (13, 16), health 100 to 98; at (21, 15), health 98 to 97; at (19, 12), health 97 to 96; at (16, 12), health 96 to 95; at (15, 12), health 95 to 94; at (15, 12), health 94 to 92; at (15, 12), health 92 to 91; at (15, 12), health 91 to 90; at (15, 12), health 90 to 89; at (15, 12), health 89 to 88; at (15, 12), health 88 to 87; at (15, 12), health 87 to 85
- Transactions: 22, total fee 31476276130155500189 FRI
- Time: 2026-10-17T11:26:33+00:00 to 2026-10-17T11:32:00+00:00 (327 s)
- Stopped: back to the gate's anchor (0, 7): goblins blocked the way from (15, 12) for 8 batches of Waits in instance 4294967297; the script does not fight its way through

| # | Transaction | Hash | Fee |
|---|---|---|---|
| 1 | register | `0x01424e335d377c5eed201e6b0f4016aa14e2ad325bae2a2219e98c9169e46a2a` | 34972917402909505 FRI |
| 2 | create_adventurer | `0x01392dfff9e6da7af5e4ab9c05e447f32120e3ac72fd157a9994b05206f29d72` | 63843226294027245 FRI |
| 3 | set_build | `0x002fc6947276fbc71066a35e84f0aef75c2364fcc0ce08362c497b27c02c8d62` | 55836955116449716 FRI |
| 4 | enter (gate 1) | `0x05b6f82b4b53b8c296f0e0a494d81a67eba51df781e664ed6d85f7acc21a5e0b` | 197385665374076666 FRI |
| 5 | play (batch 1, 6 Moves) | `0x03ff6e9661ed870a20cdede289281de71e32ec6f4f73aed87871d0567488533c` | 597655072241566281 FRI |
| 6 | play (batch 2, 10 Moves) | `0x00a0ef014b5373e27750f2b042ce2be2652f9710d4a501e5ae069636a0f5f7ad` | 1097426097099603175 FRI |
| 7 | play (batch 3, 6 Moves) | `0x00b98bf6b2597b14c33825acc4a161399e6da176d4bb41a198869134e9ab0ea0` | 2476057127176115796 FRI |
| 8 | play (batch 4, 8 Moves) | `0x079de9aeb22626e7ea4ad2309ed5bb05273323fdf7511f150ce314e3f0e4a9f2` | 2443833991080587081 FRI |
| 9 | play (batch 5, 10 Moves) | `0x0535df4ec9935ec324936d8ec98455e65050312d503b67e7e3e065e9a8366f73` | 2294457203407659912 FRI |
| 10 | play (batch 6, 10 Moves) | `0x049dc4433e14d861d59d89c511d767a4cf720ad7fdfdf870445e752d45e90eb2` | 3815590801215160266 FRI |
| 11 | play (batch 7, 10 Moves) | `0x07110a91c28efd67f00c7e314865673d54b9a4abe0ec0faa20c29a6fdd8ab72a` | 2898457613034971091 FRI |
| 12 | play (batch 8, 10 Moves) | `0x06a74acfd828bce3d7247d5ab514f300cd93f76ca4b8d39b27b364677c9029d6` | 2840848890495323215 FRI |
| 13 | play (batch 9, 1 Moves) | `0x01906ef15a45b768262121d2ebdc7354f51d0fa780a73e3d62fd0407a574c6de` | 908831356516654771 FRI |
| 14 | play (batch 10, 1 Moves) | `0x015700c36165531a655846e0fa0172a90743370c736e30975cd126025a636de6` | 866888171567673345 FRI |
| 15 | play (batch 11, 2 Waits) | `0x049b51bde5cb2c1a0a09e201cf243adcb87bf33076ede8f022755d0e5425154f` | 1402391604020021652 FRI |
| 16 | play (batch 12, 2 Waits) | `0x040502915caaa81daa7bf202698273bffbb7faf9adc0551a232e1e71aa6c8cd6` | 1371337582470370576 FRI |
| 17 | play (batch 13, 2 Waits) | `0x02e45c8dd237f7f524ac420603b8618a769098967c6c871a23d966a43e8b6a0a` | 1363968890819298573 FRI |
| 18 | play (batch 14, 2 Waits) | `0x0587fc956d8c333a56075609b1a90197c718be9be3414c6811f441a4823bfa3f` | 1322580603628697399 FRI |
| 19 | play (batch 15, 2 Waits) | `0x0362f77d76c7e358adaea6050401124b69e402d2430346e59aa5f487fa97c270` | 1368681433373168976 FRI |
| 20 | play (batch 16, 2 Waits) | `0x05a95f7ed65490982ef9760031de86ba84525e05c962ade1aa754408159ffe35` | 1363968890819298573 FRI |
| 21 | play (batch 17, 2 Waits) | `0x053e8fed82cea1b2a81447317b87b733ce5c1916f71a1a0351eaa69674c3e494` | 1322580603628697399 FRI |
| 22 | play (batch 18, 2 Waits) | `0x064cc792af52cc090c861e6b12d9ce21243416c12e30277435beb45d8b1d0716` | 1368681433373168976 FRI |

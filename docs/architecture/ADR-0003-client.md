# ADR-0003 — Client technology

| | |
|---|---|
| Status | **Accepted by the owner on 2026-09-28**, subject to spike SPK-6 on real phones |
| Date | 2026-09-28 |
| Decides | Rendering engine and packaging of the client, with mobile as first priority |

## Context

- Mobile (iOS and Android) is priority one; desktop web is second.
- The game is 2D pixel art on a hex grid, one room on screen, about ten animated actors,
  and **static between two player inputs**.
- The owner's concern: web games in mobile web views heat the phone and drain the
  battery. Candidates named: Phaser, three.js, Unity, Unreal, Bevy.
- The client must run a deterministic simulation mirroring the contracts
  ([ADR-0001](ADR-0001-execution-layer.md)).

## Findings (2026-09-28)

Verified from repositories, official docs and the app stores unless marked otherwise.

### SDK state

| Client family | Dojo SDK | Controller |
|---|---|---|
| Web (TypeScript) | dojo.js 2.0.0, July 2026. **The only SDK on the current Dojo line** | Primary product. Documented Capacitor flow with an official example |
| Unity | v1.7.0, Sept 2025, self-described "early stages". No Android plugin in the repo, iOS build fixes unmerged | C# bindings described as "basic support"; no documentation page |
| Godot | Official repository is empty. Community SDK v0.8.3 (May 2026), self-declared untested | Through the community SDK |
| Bevy | Last commit July 2025, targets Dojo 1.5.1 | None |
| Unreal | No release, outdated README | Browser tab |
| React Native | No SDK; undocumented bindings | Example only, on bindings without releases |

### What shipped games do

Every Dojo game found on a mobile store is **a web client inside a web view**: Nums,
Glitch Bomb and Dope Wars (native shell of 1–3 MB around the web app, iOS only), Jokers of
Neon (Capacitor, iOS and Android). One game is presumed to use Unity; how it handles the
wallet could not be verified. No shipped game was found using native bindings, React
Native, Godot or Bevy with Controller. None of the shipped web-view games uses a canvas
game engine: they are interface-driven.

### Battery and heat

- The documented main cause is **continuous rendering when nothing changes**
  (three.js manual; a 2021 study relayed by Phaser's own news, which notes that Phaser has
  no dirty flag).
- PixiJS 8 documents a manual render loop officially. Phaser 3 and 4 have **no official
  render-on-demand mode**: only loop sleep, pause and a frame-rate limit. Phaser 4 was
  released in April 2026.
- On Android, the frame callback follows the display refresh rate: an uncapped loop runs
  at 90 or 120 Hz on recent phones. iOS web views are capped at 60 Hz.
- The only measurement found is on a laptop. **No study compares web-view games with
  Unity or Godot on phone battery**: the question can only be settled by our own spike.

### Store policy

- Apple guideline 3.1.1: an app may not use cryptocurrencies or wallets to unlock content,
  and owning an NFT may not unlock features in the app. Guideline 4.2: an app must be more
  than a repackaged website. Nothing addresses sponsored fees or session keys.
- Google Play requires a declaration for blockchain content and forbids promoting
  earnings.
- On-chain games in web-view shells did pass Apple's review in 2026 (Nums, Glitch Bomb,
  Dope Wars); their listings do not mention blockchain.
- Consequence for design: adventurers, items or gold as tokens that gate gameplay
  (Q-07) interact with these rules. To examine before deciding Q-07.

### How other on-chain games predict

Every Starknet game whose client could be inspected **mirrors the contract logic by hand**
in TypeScript or JavaScript (Death Mountain, Eternum, Glitch Bomb, Nums, zKube, Dark
Shuffle); none executes Cairo in the client. Two of them (Glitch Bomb, Nums) have an
offline engine with tests labelled after the Cairo functions they mirror, ported by hand.
**No shared test vectors or differential testing between Cairo and client tests was found
in any of them.** Dojo's own optimistic update is a manual state patch, not logic
execution. Outside Starknet, one library runs the real EVM in the browser and argues
against hand-written reducers because they drift.

Consequence: a hand-written mirror is the proven practice, and generated vectors (SPK-4,
option a) would already be stricter than what shipped games do.

### What a TypeScript mirror must reproduce

| Cairo behaviour | Mirror rule |
|---|---|
| Unsigned and signed integers panic on overflow and underflow | Every operation is range-checked and throws; a throw is a reverted action, never a wrapped value |
| Integer division truncates toward zero; division by zero panics | Same, on `bigint` |
| `felt252` arithmetic is modulo the field prime | Used for hashing and bitmaps only, never for game quantities |
| Poseidon hashing (seeds, Fog draws) | `@scure/starknet` 2.4.0 (August 2026, audited) |
| Room bitmaps of up to 251 bits | `bigint` |

No fixed-point library is needed: the design uses integers and one lookup table.
A Rust core shared through bindings was examined and set aside: the Dojo and Controller
binding stack pins old generator versions and several forks, and no pure C# Poseidon
exists, so it would only pay off if a native engine were chosen.

### Running the Cairo code in the client

The owner's physics game runs the Cairo executable itself in the browser through a Cairo
VM compiled to WebAssembly, which removes the divergence risk by construction. A search
reports that WebAssembly support was removed from the VM in version 3.2.0 (March 2026),
which contradicts that project's own spike on 3.2; to be settled by SPK-4. No production
example of client-side Cairo execution for prediction was found elsewhere.

## Decision

| Layer | Choice |
|---|---|
| Language | TypeScript |
| Chain access | dojo.js, Cartridge Controller (web) |
| Renderer | **PixiJS**, driven **on demand** |
| Interface | DOM (React) over the canvas |
| Packaging | **Capacitor** for iOS and Android; the same build served as a web app for desktop |
| Simulation core | A standalone package with no dependency on rendering or chain access: a TypeScript mirror, or the Cairo code itself in a WebAssembly VM, decided by SPK-4 |

### Why

1. **It is the only path where the chain stack is current and proven on mobile.** Choosing
   Unity or Godot today means maintaining an SDK one version behind, plus wallet
   integration nobody has documented. That is a larger risk to the project than rendering.
2. **The battery problem is a render-loop problem, and this game does not need a loop.**
   Between two inputs nothing moves except idle animations.
3. **One language for simulation and client.** The mirror of the Cairo logic is the main
   technical risk; it should not also cross a language boundary.
4. **Why PixiJS over Phaser**: on-demand rendering is a documented mode; physics, scenes
   and cameras from Phaser are not needed by a one-room tick game.
5. **Why not three.js**: it is a 3D library. It would serve if the game wanted a
   perspective camera, lighting or depth effects on the map; for flat pixel-art sprites it
   brings no sprite sheets, no texture atlases, no pixel-perfect snapping and no 2D
   batching out of the box, all of which would have to be written. It stays the candidate
   if the art direction ever moves to 2.5D.
6. **Phaser remains the closest fallback**: the owner knows it, and it sits on the same
   language and packaging. The renderer is isolated so that switching costs the rendering
   layer only.

### Mobile first, desktop responsive (owner's rule, 2026-09-28)

| | |
|---|---|
| Design target | A phone held in portrait. Every screen is designed for it first |
| Desktop | The same build, responsive: the layout adapts to a wide window; no separate desktop client |
| Input | Touch is the reference. Mouse maps to touch; keyboard shortcuts are additions, never the only way to do something |
| Day-to-day testing | Mostly on the desktop version, in a phone-sized viewport |
| What desktop testing cannot replace | Battery, heat, touch ergonomics, the Controller session flow inside the app shell. These are checked on real phones at SPK-6 and at every phase gate |

### Power budget rules (binding on the client)

| Rule | |
|---|---|
| No permanent render loop | Render on state change and during animations only |
| Idle animations | Capped at 12–15 frames per second, as pixel-art animation is drawn at that rate; pausable in settings |
| Resolution | Render at an integer multiple of the art resolution, capped at 2× device pixels |
| Static layers | Ground, walls and grid baked into one texture per room |
| Background | Everything stops when the app is not visible |
| Network | Subscriptions, not polling |

### Keeping the exit open

The simulation core and the chain layer are independent of PixiJS. If SPK-6 fails, the
renderer is replaced and nothing else. If a native engine becomes necessary later, the
core is the specification to port, with its test vectors.

## Validation — spike SPK-6

Run on at least one mid-range Android phone and one iPhone, inside the Capacitor shell.

| Measure | Pass threshold (proposed) |
|---|---|
| A room of 15 × 15 with 10 animated actors | Steady animation, no dropped input |
| Battery drain over 30 minutes of play | ≤ 8% on the reference phones |
| Temperature after 30 minutes | No thermal throttling reported by the system |
| Idle screen, 5 minutes | Near-zero processor use with idle animations off |
| Controller session flow in the shell | Login once with passkey; then no prompt per action |
| vRNG transaction from the shell | Works through the session |

If the thresholds are not met after applying the power rules: second spike on **Godot**
with the community SDK, then Unity.

## Consequences

| | |
|---|---|
| + | Shortest path to both stores and to the web with one code base |
| + | Follows the Dojo and Controller releases without porting work |
| − | Store review can reject thin web wrappers; the app must bundle its assets and behave as an app. Store policy for on-chain games was not verified and needs its own check before submission (PLAN, HRD-08) |
| − | Performance depends on discipline rather than on the engine; the power rules are audited |
| − | Hosted indexer: Cartridge's documentation was reported to have retired the Slot product in April 2026 and to steer towards self-hosting Torii. To confirm in SPK-5; it may add an operations task |

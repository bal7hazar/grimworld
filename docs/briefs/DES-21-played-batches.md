# DES-21 — Played actions sent in batches

## Agent
Title: `[Opus 5.5] DES-21 played actions sent in batches` · Profile: implement · Branch:
`docs/des-21-played-batches` · A design task: no code.

## Goal
After this task the design says exactly how a fight is played on the client and sent to the
chain in batches (D-133), so that ENG-01 can freeze the entrypoints and CLI-03 can build the
client's side. The player still decides every action, seeing the result of the one before; the
chain still decides every result.

## Context
- **docs/decisions/2026-09-28-sepolia-verdict.md**, section *Decision* (D-133): the two notions
  (a **planned** queue keeps design/02's stop conditions; a **played** batch has no stop condition
  but validity), what is unchanged, and the first answers to settle. **This is the starting point;
  where you depart from a first answer, say why.**
- design/02 (core loop, the queue, its stop conditions, the new section *Played actions are sent in
  batches*), design/04 (combat, the tick, what goblins do after each action), design/11
  (interface), design/08 (multiplayer: constraints M-1…M-6, two adventurers in one instance),
  design/09 (MVP scope).
- ADR-0001 (the chain follows the player; optimistic client; latency figures), ADR-0002 (Fate:
  `fate(domain)`, rule 3, the transaction-hash provider of the MVP), ADR-0005 (burners), ADR-0007,
  D-40 (tactics are deterministic), I-5 (no take-back), D-127 (the tick's flood capped at 15
  layers).
- docs/research/SPK-1-sepolia.md (§4 the non-game part of a transaction, about 1.09M L2 gas; §5 the
  money table: a move in a queue of 10 costs 1.77M against 4.82M alone) and SPK-2's cost note.
- Read `CONTEXT.md` §5 (glossary): new words you need go in your escalations, not in CONTEXT.

## Scope
Settle, each with its reason, and write into the design documents:
1. **What a batch is**: the actions it may hold (moves, attacks, skills, items, waits); what ends
   one; the difference with a planned queue, stated so that a reader of design/02 cannot confuse
   them; whether a planned queue can sit inside a batch.
2. **Size**: 10 to start with, bounded by gas: state the bound as an L2 gas figure from SPK-1's
   and SPK-2's worst tick, and what the client does when the next action would pass it.
3. **When a batch leaves**: full, before a Fate action (sent alone), after a few seconds without
   input (how many, and why), the app going to the background, the end of a fight, leaving an
   instance.
4. **Actions played and not yet sent**: kept on the device, sent at the next launch, lost with the
   device; what the player sees; what happens if the instance's state on chain moved meanwhile.
5. **The chain's answer**: the contract executes the batch in order and stops at the first invalid
   action; how the client learns which ones ran; **rewind** of up to a batch: what the player sees,
   how often it can happen (a difference is a bug or a concurrent action), and the limit.
6. **Two adventurers in one instance** (design/08, M-1…M-6): batches of two players interleave;
   what validity means then, and what the rewind looks like. The MVP is solo; the door stays open.
7. **Security and fairness**: what a player can gain from the delay between playing and sending,
   and from a modified client that computes or reorders batches (the expected answer is nothing:
   rules and state are public; say so with the reasoning). Fate: a draw ends a batch and is sent
   alone; say whether batching changes anything for the transaction-hash provider of the MVP
   (ADR-0002).
8. **The entrypoints that follow**: their shape (names, arguments as a list of actions with a
   bound, what they emit), for ENG-01 to freeze. No Cairo.
9. **What ENG-01 and CLI-03 must do**: one list each, in design/02 (or the document it belongs to).

Where to write: **design/02** (the rule, sections 1 to 8) and **design/11** (what the player sees:
sending, pending actions, rewind, the app closing). Keep both documents' style: tables, short
sentences, the glossary's words.

- Out: code, contracts, ADR edits (propose them under *Escalations*), CONTEXT, PLAN.
- Allowlist: `docs/design/02-core-loop.md`, `docs/design/11-interface.md`. Anything else is an
  escalation.

## Acceptance criteria
- [ ] AC-1 Points 1 to 9 each answered in design/02 or design/11, with the reason; every first
      answer of D-133 kept or replaced with a reason.
- [ ] AC-2 The entrypoints are stated precisely enough for ENG-01 to write their signatures and
      bounds, and the gas bound of a batch is a figure with its source.
- [ ] AC-3 The security section names each way a player could try to profit from batching and why
      it gains nothing, or what closes it.
- [ ] AC-4 No contradiction left with design/02's planned queue, design/04's tick, ADR-0001,
      ADR-0002, M-1…M-6; each ADR change needed is listed under *Escalations*.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7 (the cost table: "—"). Audit: `[GPT-6-Astra]`, design
and security lenses (D-133).

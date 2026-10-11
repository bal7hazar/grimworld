import { describe, expect, it } from "vitest";
import { type PlayAction, encodeAction, encodeBatch } from "./actions";

// No vector table covers the batch felt: these are the words of contracts/logic/tests/
// test_actions.cairo (`test_batch_layout`, `test_batch_refusals`, `test_encoder_refusals`) and
// hand-computed cases from contracts/logic/src/actions.cairo (`encode_action` :45-82,
// `encode_batch` :139-165).

const TWO_128 = 1n << 128n;

describe("encodeAction (actions.cairo :45)", () => {
  it("lays each kind out as the Cairo does", () => {
    expect(encodeAction({ kind: "move", direction: 0 })).toBe(0n);
    expect(encodeAction({ kind: "turn", direction: 3 })).toBe(1n + 3n * 8n); // test_batch_layout
    expect(encodeAction({ kind: "wait" })).toBe(2n);
    expect(encodeAction({ kind: "attack", entity: 9 })).toBe(3n + 9n * 8n);
    expect(encodeAction({ kind: "skill", slot: 2, target: { tile: true, value: 300 } })).toBe(
      4n + 2n * 8n + 64n + 300n * 128n,
    );
    expect(encodeAction({ kind: "skill", slot: 0, target: { tile: false, value: 9 } })).toBe(
      4n + 9n * 128n,
    );
    expect(encodeAction({ kind: "item", slot: 1, entity: 8 })).toBe(5n + 8n + 8n * 32n);
    expect(encodeAction({ kind: "interact", tile: 5 })).toBe(6n + 5n * 8n);
  });

  it("refuses what the decoder refuses (test_encoder_refusals)", () => {
    expect(encodeAction({ kind: "move", direction: 6 })).toBeUndefined();
    expect(encodeAction({ kind: "turn", direction: 255 })).toBeUndefined();
    expect(
      encodeAction({ kind: "skill", slot: 8, target: { tile: false, value: 1 } }),
    ).toBeUndefined();
    expect(encodeAction({ kind: "item", slot: 4, entity: 1 })).toBeUndefined();
    expect(encodeAction({ kind: "move", direction: 5 })).toBe(40n);
    expect(
      encodeAction({ kind: "skill", slot: 7, target: { tile: true, value: 0xffff } }),
    ).toBeDefined();
    expect(encodeAction({ kind: "item", slot: 3, entity: 0xffff })).toBeDefined();
  });

  it("refuses an argument outside its Cairo type (u16 entity, u8 slot)", () => {
    expect(encodeAction({ kind: "attack", entity: 0x10000 })).toBeUndefined();
    expect(encodeAction({ kind: "interact", tile: -1 })).toBeUndefined();
    expect(encodeAction({ kind: "move", direction: 1.5 })).toBeUndefined();
  });
});

describe("encodeBatch (actions.cairo :139)", () => {
  it("gives test_batch_layout's word", () => {
    const actions: PlayAction[] = [
      { kind: "move", direction: 0 },
      { kind: "attack", entity: 9 },
      { kind: "skill", slot: 2, target: { tile: true, value: 300 } },
      { kind: "item", slot: 1, entity: 8 },
      { kind: "interact", tile: 5 },
      { kind: "wait" },
    ];
    const expected =
      6n +
      0n * 0x10n +
      (3n + 9n * 8n) * 0x10000000n + // bit 28
      (4n + 2n * 8n + 64n + 300n * 128n) * 0x10000000000000n + // bit 52
      (5n + 8n + 8n * 32n) * 0x10000000000000000000n + // bit 76
      (6n + 5n * 8n) * 0x10000000000000000000000000n + // bit 100
      2n * TWO_128;
    expect(encodeBatch(actions)).toBe(expected);
  });

  it("puts actions 5 to 9 in the high limb from bit 128 (ten actions at their widest)", () => {
    // test_actions.cairo's `ten()`, each code by hand
    const actions: PlayAction[] = [
      { kind: "move", direction: 0 },
      { kind: "turn", direction: 5 },
      { kind: "wait" },
      { kind: "attack", entity: 0xffff },
      { kind: "skill", slot: 7, target: { tile: true, value: 0xffff } },
      { kind: "item", slot: 3, entity: 0xffff },
      { kind: "interact", tile: 0xe0e0 },
      { kind: "skill", slot: 0, target: { tile: false, value: 9 } },
      { kind: "move", direction: 5 },
      { kind: "attack", entity: 8 },
    ];
    const low = [0n, 41n, 2n, 0x7fffbn, 0x7ffffcn];
    const high = [0x1ffffdn, 0x70706n, 0x484n, 40n, 67n];
    const word = (codes: bigint[], first: bigint) =>
      codes.reduce((sum, code, i) => sum + code * first * (1n << (24n * BigInt(i))), 0n);
    expect(encodeBatch(actions)).toBe(10n + word(low, 0x10n) + word(high, 1n) * TWO_128);
  });

  it("refuses an empty batch, an eleventh action and a batch with a bad action", () => {
    const wait: PlayAction = { kind: "wait" };
    expect(encodeBatch([])).toBeUndefined();
    expect(encodeBatch(Array.from({ length: 11 }, () => wait))).toBeUndefined();
    expect(encodeBatch(Array.from({ length: 10 }, () => wait))).toBeDefined();
    expect(encodeBatch([wait, { kind: "item", slot: 4, entity: 8 }])).toBeUndefined();
  });
});

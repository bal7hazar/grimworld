import { hash } from "starknet";
import { describe, expect, it } from "vitest";
import { DecodeError, SELECTORS, decode, decodeMarketKey } from "./events.ts";
import { ev } from "./testing/fake-node.ts";

const U64_MAX = 2n ** 64n - 1n;
const decodeRaw = (event: ReturnType<typeof ev.located>) =>
  decode(event.source, event.keys, event.data);

describe("the nine frozen events", () => {
  it("are selected by the starknet_keccak of their names", () => {
    expect(SELECTORS.LotPosted).toBe(
      `0x${BigInt(hash.getSelectorFromName("LotPosted")).toString(16)}`,
    );
    // The selector the emitter's probe on the local node reported for RankReached.
    expect(SELECTORS.RankReached).toBe(
      "0x16d3302951d592c1a86710a97d2c13ae4bfd74f29849b1a93f3d556fd98cd7d",
    );
  });

  it("decode the five of Hub at their widest", () => {
    expect(decodeRaw(ev.located(0xffff, 0xffffffff))).toEqual({
      name: "AdventurerLocated",
      hub: 0xffff,
      adventurer: 0xffffffff,
    });
    expect(decodeRaw(ev.title(9, 0xffff, 0xff))).toEqual({
      name: "TitleDisplayed",
      adventurer: 9,
      title: 0xffff,
      tier: 0xff,
    });
    expect(decodeRaw(ev.trial(9, 3, true))).toEqual({
      name: "TrialPassed",
      adventurer: 9,
      rank: 3,
      firstAttempt: true,
    });
    expect(decodeRaw(ev.trial(9, 3, false))).toMatchObject({
      firstAttempt: false,
    });
    expect(decodeRaw(ev.cleared(9, 6))).toEqual({
      name: "DungeonCleared",
      adventurer: 9,
      dungeon: 6,
    });
    expect(decodeRaw(ev.rank(9, 2))).toEqual({
      name: "RankReached",
      adventurer: 9,
      rank: 2,
    });
  });

  it("decode the four of Market, u64 extremes included", () => {
    expect(
      decodeRaw(
        ev.posted(U64_MAX, {
          key: 77n,
          size: 100,
          price: U64_MAX,
          expiry: 2n ** 63n,
          equipment: 0xffffffff,
          modifiers: 2n ** 250n,
        }),
      ),
    ).toEqual({
      name: "LotPosted",
      marketKey: 77n,
      key: { kind: "balance", item: 77 },
      lotSize: 100,
      lot: U64_MAX,
      price: U64_MAX,
      expiry: 2n ** 63n,
      equipment: 0xffffffff,
      modifiers: 2n ** 250n,
    });
    expect(decodeRaw(ev.closed(U64_MAX, true))).toEqual({
      name: "LotClosed",
      lot: U64_MAX,
      sold: true,
    });
    expect(decodeRaw(ev.opened(3, 12, 9))).toEqual({
      name: "TradeOpened",
      invited: 12,
      trade: 3n,
      inviter: 9,
    });
    for (const outcome of [0, 1, 2]) {
      expect(decodeRaw(ev.tradeClosed(3, outcome))).toEqual({
        name: "TradeClosed",
        trade: 3n,
        outcome,
      });
    }
  });

  it("refuse an event of the other contract, an unknown selector, a wrong shape or width", () => {
    const located = ev.located(1, 2);
    expect(() => decode("market", located.keys, located.data)).toThrow(
      DecodeError,
    );
    expect(() => decode("hub", ["0x1234", "0x1"], ["0x2"])).toThrow(
      /unknown event of hub/,
    );
    expect(() => decode("hub", [], [])).toThrow(DecodeError);
    expect(() => decode("hub", located.keys, [...located.data, "0x0"])).toThrow(
      /1 keys and 2 data/,
    );
    expect(() => decode("hub", [located.keys[0]!], located.data)).toThrow(
      DecodeError,
    );
    expect(() => decodeRaw(ev.located(0x10000, 1))).toThrow(/wider than u16/);
    expect(() => decodeRaw(ev.located(1, 2 ** 32))).toThrow(/wider than u32/);
    expect(() => decodeRaw(ev.closed(2n ** 64n, true))).toThrow(
      /wider than u64/,
    );
    const badBool = ev.trial(1, 1, true);
    expect(() =>
      decode("hub", badBool.keys, [badBool.data[0]!, "0x2"]),
    ).toThrow(/not a bool/);
    expect(() => decodeRaw(ev.tradeClosed(1, 3))).toThrow(/not 0, 1 or 2/);
    expect(() => decode("hub", located.keys, ["12"])).toThrow(/not a felt/);
    const prime = 2n ** 251n + 17n * 2n ** 192n + 1n;
    expect(() =>
      decode("hub", located.keys, [`0x${prime.toString(16)}`]),
    ).toThrow(/not a felt/);
  });
});

describe("the market key (ENG-01 §3.4)", () => {
  const equipment = (
    base: number,
    requirement: number,
    rarity: number,
    identified: boolean,
  ) =>
    2n ** 40n +
    BigInt(base) * 2n ** 16n +
    BigInt(requirement) * 2n ** 8n +
    BigInt(rarity) * 2n +
    (identified ? 1n : 0n);

  it("decodes a balance, equipment and a boss item", () => {
    expect(decodeMarketKey(0n)).toEqual({ kind: "balance", item: 0 });
    expect(decodeMarketKey(2n ** 32n - 1n)).toEqual({
      kind: "balance",
      item: 2 ** 32 - 1,
    });
    expect(decodeMarketKey(equipment(7, 12, 3, true))).toEqual({
      kind: "equipment",
      base: 7,
      requirement: 12,
      rarity: 3,
      identified: true,
    });
    expect(decodeMarketKey(equipment(0xffff, 0xff, 0x7f, false))).toEqual({
      kind: "equipment",
      base: 0xffff,
      requirement: 0xff,
      rarity: 0x7f,
      identified: false,
    });
    expect(decodeMarketKey(2n ** 41n + 0xffffn)).toEqual({
      kind: "boss",
      base: 0xffff,
    });
  });

  it("refuses every other felt", () => {
    for (const key of [
      2n ** 32n,
      2n ** 40n - 1n,
      2n ** 40n + 2n ** 32n,
      2n ** 41n + 2n ** 16n,
      2n ** 250n,
    ]) {
      expect(() => decodeMarketKey(key)).toThrow(DecodeError);
    }
  });
});

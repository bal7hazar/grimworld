import { describe, expect, it } from "vitest";
import { tileToPixel } from "../../input/coords";
import { COORD_MAX, sideOf } from "../model";
import { SIDE, kindOf } from "./kinds";
import {
  type PlacedRecord,
  type Placement,
  type RecordResult,
  bridgeAt,
  doorChoices,
  doorSide,
  footprintAt,
  hexesOf,
  overlaps,
  recordOf,
  walkFrom,
} from "./records";

const placed = (result: RecordResult): PlacedRecord => {
  if ("problem" in result) throw new Error(result.problem);
  return result;
};

const problem = (placement: Placement) => {
  const result = recordOf(placement);
  return "problem" in result ? result.problem : null;
};

describe("an NPC's record (ENG-08: template, hex, facing)", () => {
  it("carries the kind's id as the template", () => {
    expect(
      recordOf({ category: "npc", kind: "pawn_axe", hex: { x: 2, y: -3 }, facing: 4 }),
    ).toEqual({
      category: "npc",
      record: { template: "pawn_axe", hex: { x: 2, y: -3 }, facing: 4 },
    });
  });

  it("refuses a facing outside 0 to 5, an unknown kind, a kind of another category", () => {
    const at = { x: 0, y: 0 };
    expect(problem({ category: "npc", kind: "pawn", hex: at, facing: 6 as 0 })).toBe(
      "facing 6 is not 0 to 5",
    );
    expect(problem({ category: "npc", kind: "wizard", hex: at, facing: 0 })).toBe("no kind wizard");
    expect(problem({ category: "npc", kind: "castle", hex: at, facing: 0 })).toBe(
      "castle is a building, not a npc",
    );
  });
});

describe("a building's record (ENG-08: kind, footprint, anchor, door)", () => {
  it("covers its footprint from the anchor, the door on the anchor by default", () => {
    for (const anchor of [
      { x: 4, y: 2 },
      { x: 4, y: 3 },
    ]) {
      const result = placed(recordOf({ category: "building", kind: "barracks", anchor }));
      if (result.category !== "building") throw new Error(result.category);
      const { record } = result;
      expect(record.anchor).toEqual(anchor);
      expect(record.door).toEqual(anchor);
      expect(record.footprint).toHaveLength(5);
      expect(record.footprint).toContainEqual(sideOf(anchor, SIDE.west));
      expect(record.footprint).toContainEqual(sideOf(anchor, SIDE.east));
      expect(record.footprint).toContainEqual(sideOf(anchor, SIDE.northWest));
      expect(record.footprint).toContainEqual(sideOf(anchor, SIDE.northEast));
    }
  });

  it("takes another door on the footprint's border, and refuses one inside or off it", () => {
    const anchor = { x: 0, y: 0 };
    const castle = kindOf("castle");
    if (castle?.category !== "building") throw new Error("castle");
    const footprint = footprintAt(castle, anchor);
    const west = sideOf(anchor, SIDE.west);
    expect(recordOf({ category: "building", kind: "castle", anchor, door: west })).toMatchObject({
      record: { door: west },
    });
    // The hexes behind the front row's middle are surrounded by the footprint.
    const inner = walkFrom(anchor, [SIDE.northWest]);
    expect(doorSide(footprint, inner)).toBeNull();
    expect(problem({ category: "building", kind: "castle", anchor, door: inner })).toBe(
      "the door (0, 1) is not on the footprint's border",
    );
    const off = sideOf(anchor, SIDE.southEast);
    expect(problem({ category: "building", kind: "castle", anchor, door: off })).toMatch(/border/);
    expect(doorChoices(footprint)).toHaveLength(8);
    expect(doorChoices(footprint)).not.toContainEqual(inner);
  });

  it("opens a door toward the viewer first", () => {
    const anchor = { x: 0, y: 0 };
    const hut = kindOf("hut");
    if (hut?.category !== "building") throw new Error("hut");
    expect(doorSide(footprintAt(hut, anchor), anchor)).toBe(SIDE.southEast);
  });
});

describe("a prop's record (ENG-08: kind, hex, optional variant, facing or flip)", () => {
  const hex = { x: 1, y: 1 };

  it("writes a variant only for a prop of several sprites, a flip only when it mirrors", () => {
    expect(placed(recordOf({ category: "prop", kind: "rock", hex, variant: 2 })).record).toEqual({
      kind: "rock",
      hex,
      variant: 2,
    });
    expect(placed(recordOf({ category: "prop", kind: "rock", hex })).record).toEqual({
      kind: "rock",
      hex,
      variant: 0,
    });
    expect(placed(recordOf({ category: "prop", kind: "duck", hex, flip: true })).record).toEqual({
      kind: "duck",
      hex,
      flip: true,
    });
    expect(placed(recordOf({ category: "prop", kind: "duck", hex, flip: false })).record).toEqual({
      kind: "duck",
      hex,
    });
  });

  it("turns a facing prop by facing, never by flip or variant", () => {
    expect(placed(recordOf({ category: "prop", kind: "cannon", hex, facing: 3 })).record).toEqual({
      kind: "cannon",
      hex,
      facing: 3,
    });
    expect(placed(recordOf({ category: "prop", kind: "cannon", hex })).record).toEqual({
      kind: "cannon",
      hex,
      facing: 0,
    });
    expect(problem({ category: "prop", kind: "cannon", hex, flip: true })).toBe(
      "cannon turns by facing, not by flip",
    );
    expect(problem({ category: "prop", kind: "cannon", hex, variant: 1 })).toBe(
      "cannon has no variant",
    );
    expect(problem({ category: "prop", kind: "rock", hex, facing: 1 })).toBe(
      "rock turns by flip, not by facing",
    );
    expect(problem({ category: "prop", kind: "rock", hex, variant: 4 })).toBe(
      "rock has no variant 4",
    );
    expect(problem({ category: "prop", kind: "duck", hex, variant: 1 })).toBe(
      "duck has no variant 1",
    );
  });
});

describe("a bridge's record (D-217: deck hexes and two end hexes)", () => {
  it("runs North-South, its ends in one column on screen, on both row parities", () => {
    const stone = kindOf("stone_bridge");
    if (stone?.category !== "bridge") throw new Error("stone_bridge");
    for (const south of [
      { x: 0, y: 0 },
      { x: 5, y: 7 },
    ]) {
      for (const mirrored of [false, true]) {
        const { deck, ends } = bridgeAt(stone, south, mirrored);
        expect(deck).toHaveLength(1);
        expect(ends[0]).toEqual(south);
        const a = tileToPixel(ends[0]);
        const b = tileToPixel(ends[1]);
        expect(b.x).toBeCloseTo(a.x);
        expect(b.y).toBeLessThan(a.y);
        // The deck between them, half a hex aside.
        const d = tileToPixel(deck[0]!);
        expect(d.y).toBeCloseTo((a.y + b.y) / 2);
        expect(Math.sign(d.x - a.x)).toBe(mirrored ? -1 : 1);
      }
    }
  });

  it("is written as its kind, its deck and its ends", () => {
    const south = { x: 2, y: 2 };
    expect(recordOf({ category: "bridge", kind: "covered_bridge", south })).toEqual({
      category: "bridge",
      record: {
        kind: "covered_bridge",
        deck: [sideOf(south, SIDE.northEast)],
        ends: [south, sideOf(sideOf(south, SIDE.northEast), SIDE.northWest)],
      },
    });
  });
});

describe("hexes, overlaps and the plane's bound", () => {
  it("lists every hex a placement covers", () => {
    const bridge = placed(
      recordOf({ category: "bridge", kind: "stone_bridge", south: { x: 0, y: 0 } }),
    );
    expect(hexesOf(bridge)).toHaveLength(3);
    const castle = placed(
      recordOf({ category: "building", kind: "castle", anchor: { x: 0, y: 0 } }),
    );
    expect(hexesOf(castle)).toHaveLength(10);
    const npc = placed(recordOf({ category: "npc", kind: "pig", hex: { x: 0, y: 2 }, facing: 0 }));
    expect(overlaps(castle, npc)).toBe(true);
    expect(overlaps(castle, bridge)).toBe(true);
    const far = placed(recordOf({ category: "npc", kind: "pig", hex: { x: 9, y: 9 }, facing: 0 }));
    expect(overlaps(castle, far)).toBe(false);
  });

  it("refuses a placement reaching past the plane's bound", () => {
    expect(
      problem({ category: "building", kind: "castle", anchor: { x: 0, y: COORD_MAX } }),
    ).toMatch(/past the plane's bound/);
    expect(
      problem({ category: "npc", kind: "pig", hex: { x: COORD_MAX + 1, y: 0 }, facing: 0 }),
    ).toBe(`(${COORD_MAX + 1}, 0) is past the plane's bound`);
  });
});

import {
  type Content,
  Felts,
  Illegal,
  ORIGIN,
  actionAct,
  memberPlace,
  neighbor,
  reach,
  readContent,
  shapes,
} from "@grimworld/sim";
import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { readWorld } from "./fromWords";
import type { Armed } from "./state";
import { type CombatWorld, adventurerAt, aiming, areaOf, positionOf, tileOf } from "./targeting";
import { type ActRow, actIds, actRow, contentOf, rows } from "./vectors.testkit";

/** Row 0's content, which the rows before RV-03a2's second `content` row (223) read. */
const ACT = contentOf("act.jsonl");
const contents = new Map<number, Content>();
/** The content a row reads: the last `content` row at or before it (row 0, or 223 from RV-03a2). */
function contentAt(id: number): Content {
  let at = id;
  while (rows("act.jsonl")[at]!.fn !== "content") at -= 1;
  let content = contents.get(at);
  if (content === undefined) {
    const read = new Felts(rows("act.jsonl")[at]!.ok!.map(BigInt));
    contents.set(at, (content = readContent(read)));
    read.end();
  }
  return content;
}
const worldOf = (row: ActRow): CombatWorld =>
  readWorld(row.words, contentAt(row.id), row.ground, row.board);
const has = (tiles: readonly Tile[], t: Tile) => tiles.some((u) => u.x === t.x && u.y === t.y);
const tileFrom = (value: number): Tile => ({ x: value % 256, y: Math.floor(value / 256) });
const armedOf = (row: ActRow): Armed => {
  if (row.action.kind === "skill") return { kind: "skill", slot: row.action.slot };
  if (row.action.kind === "item") return { kind: "item", slot: row.action.slot };
  throw new Error(`row ${row.id} plays a ${row.action.kind}`);
};
const outcome = (row: ActRow) => actionAct({ ...row, content: contentAt(row.id) }).outcome;

describe("targeting reads client/sim's aim (§4.1, §4.3)", () => {
  it("on every act.jsonl skill and item row: a target is marked or tinted exactly when aim accepts it", () => {
    let checked = 0;
    for (const id of actIds()) {
      const row = actRow(id);
      if (row.action.kind !== "skill" && row.action.kind !== "item") continue;
      const out = outcome(row);
      const refused = "illegal" in out ? out.illegal : undefined;
      // Only the rows that reach the target's check: accepted, or refused by Target, Reach or Trap
      if (
        refused !== undefined &&
        !([Illegal.Target, Illegal.Reach, Illegal.Trap] as number[]).includes(refused)
      ) {
        continue;
      }
      const cw = worldOf(row);
      const aim = aiming(cw, armedOf(row));
      expect(aim, `row ${id}`).not.toBeNull();
      if (aim!.addressing === "self") {
        expect(refused, `row ${id}: a SELF carrier is aimed at the source`).toBeUndefined();
        continue;
      }
      const action = row.action;
      const tile = action.kind === "skill" ? action.target.tile : aim!.addressing === "tile";
      const value = action.kind === "skill" ? action.target.value : action.entity;
      const accepted = tile
        ? aim!.addressing === "tile" && has(aim!.reach, tileFrom(value))
        : aim!.addressing !== "tile" && aim!.marked.includes(value);
      expect(accepted, `row ${id}`).toBe(refused === undefined);
      checked += 1;
    }
    expect(checked).toBeGreaterThan(40);
  });

  it("a SELF carrier: the adventurer is the target, no range", () => {
    const row = actRow(50);
    const aim = aiming(worldOf(row), armedOf(row))!;
    expect(aim).toMatchObject({ addressing: "self", marked: [0], reach: [] });
  });

  it("a FOE carrier: the goblins in reach are marked, the one out of reach is not", () => {
    // Row 70 plays skill 0 on goblin 8; row 71 the same words on goblin 9, refused with Reach
    const aim = aiming(worldOf(actRow(70)), { kind: "skill", slot: 0 })!;
    expect(aim.addressing).toBe("foe");
    expect(aim.marked).toContain(8);
    expect(aim.marked).not.toContain(9);
    expect(outcome(actRow(71))).toEqual({ illegal: Illegal.Reach });
  });

  it("an ALLY carrier: the other member in reach is marked, no goblin", () => {
    const row = actRow(77);
    const aim = aiming(worldOf(row), armedOf(row))!;
    expect(aim.addressing).toBe("ally");
    expect(aim.marked).toContain(1);
    expect(aim.marked.every((e) => e < 8)).toBe(true);
  });

  it("a TILE carrier: its tile in reach is tinted, the one out of reach is not", () => {
    // Row 88 plays skill 0 on tile 1802; row 89 on 1803, refused with Reach
    const aim = aiming(worldOf(actRow(88)), { kind: "skill", slot: 0 })!;
    expect(aim.addressing).toBe("tile");
    expect(has(aim.reach, tileFrom(1802))).toBe(true);
    expect(has(aim.reach, tileFrom(1803))).toBe(false);
    expect(outcome(actRow(89))).toEqual({ illegal: Illegal.Reach });
  });

  it("a TILE carrier armed at tile (0, 7) skips the off-board tiles of the window", () => {
    // Row 88's world with the adventurer put at the spawn tile (0, 7), seven columns and nine
    // rows into the window: it reaches tiles with a negative x or y, on which `BoardTrait::tile`
    // panics (`u8_add Overflow`)
    const row = actRow(88);
    const board = { ...row.board, x: ORIGIN - 7, y: ORIGIN - 2 };
    const cw = readWorld(row.words, ACT, row.ground, board);
    const member = cw.world.members[0]!;
    const was = memberPlace(member);
    const moved = BigInt(-was.x + 256 * (7 - was.y)) * 2n ** 32n;
    member.words = { ...member.words, state: member.words.state + moved };
    expect(memberPlace(member)).toMatchObject({ x: 0, y: 7 });
    expect(tileOf(board, 0)).toEqual({ x: -7, y: -2 });
    const aim = aiming(cw, { kind: "skill", slot: 0 })!;
    expect(aim.addressing).toBe("tile");
    expect(aim.reach.length + aim.greyed.length).toBeGreaterThan(0);
    for (const t of [...aim.reach, ...aim.greyed]) {
      expect(t.x).toBeGreaterThanOrEqual(0);
      expect(t.y).toBeGreaterThanOrEqual(0);
    }
  });

  it("a TILE carrier armed at tile (240, 240) skips the tiles above 255 - ORIGIN (review t-0009)", () => {
    // Row 88's world with the adventurer put at (240, 240), seven columns and nine rows into the
    // window: it reaches tiles above 240, where `BoardTrait::tile`'s u8 add of ORIGIN overflows
    const top = 255 - ORIGIN;
    const row = actRow(88);
    const board = { ...row.board, x: top - 7 + ORIGIN, y: top - 2 + ORIGIN };
    const cw = readWorld(row.words, ACT, row.ground, board);
    const member = cw.world.members[0]!;
    const was = memberPlace(member);
    const moved = BigInt(top - was.x + 256 * (top - was.y)) * 2n ** 32n;
    member.words = { ...member.words, state: member.words.state + moved };
    expect(memberPlace(member)).toMatchObject({ x: top, y: top });
    expect(tileOf(board, 224)).toEqual({ x: top + 7, y: top + 12 });
    let aim: ReturnType<typeof aiming> = null;
    expect(() => (aim = aiming(cw, { kind: "skill", slot: 0 }))).not.toThrow();
    expect(aim!.addressing).toBe("tile");
    expect(aim!.reach.length + aim!.greyed.length).toBeGreaterThan(0);
    for (const t of [...aim!.reach, ...aim!.greyed]) {
      expect(t.x).toBeLessThanOrEqual(top);
      expect(t.y).toBeLessThanOrEqual(top);
    }
  });

  it("a tile in range but out of sight is greyed, and aim refuses it with Reach", () => {
    // Row 88's TILE skill; a wall put between the adventurer and a tile two steps away
    const row = actRow(88);
    const plain = worldOf(row);
    const from = adventurerAt(plain);
    const aimPlain = aiming(plain, { kind: "skill", slot: 0 })!;
    expect(aimPlain.range).toBeGreaterThanOrEqual(2);
    let tested = 0;
    for (let facing = 0; facing < 6; facing++) {
      const mid = neighbor(from, facing);
      const far = mid === undefined ? undefined : neighbor(mid, facing);
      if (mid === undefined || far === undefined) continue;
      const open = row.board.open;
      if (((open >> BigInt(mid)) & 1n) === 0n || ((open >> BigInt(far)) & 1n) === 0n) continue;
      const board = { ...row.board, open: open - (1n << BigInt(mid)) };
      const cw = readWorld(row.words, ACT, row.ground, board);
      const aim = aiming(cw, { kind: "skill", slot: 0 })!;
      const target = tileOf(board, far);
      expect(has(aim.greyed, target), `facing ${facing}`).toBe(true);
      expect(has(aim.reach, target), `facing ${facing}`).toBe(false);
      const out = actionAct({
        ...row,
        board,
        content: ACT,
        action: {
          kind: "skill",
          slot: 0,
          target: { tile: true, value: target.x + 256 * target.y },
        },
      }).outcome;
      expect(out).toEqual({ illegal: Illegal.Reach });
      tested += 1;
    }
    expect(tested).toBeGreaterThan(0);
  });

  it("a TRAP skill: its tinted tiles are exactly those spot accepts; an occupied tile is refused with Trap", () => {
    // Row 91: a trap skill on tile 1800, a goblin's, refused with Trap; row 93 on 1798, played
    const row = actRow(91);
    const cw = worldOf(row);
    const aim = aiming(cw, armedOf(row))!;
    expect(aim.trap).toBe(true);
    expect(outcome(row)).toEqual({ illegal: Illegal.Trap });
    expect(has(aim.reach, tileFrom(1800))).toBe(false);
    expect(has(aim.greyed, tileFrom(1800))).toBe(true);
    expect(has(aim.reach, tileFrom(1798))).toBe(true);
    expect(outcome(actRow(93))).toEqual({ ticks: 2 });
    // Every tinted tile, played, is not refused with Trap; every greyed one in reach is
    for (const t of [...aim.reach, ...aim.greyed]) {
      const out = actionAct({
        ...row,
        content: ACT,
        action: { kind: "skill", slot: 0, target: { tile: true, value: t.x + 256 * t.y } },
      }).outcome;
      const trapRefused = "illegal" in out && out.illegal === Illegal.Trap;
      if (has(aim.reach, t)) expect(trapRefused, `${t.x},${t.y}`).toBe(false);
      else if (!("illegal" in out && out.illegal === Illegal.Reach)) {
        expect(trapRefused, `${t.x},${t.y}`).toBe(true);
      }
    }
  });
});

describe("the area of a carrier's shapes (§4.2)", () => {
  it("a RING_1 on self: the six tiles around the adventurer, not its own", () => {
    // Skill 40: DAMAGE and a CONDITION, both SELF, RING_1, on foes (act.jsonl's content)
    const at = ACT.skills.findIndex((s) => s.id === 40);
    expect(at).toBeGreaterThanOrEqual(0);
    const row = actRow(50);
    const words = { ...row.words, members: row.words.members.map((m) => ({ ...m })) };
    // Put skill 40 in bar slot 0 (`MemberBar`'s low 16 bits)
    const bar = words.members[0]!.bar;
    words.members[0]!.bar = bar - (bar & 0xffffn) + 40n;
    const cw = readWorld(words, ACT, row.ground, row.board);
    const me = memberPlace(cw.world.members[0]!);
    const area = areaOf(cw, { kind: "skill", slot: 0 }, { x: me.x, y: me.y });
    expect(area.tiles.length).toBeGreaterThan(0);
    expect(area.tiles.length).toBeLessThanOrEqual(6);
    expect(has(area.tiles, { x: me.x, y: me.y })).toBe(false);
    for (const t of area.tiles) {
      expect(reach((1n << 240n) - 1n, adventurerAt(cw), positionOf(cw.board, t), 1)).toBe(true);
    }
    expect(area.marked.every((e) => e >= 8)).toBe(true);
  });

  it("a DISC_1 potion: the centre and its neighbours, the goblins on them marked", () => {
    // Belt slot 0 holds potion 100: DAMAGE on a tile, DISC_1, foes; row 144 throws it on tile 1801
    expect(ACT.potions.find((p) => p.id === 100)).toBeDefined();
    const row = actRow(144);
    const cw = worldOf(row);
    const centre = tileFrom(1801);
    const area = areaOf(cw, { kind: "item", slot: 0 }, centre);
    expect(has(area.tiles, centre)).toBe(true);
    expect(area.tiles.length).toBeGreaterThan(1);
    expect(area.tiles.length).toBeLessThanOrEqual(7);
    // The two goblins the row's potion damaged (its words after) are the ones marked
    const out = actionAct({ ...row, content: ACT });
    const hurt = out.words.goblins
      .filter((g, k) => g.state !== row.words.goblins[k]!.state)
      .map((g) => g.entity);
    expect([...area.marked].sort()).toEqual([...hurt].sort());
  });

  it("tiles are the window's positions read back to the location's", () => {
    const cw = worldOf(actRow(70));
    const me = memberPlace(cw.world.members[0]!);
    expect(tileOf(cw.board, adventurerAt(cw))).toEqual({ x: me.x, y: me.y });
    expect(shapes.DISC_1).toBe(3);
  });
});

import { describe, expect, it } from "vitest";
import { History, UNDO_DEPTH } from "./history";
import { FLOOR, WALL, createMap, indexOf, paint } from "./model";

const newZone = () =>
  createMap({
    kind: "zone",
    name: "Steps",
    location: 1,
    width: 15,
    height: 15,
    biome: "meadow",
    start: "wall",
  });

describe("undo and redo (O-7)", () => {
  it("a stroke is one step, undone and redone whole", () => {
    const doc = newZone();
    const history = new History();
    history.begin();
    for (let x = 0; x < 10; x++) {
      history.record(doc, paint(doc, [{ x, y: 0 }], { layer: "terrain", value: FLOOR }));
    }
    history.end();
    expect(history.steps).toBe(1);
    expect(doc.terrain[indexOf(doc, { x: 9, y: 0 })]).toBe(FLOOR);
    expect(history.undo(doc)).toBe(true);
    expect(doc.terrain.slice(0, 10).every((v) => v === WALL)).toBe(true);
    expect(history.redo(doc)).toBe(true);
    expect(doc.terrain.slice(0, 10).every((v) => v === FLOOR)).toBe(true);
  });

  it("keeps 200 steps: the 201st drops the oldest, and 200 undos bring back the state after it", () => {
    expect(UNDO_DEPTH).toBe(200);
    const doc = newZone();
    const history = new History();
    // 201 steps, each one hex of row 0 and row 1 to floor.
    const tile = (k: number) => ({ x: k % 225, y: Math.floor(k / 225) });
    for (let k = 0; k <= 200; k++) {
      history.record(doc, paint(doc, [tile(k)], { layer: "terrain", value: FLOOR }));
    }
    expect(history.steps).toBe(200);
    let undone = 0;
    while (history.undo(doc)) undone += 1;
    expect(undone).toBe(200);
    // The first step stays: it was dropped from the history, not undone.
    expect(doc.terrain[indexOf(doc, tile(0))]).toBe(FLOOR);
    for (let k = 1; k <= 200; k++) expect(doc.terrain[indexOf(doc, tile(k))]).toBe(WALL);
    // And 200 redos give the 201 hexes again.
    let redone = 0;
    while (history.redo(doc)) redone += 1;
    expect(redone).toBe(200);
    for (let k = 0; k <= 200; k++) expect(doc.terrain[indexOf(doc, tile(k))]).toBe(FLOOR);
  });

  it("a new step clears what was undone; an empty stroke is no step", () => {
    const doc = newZone();
    const history = new History();
    history.record(doc, paint(doc, [{ x: 1, y: 1 }], { layer: "terrain", value: FLOOR }));
    history.undo(doc);
    expect(history.canRedo()).toBe(true);
    history.record(doc, paint(doc, [{ x: 2, y: 2 }], { layer: "terrain", value: FLOOR }));
    expect(history.canRedo()).toBe(false);
    history.begin();
    history.end();
    expect(history.steps).toBe(1);
    expect(history.undo(doc)).toBe(true);
    expect(history.undo(doc)).toBe(false);
  });
});

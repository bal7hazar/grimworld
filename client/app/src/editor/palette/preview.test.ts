import { describe, expect, it } from "vitest";
import { tileToPixel } from "../../input/coords";
import type { Facing } from "../../render/view";
import { sideOf } from "../model";
import { SIDE } from "./kinds";
import { PREVIEW_COLOURS, drawPreview, facingArrow, previewOf } from "./preview";

const at = { x: 3, y: 2 };

describe("the placement preview (CLI-09e)", () => {
  it("shows a building's footprint, its door and the doorstep outside it", () => {
    const preview = previewOf({ category: "building", kind: "barracks", anchor: at });
    expect(preview.problem).toBeNull();
    expect(preview.sprite).toBe("barracks");
    const roles = preview.hexes.map((h) => h.role);
    expect(roles.filter((r) => r === "footprint")).toHaveLength(4);
    expect(roles.filter((r) => r === "door")).toHaveLength(1);
    expect(preview.hexes.find((h) => h.role === "door")?.tile).toEqual(at);
    expect(preview.hexes.find((h) => h.role === "doorstep")?.tile).toEqual(
      sideOf(at, SIDE.southEast),
    );
  });

  it("shows an NPC's facing, mirrored on the West facings", () => {
    const mirrored = ([0, 1, 2, 3, 4, 5] as Facing[]).map(
      (facing) => previewOf({ category: "npc", kind: "lancer", hex: at, facing }).mirrored,
    );
    expect(mirrored).toEqual([false, false, true, true, true, false]);
    const preview = previewOf({ category: "npc", kind: "lancer", hex: at, facing: 1 });
    expect(preview).toMatchObject({
      facing: 1,
      sprite: "npc_lancer",
      hexes: [{ tile: at, role: "hex" }],
    });
  });

  it("shows a prop's variant or facing sprite, and its flip", () => {
    expect(previewOf({ category: "prop", kind: "rock", hex: at, variant: 2 })).toMatchObject({
      sprite: "rock3",
      mirrored: false,
      facing: null,
    });
    expect(previewOf({ category: "prop", kind: "rock", hex: at, flip: true }).mirrored).toBe(true);
    expect(previewOf({ category: "prop", kind: "cannon", hex: at, facing: 2 })).toMatchObject({
      sprite: "cannon_upright",
      mirrored: true,
      facing: 2,
    });
  });

  it("shows a bridge's ends and deck", () => {
    const preview = previewOf({ category: "bridge", kind: "stone_bridge", south: at });
    expect(preview.hexes.map((h) => h.role)).toEqual(["end", "deck", "end"]);
    expect(preview.hexes[0]?.tile).toEqual(at);
  });

  it("shows a refused placement on its hex, with the reason", () => {
    const preview = previewOf({
      category: "building",
      kind: "castle",
      anchor: at,
      door: { x: 40, y: 40 },
    });
    expect(preview.problem).toMatch(/border/);
    expect(preview.hexes).toEqual([{ tile: at, role: "hex" }]);
    expect(previewOf({ category: "npc", kind: "nobody", hex: at, facing: 0 }).problem).toBe(
      "no kind nobody",
    );
  });

  it("points the facing's arrow along the facing", () => {
    const c = tileToPixel(at);
    const tip = (facing: Facing) => {
      const p = facingArrow(at, facing);
      return { x: p[0]! - c.x, y: p[1]! - c.y };
    };
    expect(tip(0).x).toBeGreaterThan(0);
    expect(tip(0).y).toBeCloseTo(0);
    expect(tip(3).x).toBeLessThan(0);
    expect(tip(1).y).toBeLessThan(0); // North-East: up on screen
    expect(tip(5).y).toBeGreaterThan(0); // South-East: down
  });

  it("draws one fill per hex and one for the facing, red when refused", () => {
    const fills: string[] = [];
    const ctx = new Proxy(
      {},
      {
        get: (target: Record<string, unknown>, key: string) =>
          key === "fill" ? () => fills.push(String(target.fillStyle)) : (target[key] ?? (() => {})),
        set: (target: Record<string, unknown>, key: string, value) => {
          target[key] = value;
          return true;
        },
      },
    ) as unknown as CanvasRenderingContext2D;
    const camera = { centre: tileToPixel(at), scale: 1 };
    const viewport = { width: 400, height: 300 };
    drawPreview(
      ctx,
      camera,
      viewport,
      previewOf({ category: "npc", kind: "pig", hex: at, facing: 0 }),
    );
    expect(fills).toEqual([PREVIEW_COLOURS.hex, PREVIEW_COLOURS.facing]);
    fills.length = 0;
    drawPreview(
      ctx,
      camera,
      viewport,
      previewOf({ category: "npc", kind: "x", hex: at, facing: 0 }),
    );
    expect(fills).toEqual([PREVIEW_COLOURS.problem]);
  });
});

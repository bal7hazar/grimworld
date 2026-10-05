import { type Camera, TILE_WIDTH, type Viewport, tileToPixel } from "../../input/coords";
import { isMirrored } from "../../render/facing";
import { hexCorners } from "../../render/ground";
import type { Facing, Tile } from "../../render/view";
import { sideOf } from "../model";
import { kindOf } from "./kinds";
import { type Placement, doorSide, recordOf } from "./records";

/**
 * The placement preview (CLI-09e): what a placement would cover, before the author drops it.
 * Plain shapes over the game's canvas, as the editor's overlays (`../overlay.ts`): a building's
 * footprint with its door and the doorstep outside it, an NPC's or a cannon's facing, a bridge's
 * deck and ends. The sprite itself is the renderer's (part 2).
 */

export type PreviewRole = "hex" | "footprint" | "door" | "doorstep" | "deck" | "end";

export interface Preview {
  readonly hexes: readonly { readonly tile: Tile; readonly role: PreviewRole }[];
  /** The facing drawn on the first hex, or null. */
  readonly facing: Facing | null;
  /** The sprite the placement draws, and whether it is mirrored. */
  readonly sprite: string | null;
  readonly mirrored: boolean;
  /** Why the placement cannot be dropped, or null. */
  readonly problem: string | null;
}

/** The preview of a placement: its record's hexes, or its hex alone with the problem. */
export function previewOf(placement: Placement): Preview {
  const result = recordOf(placement);
  const at =
    placement.category === "building"
      ? placement.anchor
      : placement.category === "bridge"
        ? placement.south
        : placement.hex;
  if ("problem" in result) {
    return {
      hexes: [{ tile: at, role: "hex" }],
      facing: null,
      sprite: null,
      mirrored: false,
      problem: result.problem,
    };
  }
  const kind = kindOf(placement.kind)!;
  switch (result.category) {
    case "npc": {
      const { hex, facing } = result.record;
      const sprite = kind.category === "npc" ? kind.sprite : null;
      return {
        hexes: [{ tile: hex, role: "hex" }],
        facing,
        sprite,
        mirrored: isMirrored(facing),
        problem: null,
      };
    }
    case "prop": {
      const { hex, variant, facing, flip } = result.record;
      if (kind.category !== "prop") break;
      const sprite = kind.art[facing ?? variant ?? 0] ?? null;
      const mirrored = facing !== undefined ? isMirrored(facing) : flip === true;
      return {
        hexes: [{ tile: hex, role: "hex" }],
        facing: facing ?? null,
        sprite,
        mirrored,
        problem: null,
      };
    }
    case "building": {
      const { footprint, door } = result.record;
      const side = doorSide(footprint, door)!;
      const hexes = footprint.map((tile) => ({
        tile,
        role: (tile.x === door.x && tile.y === door.y ? "door" : "footprint") as PreviewRole,
      }));
      hexes.push({ tile: sideOf(door, side), role: "doorstep" });
      const sprite = kind.category === "building" ? kind.sprite : null;
      return { hexes, facing: null, sprite, mirrored: false, problem: null };
    }
    case "bridge": {
      const { deck, ends } = result.record;
      const sprite = kind.category === "bridge" ? kind.sprite : null;
      return {
        hexes: [
          { tile: ends[0], role: "end" },
          ...deck.map((tile) => ({ tile, role: "deck" as PreviewRole })),
          { tile: ends[1], role: "end" },
        ],
        facing: null,
        sprite,
        mirrored: false,
        problem: null,
      };
    }
  }
  return {
    hexes: [{ tile: at, role: "hex" }],
    facing: null,
    sprite: null,
    mirrored: false,
    problem: "unknown kind",
  };
}

export const PREVIEW_COLOURS: Readonly<Record<PreviewRole | "problem" | "facing", string>> = {
  hex: "rgba(255, 255, 255, 0.28)",
  footprint: "rgba(255, 210, 63, 0.3)",
  door: "rgba(255, 140, 40, 0.6)",
  doorstep: "rgba(120, 220, 120, 0.4)",
  deck: "rgba(140, 180, 255, 0.45)",
  end: "rgba(120, 220, 120, 0.4)",
  problem: "rgba(230, 60, 60, 0.5)",
  facing: "#ffffff",
};

/**
 * The facing's arrow on a hex, in world pixels: from the centre toward `facing × 60°`
 * counter-clockwise from East (`render/facing.ts`), three points of a triangle.
 */
export function facingArrow(tile: Tile, facing: Facing): number[] {
  const c = tileToPixel(tile);
  const angle = (-facing * Math.PI) / 3;
  const along = (d: number, side: number) => [
    c.x + d * Math.cos(angle) - side * Math.sin(angle),
    c.y + d * Math.sin(angle) + side * Math.cos(angle),
  ];
  const r = TILE_WIDTH / 2;
  return [...along(r * 0.85, 0), ...along(r * 0.25, -r * 0.3), ...along(r * 0.25, r * 0.3)];
}

/** Draws a preview in the renderer's camera, over the editor's overlays. */
export function drawPreview(
  ctx: CanvasRenderingContext2D,
  camera: Camera,
  viewport: Viewport,
  preview: Preview,
): void {
  const { scale, centre } = camera;
  const ox = viewport.width / 2 - centre.x * scale;
  const oy = viewport.height / 2 - centre.y * scale;
  for (const { tile, role } of preview.hexes) {
    const corners = hexCorners(tileToPixel(tile), -1);
    ctx.beginPath();
    ctx.moveTo(corners[0]! * scale + ox, corners[1]! * scale + oy);
    for (let k = 2; k < 12; k += 2)
      ctx.lineTo(corners[k]! * scale + ox, corners[k + 1]! * scale + oy);
    ctx.closePath();
    ctx.fillStyle = preview.problem ? PREVIEW_COLOURS.problem : PREVIEW_COLOURS[role];
    ctx.fill();
  }
  const first = preview.hexes[0];
  if (preview.facing !== null && first) {
    const p = facingArrow(first.tile, preview.facing);
    ctx.beginPath();
    ctx.moveTo(p[0]! * scale + ox, p[1]! * scale + oy);
    ctx.lineTo(p[2]! * scale + ox, p[3]! * scale + oy);
    ctx.lineTo(p[4]! * scale + ox, p[5]! * scale + oy);
    ctx.closePath();
    ctx.fillStyle = PREVIEW_COLOURS.facing;
    ctx.fill();
  }
}

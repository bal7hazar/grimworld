import { describe, expect, it } from "vitest";
import { libraryFrom } from "../../render/sprites";
import { SYNTHETIC_INDEX, syntheticSheet } from "../../test/syntheticAtlas";
import { kindOf } from "./kinds";
import { thumbFit, thumbOf, thumbsFromLibrary } from "./thumbs";

describe("the palette's thumbnails (CLI-09e)", () => {
  it("shows an NPC's idle frame 0, a prop's first sprite, a building's still", () => {
    expect(thumbOf(kindOf("pawn")!)).toEqual({ sprite: "npc_pawn", animation: "idle", frame: 0 });
    expect(thumbOf(kindOf("warrior")!)).toEqual({
      sprite: "vanguard",
      animation: "idle",
      frame: 0,
    });
    expect(thumbOf(kindOf("rock")!)).toEqual({ sprite: "rock1", animation: "still", frame: 0 });
    expect(thumbOf(kindOf("cannon")!)).toEqual({
      sprite: "cannon_right",
      animation: "still",
      frame: 0,
    });
    expect(thumbOf(kindOf("castle")!)).toEqual({ sprite: "castle", animation: "still", frame: 0 });
    expect(thumbOf(kindOf("stone_bridge")!).sprite).toBe("stone_bridge");
  });

  it("cuts a frame of the loaded atlas from its page", async () => {
    const sheet = await syntheticSheet();
    const library = libraryFrom(SYNTHETIC_INDEX, [sheet]);
    const thumbs = thumbsFromLibrary(library);
    const idle = thumbs("runt", "idle", 0);
    expect(idle).toMatchObject({ x: 0, y: 0, w: 32, h: 40 });
    expect(idle?.image).toBeDefined();
    expect(thumbs("runt", "idle", 2)).toMatchObject({ x: 64, w: 32 });
    expect(thumbs("runt", "move", 1)).toMatchObject({ x: 160 });
    expect(thumbs("runt", "attack", 0)).toBeNull();
    expect(thumbs("castle", "still", 0)).toBeNull();
  });

  it("fits a frame in its box: whole multiples when it fits, shrunk when it does not", () => {
    // A 20 x 10 prop in 48 px: twice its size, centred, on the bottom.
    expect(thumbFit(20, 10, 48)).toEqual({ scale: 2, x: 4, y: 28, w: 40, h: 20 });
    // A 120 x 240 building: half its size.
    expect(thumbFit(120, 240, 48)).toEqual({ scale: 0.2, x: 12, y: 0, w: 24, h: 48 });
    expect(thumbFit(48, 48, 48)).toEqual({ scale: 1, x: 0, y: 0, w: 48, h: 48 });
  });
});

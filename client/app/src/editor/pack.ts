import { TILE_WIDTH } from "../input/coords";
import { isMirrored } from "../render/facing";
import type { Facing, Tile } from "../render/view";
import type { MapMeta } from "./model";
import type { FieldSpec, KindSpec, PlaceChoice, StructureLook } from "./objects";
import {
  BRIDGES,
  BRIDGE_RUNS,
  BUILDINGS,
  type BridgeRun,
  type Category,
  type Kind,
  NPCS,
  PROPS,
  type Placement,
  type RecordResult,
  doorChoices,
  footprintAt,
  kindOf,
  recordOf,
} from "./palette";

/**
 * The pack's objects (CLI-09e part 2): the palette's buildings, characters (NPCs), props and
 * bridges as objects of the editor's map, on a zone or a town. Each is one `MapObject` with its
 * kind's id in `type`; the record ENG-08's export writes for it is `recordFor` (the palette's
 * `recordOf`, in the shapes track game agreed under D-215). Presentation and authoring data, no
 * rule: the converter alone makes a footprint or a blocking prop's hex unwalkable.
 *
 * - A building stands with its base row's hex under its centre on `at` (its anchor); `door` is the
 *   door's offset from the anchor, `"dx,dy"`, a hex of the footprint's border (the anchor, `"0,0"`,
 *   by default).
 * - A character stands on `at`, facing 0 to 5 (East, then counter-clockwise).
 * - A prop stands on `at`: a variant and a mirror for a prop that turns by flip, a facing for one
 *   that turns by facing (the cannon). Both are kept on the object; the record writes the one its
 *   kind uses.
 * - A bridge's southern end is `at`; its deck and northern end follow (D-217). Placed and drawn
 *   only: its walking waits for ENG-08b.
 */
export type PackObject =
  | {
      readonly kind: "building";
      readonly at: Tile;
      readonly type: string;
      readonly depth: number;
      readonly door: string;
      /**
       * The hexes it covers as offsets from the anchor, `"dx,dy;dx,dy;…"`, when a file gave them
       * (an export's footprint, CLI-09c); `""`: drawn from its kind and depth.
       */
      readonly footprint: string;
    }
  | { readonly kind: "npc"; readonly at: Tile; readonly type: string; readonly facing: number }
  | {
      readonly kind: "scenery";
      readonly at: Tile;
      readonly type: string;
      readonly variant: number;
      readonly facing: number;
      readonly mirror: boolean;
    }
  | {
      readonly kind: "bridge";
      readonly at: Tile;
      readonly type: string;
      readonly mirror: boolean;
      readonly run: BridgeRun;
    };

export type PackKind = PackObject["kind"];
type Of<K extends PackKind> = Extract<PackObject, { kind: K }>;

/** The object kind a palette category places. */
export const PACK_KIND_OF: Readonly<Record<Category, PackKind>> = {
  building: "building",
  npc: "npc",
  prop: "scenery",
  bridge: "bridge",
};

export const PACK_KINDS: readonly PackKind[] = ["building", "npc", "scenery", "bridge"];

export function isPack(object: { readonly kind: string }): object is PackObject {
  return (PACK_KINDS as readonly string[]).includes(object.kind);
}

/** The facings by name, as `render/facing.ts` numbers them. */
export const FACING_NAMES: readonly string[] = [
  "East",
  "North-East",
  "North-West",
  "West",
  "South-West",
  "South-East",
];

const DOOR = /^(-?\d+),(-?\d+)$/;

/** The door's hex from its offset, or null when the offset is not `"dx,dy"`. */
export function doorOf(object: Of<"building">): Tile | null {
  const m = DOOR.exec(object.door);
  return m ? { x: object.at.x + Number(m[1]), y: object.at.y + Number(m[2]) } : null;
}

const OFFSETS = /^-?\d+,-?\d+(;-?\d+,-?\d+)*$/;

/** A footprint as the offsets from its anchor the object keeps. */
export function footprintOffsets(anchor: Tile, hexes: readonly Tile[]): string {
  return hexes.map((t) => doorOffset(anchor, t)).join(";");
}

/** The hexes of a footprint the object keeps, or null when it has none (drawn from its kind). */
function givenFootprint(object: Of<"building">): Tile[] | null {
  if (!OFFSETS.test(object.footprint)) return null;
  return object.footprint.split(";").map((o) => {
    const [dx, dy] = o.split(",").map(Number) as [number, number];
    return { x: object.at.x + dx, y: object.at.y + dy };
  });
}

/** A door hex as the offset the object keeps. */
export function doorOffset(anchor: Tile, door: Tile): string {
  return `${door.x - anchor.x},${door.y - anchor.y}`;
}

/** What a pack object would be placed as: the palette's placement. */
export function placementOf(object: PackObject): Placement {
  switch (object.kind) {
    case "building": {
      const door = doorOf(object);
      return {
        category: "building",
        kind: object.type,
        anchor: object.at,
        // An offset that is not one is refused by the record (off the border).
        door: door ?? { x: Number.NaN, y: Number.NaN },
        depth: object.depth,
        ...(givenFootprint(object) ? { footprint: givenFootprint(object)! } : {}),
      };
    }
    case "npc":
      return {
        category: "npc",
        kind: object.type,
        hex: object.at,
        facing: object.facing as Facing,
      };
    case "scenery": {
      const kind = kindOf(object.type);
      if (kind?.category === "prop" && kind.turn === "facing") {
        return {
          category: "prop",
          kind: object.type,
          hex: object.at,
          facing: object.facing as Facing,
        };
      }
      return {
        category: "prop",
        kind: object.type,
        hex: object.at,
        variant: object.variant,
        flip: object.mirror,
      };
    }
    case "bridge":
      return {
        category: "bridge",
        kind: object.type,
        south: object.at,
        mirrored: object.mirror,
        run: object.run,
      };
  }
}

/** The record ENG-08's export writes for a pack object, or what is wrong with it. */
export function recordFor(object: PackObject): RecordResult {
  return recordOf(placementOf(object));
}

/**
 * A building's footprint: the file's when it gave one, else from its kind (its anchor alone for a
 * kind the table lacks).
 */
export function buildingFootprint(object: Of<"building">): Tile[] {
  const given = givenFootprint(object);
  if (given) return given;
  const kind = kindOf(object.type);
  if (kind?.category !== "building") return [object.at];
  const depth = Number.isInteger(object.depth) && object.depth <= 8 ? object.depth : kind.depth;
  return footprintAt(kind, object.at, depth);
}

/** The sprite a prop draws and whether it is mirrored, or null for a kind the table lacks. */
export function propSprite(object: Of<"scenery">): { sprite: string; mirror: boolean } | null {
  const kind = kindOf(object.type);
  if (kind?.category !== "prop") return null;
  if (kind.turn === "facing") {
    const sprite = kind.art[object.facing];
    return sprite ? { sprite, mirror: isMirrored(object.facing as Facing) } : null;
  }
  const sprite = kind.art[object.variant];
  return sprite ? { sprite, mirror: object.mirror } : null;
}

/** Whether a prop's kind blocks: its hex is a wall in the walk's world (ENG-08's kind table). */
export function blocks(object: Of<"scenery">): boolean {
  const kind = kindOf(object.type);
  return kind?.category === "prop" && kind.blocks;
}

const typeField = (label: string, kinds: readonly Kind[]): FieldSpec => ({
  key: "type",
  label,
  type: "choice",
  options: () => kinds.map((k) => [k.id, k.label] as const),
  // A kind the table lacks is read, and E-23 names it: the file stays open.
  valid: (v) => typeof v === "string" && v.length > 0,
});

const FACING: FieldSpec = {
  key: "facing",
  label: "Faces [R]",
  type: "choice",
  numeric: true,
  options: () => FACING_NAMES.map((name, i) => [String(i), name] as const),
  valid: (v) => Number.isInteger(v) && (v as number) >= 0 && (v as number) <= 5,
};

const MIRROR: FieldSpec = { key: "mirror", label: "Mirror [H]", type: "toggle" };

const DOOR_FIELD: FieldSpec = {
  key: "door",
  label: "Door [R]",
  type: "choice",
  // The footprint's border, by hex; a file's door off it stays shown, and E-20 names it.
  options: (_meta: MapMeta, object) => {
    if (object?.kind !== "building") return [];
    return doorChoices(buildingFootprint(object)).map(
      (t) => [doorOffset(object.at, t), `(${t.x}, ${t.y})`] as const,
    );
  },
  valid: (v) => typeof v === "string" && DOOR.test(v),
};

const first = <K extends Kind>(kinds: readonly K[], id: string | undefined): string =>
  id !== undefined && kinds.some((k) => k.id === id) ? id : kinds[0]!.id;

/** The look of a still the renderer draws: a building, a prop, a bridge. */
const still = (
  kind: StructureLook["kind"],
  sprite: string,
  width: number,
  mirror?: boolean,
): StructureLook => ({
  kind,
  sprite,
  width,
  // The shape drawn without the atlas: the table keeps no height (the art's own is drawn).
  height: width,
  shape: "decor",
  // Set whenever the look decides it (a facing prop's facing): the object's flag is then ignored.
  ...(mirror !== undefined ? { mirror } : {}),
});

export const PACK_ROWS: { readonly [K in PackKind]: KindSpec<Of<K>> } = {
  building: {
    map: "both",
    name: "Building",
    letters: () => "B",
    fields: [
      typeField("Building", BUILDINGS),
      { key: "depth", label: "Depth (rows)", type: "number" },
      DOOR_FIELD,
      {
        key: "footprint",
        label: "Footprint",
        type: "choice",
        // A file's footprint stays until the author draws it from the kind again.
        options: (_meta: MapMeta, object) => [
          ...(object?.kind === "building" && object.footprint
            ? [[object.footprint, "As the file gives it"] as const]
            : []),
          ["", "Drawn from its kind"] as const,
        ],
        valid: (v) => v === "" || (typeof v === "string" && OFFSETS.test(v)),
        fallback: "",
      },
    ],
    note: "Its footprint is unwalkable but for its door (ENG-08).",
    create: (choice: PlaceChoice, at: Tile) => {
      const type = first(BUILDINGS, choice.type);
      return {
        kind: "building",
        at,
        type,
        depth: BUILDINGS.find((k) => k.id === type)!.depth,
        door: "0,0",
        footprint: "",
      };
    },
    footprint: buildingFootprint,
    covers: (o) => {
      const door = doorOf(o);
      return buildingFootprint(o).filter((t) => !door || t.x !== door.x || t.y !== door.y);
    },
    look: (o) => {
      const kind = kindOf(o.type);
      return still(
        "building",
        kind?.category === "building" ? kind.sprite : o.type,
        kind?.category === "building" ? kind.width : TILE_WIDTH,
      );
    },
    record: recordFor,
  },
  npc: {
    map: "both",
    name: "Character",
    letters: () => "N",
    fields: [typeField("Character", NPCS), FACING],
    note: "Client-only: a unit template, a hex, a facing (ENG-08).",
    create: (choice: PlaceChoice, at: Tile) => ({
      kind: "npc",
      at,
      type: first(NPCS, choice.type),
      facing: 0,
    }),
    // Its idle loop, played by the renderer (CLI-09e part 3), mirrored on the West facings.
    look: (o) => {
      const kind = kindOf(o.type);
      return {
        kind: "figure",
        sprite: kind?.category === "npc" ? kind.sprite : o.type,
        animation: kind?.category === "npc" ? kind.animation : "idle",
        width: TILE_WIDTH / 2,
        height: TILE_WIDTH / 2,
        mirror: isMirrored(o.facing as Facing),
      };
    },
    record: recordFor,
  },
  scenery: {
    map: "both",
    name: "Pack prop",
    letters: () => "S",
    fields: [
      typeField("Prop", PROPS),
      { key: "variant", label: "Variant", type: "number" },
      FACING,
      MIRROR,
    ],
    create: (choice: PlaceChoice, at: Tile) => ({
      kind: "scenery",
      at,
      type: first(PROPS, choice.type),
      variant: 0,
      facing: 0,
      mirror: false,
    }),
    covers: (o) => (blocks(o) ? [o.at] : []),
    look: (o) => {
      const art = propSprite(o);
      return still("prop", art?.sprite ?? o.type, TILE_WIDTH, art?.mirror);
    },
    record: recordFor,
  },
  bridge: {
    map: "both",
    name: "Bridge",
    letters: () => "Br",
    fields: [
      typeField("Bridge", BRIDGES),
      MIRROR,
      {
        key: "run",
        label: "Runs",
        type: "choice",
        options: () => BRIDGE_RUNS.map((r) => [r, r === "north" ? "North" : "West"] as const),
        fallback: "north",
      },
    ],
    note: "Placed and drawn only: its walking waits for ENG-08b (D-217).",
    create: (choice: PlaceChoice, at: Tile) => ({
      kind: "bridge",
      at,
      type: first(BRIDGES, choice.type),
      mirror: false,
      run: "north",
    }),
    look: (o) => {
      const kind = kindOf(o.type);
      return still("building", kind?.category === "bridge" ? kind.sprite : o.type, TILE_WIDTH * 2);
    },
    record: recordFor,
  },
};

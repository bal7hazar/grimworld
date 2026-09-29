import type { Caste, Facing, Mark, Profession, Tile, TileKind, ViewActor } from "../../render/view";
import { CHUNK, type SandboxWorld } from "../world";

/** A goblin's facing and mark, when the fixture does not give its own. */
export interface GoblinLook {
  readonly facing: Facing;
  readonly mark: Mark | null;
}

const CASTES: Record<string, Caste> = {
  r: "runt",
  s: "skirmisher",
  l: "slinger",
  h: "shaman",
  H: "hobgoblin",
};

export interface AsciiFixture {
  readonly name: string;
  readonly description: string;
  /**
   * The map as it is drawn on screen: the **first line is the highest row** (North) and the
   * **first character the highest `x`** (West), as the library's printer draws a board. `#` wall,
   * `.` floor, `A` the adventurer, `r s l h H` a runt, skirmisher, slinger, shaman, hobgoblin (on
   * floor). Width and height are whole chunks.
   */
  readonly map: readonly string[];
  readonly profession: Profession;
  readonly adventurerFacing: Facing;
  readonly goblins: GoblinLook;
  /** Per goblin, in reading order of the map (first line first, left to right). */
  readonly overrides?: Readonly<Record<number, Partial<GoblinLook>>>;
  /** Chunks `[cx, cy]` not revealed: their tiles are `unrevealed` (D-136). */
  readonly unrevealed?: readonly (readonly [number, number])[];
  readonly path?: readonly Tile[];
}

/** Ids: the adventurer is 1, goblins 2, 3, … in reading order of the map. */
export function fromAscii(fixture: AsciiFixture): SandboxWorld {
  const height = fixture.map.length;
  const width = fixture.map[0]?.length ?? 0;
  if (width % CHUNK !== 0 || height % CHUNK !== 0) {
    throw new Error(`${fixture.name}: ${width} × ${height} is not whole chunks of ${CHUNK}`);
  }
  const kinds: TileKind[] = new Array<TileKind>(width * height).fill("wall");
  const actors: ViewActor[] = [];
  let goblin = 0;
  fixture.map.forEach((line, row) => {
    if (line.length !== width) throw new Error(`${fixture.name}: line ${row} is not ${width} wide`);
    const y = height - 1 - row;
    [...line].forEach((glyph, column) => {
      const x = width - 1 - column;
      kinds[y * width + x] = glyph === "#" ? "wall" : "floor";
      if (glyph === "A") {
        actors.push({
          id: 1,
          side: "adventurer",
          profession: fixture.profession,
          tile: { x, y },
          facing: fixture.adventurerFacing,
          mark: null,
        });
      }
      const caste = CASTES[glyph];
      if (caste) {
        const look = { ...fixture.goblins, ...fixture.overrides?.[goblin] };
        actors.push({ id: 2 + goblin, side: "goblin", caste, tile: { x, y }, ...look });
        goblin += 1;
      } else if (glyph !== "#" && glyph !== "." && glyph !== "A") {
        throw new Error(`${fixture.name}: unknown glyph ${glyph}`);
      }
    });
  });
  for (const [cx, cy] of fixture.unrevealed ?? []) {
    for (let y = cy * CHUNK; y < (cy + 1) * CHUNK; y++) {
      for (let x = cx * CHUNK; x < (cx + 1) * CHUNK; x++) kinds[y * width + x] = "unrevealed";
    }
  }
  if (!actors.some((a) => a.side === "adventurer")) throw new Error(`${fixture.name}: no A`);
  actors.sort((a, b) => a.id - b.id);
  return {
    name: fixture.name,
    description: fixture.description,
    terrain: { width, height, kinds },
    actors,
    adventurerId: 1,
    path: fixture.path ?? [],
  };
}

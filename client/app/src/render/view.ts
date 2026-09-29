/**
 * The renderer's input: what is on screen, as data (ORCH-client-visual §6.3). Nothing here computes
 * a rule of the game; CLI-02 or CLI-03 will produce a `ViewState` from `client/sim`, the sandbox
 * produces it from fixtures.
 *
 * Coordinates are global offset coordinates of the map library (`hexx-cairo`, pointy-top, odd-r,
 * index `i = y * width + x`): `x` grows toward the West, `y` toward the North, and odd rows are
 * shifted half a tile toward increasing `x` (see `input/coords.ts`).
 */

/** A tile of the location, in global offset coordinates. */
export interface Tile {
  readonly x: number;
  readonly y: number;
}

/** A tile of a chunk not revealed is wall for the rules (D-136); it is drawn apart. */
export type TileKind = "floor" | "wall" | "unrevealed";

/**
 * A tile to draw. Whether it is seen now or seen before is not a field: `ViewState.sight` is the
 * one source of truth. A revealed tile in `sight` is seen now (drawn bright); every other revealed
 * tile was seen before (design/18: terrain of every revealed chunk, dimmed beyond sight).
 */
export interface ViewTile extends Tile {
  readonly kind: TileKind;
}

/**
 * The six facings, numbered as the library's `Direction`: 0 East, 1 North-East, 2 North-West,
 * 3 West, 4 South-West, 5 South-East (counter-clockwise from East).
 */
export type Facing = 0 | 1 | 2 | 3 | 4 | 5;

export type Caste = "runt" | "skirmisher" | "slinger" | "shaman" | "hobgoblin";
export type Profession = "vanguard" | "warden" | "cleric" | "arcanist";

/** The mark drawn over a goblin (design/11). A goblin on watch has none. */
export type Mark = "asleep" | "alerted" | "engaged" | "fleeing";

interface ActorBase {
  /** Entity id. */
  readonly id: number;
  readonly tile: Tile;
  readonly facing: Facing;
  readonly mark: Mark | null;
}

export interface ViewAdventurer extends ActorBase {
  readonly side: "adventurer";
  readonly profession: Profession;
}

export interface ViewGoblin extends ActorBase {
  readonly side: "goblin";
  readonly caste: Caste;
}

export type ViewActor = ViewAdventurer | ViewGoblin;

/** The six tiles around an actor, as four arcs (design/04, D-41), already filtered by the producer. */
export interface ViewArcs {
  readonly actorId: number;
  readonly front: readonly Tile[];
  readonly frontSide: readonly Tile[];
  readonly rearSide: readonly Tile[];
  readonly back: readonly Tile[];
}

export interface ViewState {
  /** Every tile to draw: revealed terrain, and the unrevealed tiles next to it. */
  readonly tiles: readonly ViewTile[];
  /** The actors to draw: the adventurer, and the goblins in sight only. */
  readonly actors: readonly ViewActor[];
  readonly adventurerId: number;
  /** The tiles in sight (radius 6 around the adventurer): the only record of "seen now". */
  readonly sight: readonly Tile[];
  /** The arcs of the selected actor, if any. */
  readonly arcs: ViewArcs | null;
  /** The planned path, as tiles, first step first. */
  readonly path: readonly Tile[];
  readonly selectedTile: Tile | null;
}

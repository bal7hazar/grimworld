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
 * What a tile's ground looks like (CLI-03g1): presentation only, never read by a rule. Grass and
 * earth are land; water is never walked (a water tile is `wall`).
 */
export type GroundKind = "grass" | "water" | "earth";

/**
 * A tile to draw. Whether it is seen now or seen before is not a field: `ViewState.sight` is the
 * one source of truth. A revealed tile in `sight` is seen now (drawn bright); every other revealed
 * tile was seen before, dimmed (and in grayscale under `ViewState.fog`). In an instance a tile
 * never in sight is sent as unrevealed, whatever its chunk (CLI-03n, `fog.ts`).
 */
export interface ViewTile extends Tile {
  readonly kind: TileKind;
  /** Its ground (CLI-03g1); absent is grass, so that a view written by hand stays a meadow. */
  readonly ground?: GroundKind;
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

/**
 * A building or a prop standing on the map (CLI-03f): design/10's obstacle object of the wall
 * hexes it covers. It never moves. Drawn from the atlas's still `sprite` at native size, the middle
 * of its base on its hex's centre, or as a shape without the atlas.
 */
export interface ViewStructure {
  /** Unique in the view; breaks a tie of the drawing order. */
  readonly key: string;
  readonly kind: "building" | "prop";
  /** The still's name in the atlas (`tools/art`, roles `building` and `prop`). */
  readonly sprite: string;
  /** The hex its base stands on. */
  readonly at: Tile;
  /** Its native size in art pixels: the shape drawn without the atlas. */
  readonly width: number;
  readonly height: number;
  readonly mirror?: boolean;
  /** The shape without the atlas: a house (the default), a decor house, or the Gate's arch. */
  readonly shape?: "house" | "decor" | "gate";
  /** The wall hexes it stands on: they draw no rock, the structure is their obstacle object. */
  readonly covers: readonly Tile[];
}

export interface ViewState {
  /** Every tile to draw: revealed terrain, and the unrevealed tiles next to it. */
  readonly tiles: readonly ViewTile[];
  /**
   * The actors to draw: the adventurer, and the goblins it has seen the tile of (on an explored
   * tile, CLI-03n); in a hub, every one.
   */
  readonly actors: readonly ViewActor[];
  readonly adventurerId: number;
  /** The tiles in sight (radius 6 around the adventurer): the only record of "seen now". */
  readonly sight: readonly Tile[];
  /** The arcs of the selected actor, if any. */
  readonly arcs: ViewArcs | null;
  /** The planned path, as tiles, first step first. */
  readonly path: readonly Tile[];
  /** Steps of a planned path that a stop or a cancel dropped: they fade out (design/11). */
  readonly dropped: readonly Tile[];
  readonly selectedTile: Tile | null;
  /**
   * Buildings and props (a hub's, CLI-03f); none in a zone. Optional so that a view written by hand
   * (the renderer's tests) stays a zone's; `toView` always gives it.
   */
  readonly structures?: readonly ViewStructure[];
  /**
   * The ground beyond the tiles (CLI-03g1): an island's endless water. Absent: the background,
   * and no lip toward it.
   */
  readonly void?: GroundKind;
  /**
   * Exploration by sight (CLI-03n, D-213): the revealed tiles beyond sight are drawn in grayscale,
   * and the void within `sightRadius` of the adventurer in colour, as the tiles in sight. Absent
   * (a hub, `?fog=full`, a view written by hand): everything in colour.
   */
  readonly fog?: { readonly sightRadius: number };
  /**
   * The tiles as the chain holds them, when `tiles` hides some (an instance, CLI-03n, either
   * `FogMode`): the chunks are baked from these, so that a step that explores rebakes nothing,
   * and the tiles hidden are covered as unrevealed, once a step. Absent: `tiles` are baked.
   */
  readonly revealed?: readonly ViewTile[];
}

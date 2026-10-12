// The simulation core (ADR-0003): the TypeScript mirror of the rules the chain decides, held
// equal to the Cairo code by the vector tables (`src/parity/`, D-140). No randomness, no clock,
// no I/O (mandate §6).

export * from "./felt";
export { EXP2_HIGH, EXP2_LOW, EXP2_X40, exp2 } from "./exp2";
export {
  Arc,
  FAR,
  HEIGHT,
  SIZE,
  WIDTH,
  arc,
  assertValidOpen,
  distance,
  errors as windowErrors,
  facing,
  front,
  inside,
  neighbor,
  range,
  reach,
  shape,
  shapes,
  sight,
  tiles,
} from "./window";
export {
  CRIPPLED_MOVE_TICKS,
  MAX_AWAKE,
  ORIGIN,
  awake,
  board,
  errors as movementErrors,
  flood,
  flood_distance,
  move_ticks,
  next_step,
  origin,
  position,
} from "./movement";
export type { Board, Flood, Origin, Sleeper } from "./movement";
export {
  AXE,
  HitClass,
  errors as hitErrors,
  hitFromFelts,
  level_strength,
  outcomeToFelts,
  resolve,
  weapon_base,
  weapon_strength,
} from "./hit";
export type { Hit, HitOutcome, HitTarget } from "./hit";
export {
  BREW,
  CHEST,
  ENTRY,
  HINT,
  IDENTIFY,
  LIFT,
  LOOT,
  PURPOSES,
  REVEAL,
  RIFT_BOARD,
  derive,
  domain,
} from "./fate";
export {
  LIVE,
  LIVE_HIGH,
  TWO_POW_128,
  byte_at,
  errors as packingErrors,
  field,
  fits,
  join,
  limbs,
  low_field,
  pack_bitmap,
  pack_counter,
  pack_lanes16,
  pack_lanes32,
  peel,
  split,
  u16_at,
  u32_at,
  unpack_bitmap,
  unpack_counter,
  unpack_lanes16,
  unpack_lanes32,
} from "./packing";
export type { Bitmap, Counter, Lanes16, Lanes32 } from "./packing";
export {
  BORDER,
  ChunkKind,
  chunks,
  corner,
  decide,
  errors as revealErrors,
  feed,
  generate,
  hosts,
  inside as chunkInside,
  kind as chunkKind,
  mask,
  member,
  neighbour,
  opening,
  openings,
  outline,
  piece,
  progressToFelts,
  reveal,
  revealable,
  revealedToFelts,
  revealFromFelts,
  root,
  seam,
  side,
  touches,
  word,
} from "./reveal";
export type {
  Features,
  PackPlacement,
  PlacedObject,
  Progress,
  Revealed,
  SetPiece,
  Site,
  Terrain,
} from "./reveal";
export { bits16, bits8, from16, from8 } from "./signed";
export {
  Illegal,
  LAST_TICK,
  NotMirrored,
  board as segmentBoard,
  flag,
  run as runSegment,
  status,
  unported,
} from "./segment";
export { load as loadGoblin, store as storeGoblin } from "./segment/goblin";
export type { Goblin } from "./segment/goblin";
export type { Ran, Segment } from "./segment";
// The seam of the classes a segment calls; their ports replace the parity tests' replayer
export { digest as callDigest } from "./segment/classes";
export type { ActCall, Classes, TicksCall, TriggerCall } from "./segment/classes";
// `TrapLibrary::trigger`, computed (CLI-02g-D): a `Classes.trigger` for a preview
export { triggerClass as trapTrigger } from "./trap";
// `ActionLibrary::act`, computed (CLI-02g-E): a `Classes.act` for a preview
export { actClass as actionAct } from "./action";
// `TickLibrary::ticks`, computed (CLI-02g-F): a `Classes.ticks` for a preview
export { ticksClass as tickTicks } from "./tick";
export {
  Felts,
  readAction,
  readArea,
  readBoard,
  readCall,
  readContent,
  readDone,
  readGround,
  readWords,
  writeAction,
  writeArea,
  writeBoard,
  writeCall,
  writeContent,
  writeDone,
  writeGround,
  writeWords,
} from "./segment/serde";
export type {
  Action,
  Area,
  Board as SegmentBoard,
  Call,
  Done,
  Ground,
  Outcome,
  Target,
} from "./segment/serde";
export type {
  CasteSheet,
  Content,
  GoblinWords,
  MemberWords,
  PotionSheet,
  SkillSheet,
  Words,
} from "./segment/words";
// What the combat UI reads of a world (CLI-05a): the loaders, and each figure's own function, so
// that the client reads what client/sim stores and never re-derives it
export { world as loadWorld } from "./segment/world";
export type { World } from "./segment/world";
export {
  ABSENT,
  ABSENT_LANE,
  NO_SLOT,
  crippled as memberCrippled,
  held as heldEffect,
  load as loadMember,
  place as memberPlace,
  sheets as indexSheets,
} from "./segment/words";
export type { Held, Member, Sheets } from "./segment/words";
export {
  crippled as goblinCrippled,
  effect_of as goblinEffect,
  place as goblinPlace,
  recharge as goblinRecharge,
} from "./segment/goblin";
export { MAX_CLOCK, addressing, filter, holding, rank as barRank, target } from "./executor";
export type { Actor, Carrier } from "./executor";
export {
  aim,
  belt_count,
  energy,
  glyphs,
  is_spell,
  mixed,
  skill_kind as skillKind,
  weapon_required,
} from "./action";
export { belt_item as beltItem, recharge as memberRecharge } from "./body/member";
export { ai as aiState, degeneration, effect_pips, heal, held } from "./segment/tick";
export { object as groundObject, spot } from "./trap";
export { activation, condition } from "./combat";
export { kind } from "./effect";
export type { Entry } from "./effect";

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
  range,
  reach,
  shape,
  shapes,
  sight,
  tiles,
} from "./window";
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

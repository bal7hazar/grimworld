// The world a segment runs over (`types::world::World`) and its load and store
// (`WordsTrait::indexed`, `WorldStoreTrait::store`): every member and every goblin loaded once
// through the content's index, the awake set formed in the same pass and refused above
// `MAX_AWAKE` (`WorldAssert::assert_awake`), the words written back from the loaded actors.

import { panic } from "../felt";
import { type Goblin, load as loadGoblin, store as storeGoblin } from "./goblin";
import {
  type Member,
  type Sheets,
  type Words,
  load as loadMember,
  store as storeMember,
} from "./words";

/** The awake set of one tick (`types::world::MAX_AWAKE`, design/02). */
export const MAX_AWAKE = 8;

export const errors = {
  AWAKE: "tick: more than 8 awake",
} as const;

/** The world a segment runs over (`types::world::World`), its goblins loaded. */
export type World = {
  clock: number;
  members: Member[];
  goblins: Goblin[];
  killed: number[];
  defeated: boolean;
};

/** `WorldAssert::assert_awake`: the awake set (the indexes of the goblins awake) holds at most `MAX_AWAKE`. */
export function assert_awake(woken: readonly number[]): void {
  if (!(woken.length <= MAX_AWAKE)) panic(errors.AWAKE);
}

/**
 * `WordsTrait::load` (and `SegmentTrait::reload`): the world of `words`, each member and each goblin
 * loaded, and the awake set checked.
 */
export function world(words: Words, sheets: Sheets): World {
  const members = words.members.map((member) => loadMember(member, sheets));
  const goblins = words.goblins.map((goblin) => loadGoblin(goblin, sheets));
  assert_awake(goblins.flatMap((goblin, at) => (goblin.awake ? [at] : [])));
  return {
    clock: words.clock,
    members,
    goblins,
    killed: [...words.killed],
    defeated: words.defeated,
  };
}

/** `WorldStoreTrait::store`: the words of the world. */
export function words(world: World): Words {
  return {
    clock: world.clock,
    members: world.members.map(storeMember),
    goblins: world.goblins.map(storeGoblin),
    killed: [...world.killed],
    defeated: world.defeated,
  };
}

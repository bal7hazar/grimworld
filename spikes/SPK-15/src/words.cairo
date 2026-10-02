//! Lever 1 (CBT-02d's escalation 2): the frozen goblins kept as their words until a step or a hook
//! touches them. Main's `WordsTrait::load` decodes every goblin of the call (up to 100, each
//! ~71,000 with its caste's and its effect's lookups) and `WorldStoreTrait::store` re-encodes each
//! (~21,000), though the steps read and write only the awake set (≤ 8). Here:
//! - `lazy_load` decodes the members and the awake set only; the other goblins stay as the words
//! the call
//!   received (`Lazy.words`);
//! - `lazy_store` writes the awake set back into its places and copies every other word unchanged;
//! - perception (`awake`, ENG-07's step 0) reads a frozen goblin's AI state from its words (one
//!   field), decodes a goblin it wakes and encodes one it puts to sleep;
//! - a hook that touches a frozen goblin (§9.2 counts up to 6 an action) decodes it (`thaw`) and
//!   writes it back as words (`set_frozen`), a 4-felt entry where main's array holds 24.
//! What changes: `load`'s contract with perception (it reads words, not `Goblin` values) and the
//! content's index (`Index`), which `load` must keep for the call to decode a goblin later.

use grimworld_logic::models::goblin::{Goblin, GoblinTrait, GoblinWords};
use grimworld_logic::models::member::{Member, MemberTrait, MemberWords};
use grimworld_logic::packing::{P24, field, limbs};
use grimworld_logic::types::tick::{Content, ContentTrait, Index, Sheets, ai};
use grimworld_logic::types::world::{MAX_AWAKE, Words};

/// The call's world with its frozen goblins kept as words.
#[derive(Drop, Debug)]
pub struct Lazy {
    pub clock: u32,
    pub members: Array<Member>,
    /// Every goblin's words, ascending entity id; an awake goblin's entry is stale (its value is in
    /// `awake`).
    pub words: Span<GoblinWords>,
    /// The awake set's indexes in `words`, ascending, and their current values.
    pub woken: Span<u32>,
    pub awake: Array<Goblin>,
    /// Every goblin's AI state, read once from its words (`GoblinState` bits 24–31), for
    /// perception (`awake_single`); an awake goblin's is its value's at the last selection.
    pub ais: Span<u8>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

#[generate_trait]
pub impl LazyImpl of LazyTrait {
    /// The world of the call, its sheets and its index: the members and the awake set decoded, the
    /// other goblins left as words.
    fn lazy_load(self: Words, content: @Content) -> (Lazy, Sheets, Index) {
        let (sheets, mut index) = content.index();
        let mut members = array![];
        for words in self.members {
            members.append(MemberTrait::load(words, ref index, @sheets));
        }
        let mut woken = array![];
        let mut awake = array![];
        let mut ais = array![];
        let mut i = 0;
        for words in self.goblins.span() {
            ais.append(Self::ai_of(words));
            if *words.awake {
                woken.append(i);
                awake.append(GoblinTrait::load(*words, ref index, @sheets));
            }
            i += 1;
        }
        assert(woken.len() <= MAX_AWAKE, 'tick: more than 8 awake');
        let lazy = Lazy {
            clock: self.clock,
            members,
            words: self.goblins.span(),
            woken: woken.span(),
            awake,
            ais: ais.span(),
            killed: self.killed,
            defeated: self.defeated,
        };
        (lazy, sheets, index)
    }

    /// The words of the world: the members and the awake set encoded, every other goblin's words as
    /// they came.
    fn lazy_store(self: Lazy) -> Words {
        let mut members: Array<MemberWords> = array![];
        for member in self.members.span() {
            members.append(member.store());
        }
        let all = self.words;
        let mut goblins = array![];
        let mut from = 0;
        let mut k = 0;
        for index in self.woken {
            goblins.append_span(all.slice(from, *index - from));
            goblins.append(self.awake[k].store());
            from = *index + 1;
            k += 1;
        }
        goblins.append_span(all.slice(from, all.len() - from));
        Words { clock: self.clock, members, goblins, killed: self.killed, defeated: self.defeated }
    }

    /// Goblin `index` decoded from its words (a frozen goblin a hook touches).
    fn thaw(self: @Lazy, index: u32, ref content: Index, sheets: @Sheets) -> Goblin {
        GoblinTrait::load(*self.words[index], ref content, sheets)
    }

    /// A frozen goblin written back as its words: the 4-felt entries rebuilt around it.
    fn set_frozen(ref self: Lazy, index: u32, goblin: Goblin) {
        let all = self.words;
        let mut rebuilt = array![];
        rebuilt.append_span(all.slice(0, index));
        rebuilt.append(goblin.store());
        rebuilt.append_span(all.slice(index + 1, all.len() - index - 1));
        self.words = rebuilt.span();
        let ais = self.ais;
        let mut states = array![];
        states.append_span(ais.slice(0, index));
        states.append(goblin.ai);
        states.append_span(ais.slice(index + 1, ais.len() - index - 1));
        self.ais = states.span();
    }

    /// The awake set's selection (§5.2, main's `TickTrait::awake`) over words: a frozen goblin's
    /// key from its AI state in its words, the set's from their values; the goblins woken are
    /// decoded, the goblins put to sleep encoded, every awake flag written in the words.
    fn awake(ref self: Lazy, distances: Span<u16>, ref content: Index, sheets: @Sheets) {
        let all = self.words;
        let count = all.len();
        assert(distances.len() == count, 'tick: one distance a goblin');
        let woken = self.woken;
        let values = self.awake.span();
        let mut keys: Array<u32> = array![];
        let mut from = 0;
        let mut k = 0;
        for index in woken {
            while from < *index {
                keys.append(Self::word_key(all[from], *distances[from]));
                from += 1;
            }
            keys.append(Self::value_key(values[k], *distances[from]));
            from += 1;
            k += 1;
        }
        while from < count {
            keys.append(Self::word_key(all[from], *distances[from]));
            from += 1;
        }
        let keys = keys.span();
        let (found, last) = SelectionTrait::scan(keys);
        self.place(keys, found, last, ref content, sheets);
    }

    /// The same selection from the AI states `lazy_load` kept (`Lazy.ais`), in one pass over the
    /// keys (`SelectionTrait::single`) where main's makes 8.
    fn awake_single(ref self: Lazy, distances: Span<u16>, ref content: Index, sheets: @Sheets) {
        let all = self.words;
        let count = all.len();
        assert(distances.len() == count, 'tick: one distance a goblin');
        let ais = self.ais;
        let woken = self.woken;
        let values = self.awake.span();
        let mut keys: Array<u32> = array![];
        let mut from = 0;
        let mut k = 0;
        for index in woken {
            while from < *index {
                keys.append(Self::ai_key(*ais[from], *all[from].entity, *distances[from]));
                from += 1;
            }
            keys.append(Self::value_key(values[k], *distances[from]));
            from += 1;
            k += 1;
        }
        while from < count {
            keys.append(Self::ai_key(*ais[from], *all[from].entity, *distances[from]));
            from += 1;
        }
        let keys = keys.span();
        let (found, last) = SelectionTrait::single(keys);
        self.place(keys, found, last, ref content, sheets);
    }

    /// The flags of a selection written: the goblins woken decoded, the goblins put to sleep
    /// encoded, the set's indexes and values formed again.
    fn place(
        ref self: Lazy, keys: Span<u32>, found: u32, last: u32, ref content: Index, sheets: @Sheets,
    ) {
        let all = self.words;
        let count = all.len();
        let woken = self.woken;
        let values = self.awake.span();
        let any = found > 0;
        let mut words = array![];
        let mut now: Array<u32> = array![];
        let mut awake = array![];
        let mut ais: Array<u8> = array![];
        let mut k = 0;
        let mut i = 0;
        while i < count {
            let flag = any && *keys[i] <= last;
            let was = k < woken.len() && *woken[k] == i;
            if was {
                let mut goblin = *values[k];
                ais.append(goblin.ai);
                goblin.awake = flag;
                if flag {
                    now.append(i);
                    awake.append(goblin);
                    let mut entry = *all[i];
                    entry.awake = true;
                    words.append(entry);
                } else {
                    words.append(goblin.store());
                }
                k += 1;
            } else {
                let mut entry = *all[i];
                entry.awake = flag;
                ais.append(*self.ais[i]);
                if flag {
                    now.append(i);
                    awake.append(GoblinTrait::load(entry, ref content, sheets));
                }
                words.append(entry);
            }
            i += 1;
        }
        self.words = words.span();
        self.woken = now.span();
        self.awake = awake;
        self.ais = ais.span();
    }

    /// A goblin's AI state in its words, `GoblinState` bits 24–31.
    #[inline(always)]
    fn ai_of(words: @GoblinWords) -> u8 {
        let (low, _) = limbs(*words.state);
        field(low, P24, 0x100).try_into().unwrap()
    }

    /// A frozen goblin's key from its AI state kept at load.
    #[inline(always)]
    fn ai_key(state: u8, entity: u16, distance: u16) -> u32 {
        if state < ai::DEAD && state != ai::ASLEEP {
            distance.into() * 0x10000 + entity.into()
        } else {
            0xFFFFFFFF
        }
    }

    /// A frozen goblin's key, `distance × 2^16 + entity` if alive and not asleep, else none.
    #[inline(always)]
    fn word_key(words: @GoblinWords, distance: u16) -> u32 {
        let state = Self::ai_of(words);
        if state < ai::DEAD && state != ai::ASLEEP {
            distance.into() * 0x10000 + (*words.entity).into()
        } else {
            0xFFFFFFFF
        }
    }

    /// An awake goblin's key from its value (main's `TickTrait::key`).
    #[inline(always)]
    fn value_key(goblin: @Goblin, distance: u16) -> u32 {
        if goblin.is_alive() && *goblin.ai != ai::ASLEEP {
            distance.into() * 0x10000 + (*goblin.entity).into()
        } else {
            0xFFFFFFFF
        }
    }
}

/// The awake set's selection of the 8 smallest keys (`distance × 2^16 + entity`, unique;
/// `0xFFFFFFFF` for a goblin that cannot wake): how many were found and the largest of them.
#[generate_trait]
pub impl SelectionImpl of SelectionTrait {
    /// Main's (`TickTrait::awake`): 8 scans of every key, each finding the next smallest.
    fn scan(keys: Span<u32>) -> (u32, u32) {
        let mut last: u32 = 0;
        let mut found = 0;
        while found < MAX_AWAKE {
            let mut least: u32 = 0xFFFFFFFF;
            for key in keys {
                if (found == 0 || *key > last) && *key < least {
                    least = *key;
                }
            }
            if least == 0xFFFFFFFF {
                break;
            }
            last = least;
            found += 1;
        }
        (found, last)
    }

    /// One pass: the 8 smallest kept in order, a key below the eighth inserted by a cascade of
    /// exchanges.
    fn single(keys: Span<u32>) -> (u32, u32) {
        let none: u32 = 0xFFFFFFFF;
        let (mut b0, mut b1, mut b2, mut b3) = (none, none, none, none);
        let (mut b4, mut b5, mut b6, mut b7) = (none, none, none, none);
        for key in keys {
            let mut x = *key;
            if x < b7 {
                if x < b0 {
                    let t = b0;
                    b0 = x;
                    x = t;
                }
                if x < b1 {
                    let t = b1;
                    b1 = x;
                    x = t;
                }
                if x < b2 {
                    let t = b2;
                    b2 = x;
                    x = t;
                }
                if x < b3 {
                    let t = b3;
                    b3 = x;
                    x = t;
                }
                if x < b4 {
                    let t = b4;
                    b4 = x;
                    x = t;
                }
                if x < b5 {
                    let t = b5;
                    b5 = x;
                    x = t;
                }
                if x < b6 {
                    let t = b6;
                    b6 = x;
                    x = t;
                }
                b7 = x;
            }
        }
        let best = [b0, b1, b2, b3, b4, b5, b6, b7];
        let mut found = 0;
        let mut last = 0;
        for b in best.span() {
            if *b != none {
                found += 1;
                last = *b;
            }
        }
        (found, last)
    }
}

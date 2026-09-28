//! The measured entrypoints as a native Starknet contract (ADR-0007), ephemeral domain only.
//!
//! Storage, packed by hand (docs/CAIRO.md §4, §5), keyed by instance (M-1):
//! - `chunks`: per chunk, `ChunkLayers { terrain, occupied }`, two slots under one key
//!   `instance * 2^16 + cy * 2^8 + cx`;
//! - `revealed`: per instance, bit `15 cy + cx` of each chunk revealed;
//! - `instances`: per instance, `biome + 2^8 width + 2^16 height` (width and height in chunks);
//! - `adventurers`: per instance, the adventurer's tile `x + 2^8 y`;
//! - `goblins`: per instance, up to 8 goblins in one felt, `x + 2^8 y` in 16 bits each (goblin
//!   `j` at bit 16 j), their count at bit 128. The goblins' other fields are SPK-2's;
//! - `windows`: variant B only, the stored window `{ origin, terrain, occupied }` (D-120 rejected
//!   it; here for comparison);
//! - `standins`: variant S only, SPK-2's stand-in: the terrain of the window already assembled, one
//!   slot per instance (SPK-2 measured its tick on it; S is here so that the two add up).
//! Each is read once and written once per transaction at most.
//!
//! Throwaway: the setup entrypoints are open, there is no owner check and no event.

use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use crate::window::Layers;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ChunkLayers {
    pub terrain: felt252,
    pub occupied: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct StoredWindow {
    pub origin: felt252,
    pub terrain: felt252,
    pub occupied: felt252,
}

#[starknet::interface]
pub trait IMap<T> {
    // Setup, not measured
    fn setup_instance(ref self: T, instance: u32, biome: u8, width: u8, height: u8);
    fn setup_chunk(ref self: T, instance: u32, cx: u8, cy: u8, terrain: felt252, occupied: felt252);
    fn setup_goblins(ref self: T, instance: u32, goblins: Array<(u8, u8)>);
    fn setup_adventurer(ref self: T, instance: u32, x: u8, y: u8);
    fn setup_window(ref self: T, instance: u32);
    fn setup_worst_case(ref self: T, instance: u32, moved: bool, stored: bool);
    fn setup_reveal(ref self: T, instance: u32, biome: u8, case: u8);
    fn setup_standin(ref self: T, instance: u32, moved: bool);
    // Measured
    fn reveal(ref self: T, instance: u32, chunks: Array<(u8, u8)>);
    fn act(ref self: T, instance: u32, direction: u8);
    fn act_stored(ref self: T, instance: u32, direction: u8);
    fn act_standin(ref self: T, instance: u32, direction: u8);
    fn act_deferred(ref self: T, instance: u32, direction: u8);
    // Views
    fn chunk(self: @T, instance: u32, cx: u8, cy: u8) -> Layers;
    fn goblins(self: @T, instance: u32) -> Array<(u8, u8)>;
    fn adventurer(self: @T, instance: u32) -> (u8, u8);
    fn stored_window(self: @T, instance: u32) -> (felt252, Layers);
}

/// Direction of a move: East, NorthEast, NorthWest, West, SouthWest, SouthEast; 6 is no move.
pub const STAY: u8 = 6;

pub mod errors {
    pub const REVEAL_TOO_MANY: felt252 = 'reveal: more than 3 chunks';
    pub const REVEAL_KNOWN: felt252 = 'reveal: chunk already revealed';
    pub const REVEAL_OUTSIDE: felt252 = 'reveal: chunk outside';
    pub const MOVE_BLOCKED: felt252 = 'move: tile blocked';
}

/// Storage key of a chunk.
#[inline(always)]
pub fn chunk_key(instance: u32, cx: u8, cy: u8) -> felt252 {
    instance.into() * 0x10000 + cy.into() * 0x100 + cx.into()
}

/// Global neighbour of a tile (odd-r, the library's directions).
pub fn neighbour(x: u8, y: u8, direction: u8) -> (u8, u8) {
    let (_, odd) = DivRem::div_rem(y, 2);
    let odd = odd == 1;
    match direction {
        0 => (x - 1, y),
        1 => if odd {
            (x, y + 1)
        } else {
            (x - 1, y + 1)
        },
        2 => if odd {
            (x + 1, y + 1)
        } else {
            (x, y + 1)
        },
        3 => (x + 1, y),
        4 => if odd {
            (x + 1, y - 1)
        } else {
            (x, y - 1)
        },
        _ => if odd {
            (x, y - 1)
        } else {
            (x - 1, y - 1)
        },
    }
}

/// Goblins packed in one felt, `x + 2^8 y` in 16 bits each, the count at bit 128.
pub fn pack_goblins(goblins: Span<(u8, u8)>) -> felt252 {
    let mut packed: felt252 = 0;
    let mut factor: felt252 = 1;
    for (x, y) in goblins {
        packed += factor * ((*x).into() + (*y).into() * 0x100);
        factor *= 0x10000;
    }
    packed + goblins.len().into() * 0x100000000000000000000000000000000
}

pub fn unpack_goblins(packed: felt252) -> Array<(u8, u8)> {
    let wide: u256 = packed.into();
    let mut count = wide.high;
    let mut rest = wide.low;
    let mut out: Array<(u8, u8)> = array![];
    while count != 0 {
        count -= 1;
        let (next, y) = DivRem::div_rem(rest, 0x10000);
        let (y, x) = DivRem::div_rem(y, 0x100);
        out.append((x.try_into().unwrap(), y.try_into().unwrap()));
        rest = next;
    }
    out
}

#[starknet::contract]
pub mod Instances {
    use core::poseidon::poseidon_hash_span;
    use origami_hexmap::helpers::bits::Bits;
    use starknet::get_tx_info;
    use crate::boards::CAPPED_TERRAIN;
    use crate::chunk::{Biome, Side, Sides, generate_chunk};
    use crate::fixtures::{
        LOCATION, REVEAL_AROUND, neighbour_terrain, worst_adventurer, worst_chunks, worst_goblins,
    };
    use crate::flood::FLOOD_LAYERS;
    use crate::tick::{ChunkOccupancy, apply_moves, world_tick};
    use crate::window::{Layers, assemble_window, scatter_window, window_chunks, window_origin};
    use super::{
        ChunkLayers, IMap, Map, STAY, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, StoredWindow, chunk_key, errors,
        neighbour, pack_goblins, unpack_goblins,
    };

    #[storage]
    struct Storage {
        instances: Map<u32, felt252>,
        revealed: Map<u32, felt252>,
        chunks: Map<felt252, ChunkLayers>,
        adventurers: Map<u32, felt252>,
        goblins: Map<u32, felt252>,
        windows: Map<u32, StoredWindow>,
        standins: Map<u32, felt252>,
    }

    /// The random word of a reveal: a stand-in for `fate(domain)` reading the transaction hash
    /// (ADR-0002, ADR-0006 §2).
    fn fate(instance: u32, domain: felt252) -> felt252 {
        let hash = get_tx_info().unbox().transaction_hash;
        poseidon_hash_span(array![hash, instance.into(), domain].span())
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        /// The adventurer's tile after its move, and whether it moved.
        fn position(self: @ContractState, instance: u32, direction: u8) -> (u8, u8, bool) {
            let packed: u256 = self.adventurers.read(instance).into();
            let (y, x) = DivRem::div_rem(packed.low, 0x100);
            let (x, y): (u8, u8) = (x.try_into().unwrap(), y.try_into().unwrap());
            if direction == STAY {
                return (x, y, false);
            }
            let (x, y) = neighbour(x, y, direction);
            (x, y, true)
        }

        /// Read the chunks under the window at an origin: 2 or 4 chunks, 2 slots each.
        fn read_chunks(
            self: @ContractState, instance: u32, origin_x: u8, origin_y: u8,
        ) -> (Array<Layers>, ChunkOccupancy) {
            let (cx0, cy0, dx, _) = window_chunks(origin_x, origin_y);
            let mut chunks: Array<Layers> = array![];
            let ll = self.read_chunk(instance, cx0, cy0);
            let ul = self.read_chunk(instance, cx0, cy0 + 1);
            chunks.append(ll);
            chunks.append(ul);
            let (lr, ur) = if dx != 0 {
                let lr = self.read_chunk(instance, cx0 + 1, cy0);
                let ur = self.read_chunk(instance, cx0 + 1, cy0 + 1);
                chunks.append(lr);
                chunks.append(ur);
                (lr.occupied, ur.occupied)
            } else {
                (0, 0)
            };
            let occupancy = ChunkOccupancy {
                cx0, cy0, slots: (ll.occupied, ul.occupied, lr, ur), dirty: 0,
            };
            (chunks, occupancy)
        }

        /// The occupied layer of a chunk if a move touches it (`flag` non-zero), else 0.
        #[inline(always)]
        fn touched(self: @ContractState, instance: u32, cx: u8, cy: u8, flag: u8) -> felt252 {
            if flag != 0 {
                self.chunks.entry(chunk_key(instance, cx, cy)).occupied.read()
            } else {
                0
            }
        }

        #[inline(always)]
        fn read_chunk(self: @ContractState, instance: u32, cx: u8, cy: u8) -> Layers {
            let entry = self.chunks.entry(chunk_key(instance, cx, cy));
            Layers { terrain: entry.terrain.read(), occupied: entry.occupied.read() }
        }

        /// Write back the occupied layers that changed.
        fn write_occupancy(ref self: ContractState, instance: u32, chunks: ChunkOccupancy) {
            let (s0, s1, s2, s3) = chunks.slots;
            let (cx0, cy0, dirty) = (chunks.cx0, chunks.cy0, chunks.dirty);
            if dirty & 1 != 0 {
                self.chunks.entry(chunk_key(instance, cx0, cy0)).occupied.write(s0);
            }
            if dirty & 2 != 0 {
                self.chunks.entry(chunk_key(instance, cx0, cy0 + 1)).occupied.write(s1);
            }
            if dirty & 4 != 0 {
                self.chunks.entry(chunk_key(instance, cx0 + 1, cy0)).occupied.write(s2);
            }
            if dirty & 8 != 0 {
                self.chunks.entry(chunk_key(instance, cx0 + 1, cy0 + 1)).occupied.write(s3);
            }
        }

        /// Move the adventurer if asked: the tile must be walkable and free in the window.
        fn settle(
            ref self: ContractState,
            instance: u32,
            x: u8,
            y: u8,
            moved: bool,
            window: Layers,
            centre: u8,
        ) {
            if !moved {
                return;
            }
            let terrain: u256 = window.terrain.into();
            let occupied: u256 = window.occupied.into();
            assert(
                Bits::get(terrain, centre) && !Bits::get(occupied, centre), errors::MOVE_BLOCKED,
            );
            self.adventurers.write(instance, x.into() + y.into() * 0x100);
        }

        /// What a side of chunk `(cx, cy)` faces, `(nx, ny)` its neighbour on that side.
        fn facing(
            self: @ContractState,
            instance: u32,
            inside: bool,
            nx: u8,
            ny: u8,
            revealed: u256,
            fresh: Span<(u8, u8, felt252)>,
        ) -> Side {
            if !inside {
                return Side::Border;
            }
            if !Bits::get(revealed, 15 * ny + nx) {
                return Side::Open;
            }
            for (fx, fy, terrain) in fresh {
                if *fx == nx && *fy == ny {
                    return Side::Copy(*terrain);
                }
            }
            Side::Copy(self.chunks.entry(chunk_key(instance, nx, ny)).terrain.read())
        }
    }

    #[abi(embed_v0)]
    impl MapImpl of IMap<ContractState> {
        fn setup_instance(
            ref self: ContractState, instance: u32, biome: u8, width: u8, height: u8,
        ) {
            self
                .instances
                .write(instance, biome.into() + width.into() * 0x100 + height.into() * 0x10000);
        }

        fn setup_chunk(
            ref self: ContractState,
            instance: u32,
            cx: u8,
            cy: u8,
            terrain: felt252,
            occupied: felt252,
        ) {
            let entry = self.chunks.entry(chunk_key(instance, cx, cy));
            entry.terrain.write(terrain);
            entry.occupied.write(occupied);
            let revealed: u256 = self.revealed.read(instance).into();
            let bit = 15 * cy + cx;
            if !Bits::get(revealed, bit) {
                self.revealed.write(instance, Bits::to_felt(revealed) + Bits::pow(bit));
            }
        }

        fn setup_goblins(ref self: ContractState, instance: u32, goblins: Array<(u8, u8)>) {
            self.goblins.write(instance, pack_goblins(goblins.span()));
        }

        fn setup_adventurer(ref self: ContractState, instance: u32, x: u8, y: u8) {
            self.adventurers.write(instance, x.into() + y.into() * 0x100);
        }

        fn setup_window(ref self: ContractState, instance: u32) {
            let (x, y, _) = self.position(instance, STAY);
            let (origin_x, origin_y, _) = window_origin(x, y);
            let (chunks, _) = self.read_chunks(instance, origin_x, origin_y);
            let window = assemble_window(origin_x, origin_y, chunks.span());
            self
                .windows
                .write(
                    instance,
                    StoredWindow {
                        origin: origin_x.into() + origin_y.into() * 0x100,
                        terrain: window.terrain,
                        occupied: window.occupied,
                    },
                );
        }

        fn setup_worst_case(ref self: ContractState, instance: u32, moved: bool, stored: bool) {
            for (cx, cy, layers) in worst_chunks() {
                self.setup_chunk(instance, cx, cy, layers.terrain, layers.occupied);
            }
            self.setup_goblins(instance, worst_goblins());
            let (x, y) = worst_adventurer();
            // The move variant starts one tile West and steps East onto the worst-case tile
            let x = if moved {
                x + 1
            } else {
                x
            };
            self.setup_adventurer(instance, x, y);
            if stored {
                self.setup_window(instance);
            }
        }

        /// The stand-in of variant S: the worst-case window's terrain, the goblins, the adventurer.
        fn setup_standin(ref self: ContractState, instance: u32, moved: bool) {
            self.setup_goblins(instance, worst_goblins());
            let (x, y) = worst_adventurer();
            let x = if moved {
                x + 1
            } else {
                x
            };
            self.setup_adventurer(instance, x, y);
            self.standins.write(instance, CAPPED_TERRAIN);
        }

        /// Case 0: nothing revealed around the L of `fixtures`; 1: the 7 chunks around it; 2: those
        /// and B and C, so that A has its 4 neighbours known.
        fn setup_reveal(ref self: ContractState, instance: u32, biome: u8, case: u8) {
            self.setup_instance(instance, biome, LOCATION, LOCATION);
            let kind: Biome = biome.try_into().unwrap();
            if case >= 1 {
                for (cx, cy) in REVEAL_AROUND.span() {
                    let terrain = neighbour_terrain(kind, *cx, *cy);
                    self.setup_chunk(instance, *cx, *cy, terrain, 0);
                }
            }
            if case == 2 {
                for (cx, cy) in array![(3_u8, 2_u8), (2, 3)] {
                    let terrain = neighbour_terrain(kind, cx, cy);
                    self.setup_chunk(instance, cx, cy, terrain, 0);
                }
            }
        }

        /// Reveal up to 3 chunks in one action (design/02 *Simulation budget*): each is generated
        /// from a fresh random word and the edges of its neighbours already generated, then
        /// written; the revealed set is written once.
        fn reveal(ref self: ContractState, instance: u32, chunks: Array<(u8, u8)>) {
            assert(chunks.len() <= 3, errors::REVEAL_TOO_MANY);
            let meta: u256 = self.instances.read(instance).into();
            let (rest, biome) = DivRem::div_rem(meta.low, 0x100);
            let (height, width) = DivRem::div_rem(rest, 0x100);
            let biome: Biome = TryInto::<u8, Biome>::try_into(biome.try_into().unwrap()).unwrap();
            let (width, height): (u8, u8) = (width.try_into().unwrap(), height.try_into().unwrap());
            let mut revealed = self.revealed.read(instance);
            let mut fresh: Array<(u8, u8, felt252)> = array![];
            for (cx, cy) in chunks {
                assert(cx < width && cy < height, errors::REVEAL_OUTSIDE);
                let bit = 15 * cy + cx;
                let known: u256 = revealed.into();
                assert(!Bits::get(known, bit), errors::REVEAL_KNOWN);
                let seen = fresh.span();
                let sides = Sides {
                    east: self
                        .facing(instance, cx > 0, cx - if cx > 0 {
                            1
                        } else {
                            0
                        }, cy, known, seen),
                    west: self.facing(instance, cx + 1 < width, cx + 1, cy, known, seen),
                    south: self
                        .facing(instance, cy > 0, cx, cy - if cy > 0 {
                            1
                        } else {
                            0
                        }, known, seen),
                    north: self.facing(instance, cy + 1 < height, cx, cy + 1, known, seen),
                };
                let key = chunk_key(instance, cx, cy);
                let (_, odd) = DivRem::div_rem(cy, 2);
                let terrain = generate_chunk(fate(instance, key), biome, sides, odd == 1);
                self.chunks.entry(key).terrain.write(terrain);
                revealed += Bits::pow(bit);
                fresh.append((cx, cy, terrain));
            }
            self.revealed.write(instance, revealed);
        }

        /// Variant A (D-120): the window is assembled from the chunks at each tick, never stored.
        fn act(ref self: ContractState, instance: u32, direction: u8) {
            let (x, y, moved) = self.position(instance, direction);
            let (origin_x, origin_y, centre) = window_origin(x, y);
            let (chunks, mut occupancy) = self.read_chunks(instance, origin_x, origin_y);
            let window = assemble_window(origin_x, origin_y, chunks.span());
            self.settle(instance, x, y, moved, window, centre);
            let goblins = unpack_goblins(self.goblins.read(instance));
            let (next, moves, _, _) = world_tick(
                origin_x, origin_y, centre, window, goblins.span(), FLOOD_LAYERS,
            );
            if moves.len() != 0 {
                apply_moves(ref occupancy, moves.span());
                self.write_occupancy(instance, occupancy);
                self.goblins.write(instance, pack_goblins(next.span()));
            }
        }

        /// Variant B (the design D-120 rejected, for comparison): the window is stored; it is
        /// re-centred on the adventurer (assembled from the chunks) when its origin changes, and
        /// written back; otherwise it is read as it is. Chunks' occupied layers are kept up to date
        /// as in A: those a move touches are read, changed and written.
        fn act_stored(ref self: ContractState, instance: u32, direction: u8) {
            let (x, y, moved) = self.position(instance, direction);
            let (origin_x, origin_y, centre) = window_origin(x, y);
            let origin: felt252 = origin_x.into() + origin_y.into() * 0x100;
            let entry = self.windows.entry(instance);
            let stored_origin = entry.origin.read();
            let (window, mut occupancy, recentred) = if stored_origin == origin {
                let window = Layers {
                    terrain: entry.terrain.read(), occupied: entry.occupied.read(),
                };
                let (cx0, cy0, _, _) = window_chunks(origin_x, origin_y);
                (window, ChunkOccupancy { cx0, cy0, slots: (0, 0, 0, 0), dirty: 0 }, false)
            } else {
                let (chunks, occupancy) = self.read_chunks(instance, origin_x, origin_y);
                (assemble_window(origin_x, origin_y, chunks.span()), occupancy, true)
            };
            self.settle(instance, x, y, moved, window, centre);
            let goblins = unpack_goblins(self.goblins.read(instance));
            let (next, moves, _, occupied) = world_tick(
                origin_x, origin_y, centre, window, goblins.span(), FLOOD_LAYERS,
            );
            if moves.len() != 0 {
                if !recentred {
                    // [Effect] Read the occupied layers the moves touch
                    let (cx0, cy0) = (occupancy.cx0, occupancy.cy0);
                    let mut touched: u8 = 0;
                    for m in moves.span() {
                        for (tx, ty) in array![(*m.from_x, *m.from_y), (*m.to_x, *m.to_y)] {
                            let (slot, _) = crate::tick::locate(cx0, cy0, tx, ty);
                            let flag: u8 = match slot {
                                0 => 1,
                                1 => 2,
                                2 => 4,
                                _ => 8,
                            };
                            touched = touched | flag;
                        }
                    }
                    occupancy
                        .slots =
                            (
                                self.touched(instance, cx0, cy0, touched & 1),
                                self.touched(instance, cx0, cy0 + 1, touched & 2),
                                self.touched(instance, cx0 + 1, cy0, touched & 4),
                                self.touched(instance, cx0 + 1, cy0 + 1, touched & 8),
                            );
                }
                apply_moves(ref occupancy, moves.span());
                self.write_occupancy(instance, occupancy);
                self.goblins.write(instance, pack_goblins(next.span()));
            }
            // [Effect] Write the window back: all of it when re-centred, its occupancy otherwise
            if recentred {
                self
                    .windows
                    .write(instance, StoredWindow { origin, terrain: window.terrain, occupied });
            } else if moves.len() != 0 {
                entry.occupied.write(occupied);
            }
        }

        /// Variant S, SPK-2's stand-in: the window's terrain in one slot, the occupancy derived
        /// from the goblins' tiles, no chunk read or write. What A adds to it is the chunked map's
        /// cost.
        fn act_standin(ref self: ContractState, instance: u32, direction: u8) {
            let (x, y, moved) = self.position(instance, direction);
            let (origin_x, origin_y, centre) = window_origin(x, y);
            let goblins = unpack_goblins(self.goblins.read(instance));
            let mut occupied: felt252 = 0;
            for (gx, gy) in goblins.span() {
                if *gx > origin_x && *gy > origin_y && *gx - origin_x < 14 && *gy - origin_y < 15 {
                    occupied += Bits::pow((*gy - origin_y) * 15 + *gx - origin_x);
                }
            }
            let window = Layers { terrain: self.standins.read(instance), occupied };
            self.settle(instance, x, y, moved, window, centre);
            let (next, moves, _, _) = world_tick(
                origin_x, origin_y, centre, window, goblins.span(), FLOOD_LAYERS,
            );
            if moves.len() != 0 {
                self.goblins.write(instance, pack_goblins(next.span()));
            }
        }

        /// Variant B' (stored window as the working copy): while the window stays, the tick reads
        /// and writes only the window; the chunks' occupied layers are brought up to date when it
        /// moves (read, the old window written back into them, written), then it is re-centred.
        fn act_deferred(ref self: ContractState, instance: u32, direction: u8) {
            let (x, y, moved) = self.position(instance, direction);
            let (origin_x, origin_y, centre) = window_origin(x, y);
            let origin: felt252 = origin_x.into() + origin_y.into() * 0x100;
            let entry = self.windows.entry(instance);
            let stored_origin = entry.origin.read();
            if stored_origin == origin {
                let window = Layers {
                    terrain: entry.terrain.read(), occupied: entry.occupied.read(),
                };
                self.settle(instance, x, y, moved, window, centre);
                let goblins = unpack_goblins(self.goblins.read(instance));
                let (next, moves, _, occupied) = world_tick(
                    origin_x, origin_y, centre, window, goblins.span(), FLOOD_LAYERS,
                );
                if moves.len() != 0 {
                    self.goblins.write(instance, pack_goblins(next.span()));
                    entry.occupied.write(occupied);
                }
                return;
            }
            // [Effect] Write the old window's occupancy back into its chunks
            let old: u256 = stored_origin.into();
            let (old_y, old_x) = DivRem::div_rem(old.low, 0x100);
            let (old_x, old_y): (u8, u8) = (old_x.try_into().unwrap(), old_y.try_into().unwrap());
            let (cx0, cy0, dx, _) = window_chunks(old_x, old_y);
            let four = dx != 0;
            let before = (
                self.chunks.entry(chunk_key(instance, cx0, cy0)).occupied.read(),
                self.chunks.entry(chunk_key(instance, cx0, cy0 + 1)).occupied.read(),
                if four {
                    self.chunks.entry(chunk_key(instance, cx0 + 1, cy0)).occupied.read()
                } else {
                    0
                },
                if four {
                    self.chunks.entry(chunk_key(instance, cx0 + 1, cy0 + 1)).occupied.read()
                } else {
                    0
                },
            );
            let after = scatter_window(old_x, old_y, entry.occupied.read(), before);
            let (b0, b1, b2, b3) = before;
            let (a0, a1, a2, a3) = after;
            if a0 != b0 {
                self.chunks.entry(chunk_key(instance, cx0, cy0)).occupied.write(a0);
            }
            if a1 != b1 {
                self.chunks.entry(chunk_key(instance, cx0, cy0 + 1)).occupied.write(a1);
            }
            if four && a2 != b2 {
                self.chunks.entry(chunk_key(instance, cx0 + 1, cy0)).occupied.write(a2);
            }
            if four && a3 != b3 {
                self.chunks.entry(chunk_key(instance, cx0 + 1, cy0 + 1)).occupied.write(a3);
            }
            // [Compute] Re-centre: the same chunks reuse the occupancy in memory
            let (ncx0, ncy0, ndx, _) = window_chunks(origin_x, origin_y);
            let window = if ncx0 == cx0 && ncy0 == cy0 && (ndx != 0) == four {
                let mut chunks: Array<Layers> = array![
                    Layers {
                        terrain: self.chunks.entry(chunk_key(instance, cx0, cy0)).terrain.read(),
                        occupied: a0,
                    },
                    Layers {
                        terrain: self
                            .chunks
                            .entry(chunk_key(instance, cx0, cy0 + 1))
                            .terrain
                            .read(),
                        occupied: a1,
                    },
                ];
                if four {
                    chunks
                        .append(
                            Layers {
                                terrain: self
                                    .chunks
                                    .entry(chunk_key(instance, cx0 + 1, cy0))
                                    .terrain
                                    .read(),
                                occupied: a2,
                            },
                        );
                    chunks
                        .append(
                            Layers {
                                terrain: self
                                    .chunks
                                    .entry(chunk_key(instance, cx0 + 1, cy0 + 1))
                                    .terrain
                                    .read(),
                                occupied: a3,
                            },
                        );
                }
                assemble_window(origin_x, origin_y, chunks.span())
            } else {
                let (chunks, _) = self.read_chunks(instance, origin_x, origin_y);
                assemble_window(origin_x, origin_y, chunks.span())
            };
            self.settle(instance, x, y, moved, window, centre);
            let goblins = unpack_goblins(self.goblins.read(instance));
            let (next, moves, _, occupied) = world_tick(
                origin_x, origin_y, centre, window, goblins.span(), FLOOD_LAYERS,
            );
            if moves.len() != 0 {
                self.goblins.write(instance, pack_goblins(next.span()));
            }
            self
                .windows
                .write(instance, StoredWindow { origin, terrain: window.terrain, occupied });
        }

        fn chunk(self: @ContractState, instance: u32, cx: u8, cy: u8) -> Layers {
            self.read_chunk(instance, cx, cy)
        }

        fn goblins(self: @ContractState, instance: u32) -> Array<(u8, u8)> {
            unpack_goblins(self.goblins.read(instance))
        }

        fn adventurer(self: @ContractState, instance: u32) -> (u8, u8) {
            let (x, y, _) = self.position(instance, STAY);
            (x, y)
        }

        fn stored_window(self: @ContractState, instance: u32) -> (felt252, Layers) {
            let entry = self.windows.entry(instance);
            (
                entry.origin.read(),
                Layers { terrain: entry.terrain.read(), occupied: entry.occupied.read() },
            )
        }
    }
}

//! The ephemeral contract (ADR-0007: two contracts at least, persistent and ephemeral): instances,
//! the adventurer's snapshot, goblins, and the stand-in of the window. The measured actions are the
//! same as part 1's `tick_worst_case` and `queue_moves`, on three goblin layouts (`layout`):
//! - `FELT`: one felt per goblin, packed by hand: the same storage as part 1's goblin model (one
//!   slot, `IntrospectPacked`), hence the controlled comparison (fix loop 1, C-2);
//! - `SLOTS`: one storage struct per goblin, one slot per field (11 slots): a layout experiment;
//! - `PACKED`: the 8 goblins of an instance under one key (mirrors part 1's `Pack`).
//! `checked` adds the owner check of ADR-0007; part 1's systems have none, so the controlled pair
//! runs unchecked and the check is measured apart.

use spk2n::models::{Goblin, Instance, InstanceAdventurer};
use starknet::ContractAddress;

pub const FELT: u8 = 0;
pub const SLOTS: u8 = 1;
pub const PACKED: u8 = 2;

#[starknet::interface]
pub trait IInstances<T> {
    fn set_hub(ref self: T, hub: ContractAddress);
    /// The worst-case tick on an instance, its goblins written in every layout.
    fn setup_worst_case(ref self: T, instance_id: u32, owner: ContractAddress);
    /// The queue on an instance with its first `goblins` goblins, in every layout.
    fn setup_queue(ref self: T, instance_id: u32, goblins: u8, owner: ContractAddress);
    /// An adversarial tick (fixtures::MAZE, SEALED or DEEP), in every layout.
    fn setup_board(ref self: T, instance_id: u32, owner: ContractAddress);
    /// The expensive valid queue (fixtures::SERPENT), in every layout.
    fn setup_serpent(ref self: T, instance_id: u32, owner: ContractAddress);
    fn attack(ref self: T, instance_id: u32, target: u32, layout: u8, checked: bool);
    fn walk(ref self: T, instance_id: u32, moves: Array<u8>, layout: u8, checked: bool) -> u8;
    /// Called by the hub on `enter`: a new instance and the adventurer's snapshot.
    fn open(
        ref self: T, owner: ContractAddress, adventurer: u32, location: u32, x: u8, y: u8, level: u8,
    ) -> u32;
    /// Returned: the instance is closed, the results go to the hub in one call.
    fn leave(ref self: T, instance_id: u32);
    fn instance(self: @T, instance_id: u32) -> Instance;
    fn adventurer(self: @T, instance_id: u32) -> InstanceAdventurer;
    fn goblin(self: @T, instance_id: u32, id: u32) -> Goblin;
    fn goblin_felt(self: @T, instance_id: u32, id: u32) -> Goblin;
    fn goblin_packed(self: @T, instance_id: u32, id: u32) -> Goblin;
    fn entry_draw(self: @T, instance_id: u32) -> felt252;
}

#[starknet::contract]
pub mod Instances {
    use core::num::traits::Zero;
    use spk2n::fate::fate;
    use spk2n::fixtures::{
        COMB, PILLARS, QUEUE_LENGTH, SERPENTINE, START_X, START_Y, adventurer as fixture_adventurer,
        board, queue_goblins, serpent_goblins, window, worst_goblins,
    };
    use super::{FELT, SLOTS};
    use spk2n::models::{
        Goblin, GoblinPack, GoblinSlots, Instance, InstanceAdventurer, from_slots, pack_adventurer,
        pack_goblin, pack_instance, to_slots, unpack_adventurer, unpack_goblin, unpack_instance,
    };
    use spk2n::rules::{attack, in_sight, neighbour, origin_key, window_origin, world_tick};
    use spk2n::board::{bitwise, has};
    use spk2n::systems::hub::{IHubDispatcher, IHubDispatcherTrait};
    use spk2n::tables::WIDTH;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    /// Longest queue (design/02: a cap set by measurement; 10 is the brief's worst case).
    pub const MAX_QUEUE: u32 = 10;
    /// Instances opened from the hub start after the fixtures' ids.
    const FIRST_OPENED: u32 = 100;

    #[storage]
    struct Storage {
        admin: ContractAddress,
        hub: ContractAddress,
        last_id: u32,
        owners: Map<u32, ContractAddress>,
        /// `pack_instance`
        instances: Map<u32, u128>,
        draws: Map<u32, felt252>,
        /// (instance, adventurer) -> `pack_adventurer`
        adventurers: Map<(u32, u32), felt252>,
        goblin_slots: Map<(u32, u32), GoblinSlots>,
        goblin_felts: Map<(u32, u32), felt252>,
        goblin_packs: Map<u32, GoblinPack>,
        /// Stand-in for the window assembled from the chunks (SPK-7): (instance, origin) -> terrain.
        windows: Map<(u32, u16), felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Acted: Acted,
        Opened: Opened,
        Closed: Closed,
    }

    /// A tick-consuming action resolved: the client re-reads its instance by view calls.
    #[derive(Drop, starknet::Event)]
    pub struct Acted {
        #[key]
        pub instance_id: u32,
        pub clock: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Opened {
        #[key]
        pub instance_id: u32,
        pub adventurer: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Closed {
        #[key]
        pub instance_id: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
        self.last_id.write(FIRST_OPENED);
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn only_admin(self: @ContractState) {
            assert(get_caller_address() == self.admin.read(), 'not the admin');
        }

        /// Player entrypoints: the caller owns the instance's adventurer.
        fn owned(self: @ContractState, instance_id: u32) -> Instance {
            assert(self.owners.read(instance_id) == get_caller_address(), 'not the owner');
            unpack_instance(instance_id, self.instances.read(instance_id))
        }

        /// The instance, with the owner check or without it (the controlled comparison, C-2).
        fn load(self: @ContractState, instance_id: u32, checked: bool) -> Instance {
            if checked {
                return self.owned(instance_id);
            }
            unpack_instance(instance_id, self.instances.read(instance_id))
        }

        fn read_goblins(self: @ContractState, layout: u8, instance: @Instance) -> Array<Goblin> {
            if layout == FELT {
                self.read_felts(instance)
            } else if layout == SLOTS {
                self.read_slots(instance)
            } else {
                self.read_pack(instance)
            }
        }

        fn write_goblins(
            ref self: ContractState, layout: u8, instance_id: u32, goblins: Span<Goblin>,
        ) {
            if layout == FELT {
                self.write_felts(goblins)
            } else if layout == SLOTS {
                self.write_slots(goblins)
            } else {
                self.write_pack(instance_id, goblins)
            }
        }

        fn read_adventurer(self: @ContractState, instance: @Instance) -> InstanceAdventurer {
            let (id, owner) = (*instance.id, *instance.adventurer);
            let adventurer = unpack_adventurer(id, owner, self.adventurers.read((id, owner)));
            assert(adventurer.health != 0, 'adventurer defeated');
            adventurer
        }

        fn write_state(
            ref self: ContractState, instance: @Instance, adventurer: @InstanceAdventurer,
        ) {
            self.instances.write(*instance.id, pack_instance(instance));
            self.adventurers.write((*instance.id, *instance.adventurer), pack_adventurer(adventurer));
            self.emit(Acted { instance_id: *instance.id, clock: *instance.clock });
        }

        // Goblin layouts ----------------------------------------------------------------------

        fn read_slots(self: @ContractState, instance: @Instance) -> Array<Goblin> {
            let mut goblins: Array<Goblin> = array![];
            let mut id: u32 = 1;
            while id <= (*instance.goblins).into() {
                let slots = self.goblin_slots.entry((*instance.id, id)).read();
                goblins.append(from_slots(*instance.id, id, slots));
                id += 1;
            }
            goblins
        }

        fn write_slots(ref self: ContractState, goblins: Span<Goblin>) {
            for goblin in goblins {
                self.goblin_slots.entry((*goblin.instance_id, *goblin.id)).write(to_slots(goblin));
            }
        }

        fn read_felts(self: @ContractState, instance: @Instance) -> Array<Goblin> {
            let mut goblins: Array<Goblin> = array![];
            let mut id: u32 = 1;
            while id <= (*instance.goblins).into() {
                let packed = self.goblin_felts.read((*instance.id, id));
                goblins.append(unpack_goblin(*instance.id, id, packed));
                id += 1;
            }
            goblins
        }

        fn write_felts(ref self: ContractState, goblins: Span<Goblin>) {
            for goblin in goblins {
                self.goblin_felts.write((*goblin.instance_id, *goblin.id), pack_goblin(goblin));
            }
        }

        fn read_pack(self: @ContractState, instance: @Instance) -> Array<Goblin> {
            let i = *instance.id;
            if *instance.goblins == 0 {
                return array![];
            }
            assert(*instance.goblins == 8, 'a pack holds 8 goblins');
            let p = self.goblin_packs.entry(i).read();
            array![
                unpack_goblin(i, 1, p.g0), unpack_goblin(i, 2, p.g1), unpack_goblin(i, 3, p.g2),
                unpack_goblin(i, 4, p.g3), unpack_goblin(i, 5, p.g4), unpack_goblin(i, 6, p.g5),
                unpack_goblin(i, 7, p.g6), unpack_goblin(i, 8, p.g7),
            ]
        }

        fn write_pack(ref self: ContractState, instance_id: u32, goblins: Span<Goblin>) {
            if goblins.len() != 8 {
                return;
            }
            self
                .goblin_packs
                .entry(instance_id)
                .write(
                    GoblinPack {
                        g0: pack_goblin(goblins[0]),
                        g1: pack_goblin(goblins[1]),
                        g2: pack_goblin(goblins[2]),
                        g3: pack_goblin(goblins[3]),
                        g4: pack_goblin(goblins[4]),
                        g5: pack_goblin(goblins[5]),
                        g6: pack_goblin(goblins[6]),
                        g7: pack_goblin(goblins[7]),
                    },
                );
        }

        fn write_all_layouts(ref self: ContractState, instance_id: u32, goblins: Span<Goblin>) {
            self.write_slots(goblins);
            self.write_felts(goblins);
            self.write_pack(instance_id, goblins);
        }

        // The actions, on goblins in memory ---------------------------------------------------

        /// The adventurer attacks the adjacent goblin `target`, then one tick runs.
        fn act(
            self: @ContractState,
            ref instance: Instance,
            ref adventurer: InstanceAdventurer,
            goblins: Array<Goblin>,
            target: u32,
        ) -> Array<Goblin> {
            let (x, y, _) = window_origin(adventurer.x, adventurer.y);
            let terrain = self.windows.read((instance.id, origin_key(x, y)));
            let mut attacked: Array<Goblin> = array![];
            for goblin in goblins {
                let mut goblin = goblin;
                if goblin.id == target {
                    attack(ref adventurer, ref goblin);
                }
                attacked.append(goblin);
            }
            let (goblins, _) = world_tick(ref adventurer, attacked.span(), terrain, instance.clock);
            instance.clock += 1;
            goblins
        }

        /// The queue (design/02 *Action batching*), as part 1's `queue_moves.walk`.
        fn walk_on(
            self: @ContractState,
            ref instance: Instance,
            ref adventurer: InstanceAdventurer,
            goblins: Array<Goblin>,
            moves: Array<u8>,
        ) -> (Array<Goblin>, u8) {
            assert(moves.len() <= MAX_QUEUE, 'queue too long');
            let mut goblins = goblins;
            let (x, y, _) = window_origin(adventurer.x, adventurer.y);
            let mut terrain = self.windows.read((instance.id, origin_key(x, y)));
            let mut seen = in_sight(@adventurer, goblins.span());
            let mut done: u8 = 0;
            for direction in moves {
                // [Check] An invalid move drops the rest of the queue, without reverting
                let (nx, ny) = neighbour(adventurer.x, adventurer.y, direction);
                let (ox, oy, _) = window_origin(adventurer.x, adventurer.y);
                let tile = (ny - oy) * WIDTH + (nx - ox);
                if !has(terrain.into(), tile) || occupied(goblins.span(), nx, ny) {
                    break;
                }
                // [Compute] The move, then one tick on the window that followed
                adventurer.x = nx;
                adventurer.y = ny;
                adventurer.facing = direction;
                let (ox, oy, _) = window_origin(nx, ny);
                terrain = self.windows.read((instance.id, origin_key(ox, oy)));
                let (next, hit) = world_tick(
                    ref adventurer, goblins.span(), terrain, instance.clock,
                );
                goblins = next;
                instance.clock += 1;
                done += 1;
                // [Check] Stop conditions: hit by a goblin, a goblin entered sight, defeat
                let now = in_sight(@adventurer, goblins.span());
                let (_, changed, _) = bitwise(seen.into(), now.into());
                let (entered, _, _) = bitwise(changed, now.into());
                seen = now;
                if hit || entered != 0 || adventurer.health == 0 {
                    break;
                }
            }
            (goblins, done)
        }

        fn write_fixture(
            ref self: ContractState,
            instance_id: u32,
            goblins: Span<Goblin>,
            owner: ContractAddress,
            conditions: bool,
        ) {
            let instance = Instance {
                id: instance_id,
                clock: 0,
                location: 10,
                adventurer: 1,
                goblins: goblins.len().try_into().unwrap(),
            };
            self.owners.write(instance_id, owner);
            self.instances.write(instance_id, pack_instance(@instance));
            self
                .adventurers
                .write(
                    (instance_id, 1), pack_adventurer(@fixture_adventurer(instance_id, 1, conditions)),
                );
            self.write_all_layouts(instance_id, goblins);
        }
    }

    /// Whether a goblin alive stands on a tile.
    fn occupied(goblins: Span<Goblin>, x: u8, y: u8) -> bool {
        for goblin in goblins {
            if *goblin.health != 0 && *goblin.x == x && *goblin.y == y {
                return true;
            }
        }
        false
    }

    #[abi(embed_v0)]
    impl InstancesImpl of super::IInstances<ContractState> {
        fn set_hub(ref self: ContractState, hub: ContractAddress) {
            self.only_admin();
            self.hub.write(hub);
        }

        fn setup_worst_case(ref self: ContractState, instance_id: u32, owner: ContractAddress) {
            self.only_admin();
            let goblins = worst_goblins(instance_id);
            self.write_fixture(instance_id, goblins.span(), owner, true);
            let (x, y, _) = window_origin(START_X, START_Y);
            self.windows.write((instance_id, origin_key(x, y)), window(COMB, x, y));
        }

        fn setup_queue(ref self: ContractState, instance_id: u32, goblins: u8, owner: ContractAddress) {
            self.only_admin();
            let mut kept: Array<Goblin> = array![];
            for goblin in queue_goblins(instance_id) {
                if goblin.id <= goblins.into() {
                    kept.append(goblin);
                }
            }
            self.write_fixture(instance_id, kept.span(), owner, false);
            let (x, y, _) = window_origin(START_X, START_Y);
            let mut step: u8 = 0;
            while step <= QUEUE_LENGTH {
                self
                    .windows
                    .write((instance_id, origin_key(x + step, y)), window(PILLARS, x + step, y));
                step += 1;
            }
        }

        fn setup_board(ref self: ContractState, instance_id: u32, owner: ContractAddress) {
            self.only_admin();
            let (terrain, goblins) = board(instance_id);
            self.write_fixture(instance_id, goblins.span(), owner, true);
            let (x, y, _) = window_origin(START_X, START_Y);
            self.windows.write((instance_id, origin_key(x, y)), terrain);
        }

        fn setup_serpent(ref self: ContractState, instance_id: u32, owner: ContractAddress) {
            self.only_admin();
            let goblins = serpent_goblins(instance_id);
            self.write_fixture(instance_id, goblins.span(), owner, false);
            let (x, y, _) = window_origin(START_X, START_Y);
            let mut step: u8 = 0;
            while step <= QUEUE_LENGTH {
                self
                    .windows
                    .write((instance_id, origin_key(x + step, y)), window(SERPENTINE, x + step, y));
                step += 1;
            }
        }

        fn attack(ref self: ContractState, instance_id: u32, target: u32, layout: u8, checked: bool) {
            let mut instance = self.load(instance_id, checked);
            let mut adventurer = self.read_adventurer(@instance);
            let goblins = self.read_goblins(layout, @instance);
            let goblins = self.act(ref instance, ref adventurer, goblins, target);
            self.write_goblins(layout, instance_id, goblins.span());
            self.write_state(@instance, @adventurer);
        }

        fn walk(
            ref self: ContractState, instance_id: u32, moves: Array<u8>, layout: u8, checked: bool,
        ) -> u8 {
            let mut instance = self.load(instance_id, checked);
            let mut adventurer = self.read_adventurer(@instance);
            let goblins = self.read_goblins(layout, @instance);
            let (goblins, done) = self.walk_on(ref instance, ref adventurer, goblins, moves);
            self.write_goblins(layout, instance_id, goblins.span());
            self.write_state(@instance, @adventurer);
            done
        }

        fn open(
            ref self: ContractState,
            owner: ContractAddress,
            adventurer: u32,
            location: u32,
            x: u8,
            y: u8,
            level: u8,
        ) -> u32 {
            assert(get_caller_address() == self.hub.read(), 'not the hub');
            let id = self.last_id.read() + 1;
            self.last_id.write(id);
            let instance = Instance { id, clock: 0, location, adventurer, goblins: 0 };
            let level: u16 = level.into();
            let snapshot = InstanceAdventurer {
                instance_id: id,
                adventurer,
                x,
                y,
                facing: 0,
                health: 100 + 20 * (level - 1),
                max_health: 100 + 20 * (level - 1),
                energy: 60,
                max_energy: 75,
                armor: 80,
                strength: 60,
                damage: 18,
                regeneration: 2,
                energy_regeneration: 3,
                bleeding: 0,
                poison: 0,
                burning: 0,
            };
            self.owners.write(id, owner);
            self.instances.write(id, pack_instance(@instance));
            self.draws.write(id, fate('entry'));
            self.adventurers.write((id, adventurer), pack_adventurer(@snapshot));
            self.emit(Opened { instance_id: id, adventurer });
            id
        }

        fn leave(ref self: ContractState, instance_id: u32) {
            let instance = self.owned(instance_id);
            // [Write] The instance is closed and its state discarded (goblins: none were placed)
            self.owners.write(instance_id, Zero::zero());
            self.instances.write(instance_id, 0);
            self.draws.write(instance_id, 0);
            self.adventurers.write((instance_id, instance.adventurer), 0);
            self.emit(Closed { instance_id });
            // [Call] The results, in one call to the persistent contract
            IHubDispatcher { contract_address: self.hub.read() }
                .apply_results(instance.adventurer, 0);
        }

        fn instance(self: @ContractState, instance_id: u32) -> Instance {
            unpack_instance(instance_id, self.instances.read(instance_id))
        }

        fn adventurer(self: @ContractState, instance_id: u32) -> InstanceAdventurer {
            let instance = unpack_instance(instance_id, self.instances.read(instance_id));
            unpack_adventurer(
                instance_id,
                instance.adventurer,
                self.adventurers.read((instance_id, instance.adventurer)),
            )
        }

        fn goblin(self: @ContractState, instance_id: u32, id: u32) -> Goblin {
            from_slots(instance_id, id, self.goblin_slots.entry((instance_id, id)).read())
        }

        fn goblin_felt(self: @ContractState, instance_id: u32, id: u32) -> Goblin {
            unpack_goblin(instance_id, id, self.goblin_felts.read((instance_id, id)))
        }

        fn goblin_packed(self: @ContractState, instance_id: u32, id: u32) -> Goblin {
            let p = self.goblin_packs.entry(instance_id).read();
            let packed = match id {
                1 => p.g0,
                2 => p.g1,
                3 => p.g2,
                4 => p.g3,
                5 => p.g4,
                6 => p.g5,
                7 => p.g6,
                _ => p.g7,
            };
            unpack_goblin(instance_id, id, packed)
        }

        fn entry_draw(self: @ContractState, instance_id: u32) -> felt252 {
            self.draws.read(instance_id)
        }
    }
}

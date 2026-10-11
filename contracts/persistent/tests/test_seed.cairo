// ENG-03: the test region (`contracts/seed/test-region.json`, described in
// `contracts/seed/README.md`) written through `set_record` and read back through one `bundle`.
// `SeedTrait::write(registry)` is the helper later tests build on (ENG-05, ENG-06): it reads the
// data file, builds every record as its model (`grimworld_logic::models`), packs it through
// `content::Record`, and writes it as the administrator.
//
// snforge's `read_json` puts an object's values in the alphabetical order of its keys, flattens
// nested arrays, drops empty ones and writes a one-element array without its length: the file
// therefore holds, per kind, one flat array (a record a line, fixed columns, never empty) and the
// names of its columns, which are read with a cursor (`Stream`) and checked (`SeedAssert`).
use grimworld_logic::content::{
    CASTE, GATE, LOCATION, OUTLINE, PACK, QUOTAS, REGION, Record, SKILL, SPAWN_TABLE, parts,
};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
use grimworld_logic::models::caste::{Caste, CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::gate::{Gate, GateRecord, GateTrait, kind as gate_kind};
use grimworld_logic::models::location::{Location, LocationRecord, LocationTrait, biome, kind};
use grimworld_logic::models::outline::{CHUNK_SET, Outline, OutlineRecord, OutlineTrait};
use grimworld_logic::models::pack::{Pack, PackCaste, PackRecord, PackTrait};
use grimworld_logic::models::quotas::{
    Quota, QuotaSet, QuotaSetRecord, QuotaSetTrait, kind as quota,
};
use grimworld_logic::models::region::{Region, RegionRecord, RegionTrait};
use grimworld_logic::models::skill::{Skill, SkillRecord, SkillTrait};
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable, SpawnTableRecord, SpawnTableTrait};
use grimworld_logic::packing::Lanes16;
use grimworld_logic::types::effect::{Entry, EntryTrait};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use snforge_std::fs::{FileTrait, read_json};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ADMIN: felt252 = 0xad;
/// Columns of a location's row, and where its 15 set pieces start.
const LOCATION_COLUMNS: u32 = 31;
const SET_PIECES_AT: u32 = 16;
/// Columns of an outline's row, and of a gate's.
const OUTLINE_COLUMNS: u32 = 17;
const GATE_COLUMNS: u32 = 10;
/// Columns of a pack template's row, a spawn table's and a location's quotas' (ENG-05).
const PACK_COLUMNS: u32 = 17;
const SPAWN_TABLE_COLUMNS: u32 = 16;
const QUOTA_COLUMNS: u32 = 19;
/// Columns of a skill's row (three entries of 12) and of a caste's (ENG-07t).
const SKILL_COLUMNS: u32 = 47;
const CASTE_COLUMNS: u32 = 30;

pub mod errors {
    pub const TRUNCATED: felt252 = 'seed: truncated';
    pub const LENGTH: felt252 = 'seed: length';
    pub const COLUMN: felt252 = 'seed: a column name';
    pub const COLUMNS: felt252 = 'seed: columns';
    pub const SHORT_ROW: felt252 = 'seed: a row is short';
    pub const UNREAD: felt252 = 'seed: unread values';
    pub const RANGE: felt252 = 'seed: value out of range';
    pub const NAME: felt252 = 'seed: region name';
    pub const SEALED: felt252 = 'seed: sealed is 0 or 1';
    pub const OUTLINE_ROW: felt252 = 'seed: outline row';
}

/// A region's row: four numbers and its name.
#[derive(Drop)]
struct RegionRow {
    numbers: Span<felt252>,
    name: ByteArray,
}

/// The file, in the order `read_json` gives its keys.
#[derive(Drop)]
pub struct Seed {
    caste_fields: Array<ByteArray>,
    castes: Span<felt252>,
    gate_fields: Array<ByteArray>,
    gates: Span<felt252>,
    location_fields: Array<ByteArray>,
    locations: Span<felt252>,
    outline_fields: Array<ByteArray>,
    outlines: Span<felt252>,
    pack_fields: Array<ByteArray>,
    packs: Span<felt252>,
    quota_fields: Array<ByteArray>,
    quotas: Span<felt252>,
    region_fields: Array<ByteArray>,
    regions: Array<RegionRow>,
    skill_fields: Array<ByteArray>,
    skills: Span<felt252>,
    spawn_table_fields: Array<ByteArray>,
    spawn_tables: Span<felt252>,
}

/// What was written, in the order written: `(kind, id)` of every record, and the felts of all of
/// them in the same order.
#[derive(Drop)]
pub struct Written {
    pub requests: Array<(u8, u32)>,
    pub felts: Array<felt252>,
}

/// A cursor over `read_json`'s felts.
#[generate_trait]
impl StreamImpl of Stream {
    fn length(ref self: Span<felt252>) -> u32 {
        let length = *SeedAssert::assert_some(self.pop_front(), errors::TRUNCATED);
        SeedAssert::assert_some(length.try_into(), errors::LENGTH)
    }

    fn take(ref self: Span<felt252>, count: u32) -> Span<felt252> {
        SeedAssert::assert_available(self, count);
        let taken = self.slice(0, count);
        self = self.slice(count, self.len() - count);
        taken
    }

    /// An array of strings: its length, then each `ByteArray`.
    fn names(ref self: Span<felt252>) -> Array<ByteArray> {
        let mut names: Array<ByteArray> = array![];
        for _ in 0..Self::length(ref self) {
            names
                .append(
                    SeedAssert::assert_some(
                        Serde::<ByteArray>::deserialize(ref self), errors::COLUMN,
                    ),
                );
        }
        names
    }

    /// An array of numbers: its length, then the numbers.
    fn numbers(ref self: Span<felt252>) -> Span<felt252> {
        let count = Self::length(ref self);
        Self::take(ref self, count)
    }
}

/// A row of the file, read as the model it describes.
#[generate_trait]
impl RowImpl of Row {
    fn field<T, +TryInto<felt252, T>, +Drop<T>>(self: Span<felt252>, i: u32) -> T {
        SeedAssert::assert_some((*self[i]).try_into(), errors::RANGE)
    }

    fn location(self: Span<felt252>) -> Location {
        let s = SET_PIECES_AT;
        let set_pieces = Lanes16 {
            lanes: [
                self.field(s), self.field(s + 1), self.field(s + 2), self.field(s + 3),
                self.field(s + 4), self.field(s + 5), self.field(s + 6), self.field(s + 7),
                self.field(s + 8), self.field(s + 9), self.field(s + 10), self.field(s + 11),
                self.field(s + 12), self.field(s + 13), self.field(s + 14),
            ],
        };
        let sealed: u8 = self.field(13);
        SeedAssert::assert_sealed(sealed);
        LocationTrait::new(
            self.field(1),
            self.field(2),
            self.field(3),
            self.field(4),
            self.field(5),
            self.field(6),
            self.field(7),
            self.field(8),
            self.field(9),
            self.field(10),
            self.field(11),
            self.field(12),
            sealed == 1,
            self.field(14),
            self.field(15),
            set_pieces,
        )
    }

    /// Bit `c` of `row_r` is bit `15 r + c` of the outline. A test helper, not a contract: `u256`
    /// only to split the rows' sum into its two limbs.
    fn outline(self: Span<felt252>) -> Outline {
        let mut bits: u256 = 0;
        let mut factor: u256 = 1;
        for i in 2..OUTLINE_COLUMNS {
            let value: u16 = self.field(i);
            SeedAssert::assert_outline_row(value);
            bits += value.into() * factor;
            factor *= 0x8000;
        }
        OutlineTrait::new(bits.low, bits.high)
    }

    /// A pack template: five `(caste, min, max)`, then its level offset.
    fn pack(self: Span<felt252>) -> Pack {
        PackTrait::new(
            [self.caste(0), self.caste(1), self.caste(2), self.caste(3), self.caste(4)],
            self.field(16),
        )
    }

    fn caste(self: Span<felt252>, i: u32) -> PackCaste {
        PackCaste {
            caste: self.field(1 + 3 * i), min: self.field(2 + 3 * i), max: self.field(3 + 3 * i),
        }
    }

    /// A spawn table: seven `(template, weight)`, then its density.
    fn spawn_table(self: Span<felt252>) -> SpawnTable {
        SpawnTableTrait::new(
            [
                self.spawn(0), self.spawn(1), self.spawn(2), self.spawn(3), self.spawn(4),
                self.spawn(5), self.spawn(6),
            ],
            self.field(15),
        )
    }

    fn spawn(self: Span<felt252>, i: u32) -> Spawn {
        Spawn { template: self.field(1 + 2 * i), weight: self.field(2 + 2 * i) }
    }

    /// A location's quotas: six `(kind, param, count)`.
    fn quotas(self: Span<felt252>) -> QuotaSet {
        QuotaSetTrait::new(
            [
                self.quota(0), self.quota(1), self.quota(2), self.quota(3), self.quota(4),
                self.quota(5),
            ],
        )
    }

    fn quota(self: Span<felt252>, i: u32) -> Quota {
        Quota {
            kind: self.field(1 + 3 * i), param: self.field(2 + 3 * i), count: self.field(3 + 3 * i),
        }
    }

    /// A skill: its header, then three entries of 12 fields.
    fn skill(self: Span<felt252>) -> Skill {
        SkillTrait::new(
            self.field(1),
            self.field(2),
            self.field(3),
            self.field(4),
            self.field(5),
            self.field(6),
            self.field(7),
            self.field(8),
            self.field(9),
            self.field(10) == 1,
            [self.entry(11), self.entry(23), self.entry(35)],
        )
    }

    fn entry(self: Span<felt252>, at: u32) -> Entry {
        EntryTrait::new(
            self.field(at),
            self.field(at + 1),
            self.field(at + 2),
            self.field(at + 3),
            self.field(at + 4),
            self.field(at + 5),
            self.field(at + 6),
            self.field(at + 7),
            self.field(at + 8),
            self.field(at + 9),
            self.field(at + 10),
            self.field(at + 11),
        )
    }

    /// A caste: the sheet's fields in order, the weapon's five inline.
    fn sheet(self: Span<felt252>) -> Caste {
        CasteTrait::new(
            self.field(1),
            self.field(2),
            self.field(3),
            self.field(4),
            self.field(5),
            [
                self.field(6), self.field(7), self.field(8), self.field(9), self.field(10),
                self.field(11), self.field(12), self.field(13), self.field(14),
            ],
            WeaponTrait::new(
                self.field(15), self.field(16), self.field(17), self.field(18), self.field(19),
            ),
            self.field(20),
            self.field(21),
            [self.field(22), self.field(23), self.field(24), self.field(25)],
            self.field(26),
            self.field(27),
            self.field(28),
            self.field(29) == 1,
        )
    }

    fn gate(self: Span<felt252>) -> Gate {
        GateTrait::new(
            self.field(1),
            self.field(2),
            self.field(3),
            self.field(4),
            self.field(5),
            self.field(6),
            self.field(7),
            self.field(8),
            self.field(9),
        )
    }
}

/// A region's name: a short string of at most 15 characters.
#[generate_trait]
impl NameImpl of Name {
    fn short(self: @ByteArray) -> felt252 {
        SeedAssert::assert_name(self);
        let mut word: felt252 = 0;
        for i in 0..self.len() {
            word = word * 256 + self.at(i).unwrap().into();
        }
        word
    }
}

#[generate_trait]
impl SeedAssert of SeedAssertTrait {
    /// The file's column names are these, in this order; returns the number of rows.
    fn assert_columns(
        fields: @Array<ByteArray>, expected: Array<ByteArray>, rows: Span<felt252>,
    ) -> u32 {
        assert(fields.len() == expected.len(), errors::COLUMNS);
        for i in 0..expected.len() {
            assert(fields[i] == expected[i], errors::COLUMN);
        }
        let (count, rest) = DivRem::div_rem(rows.len(), expected.len().try_into().unwrap());
        Self::assert_whole(rest);
        count
    }

    /// A value the file must hold: a parse that failed refuses with `message`.
    fn assert_some<T, +Drop<T>>(value: Option<T>, message: felt252) -> T {
        value.expect(message)
    }

    /// The stream still holds `count` felts.
    fn assert_available(stream: Span<felt252>, count: u32) {
        assert(stream.len() >= count, errors::TRUNCATED);
    }

    /// A table's elements are a whole number of rows.
    fn assert_whole(rest: u32) {
        assert(rest == 0, errors::SHORT_ROW);
    }

    /// Nothing is left after the last table.
    fn assert_read(stream: Span<felt252>) {
        assert(stream.len() == 0, errors::UNREAD);
    }

    fn assert_region_columns(fields: @Array<ByteArray>, expected: @Array<ByteArray>) {
        assert(fields == expected, errors::COLUMNS);
    }

    fn assert_sealed(value: u8) {
        assert(value <= 1, errors::SEALED);
    }

    /// A row of an outline holds 15 bits, one a column.
    fn assert_outline_row(value: u16) {
        assert(value < 0x8000, errors::OUTLINE_ROW);
    }

    /// A region's name is a short string of at most 15 characters.
    fn assert_name(name: @ByteArray) {
        assert(name.len() <= 15, errors::NAME);
    }
}

#[generate_trait]
pub impl SeedImpl of SeedTrait {
    /// The test region's file.
    fn load() -> Seed {
        let file = FileTrait::new("../seed/test-region.json");
        let felts = read_json(@file);
        let mut stream = felts.span();
        let caste_fields = stream.names();
        let castes = stream.numbers();
        let gate_fields = stream.names();
        let gates = stream.numbers();
        let location_fields = stream.names();
        let locations = stream.numbers();
        let outline_fields = stream.names();
        let outlines = stream.numbers();
        let pack_fields = stream.names();
        let packs = stream.numbers();
        let quota_fields = stream.names();
        let quotas = stream.numbers();
        let region_fields = stream.names();
        // Five elements a row: four numbers, then the name (a `ByteArray` of several felts).
        let (count, rest) = DivRem::div_rem(stream.length(), 5);
        SeedAssert::assert_whole(rest);
        let mut regions: Array<RegionRow> = array![];
        for _ in 0..count {
            let numbers = stream.take(4);
            let name = SeedAssert::assert_some(
                Serde::<ByteArray>::deserialize(ref stream), errors::NAME,
            );
            regions.append(RegionRow { numbers, name });
        }
        let skill_fields = stream.names();
        let skills = stream.numbers();
        let spawn_table_fields = stream.names();
        let spawn_tables = stream.numbers();
        SeedAssert::assert_read(stream);
        Seed {
            caste_fields,
            castes,
            gate_fields,
            gates,
            location_fields,
            locations,
            outline_fields,
            outlines,
            pack_fields,
            packs,
            quota_fields,
            quotas,
            region_fields,
            regions,
            skill_fields,
            skills,
            spawn_table_fields,
            spawn_tables,
        }
    }

    /// Its records, packed, in the order they are written: regions, locations, outlines (whose
    /// parent location must exist first), gates, then the reveal's (ENG-05): pack templates, spawn
    /// tables and the locations' quotas (after their location).
    fn records(self: @Seed) -> Written {
        let mut written = Written { requests: array![], felts: array![] };

        let region_columns: Array<ByteArray> = array![
            "id", "town", "book", "first_location", "name",
        ];
        SeedAssert::assert_region_columns(self.region_fields, @region_columns);
        for region in self.regions.span() {
            let row = *region.numbers;
            let value = RegionTrait::new(
                row.field(1), row.field(2), row.field(3), region.name.short(),
            );
            written.add(row.field(0), @value);
        }

        let mut columns: Array<ByteArray> = array![
            "id", "kind", "region", "biome", "level_min", "level_max", "rank", "width", "height",
            "target", "floors", "next_floor", "spawn_table", "sealed", "entry_chunk", "entry_tile",
        ];
        let pieces: Array<ByteArray> = array![
            "set_piece_1", "set_piece_2", "set_piece_3", "set_piece_4", "set_piece_5",
            "set_piece_6", "set_piece_7", "set_piece_8", "set_piece_9", "set_piece_10",
            "set_piece_11", "set_piece_12", "set_piece_13", "set_piece_14", "set_piece_15",
        ];
        for name in pieces {
            columns.append(name);
        }
        let rows = SeedAssert::assert_columns(self.location_fields, columns, *self.locations);
        for i in 0..rows {
            let row = self.locations.slice(LOCATION_COLUMNS * i, LOCATION_COLUMNS);
            written.add(row.field(0), @row.location());
        }

        let columns: Array<ByteArray> = array![
            "location", "chunk", "row_0", "row_1", "row_2", "row_3", "row_4", "row_5", "row_6",
            "row_7", "row_8", "row_9", "row_10", "row_11", "row_12", "row_13", "row_14",
        ];
        let rows = SeedAssert::assert_columns(self.outline_fields, columns, *self.outlines);
        for i in 0..rows {
            let row = self.outlines.slice(OUTLINE_COLUMNS * i, OUTLINE_COLUMNS);
            written.add(OutlineTrait::id(row.field(0), row.field(1)), @row.outline());
        }

        let columns: Array<ByteArray> = array![
            "id", "source", "destination", "anchor_chunk", "anchor_tile", "entry_chunk",
            "entry_tile", "kind", "rank", "quest",
        ];
        let rows = SeedAssert::assert_columns(self.gate_fields, columns, *self.gates);
        for i in 0..rows {
            let row = self.gates.slice(GATE_COLUMNS * i, GATE_COLUMNS);
            written.add(row.field(0), @row.gate());
        }

        let mut columns: Array<ByteArray> = array!["id"];
        for i in 1..6_u8 {
            columns.append(format!("caste_{}", i));
            columns.append(format!("min_{}", i));
            columns.append(format!("max_{}", i));
        }
        columns.append("level");
        let rows = SeedAssert::assert_columns(self.pack_fields, columns, *self.packs);
        for i in 0..rows {
            let row = self.packs.slice(PACK_COLUMNS * i, PACK_COLUMNS);
            written.add(row.field(0), @row.pack());
        }

        let mut columns: Array<ByteArray> = array!["id"];
        for i in 1..8_u8 {
            columns.append(format!("template_{}", i));
            columns.append(format!("weight_{}", i));
        }
        columns.append("density");
        let rows = SeedAssert::assert_columns(self.spawn_table_fields, columns, *self.spawn_tables);
        for i in 0..rows {
            let row = self.spawn_tables.slice(SPAWN_TABLE_COLUMNS * i, SPAWN_TABLE_COLUMNS);
            written.add(row.field(0), @row.spawn_table());
        }

        let mut columns: Array<ByteArray> = array!["location"];
        for i in 1..7_u8 {
            columns.append(format!("kind_{}", i));
            columns.append(format!("param_{}", i));
            columns.append(format!("count_{}", i));
        }
        let rows = SeedAssert::assert_columns(self.quota_fields, columns, *self.quotas);
        for i in 0..rows {
            let row = self.quotas.slice(QUOTA_COLUMNS * i, QUOTA_COLUMNS);
            written.add(row.field(0), @row.quotas());
        }

        // ENG-07t: the skills the castes name (a caste is written after its skills), then the
        // castes the pack templates name, so that a fight runs on the node.
        let mut columns: Array<ByteArray> = array![
            "id", "profession", "attribute", "kind", "energy", "adrenaline", "activation",
            "recharge", "range", "target", "elite",
        ];
        for e in 1..4_u8 {
            let names: Array<ByteArray> = array![
                "kind", "param", "v0", "v12", "d0", "d12", "charges", "target", "shape", "filter",
                "guard", "scope",
            ];
            for name in names {
                columns.append(format!("e{}_{}", e, name));
            }
        }
        let rows = SeedAssert::assert_columns(self.skill_fields, columns, *self.skills);
        for i in 0..rows {
            let row = self.skills.slice(SKILL_COLUMNS * i, SKILL_COLUMNS);
            written.add(row.field(0), @row.skill());
        }

        let mut columns: Array<ByteArray> = array![
            "id", "tier", "ai", "health", "health_regen", "armor",
        ];
        for i in 1..10_u8 {
            columns.append(format!("armor_vs_{}", i));
        }
        let names: Array<ByteArray> = array![
            "weapon_class", "weapon_damage", "weapon_damage_type", "weapon_ticks", "weapon_range",
            "energy", "energy_regen", "skill_1", "skill_2", "skill_3", "skill_4", "rank", "flee",
            "loot_table", "boss",
        ];
        for name in names {
            columns.append(name);
        }
        let rows = SeedAssert::assert_columns(self.caste_fields, columns, *self.castes);
        for i in 0..rows {
            let row = self.castes.slice(CASTE_COLUMNS * i, CASTE_COLUMNS);
            written.add(row.field(0), @row.sheet());
        }
        written
    }

    /// Writes the test region into `registry` as `ADMIN`; returns what it wrote.
    fn write(registry: ContractAddress) -> Written {
        let written = Self::load().records();
        written.write(registry);
        written
    }
}

#[generate_trait]
pub impl WrittenImpl of WrittenTrait {
    /// A record, packed through its model's `Record`, appended under its kind.
    fn add<T, impl R: Record<T>, +Drop<T>>(ref self: Written, id: u32, record: @T) {
        self.requests.append((R::KIND, id));
        for felt in R::pack(record) {
            self.felts.append(*felt);
        }
    }

    /// Writes the records into `registry` as `ADMIN`, one `set_record` a record.
    fn write(self: @Written, registry: ContractAddress) {
        let admin = IRegistryAdminDispatcher { contract_address: registry };
        start_cheat_caller_address(registry, ADMIN.try_into().unwrap());
        // BND-01: the quotas are refused until the registry's zone checks are set
        admin.set_zone_checks(*declare("ZoneChecks").unwrap().contract_class().class_hash);
        let mut felts = self.felts.span();
        for request in self.requests.span() {
            let (kind, id) = *request;
            let count: u32 = parts(kind).into();
            admin.set_record(kind, id, felts.take(count));
        }
        stop_cheat_caller_address(registry);
    }
}

#[generate_trait]
impl SeedFixture of Fixture {
    fn deploy() -> ContractAddress {
        let class = declare("Registry").unwrap().contract_class();
        let (address, _) = class.deploy(@array![ADMIN]).unwrap();
        address
    }
}

// The test region, written and read back in one `bundle` (AC-4): 18 records, 22 slots (ENG-05: two
// pack templates, a spawn table, the zone's and floor 1's quotas).
#[test]
// gas: raised, BND-01: the zone checks' class set, the gates indexed
#[available_gas(l2_gas: 63206204)] // ceil(1.05 × 60196384 measured)
fn test_seed_written_and_read_back() {
    let registry = Fixture::deploy();
    let written = SeedTrait::write(registry);
    assert(written.requests.len() == 22, '22 records');
    assert(written.felts.len() == 30, '30 slots');
    let read = IRegistryReadDispatcher { contract_address: registry };
    let (version, inputs, felts) = read.bundle(written.requests.span());
    assert(version == 22, 'one version a record');
    // Every record is new: no stored snapshot can name it (D-169).
    assert(inputs == 0, 'no input rewritten');
    assert(felts == written.felts.span(), 'read back as written');
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    assert(admin.last_id(REGION) == 1, 'one region');
    assert(admin.last_id(LOCATION) == 4, 'four locations');
    assert(admin.last_id(GATE) == 5, 'five gates');
    assert(admin.last_id(OUTLINE) == 0, 'outlines are composite');

    // What the file says, field by field, through the models.
    let region = Record::<Region>::unpack(felts.slice(0, 1));
    assert(region.town == 1 && region.first_location == 1 && region.book == 0, 'region');
    assert(region.name == 'Test Region', 'region: name');
    let town = Record::<Location>::unpack(felts.slice(1, 2));
    assert(town.kind == kind::TOWN && town.region == 1 && town.width == 0, 'town');
    let zone = Record::<Location>::unpack(felts.slice(3, 2));
    assert(zone.kind == kind::ZONE && zone.biome == biome::MEADOW, 'zone');
    assert(zone.level_min == 1 && zone.level_max == 3, 'zone: band');
    assert(zone.width == 3 && zone.height == 2, 'zone: size');
    assert(zone.entry_chunk == 0 && zone.entry_tile == 105, 'zone: entry');
    let floor1 = Record::<Location>::unpack(felts.slice(5, 2));
    assert(floor1.kind == kind::DUNGEON && floor1.biome == biome::CAVE, 'floor 1');
    assert(floor1.target == 6 && floor1.floors == 2 && floor1.next_floor == 4, 'floor 1: N');
    assert(floor1.entry_chunk == 112 && floor1.entry_tile == 112, 'floor 1: entry (7, 7)');
    assert(floor1.set_pieces == Lanes16 { lanes: [0; 15] }, 'floor 1: no set piece');
    let floor2 = Record::<Location>::unpack(felts.slice(7, 2));
    assert(floor2.target == 8 && floor2.next_floor == 0, 'floor 2: last');
    // The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1).
    assert(*written.requests[5] == (OUTLINE, 2 * 256 + CHUNK_SET.into()), 'chunk set id');
    let chunks = Record::<Outline>::unpack(felts.slice(9, 1));
    assert(chunks == OutlineTrait::new(0x18007, 0), 'zone: chunk set');
    // Chunk 16's mask: rows 0-9 whole, rows 10-14 columns 0-9; 200 tiles.
    assert(*written.requests[7] == (OUTLINE, 2 * 256 + 16), 'chunk 16 id');
    let mask = Record::<Outline>::unpack(felts.slice(11, 1));
    let expected = OutlineTrait::new(0xffffffffffffffffffffffffffffffff, 0xffc1ff83ff07fe0ffffffff);
    assert(mask == expected, 'chunk 16 mask');
    let hub = Record::<Gate>::unpack(felts.slice(12, 1));
    assert(hub.source == 1 && hub.destination == 2 && hub.kind == gate_kind::HUB, 'gate 1: hub');
    assert(hub.entry_chunk == 0 && hub.entry_tile == 105, 'gate 1: entry');
    let link = Record::<Gate>::unpack(felts.slice(14, 1));
    assert(
        link.source == 2 && link.destination == 3 && link.kind == gate_kind::LINK, 'gate 3: link',
    );
    assert(link.anchor_chunk == 16 && link.anchor_tile == 110, 'gate 3: anchor');
    let floor = Record::<Gate>::unpack(felts.slice(16, 1));
    assert(floor.source == 3 && floor.destination == 4 && floor.kind == gate_kind::FLOOR, 'gate 5');
    // The reveal's records (ENG-05).
    assert(zone.spawn_table == 1 && floor1.spawn_table == 1, 'spawn table named');
    assert(admin.last_id(PACK) == 2 && admin.last_id(SPAWN_TABLE) == 1, 'packs, table');
    assert(admin.last_id(QUOTAS) == 0, 'quotas are composite');
    let first = PackRecord::unpack(felts.slice(17, 1));
    assert(first.castes.span()[1] == @PackCaste { caste: 2, min: 1, max: 3 }, 'pack 1');
    assert(first.bounds() == (2, 5), 'pack 1: 2 to 5 goblins');
    let second = PackRecord::unpack(felts.slice(18, 1));
    assert(second.level == 1 && second.bounds() == (1, 3), 'pack 2');
    let table = SpawnTableRecord::unpack(felts.slice(19, 1));
    assert(table.density == 128 && table.weight() == 4 && table.pick(3) == 2, 'spawn table');
    assert(*written.requests[16] == (QUOTAS, 2), 'the zone quotas');
    let camp = QuotaSetRecord::unpack(felts.slice(20, 1));
    assert(*camp.quotas.span()[0] == Quota { kind: quota::COLLECTOR, param: 1, count: 1 }, 'camp');
    let exit = QuotaSetRecord::unpack(felts.slice(21, 1));
    assert(*exit.quotas.span()[0] == Quota { kind: quota::EXIT, param: 5, count: 1 }, 'exit');
    // ENG-07t: the skill and the three castes the packs name.
    assert(admin.last_id(SKILL) == 1 && admin.last_id(CASTE) == 3, 'a skill, three castes');
    let rend = Record::<Skill>::unpack(felts.slice(22, 2));
    assert(rend.is_attack() && rend.count() == 1 && rend.range == 1, 'skill 1: an attack');
    for k in 0..3_u32 {
        let caste = Record::<Caste>::unpack(felts.slice(24 + 2 * k, 2));
        assert(*caste.skills.span()[0] == 1 && caste.health >= 100, 'a caste of skill 1');
    }
    let brute = Record::<Caste>::unpack(felts.slice(28, 2));
    assert(brute.tier == 2 && brute.weapon.damage == 9, 'caste 3: the brute');
}

// The baseline of the next test: the deployment, and the file read and packed.
#[test]
// gas: raised, ENG-07t: the seed holds 4 more records (a skill, three castes)
#[available_gas(l2_gas: 14452127)] // ceil(1.05 × 13763930 measured)
fn test_gas_seed_baseline() {
    Fixture::deploy();
    SeedTrait::load().records();
}

// Writing the whole test region, 18 `set_record` (AC-4): this test less the baseline.
#[test]
// gas: raised, BND-01: the zone checks' class set, the gates indexed
#[available_gas(l2_gas: 58719753)] // ceil(1.05 × 55923574 measured)
fn test_gas_seed_write() {
    let registry = Fixture::deploy();
    SeedTrait::load().records().write(registry);
}

// Writing the same seed again changes nothing: no record changed, the version stays.
#[test]
// gas: raised, BND-01: the zone checks' class set, the gates indexed
#[available_gas(l2_gas: 91340954)] // ceil(1.05 × 86991384 measured)
fn test_seed_rewritten_unchanged() {
    let registry = Fixture::deploy();
    SeedTrait::write(registry);
    SeedTrait::write(registry);
    let read = IRegistryReadDispatcher { contract_address: registry };
    assert(read.content_version() == 22, 'version kept');
}

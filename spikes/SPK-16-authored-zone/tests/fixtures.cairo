//! The sample zone as the converter wrote it (`samples/zone.golden.json`, from
//! `samples/zone.json`), decoded into the spike's models, and the reveal's `Site` of it.
//!
//! snforge's `read_json` gives the keys in alphabetical order, each array after its length:
//! `chunk_count`, then `chunk_fields`, `chunk_parts`, `records`. A felt is 8 limbs of 32 bits.

use grimworld_logic::content::{GATE, LOCATION, OUTLINE, QUOTAS as QUOTAS_KIND};
use grimworld_logic::models::chunk::Object;
use grimworld_logic::models::gate::{Gate, GateRecord};
use grimworld_logic::models::location::{Location, LocationRecord};
use grimworld_logic::models::outline::{CHUNK_SET, OutlineRecord};
use grimworld_logic::models::pack::{Pack, PackCaste};
use grimworld_logic::models::quotas::{QuotaSet, QuotaSetRecord};
use grimworld_logic::models::set_piece::SetPack;
use grimworld_logic::models::spawn_table::{Spawn, SpawnTable};
use grimworld_logic::types::reveal::Site;
use snforge_std::fs::{FileTrait, read_json};
use spk16::records::{BRIDGE, Bridge, BridgeTrait, CANDIDATES, CandidatesTrait, MarkerTrait};
use spk16::zone_chunk::ZoneChunk;

/// The location id of the sample zone.
pub const ZONE: u16 = 2;

/// Every record of the sample zone, decoded.
#[derive(Drop)]
pub struct Zone {
    pub location: Location,
    pub marker: u8,
    pub chunk_set: felt252,
    pub masks: Array<(u8, felt252)>,
    /// `(chunk, record, its two parts as the converter packed them)`.
    pub chunks: Array<(u8, ZoneChunk, Span<felt252>)>,
    pub candidates: [felt252; 3],
    pub quotas: QuotaSet,
    pub bridges: Array<(u8, u8, Bridge)>,
    pub gates: Array<(u16, Gate)>,
    /// The Heart's template (`raiders`, 2 to 5).
    pub hearts: Array<Option<Pack>>,
}

fn felt(ref stream: Span<felt252>) -> felt252 {
    let mut out: u256 = 0;
    let mut factor: u256 = 1;
    for i in 0..8_u8 {
        let limb: u256 = (*stream.pop_front().unwrap()).into();
        out += limb * factor;
        if i != 7 {
            factor *= 0x100000000;
        }
    }
    out.try_into().unwrap()
}

fn byte(ref stream: Span<felt252>) -> u8 {
    (*stream.pop_front().unwrap()).try_into().unwrap()
}

fn word(ref stream: Span<felt252>) -> u16 {
    (*stream.pop_front().unwrap()).try_into().unwrap()
}

/// The raiders and the cubs, `contracts/seed`'s two templates.
pub fn templates() -> Span<(u16, Pack)> {
    array![
        (
            1,
            Pack {
                castes: [
                    PackCaste { caste: 1, min: 1, max: 2 }, PackCaste { caste: 2, min: 1, max: 3 },
                    Default::default(), Default::default(), Default::default(),
                ],
                level: 0,
            },
        ),
        (
            2,
            Pack {
                castes: [
                    PackCaste { caste: 3, min: 1, max: 1 }, PackCaste { caste: 1, min: 0, max: 2 },
                    Default::default(), Default::default(), Default::default(),
                ],
                level: 1,
            },
        ),
    ]
        .span()
}

pub fn load() -> Zone {
    let file = FileTrait::new("samples/zone.golden.json");
    let felts = read_json(@file);
    let mut stream = felts.span();
    let count: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
    // chunk_fields: per chunk, its index, walls, 2 × (tile, template), 3 × (tile, kind, param),
    // 6 tiles, bridges, 2 gates
    let _length = stream.pop_front();
    let mut fields: Array<(u8, ZoneChunk)> = array![];
    for _ in 0..count {
        let chunk = byte(ref stream);
        let walls = felt(ref stream);
        let s0 = SetPack { tile: byte(ref stream), template: word(ref stream) };
        let s1 = SetPack { tile: byte(ref stream), template: word(ref stream) };
        let mut objects: Array<Object> = array![];
        for _ in 0..3_u8 {
            let tile = byte(ref stream);
            let kind = byte(ref stream);
            objects.append(Object { tile, kind, state: 0, param: word(ref stream) });
        }
        let tiles = [
            byte(ref stream), byte(ref stream), byte(ref stream), byte(ref stream),
            byte(ref stream), byte(ref stream),
        ];
        let bridges = byte(ref stream);
        let gates = [word(ref stream), word(ref stream)];
        fields
            .append(
                (
                    chunk,
                    ZoneChunk {
                        walls,
                        spawns: [s0, s1],
                        objects: [*objects[0], *objects[1], *objects[2]],
                        tiles,
                        bridges,
                        gates,
                    },
                ),
            );
    }
    // chunk_parts: per chunk, its index and its two parts
    let _length = stream.pop_front();
    let mut chunks: Array<(u8, ZoneChunk, Span<felt252>)> = array![];
    for i in 0..count {
        let chunk = byte(ref stream);
        let parts = array![felt(ref stream), felt(ref stream)].span();
        let (at, record) = *fields[i];
        assert(at == chunk, 'golden: chunk order');
        chunks.append((chunk, record, parts));
    }
    // records: (kind, id, a part), each part of the other records in the order written
    let length: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
    let mut location: Option<Location> = Option::None;
    let mut marker: u8 = 0;
    let mut chunk_set: felt252 = 0;
    let mut masks: Array<(u8, felt252)> = array![];
    let mut sets: Array<felt252> = array![];
    let mut quotas: Option<QuotaSet> = Option::None;
    let mut bridges: Array<(u8, u8, Bridge)> = array![];
    let mut gates: Array<(u16, Gate)> = array![];
    let mut location_parts: Array<felt252> = array![];
    for _ in 0..length / 10 {
        let kind = byte(ref stream);
        let id: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
        let part = felt(ref stream);
        if kind == LOCATION {
            location_parts.append(part);
            if location_parts.len() == 2 {
                // ENG-09 reads the marker beside the entry tile; today's unpacker reads the rest
                // of the high limb as the entry tile, so the marker is taken off first
                let part0 = *location_parts[0];
                marker = MarkerTrait::read(part0);
                let plain = part0 - (marker.into() * 0x10000) * 0x100000000000000000000000000000000;
                location =
                    Option::Some(LocationRecord::unpack(array![plain, *location_parts[1]].span()));
            }
        } else if kind == OUTLINE {
            let (_, chunk) = DivRem::div_rem(id, 256);
            let bits = OutlineRecord::unpack(array![part].span());
            let bits: felt252 = bits.low.into()
                + bits.high.into() * 0x100000000000000000000000000000000;
            if chunk == CHUNK_SET.into() {
                chunk_set = bits;
            } else {
                masks.append((chunk.try_into().unwrap(), bits));
            }
        } else if kind == CANDIDATES {
            sets.append(part);
        } else if kind == QUOTAS_KIND {
            quotas = Option::Some(QuotaSetRecord::unpack(array![part].span()));
        } else if kind == BRIDGE {
            let (rest, k) = DivRem::div_rem(id, 16);
            let (_, chunk) = DivRem::div_rem(rest, 256);
            bridges
                .append(
                    (
                        chunk.try_into().unwrap(),
                        k.try_into().unwrap(),
                        BridgeTrait::unpack(array![part].span()),
                    ),
                );
        } else if kind == GATE {
            gates.append((id.try_into().unwrap(), GateRecord::unpack(array![part].span())));
        }
    }
    let [c0, c1, c2] = CandidatesTrait::unpack(sets.span());
    let (_, raiders) = *templates()[0];
    Zone {
        location: location.unwrap(),
        marker,
        chunk_set,
        masks,
        chunks,
        candidates: [c0, c1, c2],
        quotas: quotas.unwrap(),
        bridges,
        gates,
        hearts: array![Option::None, Option::None, Option::Some(raiders)],
    }
}

#[generate_trait]
pub impl ZoneImpl of ZoneTrait {
    fn mask(self: @Zone, chunk: u8) -> felt252 {
        for entry in self.masks.span() {
            let (at, mask) = *entry;
            if at == chunk {
                return mask;
            }
        }
        0
    }

    fn chunk(self: @Zone, chunk: u8) -> ZoneChunk {
        for entry in self.chunks.span() {
            let (at, record, _) = *entry;
            if at == chunk {
                return record;
            }
        }
        panic!("no such chunk")
    }

    /// The six quotas' candidate sets (the last three empty in the sample).
    fn sets(self: @Zone) -> Span<felt252> {
        let [c0, c1, c2] = *self.candidates;
        array![c0, c1, c2, 0, 0, 0].span()
    }

    /// The reveal's `Site` of the zone (what `Instances` reads: the location, the quotas, the
    /// templates; the masks and anchors unused by the authored reveal).
    fn site(self: @Zone) -> Site {
        Site {
            target: 0,
            biome: *self.location.biome,
            level_min: *self.location.level_min,
            level_max: *self.location.level_max,
            width: *self.location.width,
            height: *self.location.height,
            entry_chunk: *self.location.entry_chunk,
            chunk_set: *self.chunk_set,
            west: 0,
            north: 0,
            masks: array![].span(),
            anchors: array![].span(),
            quotas: *self.quotas,
            tasks: array![].span(),
            spawn: SpawnTable {
                spawns: [
                    Spawn { template: 1, weight: 3 }, Spawn { template: 2, weight: 1 },
                    Default::default(), Default::default(), Default::default(), Default::default(),
                    Default::default(),
                ],
                density: 128,
            },
            packs: templates(),
            pieces: array![].span(),
        }
    }
}

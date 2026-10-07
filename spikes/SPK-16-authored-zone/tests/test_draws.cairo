//! What stays random on an authored map (ENG-08 deliverable 4, AC-5; D-215 rulings 3 and 4): the
//! quotas' hosts drawn among their candidates and each spawn point's level and count, all at
//! entry, each from a domain of its own; no order of the reveals moves any of it.

use grimworld_logic::fate::{REVEAL, derive, domain};
use grimworld_logic::models::chunk::{Features, Object, PackPlacement, Terrain, object};
use grimworld_logic::models::pack::PackTrait;
use grimworld_logic::types::reveal::board::BoardTrait;
use spk16::authored::{AuthoredTrait, HOSTS_COUNTER, SPAWN_BASE};
use spk16::zone_chunk::ZoneChunkTrait;
use crate::fixtures::{ZoneTrait, load, templates};

const INSTANCE: felt252 = 'instance 7';
const ORDERS: u32 = 6;

/// The zone's five chunks in order `k` (forward, backward, and four shuffles).
fn order(k: u32) -> Span<u8> {
    let orders = array![
        array![0, 1, 2, 15, 16], array![16, 15, 2, 1, 0], array![2, 16, 0, 15, 1],
        array![15, 0, 16, 1, 2], array![1, 2, 15, 16, 0], array![16, 0, 1, 2, 15],
    ];
    orders[k].span()
}

#[test]
fn test_hosts_among_candidates() {
    let z = load();
    let sets = z.sets();
    for e in 0..16_u32 {
        let seed = AuthoredTrait::hosts_seed(e.into(), INSTANCE);
        let hosts = AuthoredTrait::hosts(@z.quotas, sets, seed);
        let mut i: u32 = 0;
        for entry in z.quotas.quotas.span() {
            let mask = *hosts[i];
            assert(BoardTrait::minus(mask, *sets[i]) == 0, 'a host is a candidate');
            let expected = if *entry.kind == 0 {
                0
            } else {
                *entry.count
            };
            assert(BoardTrait::count(mask) == expected, 'count hosts exactly');
            i += 1;
        }
    }
}

/// Each chunk's two words, revealed in six orders over eight entropies: the same words whatever
/// the order (the hosts drawn once, every other draw keyed by the chunk).
#[test]
fn test_authored_reveal_order_free() {
    let z = load();
    let site = z.site();
    for e in 0..8_u32 {
        let entropy: felt252 = 'entropy' + e.into();
        let hosts = AuthoredTrait::hosts(
            @z.quotas, z.sets(), AuthoredTrait::hosts_seed(entropy, INSTANCE),
        );
        let mut first: Array<(u8, Terrain, Features)> = array![];
        for k in 0..ORDERS {
            let mut words: Array<(u8, Terrain, Features)> = array![];
            for chunk in order(k) {
                let record = z.chunk(*chunk);
                let (terrain, features) = AuthoredTrait::reveal(
                    @site, *chunk, @record, hosts.span(), entropy, INSTANCE,
                );
                words.append((*chunk, terrain, features));
            }
            if k == 0 {
                first = words;
            } else {
                for word in words.span() {
                    let (chunk, terrain, features) = *word;
                    let mut found = false;
                    for earlier in first.span() {
                        let (at, t, f) = *earlier;
                        if at == chunk {
                            assert(t == terrain && f == features, 'same words in every order');
                            found = true;
                        }
                    }
                    assert(found, 'every chunk');
                }
            }
        }
    }
}

/// Over 16 entropies: every quota placed exactly its count over the zone, on a candidate tile;
/// the walls copied; spawn points' packs within the band and the template's bounds (at least one);
/// a Heart at the band's top (D-208).
#[test]
fn test_authored_reveal_places_as_drawn() {
    let z = load();
    let site = z.site();
    for e in 0..16_u32 {
        let entropy: felt252 = 'entropy' + e.into();
        let hosts = AuthoredTrait::hosts(
            @z.quotas, z.sets(), AuthoredTrait::hosts_seed(entropy, INSTANCE),
        );
        let mut collectors: u8 = 0;
        let mut veins: u8 = 0;
        let mut hearts: u8 = 0;
        for entry in z.chunks.span() {
            let (chunk, record, _) = *entry;
            let (terrain, features) = AuthoredTrait::reveal(
                @site, chunk, @record, hosts.span(), entropy, INSTANCE,
            );
            assert(terrain.walls == record.walls && terrain.edges == 0, 'the plane copied');
            for item in features.objects.span() {
                let item: Object = *item;
                if item.kind == object::COLLECTOR {
                    assert(item.tile == record.tile(0), 'on its candidate');
                    collectors += 1;
                } else if item.kind == object::VEIN {
                    assert(item.tile == record.tile(1), 'on its candidate');
                    veins += 1;
                }
            }
            for pack in features.packs.span() {
                let pack: PackPlacement = *pack;
                if pack.template == 0 {
                    continue;
                }
                assert(pack.level >= site.level_min && pack.level <= site.level_max, 'band');
                let (_, template) = if pack.template == 1 {
                    *templates()[0]
                } else {
                    *templates()[1]
                };
                let (low, high) = template.bounds();
                assert(pack.count >= 1 && pack.count >= low && pack.count <= high, 'count');
                if BoardTrait::has(*hosts[2], chunk) && pack.tile == record.tile(2) {
                    assert(pack.level == site.level_max, 'heart at the band top');
                    hearts += 1;
                }
            }
        }
        assert(collectors == 1 && veins == 1 && hearts == 1, 'every quota its count');
    }
}

/// The authored draws' domains are their own (ADR-0002 rule 2): the hosts' counter 226 and the
/// spawn points' `256 + chunk` are no chunk's word (0-224) and not ENG-05's hosts (225).
#[test]
fn test_domains_apart() {
    let hosts = derive('e', domain(INSTANCE, HOSTS_COUNTER, REVEAL), 0);
    assert(hosts == AuthoredTrait::hosts_seed('e', INSTANCE), 'the hosts seed');
    assert(hosts != derive('e', domain(INSTANCE, 225, REVEAL), 0), 'not ENG-05 hosts');
    let mut c: u8 = 0;
    while c < 225 {
        let spawn = AuthoredTrait::spawn_word('e', INSTANCE, c);
        assert(spawn == derive('e', domain(INSTANCE, SPAWN_BASE + c.into(), REVEAL), 0), 'spawn');
        assert(spawn != derive('e', domain(INSTANCE, c.into(), REVEAL), 0), 'not the chunk word');
        assert(spawn != hosts, 'not the hosts');
        c += 16;
    }
}

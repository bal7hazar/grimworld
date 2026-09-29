//! The nine events of the indexer (SPK-11 §1, §6), frozen like an API: names, keys, data, order
//! and widths. The first key is the selector of the event's name; a change is a new event name,
//! which the indexer decodes beside the old one forever. `Hub` emits the first five, `Market` the
//! last four. Ids are storage ids; gold, prices and lot ids are `u64` (SPK-11 §6 point 4).

/// An adventurer entered or left a hub: travel, return, defeat, gate entry (Q4). `hub` 0: in no
/// hub (inside an instance).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct AdventurerLocated {
    #[key]
    pub hub: u16,
    pub adventurer: u32,
}

/// The displayed title was chosen (Q5): emitted only, never stored (T-1, *scope 3*).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct TitleDisplayed {
    #[key]
    pub adventurer: u32,
    pub title: u16,
    pub tier: u8,
}

/// A trial passed (rankings, version 1; emitted from the MVP on).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct TrialPassed {
    #[key]
    pub adventurer: u32,
    pub rank: u8,
    pub first_attempt: bool,
}

/// A dungeon cleared (rankings, version 1).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct DungeonCleared {
    #[key]
    pub adventurer: u32,
    pub dungeon: u16,
}

/// A promotion (rankings, version 1).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct RankReached {
    #[key]
    pub adventurer: u32,
    pub rank: u8,
}

/// A lot posted (Q1-Q3). `equipment` 0 for balances; `modifiers` the packed `ItemMods`, 0 for
/// balances and unidentified pieces.
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct LotPosted {
    #[key]
    pub market_key: felt252,
    #[key]
    pub lot_size: u8,
    pub lot: u64,
    pub price: u64,
    pub expiry: u64,
    pub equipment: u32,
    pub modifiers: felt252,
}

/// A lot bought, withdrawn, or returned after expiry (Q1-Q3; a sale's time is its block's).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct LotClosed {
    #[key]
    pub lot: u64,
    pub sold: bool,
}

/// A direct trade opened (Q7), keyed on the invited account; expires 10 minutes after its block.
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct TradeOpened {
    #[key]
    pub invited: u32,
    pub trade: u64,
    pub inviter: u32,
}

/// A direct trade closed (Q7): 0 done, 1 declined, 2 cancelled.
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct TradeClosed {
    #[key]
    pub trade: u64,
    pub outcome: u8,
}

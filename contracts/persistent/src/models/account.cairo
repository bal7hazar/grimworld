//! An account (ADR-0005): the owner is a field it can change (A-7), so the adventurers do not
//! follow an address. What is shared (the vault, gold, Rifts) is keyed by account id; what is
//! personal by adventurer id (design/03, D-33).

use grimworld_logic::packing::{P16, P24, P32, P8, byte_at, join, low_field, split};
use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct AccountRecord {
    /// bits 0-7: adventurer slots (3, more can be bought, design/03)
    pub slots: u8,
    /// bits 8-15: adventurers it has
    pub adventurers: u8,
    /// bits 16-23: the highest guild rank among them (lot limit and the right to sell, design/16)
    pub highest_rank: u8,
    /// bits 24-31: panes of the vault (25 items each, design/15)
    pub vault_panes: u8,
    /// bits 32-39: lots it has open on the market
    pub lots: u8,
}

pub impl AccountRecordStorePacking of starknet::storage_access::StorePacking<
    AccountRecord, felt252,
> {
    fn pack(value: AccountRecord) -> felt252 {
        join(
            value.slots.into()
                + value.adventurers.into() * P8
                + value.highest_rank.into() * P16
                + value.vault_panes.into() * P24
                + value.lots.into() * P32,
            0,
        )
    }
    fn unpack(value: felt252) -> AccountRecord {
        let (low, _) = split(value);
        AccountRecord {
            slots: low_field(low, P8.try_into().unwrap()).try_into().unwrap(),
            adventurers: byte_at(low, P8),
            highest_rank: byte_at(low, P16),
            vault_panes: byte_at(low, P24),
            lots: byte_at(low, P32),
        }
    }
}

/// Two consecutive slots: the owner, then the record.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Account {
    pub owner: ContractAddress,
    pub record: AccountRecord,
}

/// The owner key of balances and gold: `kind × 2^32 + id`.
pub const PACK: u8 = 1;
pub const VAULT: u8 = 2;
pub const ESCROW: u8 = 3;

pub fn owner_key(kind: u8, id: u32) -> felt252 {
    kind.into() * 0x100000000 + id.into()
}

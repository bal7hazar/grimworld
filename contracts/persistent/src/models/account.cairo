//! An account (ADR-0005): the owner is a field it can change (A-7), so the adventurers do not
//! follow an address. What is shared (the vault, gold, Rifts) is keyed by account id; what is
//! personal by adventurer id (design/03, D-33).

use core::num::traits::Zero;
use grimworld_logic::packing::{Lanes32, P16, P24, P32, P8, byte_at, join, low_field, split};
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

/// The owner key of balances and gold: `kind × 2^32 + id`. `ESCROW` has one owner, id 0 (the
/// market): what each lot holds is in the lot, so posting never creates an escrow page per lot.
pub const PACK: u8 = 1;
pub const VAULT: u8 = 2;
pub const ESCROW: u8 = 3;

pub fn owner_key(kind: u8, id: u32) -> felt252 {
    kind.into() * 0x100000000 + id.into()
}

/// Adventurer slots of a new account (design/03, D-33: three; more can be bought).
pub const START_SLOTS: u8 = 3;

/// `account_adventurers` is a compact list of adventurer ids, seven per page (`Lanes32`), its
/// length `AccountRecord.adventurers`: an append writes lane `n % 7` of page `n / 7`; a removal
/// moves the last id into the hole and clears the last lane. A page once written keeps `LIVE`.
pub const IDS_PER_PAGE: u8 = 7;

/// Offset of `record` in `Account`, for a read of the stored word.
pub const RECORD_WORD: u8 = 1;

/// The stored `AccountRecord` of a new account: `START_SLOTS` slots, nothing else, `LIVE`
/// (pinned against the packer by `test_stored_words`).
pub const NEW_RECORD: felt252 = 0x400000000000000000000000000000000000000000000000000000000000003;
/// One more adventurer, added to a stored `AccountRecord` (its field at bit 8).
pub const ONE_ADVENTURER: felt252 = 0x100;

/// The refusals of accounts (ENG-04).
pub mod errors {
    /// `register` by an address that already owns an account.
    pub const HAS_ACCOUNT: felt252 = 'account exists';
    /// `create_adventurer` by an address that owns no account.
    pub const NO_ACCOUNT: felt252 = 'no account';
    /// Every slot of the account holds an adventurer (design/03, D-33).
    pub const NO_FREE_SLOT: felt252 = 'no free slot';
    /// `set_account_owner` by anyone but the account's owner (A-7).
    pub const NOT_ACCOUNT_OWNER: felt252 = 'not account owner';
    /// `set_account_owner` to an address that already owns an account (one account per address).
    pub const OWNER_HAS_ACCOUNT: felt252 = 'owner has an account';
    /// `set_account_owner` to the zero address would leave the account to nobody.
    pub const ZERO_OWNER: felt252 = 'owner is zero';
}

/// A stored `AccountRecord` changed by arithmetic, without the packer: each function is pinned
/// against the packer by `test_stored_words` (the packer is the oracle, docs/CAIRO.md §2). They
/// take and return the stored word, since unpacking and packing the record is what they save.
#[generate_trait]
pub impl AccountRecordImpl of AccountRecordTrait {
    /// `(slots, adventurers)` of a stored record, without unpacking the other fields.
    fn counts(record: felt252) -> (u8, u8) {
        let (low, _) = split(record);
        (low_field(low, P8.try_into().unwrap()).try_into().unwrap(), byte_at(low, P8))
    }

    /// The stored record with one adventurer more (its field at bit 8; below `slots` ≤ 255).
    fn with_adventurer(record: felt252) -> felt252 {
        record + ONE_ADVENTURER
    }

    /// The stored record with one adventurer less (it has at least one).
    fn without_adventurer(record: felt252) -> felt252 {
        record - ONE_ADVENTURER
    }
}

#[generate_trait]
pub impl AccountAssert of AccountAssertTrait {
    /// `register`: the caller's `account_of` is 0.
    fn assert_no_account(account_id: u32) {
        assert(account_id == 0, errors::HAS_ACCOUNT);
    }

    /// The caller's `account_of` names an account.
    fn assert_has_account(account_id: u32) {
        assert(account_id != 0, errors::NO_ACCOUNT);
    }

    /// A slot is free: fewer adventurers than slots.
    fn assert_free_slot(slots: u8, count: u8) {
        assert(count < slots, errors::NO_FREE_SLOT);
    }

    /// `set_account_owner`: the caller is the current owner (A-7), the new owner is not zero and
    /// holds no account.
    fn assert_transfer(
        owner: ContractAddress, caller: ContractAddress, to: ContractAddress, to_account: u32,
    ) {
        assert(owner == caller, errors::NOT_ACCOUNT_OWNER);
        assert(to.is_non_zero(), errors::ZERO_OWNER);
        assert(to_account == 0, errors::OWNER_HAS_ACCOUNT);
    }
}

/// A page of `account_adventurers` (a `Lanes32` of adventurer ids).
#[generate_trait]
pub impl AdventurerListImpl of AdventurerListTrait {
    /// What one unit of lane `lane` (0 to 6) adds to a stored page: a table (docs/CAIRO.md §3).
    fn unit(lane: u8) -> felt252 {
        match lane {
            0 => 0x1,
            1 => 0x100000000,
            2 => 0x10000000000000000,
            3 => 0x1000000000000000000000000,
            4 => 0x100000000000000000000000000000000,
            5 => 0x10000000000000000000000000000000000000000,
            6 => 0x1000000000000000000000000000000000000000000000000,
            _ => core::panic_with_felt252('lane above 6'),
        }
    }

    /// Lane `lane` (0 to 6).
    fn get(self: @Lanes32, lane: u8) -> u32 {
        let [a, b, c, d, e, f, g] = *self.lanes;
        match lane {
            0 => a,
            1 => b,
            2 => c,
            3 => d,
            4 => e,
            5 => f,
            6 => g,
            _ => core::panic_with_felt252('lane above 6'),
        }
    }

    /// The page with lane `lane` (0 to 6) set to `value`.
    fn set(self: @Lanes32, lane: u8, value: u32) -> Lanes32 {
        let [a, b, c, d, e, f, g] = *self.lanes;
        let lanes = match lane {
            0 => [value, b, c, d, e, f, g],
            1 => [a, value, c, d, e, f, g],
            2 => [a, b, value, d, e, f, g],
            3 => [a, b, c, value, e, f, g],
            4 => [a, b, c, d, value, f, g],
            5 => [a, b, c, d, e, value, g],
            6 => [a, b, c, d, e, f, value],
            _ => core::panic_with_felt252('lane above 6'),
        };
        Lanes32 { lanes }
    }
}

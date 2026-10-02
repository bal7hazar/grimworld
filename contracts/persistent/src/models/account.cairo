//! An account (ADR-0005): the owner is a field it can change (A-7), so the adventurers do not
//! follow an address. What is shared (the vault, gold, Rifts) is keyed by account id; what is
//! personal by adventurer id (design/03, D-33).

use core::num::traits::Zero;
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

/// The owner key of balances and gold: `kind × 2^32 + id`. `ESCROW` has one owner, id 0 (the
/// market): what each lot holds is in the lot, so posting never creates an escrow page per lot.
pub const PACK: u8 = 1;
pub const VAULT: u8 = 2;
pub const ESCROW: u8 = 3;

/// The owner key of balances and gold (`kind × 2^32 + id`).
#[generate_trait]
pub impl OwnerImpl of OwnerTrait {
    #[inline(always)]
    fn key(kind: u8, id: u32) -> felt252 {
        kind.into() * 0x100000000 + id.into()
    }

    /// The owner key of an adventurer's pack.
    #[inline(always)]
    fn pack(adventurer_id: u32) -> felt252 {
        Self::key(PACK, adventurer_id)
    }
}

/// Adventurer slots of a new account (design/03, D-33: three; more can be bought).
pub const START_SLOTS: u8 = 3;

/// `account_adventurers` is a compact list of adventurer ids, seven per page (`Lanes32`), its
/// length `AccountRecord.adventurers`: an append writes lane `n % 7` of page `n / 7`; a removal
/// moves the last id into the hole and clears the last lane (`HubStoreTrait::add_adventurer_id`,
/// `HubStoreTrait::remove_adventurer_id`). A page once written keeps `LIVE`.
pub const IDS_PER_PAGE: u8 = 7;

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
    /// The swap removal did not meet the adventurer in its account's list: an invariant, not a
    /// player's refusal (the ownership check comes first).
    pub const NOT_LISTED: felt252 = 'not in the account list';
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

/// The list `account_adventurers`: seven ids a page (`models::lanes::StoredLanes`).
#[generate_trait]
pub impl AdventurerListImpl of AdventurerListTrait {
    /// `(page, lane)` of the list's `index`-th id.
    #[inline(always)]
    fn at(index: u8) -> (u8, u8) {
        DivRem::div_rem(index, IDS_PER_PAGE.try_into().unwrap())
    }
}

/// The list's refusals (ENG-04 audit F-6), each evaluated where it was before.
#[generate_trait]
pub impl AdventurerListAssert of AdventurerListAssertTrait {
    /// The swap removal's scan has not reached the list's last id without meeting the adventurer.
    #[inline(always)]
    fn assert_listed(index: u8, last: u8) {
        assert(index != last, errors::NOT_LISTED);
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::{
        Account, AccountRecord, AdventurerListAssert, AdventurerListTrait, OwnerTrait, VAULT,
    };

    // The record's round trip through its packer, and the account's two slots.
    #[test]
    #[available_gas(l2_gas: 47534)] // ceil(1.05 × 45270 measured)
    fn test_account_layout() {
        let record = AccountRecord {
            slots: 9, adventurers: 5, highest_rank: 4, vault_panes: 2, lots: 7,
        };
        let word: felt252 = StorePacking::pack(record);
        assert(StorePacking::<AccountRecord, felt252>::unpack(word) == record, 'record trip');
        assert(starknet::Store::<Account>::size() == 2, 'account: 2 slots');
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_owner_key() {
        assert(OwnerTrait::key(VAULT, 7) == 2 * 0x100000000 + 7, 'owner key');
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_list_at() {
        assert(AdventurerListTrait::at(0) == (0, 0), 'first');
        assert(AdventurerListTrait::at(13) == (1, 6), 'fourteenth');
    }

    #[test]
    #[should_panic(expected: 'not in the account list')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_not_listed_refused() {
        AdventurerListAssert::assert_listed(3, 3);
    }
}

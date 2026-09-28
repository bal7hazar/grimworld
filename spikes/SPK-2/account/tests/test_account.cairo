//! The measuring account deploys, keeps its key and answers as an SRC-6 account.

use openzeppelin_interfaces::accounts::{AccountABIDispatcher, AccountABIDispatcherTrait, ISRC6_ID};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};

#[test]
#[available_gas(l2_gas: 1431339)] // ceil(1.05 × 1363180 measured)
fn test_account_deploys_with_its_key() {
    let key: felt252 = 0x1234;
    let (address, _) = declare("Account").unwrap().contract_class().deploy(@array![key]).unwrap();
    let account = AccountABIDispatcher { contract_address: address };
    assert!(account.get_public_key() == key);
    assert!(account.supports_interface(ISRC6_ID));
}

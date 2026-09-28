use starknet::ContractAddress;

#[derive(Copy, Drop, Serde)]
#[dojo::model]
pub struct Marker {
    #[key]
    pub owner: ContractAddress,
    pub value: u32,
}

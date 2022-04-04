use ethereum_types::U256; // allows us to easily convert from hex to U256 for verifyProof inputs
use ethers::{prelude::*, utils::Ganache};
use eyre::Result;
use std::{convert::TryFrom, sync::Arc, time::Duration};

// Generate the type-safe contract bindings by providing the json artifact
// this will embed the bytecode in a variable `JUMPCONTRACT_BYTECODE`
abigen!(JumpContract, "contract_abi.json",);

#[tokio::main]
async fn main() -> Result<()> {
    // 1. compile the contract and launch ganache, must have ganache-cli installed
    let ganache = Ganache::new().spawn();

    // 2. instantiate our wallet
    let wallet: LocalWallet = ganache.keys()[0].clone().into();

    // 3. connect to the network
    let provider =
        Provider::<Http>::try_from(ganache.endpoint())?.interval(Duration::from_millis(10u64));

    // 4. instantiate the client with the wallet
    let client = Arc::new(SignerMiddleware::new(provider, wallet));

    // 5. deploy contract, note the `legacy` call required for non EIP-1559
    let jump_contract = JumpContract::deploy(client, ())
        .unwrap()
        .legacy()
        .send()
        .await
        .unwrap();

    // proof arguments
    let (a, b, c, input) = (
        [
            U256::from_str_radix(
                "0x241a42399847fb099dac3bf4c2b0134402679858c83883115b67896e6adee980",
                16,
            )
            .unwrap(),
            U256::from_str_radix(
                "0x0a3d83a23482ca9338839502b4e13e3aeda4e77ff491a8df098e2727b048f670",
                16,
            )
            .unwrap(),
        ],
        [
            [
                U256::from_str_radix(
                    "0x28615572f8fc1c0fdab460c0778ed06a0b0a42c1ab98018c30642572ad9c1eab",
                    16,
                )
                .unwrap(),
                U256::from_str_radix(
                    "0x1b056ca078472c85a2ab544d5e7e4633099d882615cec0f877ad192f54831eca",
                    16,
                )
                .unwrap(),
            ],
            [
                U256::from_str_radix(
                    "0x215266714951da26adc3cff706cdfb9926f7e663f2d5b6fc3943abe3ff262fbb",
                    16,
                )
                .unwrap(),
                U256::from_str_radix(
                    "0x0eac220fa840c4e5d114023986071e341236057935c381aa8852fbc2dd8c6c23",
                    16,
                )
                .unwrap(),
            ],
        ],
        [
            U256::from_str_radix(
                "0x071b1cf762119f110c06c61f8b26f5b6cb9654bb25a683af13bcf2c34036b485",
                16,
            )
            .unwrap(),
            U256::from_str_radix(
                "0x0bd967490e7079abe55eca2d7880ec42e0afd3aec525da0f3ee5c9f500ba8554",
                16,
            )
            .unwrap(),
        ],
        [U256::from_str_radix(
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            16,
        )
        .unwrap()],
    );
    // 6. call contract function jump with proof arguments
    let jump = jump_contract.jump(a, b, c, input).call().await.unwrap();
    // 7. should return true if proof was valid
    assert_eq!(true, jump);
    println!("We made it!");
    Ok(())
}

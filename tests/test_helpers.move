#[test_only]
module lucky_survivor::test_helpers {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    public fun setup_aptos_coin(): (
        signer, coin::BurnCapability<AptosCoin>, coin::MintCapability<AptosCoin>
    ) {
        let aptos_framework = account::create_signer_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        (aptos_framework, burn_cap, mint_cap)
    }

    public fun fund_account(
        mint_cap: &coin::MintCapability<AptosCoin>, addr: address, amount: u64
    ) {
        let coins = coin::mint<AptosCoin>(amount, mint_cap);
        aptos_framework::aptos_account::create_account(addr);
        coin::deposit(addr, coins);
    }
}


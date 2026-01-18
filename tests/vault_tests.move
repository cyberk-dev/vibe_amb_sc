#[test_only]
module lucky_survivor::vault_tests {
    use std::signer;
    use std::option;
    use std::string;
    use aptos_framework::object;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use lucky_survivor::vault;
    use lucky_survivor::package_manager;

    fun create_fungible_asset_and_mint(
        creator: &signer, name: vector<u8>, amount: u64
    ): object::Object<Metadata> {
        let token_metadata = &object::create_named_object(creator, name);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_metadata,
            option::none(),
            string::utf8(name),
            string::utf8(name),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let mint_ref = &fungible_asset::generate_mint_ref(token_metadata);
        let fa = fungible_asset::mint(mint_ref, amount);
        let metadata = fungible_asset::asset_metadata(&fa);
        primary_fungible_store::deposit(signer::address_of(creator), fa);
        metadata
    }

    #[test(deployer = @deployer)]
    fun test_initialized(deployer: &signer) {
        package_manager::initialize_for_test();
        vault::init_for_test(deployer);
    }

    #[test(deployer = @deployer)]
    fun test_deposit(deployer: &signer) {
        package_manager::initialize_for_test();
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST", 1000);
        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);

        let fa = primary_fungible_store::withdraw(deployer, metadata, 500);
        vault::deposit_for_test(fa);

        assert!(vault::get_balance(metadata) == 500, 0);
    }

    #[test(deployer = @deployer)]
    fun test_record_prize(deployer: &signer) {
        package_manager::initialize_for_test();
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST", 1000);
        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);
        vault::record_prize_for_test(@0xABC, metadata, 100);
        assert!(vault::get_claimable_balance(@0xABC, metadata) == 100, 0);
    }

    #[test(deployer = @deployer)]
    fun test_record_prize_accumulates(deployer: &signer) {
        package_manager::initialize_for_test();
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST", 1000);
        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);
        vault::record_prize_for_test(@0xABC, metadata, 100);
        vault::record_prize_for_test(@0xABC, metadata, 100);
        assert!(vault::get_claimable_balance(@0xABC, metadata) == 200, 0);
    }

    #[test(deployer = @deployer, user = @0xABC)]
    fun test_claim_prizes(deployer: &signer, user: &signer) {
        package_manager::initialize_for_test();
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST", 1000);

        account::create_account_for_test(signer::address_of(user));

        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);

        let fa = primary_fungible_store::withdraw(deployer, metadata, 500);
        vault::deposit_for_test(fa);

        vault::record_prize_for_test(signer::address_of(user), metadata, 100);
        assert!(vault::get_claimable_balance(signer::address_of(user), metadata) == 100, 0);

        vault::claim_prizes(user, metadata);

        assert!(vault::get_claimable_balance(signer::address_of(user), metadata) == 0, 1);
        assert!(primary_fungible_store::balance(signer::address_of(user), metadata) == 100, 2);
    }

    #[test(deployer = @deployer, user = @0xABC)]
    #[expected_failure(abort_code = 1001, location = lucky_survivor::vault)]
    fun test_claim_no_balance(deployer: &signer, user: &signer) {
        package_manager::initialize_for_test();
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST", 1000);

        account::create_account_for_test(signer::address_of(user));

        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);

        let fa = primary_fungible_store::withdraw(deployer, metadata, 500);
        vault::deposit_for_test(fa);

        vault::claim_prizes(user, metadata);
    }
}

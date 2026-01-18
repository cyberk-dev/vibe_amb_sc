#[test_only]
module lucky_survivor::test_helpers {
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::object;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use lucky_survivor::vault;
    use lucky_survivor::game;
    use lucky_survivor::package_manager;
    use lucky_survivor::whitelist;

    public fun create_fungible_asset_and_mint(
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

    public fun setup_funded_vault(deployer: &signer, amount: u64): object::Object<Metadata> {
        let metadata = create_fungible_asset_and_mint(deployer, b"TEST_TOKEN", amount);

        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);

        let fa = primary_fungible_store::withdraw(deployer, metadata, amount);
        vault::deposit_for_test(fa);

        game::set_asset_for_test(metadata);

        metadata
    }

    public fun setup_funded_vault_with_metadata(
        deployer: &signer, metadata: object::Object<Metadata>, amount: u64
    ) {
        vault::init_for_test(deployer);
        vault::set_payment_fa_for_test(metadata, true);

        let fa = primary_fungible_store::withdraw(deployer, metadata, amount);
        vault::deposit_for_test(fa);

        game::set_asset_for_test(metadata);
    }

    public fun fund_account(
        deployer: &signer, metadata: object::Object<Metadata>, addr: address, amount: u64
    ) {
        aptos_framework::aptos_account::create_account(addr);
        primary_fungible_store::transfer(deployer, metadata, addr, amount);
    }

    /// Initialize whitelist for testing
    public fun setup_whitelist() {
        whitelist::init_for_test();
    }

    /// Register a user and join game with auto-generated name
    public fun register_and_join(user: &signer) {
        let addr = signer::address_of(user);
        whitelist::register(user);
        let code = whitelist::get_invite_code(addr);
        let name = generate_player_name(addr);
        game::set_display_name(user, code, name);
        game::join_game(user, code);
    }

    /// Register a user and join game with custom name
    public fun register_and_join_with_name(user: &signer, name: String) {
        let addr = signer::address_of(user);
        whitelist::register(user);
        let code = whitelist::get_invite_code(addr);
        game::set_display_name(user, code, name);
        game::join_game(user, code);
    }

    /// Generate a simple player name from address
    fun generate_player_name(addr: address): String {
        // Simple name generation based on address
        let _ = addr;
        string::utf8(b"Player")
    }
}

module lucky_survivor::router {
    use std::signer;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;
    use lucky_survivor::vault;
    use lucky_survivor::whitelist;
    use lucky_survivor::game;

    /// Caller is not the admin
    const E_NOT_ADMIN: u64 = 4001;

    /// Initialize all modules in one transaction
    public entry fun initialize_all(
        admin: &signer,
        prize_pool: u64,
        asset_metadata: Object<Metadata>
    ) {
        ensure_admin(admin);

        // 1. Vault
        vault::initialize_friend(admin);
        vault::set_payment_fa_friend(admin, asset_metadata, true);

        // 2. Whitelist
        whitelist::initialize_friend(admin);

        // 3. Game
        game::initialize_friend(admin, prize_pool);
        game::set_asset_friend(admin, asset_metadata);
    }

    inline fun ensure_admin(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_NOT_ADMIN);
    }
}

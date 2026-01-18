module lucky_survivor::vault {
    use std::signer;
    use std::event;
    use aptos_framework::object::{Object, Self};
    use aptos_framework::bcs;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;

    use lucky_survivor::package_manager;

    friend lucky_survivor::game;  // for record_prize

    //--------------------------------------------------
    // Errors
    //--------------------------------------------------
    const E_NO_CLAIMABLE_BALANCE: u64 = 1001;
    const E_ZERO_AMOUNT: u64 = 1002;
    const E_ACCESS_DENIED: u64 = 1003;
    const E_NOT_ALLOWED_PAYMENT_FA: u64 = 1004;

    //--------------------------------------------------
    // Events
    //--------------------------------------------------
    #[event]
    struct Initialized has store, drop {}

    #[event]
    struct PaymentSet has store, drop {
        metadata: Object<Metadata>,
        enabled: bool
    }

    #[event]
    struct PaymentDeposited has store, drop {
        metadata: Object<Metadata>,
        amount: u64
    }

    #[event]
    struct PaymentWithdrawn has store, drop {
        metadata: Object<Metadata>,
        amount: u64
    }

    #[event]
    struct PrizeClaimed has store, drop {
        recipient: address,
        metadata: Object<Metadata>,
        amount: u64
    }

    //--------------------------------------------------
    // Structs
    //--------------------------------------------------
    struct ClaimKey has copy, drop, store {
        user: address,
        asset: Object<Metadata>
    }

    struct Vault has key {
        payment_fas: SmartTable<Object<Metadata>, bool>,
        payment_stores: SmartTable<Object<Metadata>, Object<FungibleStore>>,
        claimable_balances: SmartTable<ClaimKey, u64>
    }

    #[test_only]
    public fun init_for_test(_admin: &signer) {
        let resource_signer = package_manager::get_signer();
        move_to(
            &resource_signer,
            Vault {
                payment_fas: smart_table::new(),
                payment_stores: smart_table::new(),
                claimable_balances: smart_table::new()
            }
        );
    }

    public entry fun initialize(admin: &signer) {
        ensure_admin(admin);
        let resource_signer = package_manager::get_signer();
        move_to(
            &resource_signer,
            Vault {
                payment_fas: smart_table::new(),
                payment_stores: smart_table::new(),
                claimable_balances: smart_table::new()
            }
        );
        event::emit(Initialized {});
    }

    public entry fun set_payment_fa(admin: &signer, metadata: Object<Metadata>, enabled: bool) acquires Vault {
        ensure_admin(admin);
        set_payment_internal(metadata, enabled);
    }

    fun set_payment_internal(metadata: Object<Metadata>, enabled: bool) acquires Vault {
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        vault.payment_fas.upsert(metadata, enabled);
        if (enabled && !vault.payment_stores.contains(metadata)) {
            let resource_signer = &package_manager::get_signer();
            let seed = bcs::to_bytes(&object::object_address(&metadata));
            let store_const = object::create_named_object(resource_signer, seed);
            let store = fungible_asset::create_store(&store_const, metadata);
            vault.payment_stores.add(metadata, store);
        };
        event::emit(PaymentSet { metadata, enabled });
    }

    fun deposit_internal(fa: FungibleAsset) acquires Vault {
        let metadata = fungible_asset::asset_metadata(&fa);
        let vault = borrow_global<Vault>(@lucky_survivor);
        assert!(vault.payment_fas.contains(metadata), E_NOT_ALLOWED_PAYMENT_FA);
        let store = *vault.payment_stores.borrow(metadata);
        let amount = fungible_asset::amount(&fa);
        dispatchable_fungible_asset::deposit(store, fa);
        event::emit(PaymentDeposited { metadata, amount });
    }

    fun withdraw_internal(metadata: Object<Metadata>, amount: u64): FungibleAsset acquires Vault {
        let vault = borrow_global<Vault>(@lucky_survivor);
        assert!(vault.payment_fas.contains(metadata), E_NOT_ALLOWED_PAYMENT_FA);
        let resource_signer = &package_manager::get_signer();
        let store = *vault.payment_stores.borrow(metadata);
        let fa = dispatchable_fungible_asset::withdraw(resource_signer, store, amount);
        event::emit(PaymentWithdrawn { metadata, amount });
        fa
    }

    public(friend) fun record_prize(recipient: address, metadata: Object<Metadata>, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        let key = ClaimKey { user: recipient, asset: metadata };
        let current_balance =
            if (vault.claimable_balances.contains(key)) {
                *vault.claimable_balances.borrow(key)
            } else { 0 };
        vault.claimable_balances.upsert(key, current_balance + amount);
    }

    public entry fun fund_vault(funder: &signer, metadata: Object<Metadata>, amount: u64) acquires Vault {
        let fa = primary_fungible_store::withdraw(funder, metadata, amount);
        deposit_internal(fa);
    }

    public entry fun withdraw_all(admin: &signer, metadata: Object<Metadata>) acquires Vault {
        ensure_admin(admin);
        let balance = get_balance(metadata);
        if (balance == 0) return;
        let fa = withdraw_internal(metadata, balance);
        primary_fungible_store::deposit(signer::address_of(admin), fa);
    }

    public entry fun claim_prizes(user: &signer, metadata: Object<Metadata>) acquires Vault {
        let addr = signer::address_of(user);
        let key = ClaimKey { user: addr, asset: metadata };
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        assert!(vault.claimable_balances.contains(key), E_NO_CLAIMABLE_BALANCE);
        let amount = *vault.claimable_balances.borrow(key);
        assert!(amount > 0, E_ZERO_AMOUNT);
        vault.claimable_balances.upsert(key, 0);

        let fa = withdraw_internal(metadata, amount);
        primary_fungible_store::deposit(addr, fa);
        event::emit(PrizeClaimed { recipient: addr, metadata, amount });
    }

    //--------------------------------------------------
    // View Functions
    //--------------------------------------------------
    #[view]
    public fun get_claimable_balance(addr: address, metadata: Object<Metadata>): u64 acquires Vault {
        let vault = borrow_global<Vault>(@lucky_survivor);
        let key = ClaimKey { user: addr, asset: metadata };
        if (vault.claimable_balances.contains(key)) {
            *vault.claimable_balances.borrow(key)
        } else { 0 }
    }

    #[view]
    public fun get_balance(metadata: Object<Metadata>): u64 acquires Vault {
        let vault = borrow_global<Vault>(@lucky_survivor);
        if (!vault.payment_fas.contains(metadata)) {
            return 0
        };
        let store = *vault.payment_stores.borrow(metadata);
        fungible_asset::balance(store)
    }

    #[view]
    public fun is_valid_payment_fa(metadata: Object<Metadata>): bool acquires Vault {
        borrow_global<Vault>(@lucky_survivor).payment_fas.contains(metadata)
    }

    //--------------------------------------------------
    // Test Helpers
    //--------------------------------------------------
    #[test_only]
    public fun deposit_for_test(fa: FungibleAsset) acquires Vault {
        deposit_internal(fa);
    }

    #[test_only]
    public fun record_prize_for_test(recipient: address, metadata: Object<Metadata>, amount: u64) acquires Vault {
        record_prize(recipient, metadata, amount);
    }

    #[test_only]
    public fun set_payment_fa_for_test(metadata: Object<Metadata>, enabled: bool) acquires Vault {
        set_payment_internal(metadata, enabled);
    }

    inline fun ensure_admin(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
    }
}

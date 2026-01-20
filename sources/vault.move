module lucky_survivor::vault {
    use std::vector;
    use std::signer;
    use std::event;
    use aptos_framework::object::{Object, Self};
    use aptos_framework::bcs;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;

    use lucky_survivor::package_manager;
    use lucky_survivor::full_math;

    friend lucky_survivor::game; // for record_prize
    friend lucky_survivor::router; // for initialize_friend

    //--------------------------------------------------
    // Errors
    //--------------------------------------------------
    const E_NO_CLAIMABLE_BALANCE: u64 = 1001;
    const E_ZERO_AMOUNT: u64 = 1002;
    const E_ACCESS_DENIED: u64 = 1003;
    const E_NOT_ALLOWED_PAYMENT_FA: u64 = 1004;
    const E_INSUFFICIENT_BALANCE: u64 = 1005;

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

    #[event]
    struct AdminPrizesDistributed has store, drop {
        recipients_count: u64,
        metadata: Object<Metadata>,
        amount_per_recipient: u64,
        total_distributed: u64
    }

    #[event]
    struct AdminPrizesRecorded has store, drop {
        recipients_count: u64,
        metadata: Object<Metadata>,
        amount_per_recipient: u64,
        total_amount: u64
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

    /// Friend function for router to initialize
    public(friend) fun initialize_friend(admin: &signer) {
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

    /// Friend function for router to set payment FA
    public(friend) fun set_payment_fa_friend(
        admin: &signer, metadata: Object<Metadata>, enabled: bool
    ) acquires Vault {
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

    public(friend) fun record_prize(
        recipient: address, metadata: Object<Metadata>, amount: u64
    ) acquires Vault {
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        let key = ClaimKey { user: recipient, asset: metadata };
        let current_balance =
            if (vault.claimable_balances.contains(key)) {
                *vault.claimable_balances.borrow(key)
            } else { 0 };
        vault.claimable_balances.upsert(key, current_balance + amount);
    }

    public entry fun fund_vault(
        funder: &signer, metadata: Object<Metadata>, amount: u64
    ) acquires Vault {
        let fa = primary_fungible_store::withdraw(funder, metadata, amount);
        deposit_internal(fa);
    }

    public entry fun withdraw_all(
        admin: &signer, metadata: Object<Metadata>
    ) acquires Vault {
        ensure_admin(admin);
        let balance = get_balance(metadata);
        if (balance == 0) return;
        let fa = withdraw_internal(metadata, balance);
        primary_fungible_store::deposit(signer::address_of(admin), fa);
    }

    public entry fun claim_prizes(
        user: &signer, metadata: Object<Metadata>
    ) acquires Vault {
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

    /// Admin function to distribute a specified amount equally among recipients
    /// Recipients are queried off-chain from whitelist and passed as parameter
    /// amount_to_distribute: total amount to distribute (vault_balance - pending_claims)
    /// Each recipient gets: amount_to_distribute / recipients.length()
    /// Only callable by deployer. Users can then claim via claim_prizes()
    public entry fun admin_distribute_prizes(
        admin: &signer,
        recipients: vector<address>,
        metadata: Object<Metadata>,
        amount_to_distribute: u64
    ) acquires Vault {
        ensure_admin(admin);
        let len = recipients.length();
        assert!(len > 0, E_ZERO_AMOUNT);
        assert!(amount_to_distribute > 0, E_ZERO_AMOUNT);

        // Calculate equal share using full_math for precision
        let amount_per_recipient =
            full_math::mul_div_u64(amount_to_distribute, 1, (len as u64));
        assert!(amount_per_recipient > 0, E_ZERO_AMOUNT);

        // Verify vault has enough balance for total distribution
        let vault_balance = get_balance(metadata);
        let total_to_distribute = amount_per_recipient * (len as u64);
        assert!(vault_balance >= total_to_distribute, E_INSUFFICIENT_BALANCE);

        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        let i = 0;
        while (i < len) {
            let recipient = recipients[i];
            let key = ClaimKey { user: recipient, asset: metadata };
            let current_balance =
                if (vault.claimable_balances.contains(key)) {
                    *vault.claimable_balances.borrow(key)
                } else { 0 };
            vault.claimable_balances.upsert(key, current_balance + amount_per_recipient);
            i += 1;
        };

        event::emit(
            AdminPrizesDistributed {
                recipients_count: len,
                metadata,
                amount_per_recipient,
                total_distributed: total_to_distribute
            }
        );
    }

    //--------------------------------------------------
    // View Functions
    //--------------------------------------------------
    #[view]
    public fun get_claimable_balance(
        addr: address, metadata: Object<Metadata>
    ): u64 acquires Vault {
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
    public fun record_prize_for_test(
        recipient: address, metadata: Object<Metadata>, amount: u64
    ) acquires Vault {
        record_prize(recipient, metadata, amount);
    }

    #[test_only]
    public fun set_payment_fa_for_test(
        metadata: Object<Metadata>, enabled: bool
    ) acquires Vault {
        set_payment_internal(metadata, enabled);
    }

    inline fun ensure_admin(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
    }
}


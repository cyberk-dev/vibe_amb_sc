module lucky_survivor::vault {
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::smart_table::{Self, SmartTable};
    use lucky_survivor::package_manager;

    const E_NO_CLAIMABLE_BALANCE: u64 = 1001;
    const E_ZERO_AMOUNT: u64 = 1002;
    const E_ACCESS_DENIED: u64 = 1003;

    friend lucky_survivor::game;

    struct Vault has key {
        balance: Coin<AptosCoin>,
        claimable_balances: SmartTable<address, u64> // Lưu số tiền được claim của mỗi user
    }

    #[test_only]
    public fun init_for_test(admin: &signer) {
        initialize(admin);
    }

    public entry fun initialize(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let resource_signer = package_manager::get_signer();
        move_to(
            &resource_signer,
            Vault {
                balance: coin::zero(),
                claimable_balances: smart_table::new()
            }
        )
    }

    public(friend) fun deposit(user: &signer, amount: u64) acquires Vault {
        let coin = coin::withdraw<AptosCoin>(user, amount);
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        coin::merge(&mut vault.balance, coin);
    }

    public(friend) fun record_prize(recipient: address, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        let current_balance =
            if (vault.claimable_balances.contains(recipient)) {
                *vault.claimable_balances.borrow(recipient)
            } else { 0 };
        vault.claimable_balances.upsert(recipient, current_balance + amount);
    }

    #[view]
    public fun get_claimable_balance(addr: address): u64 acquires Vault {
        let vault = borrow_global<Vault>(@lucky_survivor);
        if (vault.claimable_balances.contains(addr)) {
            *vault.claimable_balances.borrow(addr)
        } else { 0 }
    }

    public entry fun claim_prizes(user: &signer) acquires Vault {
        let addr = signer::address_of(user);
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        assert!(
            vault.claimable_balances.contains(addr),
            E_NO_CLAIMABLE_BALANCE
        );
        let amount = *vault.claimable_balances.borrow(addr);
        assert!(amount > 0, E_ZERO_AMOUNT);
        // reset
        vault.claimable_balances.upsert(addr, 0);
        let coins = coin::extract(&mut vault.balance, amount);
        coin::deposit(addr, coins);
    }

    #[test_only]
    public fun deposit_for_test(user: &signer, amount: u64) acquires Vault {
        deposit(user, amount);
    }

    #[test_only]
    public fun record_prize_for_test(recipient: address, amount: u64) acquires Vault {
        record_prize(recipient, amount);
    }
}


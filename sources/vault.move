module lucky_survivor::vault {
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::smart_table::{Self, SmartTable};

    const E_NO_CLAIMABLE_BALANCE: u64 = 1001;
    const E_ZERO_AMOUNT: u64 = 1002;

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
        move_to(
            admin,
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
            if (smart_table::contains(&vault.claimable_balances, recipient)) {
                *smart_table::borrow(&vault.claimable_balances, recipient)
            } else { 0 };
        smart_table::upsert(
            &mut vault.claimable_balances, recipient, current_balance + amount
        );
    }

    #[view]
    public fun get_claimable_balance(addr: address): u64 acquires Vault {
        let vault = borrow_global<Vault>(@lucky_survivor);
        if (smart_table::contains(&vault.claimable_balances, addr)) {
            *smart_table::borrow(&vault.claimable_balances, addr)
        } else { 0 }
    }

    public entry fun claim_prizes(user: &signer) acquires Vault {
        let addr = signer::address_of(user);
        let vault = borrow_global_mut<Vault>(@lucky_survivor);
        assert!(
            smart_table::contains(&vault.claimable_balances, addr),
            E_NO_CLAIMABLE_BALANCE
        );
        let amount = *smart_table::borrow(&vault.claimable_balances, addr);
        assert!(amount > 0, E_ZERO_AMOUNT);
        // reset
        smart_table::upsert(&mut vault.claimable_balances, addr, 0);
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


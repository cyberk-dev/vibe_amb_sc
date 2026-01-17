#[test_only]
module lucky_survivor::vault_tests {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use lucky_survivor::vault;
    use lucky_survivor::test_helpers;

    #[test(admin = @lucky_survivor)]
    fun test_initialized(admin: &signer) {
        vault::init_for_test(admin);
    }

    #[test(admin = @lucky_survivor, user = @0x123)]
    fun test_deposit(admin: &signer, user: &signer) {
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        test_helpers::fund_account(&mint_cap, signer::address_of(user), 1000);
        vault::init_for_test(admin);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(admin = @lucky_survivor)]
    fun test_record_prize(admin: &signer) {
        vault::init_for_test(admin);
        vault::record_prize_for_test(@0xABC, 100);
        assert!(vault::get_claimable_balance(@0xABC) == 100);
    }

    #[test(admin = @lucky_survivor)]
    fun test_record_prize_accumulates(admin: &signer) {
        vault::init_for_test(admin);
        vault::record_prize_for_test(@0xABC, 100);
        vault::record_prize_for_test(@0xABC, 100);
        assert!(vault::get_claimable_balance(@0xABC) == 200);
    }

    #[test(admin = @lucky_survivor, user = @0xABC)]
    fun test_claim_prizes(admin: &signer, user: &signer) {
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        test_helpers::fund_account(&mint_cap, @lucky_survivor, 1000);
        aptos_framework::aptos_account::create_account(signer::address_of(user));
        vault::init_for_test(admin);
        vault::deposit_for_test(admin, 500);
        vault::record_prize_for_test(signer::address_of(user), 100);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 100);
        vault::claim_prizes(user);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 0, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(admin = @lucky_survivor, user = @0xABC)]
    #[expected_failure(abort_code = 1001, location = lucky_survivor::vault)]
    fun test_claim_no_balance(admin: &signer, user: &signer) {
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        test_helpers::fund_account(&mint_cap, @lucky_survivor, 1000);
        aptos_framework::aptos_account::create_account(signer::address_of(user));
        vault::init_for_test(admin);
        vault::deposit_for_test(admin, 500);
        // vault::record_prize_for_test(signer::address_of(user), 100);
        // assert!(vault::get_claimable_balance(signer::address_of(user)) == 100);
        vault::claim_prizes(user);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 0, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}


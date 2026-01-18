#[test_only]
module lucky_survivor::vault_tests {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use lucky_survivor::vault;
    use lucky_survivor::test_helpers;
    use lucky_survivor::package_manager;

    #[test(deployer = @deployer)]
    fun test_initialized(deployer: &signer) {
        package_manager::initialize_for_test();
        vault::init_for_test(deployer);
    }

    #[test(deployer = @deployer, user = @0x123)]
    fun test_deposit(deployer: &signer, user: &signer) {
        package_manager::initialize_for_test();
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        test_helpers::fund_account(&mint_cap, signer::address_of(user), 1000);
        vault::init_for_test(deployer);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer)]
    fun test_record_prize(deployer: &signer) {
        package_manager::initialize_for_test();
        vault::init_for_test(deployer);
        vault::record_prize_for_test(@0xABC, 100);
        assert!(vault::get_claimable_balance(@0xABC) == 100);
    }

    #[test(deployer = @deployer)]
    fun test_record_prize_accumulates(deployer: &signer) {
        package_manager::initialize_for_test();
        vault::init_for_test(deployer);
        vault::record_prize_for_test(@0xABC, 100);
        vault::record_prize_for_test(@0xABC, 100);
        assert!(vault::get_claimable_balance(@0xABC) == 200);
    }

    #[test(deployer = @deployer, user = @0xABC)]
    fun test_claim_prizes(deployer: &signer, user: &signer) {
        package_manager::initialize_for_test();
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        // Fund resource account (already created by initialize_for_test)
        let coins = aptos_framework::coin::mint<aptos_framework::aptos_coin::AptosCoin>(1000, &mint_cap);
        aptos_framework::coin::register<aptos_framework::aptos_coin::AptosCoin>(&package_manager::get_signer());
        aptos_framework::coin::deposit(@lucky_survivor, coins);
        aptos_framework::aptos_account::create_account(signer::address_of(user));
        vault::init_for_test(deployer);
        let resource_signer = package_manager::get_signer();
        vault::deposit_for_test(&resource_signer, 500);
        vault::record_prize_for_test(signer::address_of(user), 100);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 100);
        vault::claim_prizes(user);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 0, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(deployer = @deployer, user = @0xABC)]
    #[expected_failure(abort_code = 1001, location = lucky_survivor::vault)]
    fun test_claim_no_balance(deployer: &signer, user: &signer) {
        package_manager::initialize_for_test();
        let (_, burn_cap, mint_cap) = test_helpers::setup_aptos_coin();
        // Fund resource account (already created by initialize_for_test)
        let coins = aptos_framework::coin::mint<aptos_framework::aptos_coin::AptosCoin>(1000, &mint_cap);
        aptos_framework::coin::register<aptos_framework::aptos_coin::AptosCoin>(&package_manager::get_signer());
        aptos_framework::coin::deposit(@lucky_survivor, coins);
        aptos_framework::aptos_account::create_account(signer::address_of(user));
        vault::init_for_test(deployer);
        let resource_signer = package_manager::get_signer();
        vault::deposit_for_test(&resource_signer, 500);
        // vault::record_prize_for_test(signer::address_of(user), 100);
        // assert!(vault::get_claimable_balance(signer::address_of(user)) == 100);
        vault::claim_prizes(user);
        assert!(vault::get_claimable_balance(signer::address_of(user)) == 0, 1);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}

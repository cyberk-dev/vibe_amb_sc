module lucky_survivor::package_manager {
    use std::signer;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::code;
    use aptos_framework::resource_account;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::string::String;
    use aptos_framework::timestamp;

    friend lucky_survivor::game;
    friend lucky_survivor::vault;

    #[test_only]
    friend lucky_survivor::package_manager_tests;
    #[test_only]
    friend lucky_survivor::test_helpers;
    #[test_only]
    friend lucky_survivor::vault_tests;
    #[test_only]
    friend lucky_survivor::game_tests;

    const E_NOT_ALLOWED: u64 = 1;

    struct PermissionConfig has key {
        signer_cap: SignerCapability,
        addresses: SmartTable<String, address>
    }

    fun init_module(package_signer: &signer) {
        let signer_cap =
            resource_account::retrieve_resource_account_cap(package_signer, @deployer);
        move_to(
            package_signer,
            PermissionConfig {
                addresses: smart_table::new<String, address>(),
                signer_cap
            }
        );
    }

    entry fun upgrade(
        upgrader: &signer, package_metadata: vector<u8>, code: vector<vector<u8>>
    ) acquires PermissionConfig {
        assert!(signer::address_of(upgrader) == @deployer, E_NOT_ALLOWED);
        let resource_signer = &get_signer();
        code::publish_package_txn(resource_signer, package_metadata, code);
    }

    public(friend) fun get_signer(): signer acquires PermissionConfig {
        let signer_cap = &borrow_global<PermissionConfig>(@lucky_survivor).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    public fun get_resource_address(): address acquires PermissionConfig {
        signer::address_of(&get_signer())
    }

    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        let addresses =
            &mut borrow_global_mut<PermissionConfig>(@lucky_survivor).addresses;
        addresses.add(name, object);
    }

    public(friend) fun address_exists(name: String): bool acquires PermissionConfig {
        borrow_global<PermissionConfig>(@lucky_survivor).addresses.contains(name)
    }

    public(friend) fun get_address(name: String): address acquires PermissionConfig {
        *borrow_global<PermissionConfig>(@lucky_survivor).addresses.borrow(name)
    }

    #[test_only]
    public fun initialize_for_test() {
        let account = &account::create_signer_for_test(@lucky_survivor);
        if (!exists<PermissionConfig>(@lucky_survivor)) {
            timestamp::set_time_has_started_for_testing(
                &account::create_signer_for_test(@0x1)
            );
            account::create_account_for_test(@lucky_survivor);
            move_to(
                account,
                PermissionConfig {
                    addresses: smart_table::new<String, address>(),
                    signer_cap: account::create_test_signer_cap(@lucky_survivor)
                }
            )
        }
    }
}


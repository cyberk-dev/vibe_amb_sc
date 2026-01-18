#[test_only]
module lucky_survivor::package_manager_tests {
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use lucky_survivor::package_manager;

    #[test]
    fun test_initialize_for_test() {
        package_manager::initialize_for_test();
        let resource_addr = package_manager::get_resource_address();
        assert!(resource_addr == @lucky_survivor, 0);
    }

    #[test]
    fun test_address_management() {
        package_manager::initialize_for_test();

        let test_name = string::utf8(b"test_module");
        let test_addr = @0x123;
        assert!(!package_manager::address_exists(test_name), 0);

        package_manager::add_address(test_name, test_addr);

        assert!(package_manager::address_exists(test_name), 1);
        assert!(package_manager::get_address(test_name) == test_addr, 2);
    }

    // #[test(deployer = @deployer)]
    // #[
    //     expected_failure(
    //         abort_code = package_manager::E_NOT_ALLOWED,
    //         location = lucky_survivor::package_manager
    //     )
    // ]
    // fun test_upgrade_not_authorized(deployer: &signer) {
    //     package_manager::initialize_for_test();
    //     // Create a random account to try upgrading
    //     let hacker = account::create_account_for_test(@0xDEAD);

    //     // Should fail because hacker != deployer
    //     package_manager::upgrade(&hacker, vector::empty(), vector::empty());
    // }
}


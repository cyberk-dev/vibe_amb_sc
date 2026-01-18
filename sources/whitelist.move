module lucky_survivor::whitelist {
    use std::string::{Self, String};
    use std::signer;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::string_utils;
    use lucky_survivor::package_manager;

    friend lucky_survivor::game;
    friend lucky_survivor::router;

    // === Error Codes ===
    const E_ALREADY_REGISTERED: u64 = 3001;
    const E_NOT_REGISTERED: u64 = 3002;
    const E_NOT_ADMIN: u64 = 3003;
    const E_INVALID_CODE: u64 = 3004;

    // === Structs ===
    struct Whitelist has key {
        next_code_id: u64,
        codes: SmartTable<String, address>, // code -> owner
        players: SmartTable<address, String> // player -> code
    }

    // === Entry Functions ===

    /// Friend function for router to initialize
    public(friend) fun initialize_friend(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_NOT_ADMIN);

        let resource_signer = package_manager::get_signer();

        move_to(
            &resource_signer,
            Whitelist {
                next_code_id: 1,
                codes: smart_table::new(),
                players: smart_table::new()
            }
        );
    }

    /// User self-registers, generates unique invite code
    public entry fun register(user: &signer) acquires Whitelist {
        let addr = signer::address_of(user);
        let whitelist = borrow_global_mut<Whitelist>(@lucky_survivor);

        // Check not already registered
        assert!(!whitelist.players.contains(addr), E_ALREADY_REGISTERED);

        // Generate unique code
        let code = generate_code(whitelist.next_code_id);
        whitelist.next_code_id += 1;

        // Store mappings
        whitelist.codes.add(code, addr);
        whitelist.players.add(addr, code);
    }

    // === View Functions ===

    #[view]
    public fun is_registered(player: address): bool acquires Whitelist {
        if (!exists<Whitelist>(@lucky_survivor)) {
            return false
        };
        let whitelist = borrow_global<Whitelist>(@lucky_survivor);
        whitelist.players.contains(player)
    }

    #[view]
    public fun get_registered_count(): u64 acquires Whitelist {
        if (!exists<Whitelist>(@lucky_survivor)) {
            return 0
        };
        let whitelist = borrow_global<Whitelist>(@lucky_survivor);
        whitelist.next_code_id - 1
    }

    #[view]
    public fun get_invite_code(player: address): String acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(@lucky_survivor);
        assert!(whitelist.players.contains(player), E_NOT_REGISTERED);
        *whitelist.players.borrow(player)
    }

    // === Friend Function (for game.move) ===

    /// Verify that the code belongs to the player
    public(friend) fun verify_code(player: address, code: String): bool acquires Whitelist {
        if (!exists<Whitelist>(@lucky_survivor)) {
            return false
        };
        let whitelist = borrow_global<Whitelist>(@lucky_survivor);

        // Check player is registered
        if (!whitelist.players.contains(player)) {
            return false
        };

        // Check code matches
        *whitelist.players.borrow(player) == code
    }

    // === Internal Functions ===

    /// Generate 6-digit code from counter (000001, 000002, ...)
    fun generate_code(id: u64): String {
        let id_str = string_utils::to_string(&id);
        let id_len = id_str.length();

        // Pad with leading zeros to make 6 digits
        let padding = string::utf8(b"");
        let zeros_needed = if (id_len < 6) {
            6 - id_len
        } else { 0 };

        let i = 0;
        while (i < zeros_needed) {
            padding.append(string::utf8(b"0"));
            i += 1;
        };

        padding.append(id_str);
        padding
    }

    // === Test Helpers ===

    #[test_only]
    public fun init_for_test() {
        package_manager::initialize_for_test();

        if (!exists<Whitelist>(@lucky_survivor)) {
            let resource_signer = package_manager::get_signer();
            move_to(
                &resource_signer,
                Whitelist {
                    next_code_id: 1,
                    codes: smart_table::new(),
                    players: smart_table::new()
                }
            );
        };
    }

    #[test_only]
    public fun reset_for_test() acquires Whitelist {
        if (exists<Whitelist>(@lucky_survivor)) {
            let Whitelist { next_code_id: _, codes, players } =
                move_from<Whitelist>(@lucky_survivor);
            codes.destroy();
            players.destroy();
        };
        init_for_test();
    }
}


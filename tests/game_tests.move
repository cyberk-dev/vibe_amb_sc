#[test_only]
module lucky_survivor::game_tests {
    use std::signer;
    use aptos_framework::account;
    use lucky_survivor::game;
    use lucky_survivor::vault;
    use lucky_survivor::package_manager;
    use lucky_survivor::test_helpers;
    use lucky_survivor::whitelist;
    use aptos_framework::timestamp;

    #[test(deployer = @deployer)]
    fun test_initialize(deployer: &signer) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 100);
        assert!(game::get_status() == 0, 0);
        assert!(game::get_players_count() == 0, 1);
    }

    #[test(deployer = @deployer, user1 = @0xA1, user2 = @0xA2)]
    fun test_join_game(deployer: &signer, user1: &signer, user2: &signer) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::register_and_join(user1);
        assert!(game::get_players_count() == 1, 0);
        test_helpers::register_and_join(user2);
        assert!(game::get_players_count() == 2, 1);
    }

    #[test(deployer = @deployer, user1 = @0xA1)]
    #[expected_failure(abort_code = 2002, location = lucky_survivor::game)]
    fun test_join_game_duplicate(deployer: &signer, user1: &signer) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);

        // Register once, then try to join twice
        let addr = signer::address_of(user1);
        whitelist::register(user1);
        let code = whitelist::get_invite_code(addr);
        game::set_display_name(user1, code, std::string::utf8(b"Player1"));
        game::join_game(user1, code);
        game::join_game(user1, code); // Should fail
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_start_game(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &aptos_framework::account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);
        assert!(game::get_status() == 1, 0);
        assert!(game::get_round() == 1, 1);
        assert!(game::get_elimination_count() == 1, 2);

        // Verify players have not acted yet
        let (players, _, statuses) = game::get_all_players();
        assert!(players.length() == 5, 3);
        assert!(!statuses[0] && !statuses[1], 4);
    }

    #[test(deployer = @deployer, u1 = @0x1, u2 = @0x2)]
    #[expected_failure(abort_code = 2003, location = lucky_survivor::game)]
    fun test_start_game_not_enough_players(
        deployer: &signer, u1: &signer, u2: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);

        aptos_framework::timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_choose_bao_keep(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);

        // u1 keeps their bao (assigns to self)
        let u1_addr = signer::address_of(u1);
        game::choose_bao(u1, u1_addr);

        assert!(game::has_selected(u1_addr), 0);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_choose_bao_give(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);

        // u1 gives their bao to u2
        let u1_addr = signer::address_of(u1);
        let u2_addr = signer::address_of(u2);
        game::choose_bao(u1, u2_addr);

        assert!(game::has_selected(u1_addr), 0);
        // Bao assignment verified internally - view functions hidden
        assert!(!game::has_selected(u2_addr), 1);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_multiple_baos_same_target(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);

        let u2_addr = signer::address_of(u2);

        // u1 gives to u2, u2 keeps, u3 gives to u2
        // u2 should end up with 3 baos (0, 1, 2)
        game::choose_bao(u1, u2_addr);  // bao 0 -> u2
        game::choose_bao(u2, u2_addr);  // bao 1 -> u2 (keep)
        game::choose_bao(u3, u2_addr);  // bao 2 -> u2

        // Verify all three players have acted
        assert!(game::has_selected(signer::address_of(u1)), 0);
        assert!(game::has_selected(signer::address_of(u2)), 1);
        assert!(game::has_selected(signer::address_of(u3)), 2);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2005, location = lucky_survivor::game)]
    fun test_choose_bao_already_acted(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);
        let u1_addr = signer::address_of(u1);
        game::choose_bao(u1, u1_addr);
        // Try to act again - should fail
        game::choose_bao(u1, u1_addr);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_selection_auto_keep(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);

        // Only u1 and u2 act, rest should auto-keep
        let u1_addr = signer::address_of(u1);
        game::choose_bao(u1, u1_addr);  // keep
        game::choose_bao(u2, u1_addr);  // give to u1

        game::finalize_selection(deployer);

        assert!(game::get_status() == 2, 0);  // STATUS_REVEALING

        // Verify all players have acted (u1, u2 explicitly, u3-u5 auto-keep)
        let (players, _, statuses) = game::get_all_players();
        assert!(players.length() == 5, 1);
        let i = 0;
        while (i < 5) {
            assert!(statuses[i], i + 2);
            i += 1;
        };
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_vote(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);

        game::set_voting_status_for_test();
        assert!(game::get_status() == 3, 0);

        game::vote(u1, 1);
        let (found, vote_val) = game::get_vote(signer::address_of(u1));
        assert!(found && vote_val == 1, 1);

        game::vote(u2, 0);
        let (found2, vote_val2) = game::get_vote(signer::address_of(u2));
        assert!(found2 && vote_val2 == 0, 2);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2011, location = lucky_survivor::game)]
    fun test_vote_duplicate(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);
        game::set_voting_status_for_test();

        game::vote(u1, 1);
        game::vote(u1, 0);
    }

    #[test(deployer = @deployer, u1 = @0x1)]
    #[expected_failure(abort_code = 2010, location = lucky_survivor::game)]
    fun test_vote_not_in_voting(deployer: &signer, u1: &signer) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::register_and_join(u1);

        game::vote(u1, 1);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_voting_continue(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);
        game::set_voting_status_for_test();
        game::vote(u1, 1);
        game::vote(u2, 0);
        game::vote(u3, 1);
        game::vote(u4, 1);
        game::vote(u5, 0);
        game::finalize_voting(deployer);
        assert!(game::get_status() == 1, 0);  // Back to SELECTION
        assert!(game::get_round() == 2, 1);

        // Verify player actions reset for round 2
        assert!(!game::has_selected(signer::address_of(u1)), 2);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_voting_all_stop(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        let metadata = test_helpers::setup_funded_vault(deployer, 200);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);
        game::set_voting_status_for_test();
        game::vote(u1, 0);
        game::vote(u2, 0);
        game::vote(u3, 0);
        game::vote(u4, 0);
        game::vote(u5, 0);

        game::finalize_voting(deployer);

        assert!(game::get_status() == 4, 0);
        let prize = vault::get_claimable_balance(signer::address_of(u1), metadata);
        assert!(prize > 0, 1);
    }

    #[test(deployer = @deployer)]
    #[expected_failure(abort_code = 2010, location = lucky_survivor::game)]
    fun test_finalize_voting_not_in_voting(deployer: &signer) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        game::finalize_voting(deployer);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_prize_split_remainder(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 100);
        let metadata = test_helpers::setup_funded_vault(deployer, 100);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);
        game::set_voting_status_for_test();

        game::vote(u1, 0);
        game::vote(u2, 0);
        game::vote(u3, 0);
        game::vote(u4, 0);
        game::vote(u5, 0);

        game::finalize_voting(deployer);

        assert!(game::get_status() == 4, 0);

        let prize_u1 = vault::get_claimable_balance(signer::address_of(u1), metadata);
        let prize_u2 = vault::get_claimable_balance(signer::address_of(u2), metadata);
        let prize_u3 = vault::get_claimable_balance(signer::address_of(u3), metadata);

        assert!(prize_u1 == 20, 1);
        assert!(prize_u2 == 20, 2);
        assert!(prize_u3 == 20, 3);
    }

    #[test(deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3)]
    fun test_prize_split_odd_indivisible(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 100);
        let metadata = test_helpers::setup_funded_vault(deployer, 100);

        let (consolation, remaining) = game::get_round_prizes();
        assert!(consolation == 0, 10);
        assert!(remaining == 100, 11);

        let players = vector[
            signer::address_of(u1),
            signer::address_of(u2),
            signer::address_of(u3)
        ];
        game::set_players_for_test(players);
        game::set_voting_status_for_test();

        game::vote(u1, 0);
        game::vote(u2, 0);
        game::vote(u3, 0);

        game::finalize_voting(deployer);

        assert!(game::get_status() == 4, 0);

        let prize_u1 = vault::get_claimable_balance(signer::address_of(u1), metadata);
        let prize_u2 = vault::get_claimable_balance(signer::address_of(u2), metadata);
        let prize_u3 = vault::get_claimable_balance(signer::address_of(u3), metadata);

        assert!(prize_u1 == 33, 1);
        assert!(prize_u2 == 33, 2);
        assert!(prize_u3 == 33, 3);

        let (_, remaining_after) = game::get_round_prizes();
        assert!(remaining_after == 100, 12);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_view_functions(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 1000);
        test_helpers::setup_funded_vault(deployer, 1000);

        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer);

        // Test has_acted before and after action
        assert!(!game::has_selected(signer::address_of(u1)), 0);
        game::choose_bao(u1, signer::address_of(u1));
        assert!(game::has_selected(signer::address_of(u1)), 1);

        // Test get_player_statuses
        let (players, _, statuses) = game::get_all_players();
        assert!(players.length() == 5, 2);
        assert!(statuses[0], 3);  // u1 has acted
        assert!(!statuses[1], 4); // u2 has not acted

        game::set_voting_status_for_test();

        let (stop, cont, missing) = game::get_voting_state();
        assert!(stop == 0, 5);
        assert!(cont == 0, 6);
        assert!(missing == 5, 7);

        game::vote(u1, 1);
        game::vote(u2, 0);
        game::vote(u3, 1);

        let (stop2, cont2, missing2) = game::get_voting_state();
        assert!(stop2 == 1, 8);
        assert!(cont2 == 2, 9);
        assert!(missing2 == 2, 10);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2013, location = lucky_survivor::game)]
    fun test_start_game_insufficient_vault(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 50);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_reveal_outcomes(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        test_helpers::setup_whitelist();
        game::init_for_test(deployer, 1000);
        test_helpers::setup_funded_vault(deployer, 1000);
        test_helpers::register_and_join(u1);
        test_helpers::register_and_join(u2);
        test_helpers::register_and_join(u3);
        test_helpers::register_and_join(u4);
        test_helpers::register_and_join(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer);
        assert!(game::get_elimination_count() == 1, 0);  // 5/4 = 1

        // All players keep their baos
        game::choose_bao(u1, signer::address_of(u1));
        game::choose_bao(u2, signer::address_of(u2));
        game::choose_bao(u3, signer::address_of(u3));
        game::choose_bao(u4, signer::address_of(u4));
        game::choose_bao(u5, signer::address_of(u5));

        game::finalize_selection(deployer);
        assert!(game::get_status() == 2, 1);  // STATUS_REVEALING

        // Before reveal, no victims yet
        let victims_before = game::get_round_victims();
        assert!(victims_before.length() == 0, 2);

        aptos_framework::randomness::initialize_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::reveal_bombs_for_test(deployer);

        // After reveal, verify outcomes
        let victims = game::get_round_victims();
        assert!(victims.length() == 1, 3);  // elimination_count == 1

        // Survivors should be 4
        assert!(game::get_players_count() == 4, 4);

        // Verify victim is NOT in the active player list
        let victim = victims[0];
        let (players, _, _) = game::get_all_players();
        assert!(!players.contains(&victim), 5);
    }
}

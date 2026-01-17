#[test_only]
module lucky_survivor::game_tests {
    use std::signer;
    use aptos_framework::account;
    use lucky_survivor::game;
    use lucky_survivor::vault;
    use aptos_framework::timestamp;

    #[test(admin = @lucky_survivor)]
    fun test_initialize(admin: &signer) {
        game::init_for_test(admin, 100);
        assert!(game::get_status() == 0, 0);
        assert!(game::get_players_count() == 0, 1);
    }

    #[test(admin = @lucky_survivor, user1 = @0xA1, user2 = @0xA2)]
    fun test_join_game(admin: &signer, user1: &signer, user2: &signer) {
        game::init_for_test(admin, 200);
        game::join_game(user1);
        assert!(game::get_players_count() == 1, 0);
        game::join_game(user2);
        assert!(game::get_players_count() == 2, 1);
    }

    #[test(admin = @lucky_survivor, user1 = @0xA1)]
    #[expected_failure(abort_code = 2002, location = lucky_survivor::game)]
    fun test_join_game_duplicate(admin: &signer, user1: &signer) {
        game::init_for_test(admin, 200);
        game::join_game(user1);
        game::join_game(user1);
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_start_game(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &aptos_framework::account::create_signer_for_test(@0x1)
        );

        game::start_game(admin, 120);
        assert!(game::get_status() == 1, 0);
        assert!(game::get_round() == 1, 1);
        assert!(game::get_elimination_count() == 1, 2);
    }

    #[test(admin = @lucky_survivor, u1 = @0x1, u2 = @0x2)]
    #[expected_failure(abort_code = 2003, location = lucky_survivor::game)]
    fun test_start_game_not_enough_players(
        admin: &signer, u1: &signer, u2: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);

        aptos_framework::timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(admin, 120); // Should fail - only 2 players
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_choose_bao(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(admin, 120);

        game::choose_bao(u1, 0);
        let (found, owner) = game::get_bao_owner(0);
        assert!(found && owner == signer::address_of(u1), 0);

        game::choose_bao(u2, 1);
        let (found2, _) = game::get_player_bao(signer::address_of(u2));
        assert!(found2, 1);
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2004, location = lucky_survivor::game)]
    fun test_choose_bao_already_taken(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(admin, 120);
        game::choose_bao(u1, 0);
        game::choose_bao(u2, 0); // Should fail - bao 0 already taken
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2005, location = lucky_survivor::game)]
    fun test_choose_bao_player_already_chose(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(admin, 120);
        game::choose_bao(u1, 0);
        game::choose_bao(u1, 1); // Should fail - u1 already chose
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_selection(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(admin, 120);

        game::choose_bao(u1, 0);
        game::choose_bao(u2, 1);

        game::finalize_selection(admin);

        assert!(game::get_status() == 2, 0); // STATUS_REVEALING

        let (found1, _) = game::get_player_bao(signer::address_of(u1));
        let (found2, _) = game::get_player_bao(signer::address_of(u2));
        let (found3, _) = game::get_player_bao(signer::address_of(u3));
        let (found4, _) = game::get_player_bao(signer::address_of(u4));
        let (found5, _) = game::get_player_bao(signer::address_of(u5));
        assert!(found1 && found2 && found3 && found4 && found5, 1);
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_vote(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(admin, 120);

        game::set_voting_status_for_test();
        assert!(game::get_status() == 3, 0); // STATUS_VOTING

        game::vote(u1, 1);
        let (found, vote_val) = game::get_vote(signer::address_of(u1));
        assert!(found && vote_val == 1, 1);

        game::vote(u2, 0);
        let (found2, vote_val2) = game::get_vote(signer::address_of(u2));
        assert!(found2 && vote_val2 == 0, 2);
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2011, location = lucky_survivor::game)]
    fun test_vote_duplicate(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(admin, 120);
        game::set_voting_status_for_test();

        game::vote(u1, 1);
        game::vote(u1, 0); // Should fail - already voted
    }

    #[test(admin = @lucky_survivor, u1 = @0x1)]
    #[expected_failure(abort_code = 2010, location = lucky_survivor::game)]
    fun test_vote_not_in_voting(admin: &signer, u1: &signer) {
        game::init_for_test(admin, 200);
        game::join_game(u1);

        // Status is PENDING, not VOTING
        game::vote(u1, 1); // Should fail
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_voting_continue(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(admin, 120);
        game::set_voting_status_for_test();
        game::vote(u1, 1);
        game::vote(u2, 0);
        game::finalize_voting(admin);
        // Should go to next round (SELECTION)
        assert!(game::get_status() == 1, 0); // STATUS_SELECTION
        assert!(game::get_round() == 2, 1); // Round 2
    }

    #[test(
        admin = @lucky_survivor, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_voting_all_stop(
        admin: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        vault::init_for_test(admin);

        game::init_for_test(admin, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(admin, 120);
        game::set_voting_status_for_test();
        game::vote(u1, 0);
        game::vote(u2, 0);
        game::vote(u3, 0);
        game::vote(u4, 0);
        game::vote(u5, 0);

        game::finalize_voting(admin);

        assert!(game::get_status() == 4, 0); // STATUS_ENDED
        let prize = vault::get_claimable_balance(signer::address_of(u1));
        assert!(prize > 0, 1);
    }

    #[test(admin = @lucky_survivor)]
    #[expected_failure(abort_code = 2010, location = lucky_survivor::game)]
    fun test_finalize_voting_not_in_voting(admin: &signer) {
        game::init_for_test(admin, 200);
        game::finalize_voting(admin); // Status is PENDING
    }
}


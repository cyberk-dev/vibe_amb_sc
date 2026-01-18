#[test_only]
module lucky_survivor::game_tests {
    use std::signer;
    use aptos_framework::account;
    use lucky_survivor::game;
    use lucky_survivor::vault;
    use lucky_survivor::package_manager;
    use lucky_survivor::test_helpers;
    use aptos_framework::timestamp;

    #[test(deployer = @deployer)]
    fun test_initialize(deployer: &signer) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 100);
        assert!(game::get_status() == 0, 0);
        assert!(game::get_players_count() == 0, 1);
    }

    #[test(deployer = @deployer, user1 = @0xA1, user2 = @0xA2)]
    fun test_join_game(deployer: &signer, user1: &signer, user2: &signer) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        game::join_game(user1);
        assert!(game::get_players_count() == 1, 0);
        game::join_game(user2);
        assert!(game::get_players_count() == 2, 1);
    }

    #[test(deployer = @deployer, user1 = @0xA1)]
    #[expected_failure(abort_code = 2002, location = lucky_survivor::game)]
    fun test_join_game_duplicate(deployer: &signer, user1: &signer) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        game::join_game(user1);
        game::join_game(user1);
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
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &aptos_framework::account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);
        assert!(game::get_status() == 1, 0);
        assert!(game::get_round() == 1, 1);
        assert!(game::get_elimination_count() == 1, 2);
    }

    #[test(deployer = @deployer, u1 = @0x1, u2 = @0x2)]
    #[expected_failure(abort_code = 2003, location = lucky_survivor::game)]
    fun test_start_game_not_enough_players(
        deployer: &signer, u1: &signer, u2: &signer
    ) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);

        aptos_framework::timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_choose_bao(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);

        game::choose_bao(u1, 0);
        let (found, owner) = game::get_bao_owner(0);
        assert!(found && owner == signer::address_of(u1), 0);

        game::choose_bao(u2, 1);
        let (found2, _) = game::get_player_bao(signer::address_of(u2));
        assert!(found2, 1);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2004, location = lucky_survivor::game)]
    fun test_choose_bao_already_taken(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);
        game::choose_bao(u1, 0);
        game::choose_bao(u2, 0);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    #[expected_failure(abort_code = 2005, location = lucky_survivor::game)]
    fun test_choose_bao_player_already_chose(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);
        game::choose_bao(u1, 0);
        game::choose_bao(u1, 1);
    }

    #[test(
        deployer = @deployer, u1 = @0x1, u2 = @0x2, u3 = @0x3, u4 = @0x4, u5 = @0x5
    )]
    fun test_finalize_selection(
        deployer: &signer,
        u1: &signer,
        u2: &signer,
        u3: &signer,
        u4: &signer,
        u5: &signer
    ) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);

        game::choose_bao(u1, 0);
        game::choose_bao(u2, 1);

        game::finalize_selection(deployer);

        assert!(game::get_status() == 2, 0);

        let (found1, _) = game::get_player_bao(signer::address_of(u1));
        let (found2, _) = game::get_player_bao(signer::address_of(u2));
        let (found3, _) = game::get_player_bao(signer::address_of(u3));
        let (found4, _) = game::get_player_bao(signer::address_of(u4));
        let (found5, _) = game::get_player_bao(signer::address_of(u5));
        assert!(found1 && found2 && found3 && found4 && found5, 1);
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
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);

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
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);
        game::set_voting_status_for_test();

        game::vote(u1, 1);
        game::vote(u1, 0);
    }

    #[test(deployer = @deployer, u1 = @0x1)]
    #[expected_failure(abort_code = 2010, location = lucky_survivor::game)]
    fun test_vote_not_in_voting(deployer: &signer, u1: &signer) {
        package_manager::initialize_for_test();
        game::init_for_test(deployer, 200);
        game::join_game(u1);

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
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);
        game::set_voting_status_for_test();
        game::vote(u1, 1);
        game::vote(u2, 0);
        game::finalize_voting(deployer);
        assert!(game::get_status() == 1, 0);
        assert!(game::get_round() == 2, 1);
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
        game::init_for_test(deployer, 200);
        let metadata = test_helpers::setup_funded_vault(deployer, 200);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);
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
        game::init_for_test(deployer, 100);
        let metadata = test_helpers::setup_funded_vault(deployer, 100);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);
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
        game::init_for_test(deployer, 1000);
        test_helpers::setup_funded_vault(deployer, 1000);

        let (round_deadline, vote_deadline) = game::get_deadlines();
        assert!(round_deadline == 0, 0);
        assert!(vote_deadline == 0, 1);

        let bao_owners = game::get_all_bao_owners();
        assert!(bao_owners.length() == 0, 2);

        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        game::start_game(deployer, 120);

        let (round_deadline2, _) = game::get_deadlines();
        assert!(round_deadline2 > 0, 3);

        let bao_owners2 = game::get_all_bao_owners();
        assert!(bao_owners2.length() == 5, 4);
        assert!(bao_owners2[0] == @0x0, 5);

        game::choose_bao(u1, 0);
        game::choose_bao(u2, 2);

        let bao_owners3 = game::get_all_bao_owners();
        assert!(bao_owners3[0] == signer::address_of(u1), 6);
        assert!(bao_owners3[1] == @0x0, 7);
        assert!(bao_owners3[2] == signer::address_of(u2), 8);

        game::set_voting_status_for_test();

        let (stop, cont, missing) = game::get_voting_state();
        assert!(stop == 0, 9);
        assert!(cont == 0, 10);
        assert!(missing == 5, 11);

        game::vote(u1, 1);
        game::vote(u2, 0);
        game::vote(u3, 1);

        let (stop2, cont2, missing2) = game::get_voting_state();
        assert!(stop2 == 1, 12);
        assert!(cont2 == 2, 13);
        assert!(missing2 == 2, 14);
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
        game::init_for_test(deployer, 200);
        test_helpers::setup_funded_vault(deployer, 50);
        game::join_game(u1);
        game::join_game(u2);
        game::join_game(u3);
        game::join_game(u4);
        game::join_game(u5);

        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        game::start_game(deployer, 120);
    }
}

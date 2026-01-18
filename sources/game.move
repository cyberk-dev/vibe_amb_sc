module lucky_survivor::game {
    use std::vector;
    use std::signer;
    use std::option::{Self, Option};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;
    use lucky_survivor::vault;
    use lucky_survivor::package_manager;
    use lucky_survivor::full_math;

    const STATUS_PENDING: u8 = 0;
    const STATUS_SELECTION: u8 = 1;
    const STATUS_REVEALING: u8 = 2;
    const STATUS_VOTING: u8 = 3;
    const STATUS_ENDED: u8 = 4;

    const VOTE_STOP: u8 = 0;
    const VOTE_CONTINUE: u8 = 1;

    const E_GAME_NOT_PENDING: u64 = 2001;
    const E_PLAYER_ALREADY_JOINED: u64 = 2002;
    const E_NOT_ENOUGH_PLAYERS: u64 = 2003;
    const E_BAO_ALREADY_CHOSEN: u64 = 2004;
    const E_PLAYER_ALREADY_CHOSE: u64 = 2005;
    const E_INVALID_BAO_INDEX: u64 = 2006;
    const E_ROUND_NOT_IN_SELECTION: u64 = 2007;
    const E_PLAYER_NOT_ACTIVE: u64 = 2008;
    const E_NOT_IN_REVEALING: u64 = 2009;
    const E_NOT_IN_VOTING: u64 = 2010;
    const E_ALREADY_VOTED: u64 = 2011;
    const E_ACCESS_DENIED: u64 = 2012;
    const E_INSUFFICIENT_VAULT_BALANCE: u64 = 2013;
    const E_ASSET_NOT_SET: u64 = 2014;
    const E_GAME_ALREADY_STARTED: u64 = 2015;
    const E_INVALID_PAYMENT_ASSET: u64 = 2016;

    struct Game has key {
        round: u8,
        status: u8,
        players: vector<address>,
        elimination_count: u64,
        bao_assignments: SmartTable<u64, address>,
        player_to_bao: SmartTable<address, u64>,
        total_bao: u64,
        bomb_indices: vector<u64>,
        round_deadline: u64,
        prize_pool: u64,
        spent_amount: u64,
        consolation_bps: vector<u64>,
        votes: SmartTable<address, u8>,
        vote_deadline: u64,
        asset_metadata: Option<Object<Metadata>>
    }

    #[event]
    struct PlayerJoined has drop, store {
        player: address,
        total_players: u64
    }

    #[event]
    struct GameStarted has drop, store {
        round: u8,
        num_players: u64,
        elimination_count: u64,
        deadline: u64
    }

    #[event]
    struct BaoChosen has drop, store {
        player: address,
        bao_index: u64,
        chosen_for: address
    }

    #[event]
    struct BombsRevealed has drop, store {
        round: u8,
        bomb_indices: vector<u64>,
        eliminated: vector<address>,
        consolation_per_person: u64
    }

    #[event]
    struct RoundEnded has drop, store {
        round: u8,
        survivors_count: u64
    }

    #[event]
    struct GameEnded has drop, store {
        winner: address,
        prize: u64
    }

    #[event]
    struct VotingStarted has drop, store {
        round: u8,
        survivors_count: u64,
        deadline: u64
    }

    #[event]
    struct PlayerVoted has drop, store {
        player: address,
        vote: u8
    }

    #[event]
    struct VotingResolved has drop, store {
        result: u8,
        continue_count: u64,
        stop_count: u64
    }

    #[event]
    struct PrizeSplit has drop, store {
        survivors: vector<address>,
        prize_per_person: u64
    }

    #[event]
    struct GameReset has drop, store {
        timestamp: u64
    }

    public entry fun initialize(admin: &signer, prize_pool: u64) {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let resource_signer = package_manager::get_signer();
        move_to(
            &resource_signer,
            Game {
                round: 0,
                status: STATUS_PENDING,
                players: vector::empty(),
                elimination_count: 0,
                bao_assignments: smart_table::new(),
                player_to_bao: smart_table::new(),
                total_bao: 0,
                bomb_indices: vector::empty(),
                round_deadline: 0,
                prize_pool,
                spent_amount: 0,
                consolation_bps: vector[25, 50, 75, 100],
                votes: smart_table::new(),
                vote_deadline: 0,
                asset_metadata: option::none()
            }
        );
    }

    public entry fun set_asset(admin: &signer, metadata: Object<Metadata>) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_ALREADY_STARTED);
        assert!(vault::is_valid_payment_fa(metadata), E_INVALID_PAYMENT_ASSET);
        game.asset_metadata = option::some(metadata);
    }

    public entry fun join_game(user: &signer) acquires Game {
        let addr = signer::address_of(user);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_NOT_PENDING);
        assert!(!game.players.contains(&addr), E_PLAYER_ALREADY_JOINED);
        game.players.push_back(addr);
        event::emit(PlayerJoined { player: addr, total_players: game.players.length() })
    }

    public entry fun start_game(admin: &signer, round_duration_secs: u64) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_NOT_PENDING);
        let num_players = game.players.length();
        assert!(num_players >= 5, E_NOT_ENOUGH_PLAYERS);
        assert!(option::is_some(&game.asset_metadata), E_ASSET_NOT_SET);
        let metadata = *option::borrow(&game.asset_metadata);
        assert!(
            vault::get_balance(metadata) >= game.prize_pool,
            E_INSUFFICIENT_VAULT_BALANCE
        );
        game.elimination_count = num_players / 4;
        if (game.elimination_count == 0) {
            game.elimination_count = 1;
        };
        game.round = 1;
        game.status = STATUS_SELECTION;
        game.total_bao = num_players;
        game.round_deadline = timestamp::now_seconds() + round_duration_secs;

        event::emit(
            GameStarted {
                round: game.round,
                num_players,
                elimination_count: game.elimination_count,
                deadline: game.round_deadline
            }
        )
    }

    public entry fun choose_bao(user: &signer, bao_index: u64) acquires Game {
        let addr = signer::address_of(user);
        choose_bao_internal(addr, bao_index, addr);
    }

    public entry fun choose_bao_for_other(
        user: &signer, bao_index: u64, target: address
    ) acquires Game {
        let addr = signer::address_of(user);
        let game = borrow_global<Game>(@lucky_survivor);
        assert!(vector::contains(&game.players, &addr), E_PLAYER_NOT_ACTIVE);
        choose_bao_internal(addr, bao_index, target);
    }

    fun choose_bao_internal(
        caller: address, bao_index: u64, target: address
    ) acquires Game {
        // check timestamp so với deadline
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_SELECTION, E_ROUND_NOT_IN_SELECTION);
        assert!(bao_index < game.total_bao, E_INVALID_BAO_INDEX);
        assert!(
            !smart_table::contains(&game.bao_assignments, bao_index),
            E_BAO_ALREADY_CHOSEN
        );
        assert!(vector::contains(&game.players, &target), E_PLAYER_NOT_ACTIVE);
        assert!(
            !smart_table::contains(&game.player_to_bao, target),
            E_PLAYER_ALREADY_CHOSE
        );
        smart_table::add(&mut game.bao_assignments, bao_index, target);
        smart_table::add(&mut game.player_to_bao, target, bao_index);

        event::emit(BaoChosen { player: caller, bao_index, chosen_for: target })
    }

    public entry fun finalize_selection(admin: &signer) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_SELECTION, E_ROUND_NOT_IN_SELECTION);
        let unassigned_players = vector[];
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            if (!game.player_to_bao.contains(player)) {
                unassigned_players.push_back(player);
            };
            i += 1;
        };

        let unassigned_bao = vector[];
        let j = 0;
        while (j < game.total_bao) {
            if (!game.bao_assignments.contains(j)) {
                unassigned_bao.push_back(j);
            };
            j += 1;
        };

        let k = 0;
        let min_len = min(unassigned_players.length(), unassigned_bao.length());
        while (k < min_len) {
            let player = unassigned_players[k];
            let bao = unassigned_bao[k];
            game.bao_assignments.add(bao, player);
            game.player_to_bao.add(player, bao);
            k += 1;
        };

        game.status = STATUS_REVEALING;
    }

    #[randomness]
    entry fun reveal_bombs(admin: &signer) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_REVEALING, E_NOT_IN_REVEALING);

        let remaining = game.players.length();

        let bombs_count =
            if (remaining <= game.elimination_count) {
                remaining - 1
            } else {
                game.elimination_count
            };

        let bombs = vector[];
        let used = vector[];
        let i = 0;
        while (i < bombs_count) {
            let idx = randomness::u64_range(0, game.total_bao);
            // Skip
            while (used.contains(&idx) || !game.bao_assignments.contains(idx)) {
                idx += 1;
            };
            bombs.push_back(idx);
            used.push_back(idx);
            i += 1;
        };

        game.bomb_indices = bombs;

        let metadata = *game.asset_metadata.borrow();
        let consolation_bps = get_consolation_bps(game.round, &game.consolation_bps);
        let consolation_amount =
            full_math::mul_div_u64(game.prize_pool, consolation_bps, 10000);

        let eliminated = vector[];
        let j = 0;
        while (j < bombs.length()) {
            let bomb_idx = bombs[j];
            let victim = *game.bao_assignments.borrow(bomb_idx);
            eliminated.push_back(victim);

            vault::record_prize(victim, metadata, consolation_amount);
            game.spent_amount += consolation_amount;
            j += 1;
        };

        event::emit(
            BombsRevealed {
                round: game.round,
                bomb_indices: bombs,
                eliminated,
                consolation_per_person: consolation_amount
            }
        );

        remove_players(&mut game.players, &eliminated);

        let survivors_count = game.players.length();
        if (survivors_count <= 1) {
            if (survivors_count == 1) {
                let winner = game.players[0];
                let winner_prize = calculate_winner_prize(game);

                vault::record_prize(winner, metadata, winner_prize);
                event::emit(GameEnded { winner, prize: winner_prize });
            };
            game.status = STATUS_ENDED;
        } else {
            start_voting_phase(game);
            event::emit(RoundEnded { round: game.round - 1, survivors_count });
        }
    }

    public entry fun vote(user: &signer, choice: u8) acquires Game {
        let addr = signer::address_of(user);
        let game = borrow_global_mut<Game>(@lucky_survivor);

        assert!(game.status == STATUS_VOTING, E_NOT_IN_VOTING);
        assert!(game.players.contains(&addr));
        assert!(!game.votes.contains(addr), E_ALREADY_VOTED);

        game.votes.add(addr, choice);

        event::emit(PlayerVoted { player: addr, vote: choice });
    }

    public entry fun finalize_voting(admin: &signer) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_VOTING, E_NOT_IN_VOTING);

        let continue_count: u64 = 0;
        let stop_count: u64 = 0;
        let i = 0;
        let len = game.players.length();

        while (i < len) {
            let player = game.players[i];
            if (game.votes.contains(player)) {
                let v = *game.votes.borrow(player);
                if (v == VOTE_CONTINUE) {
                    continue_count += 1;
                } else {
                    stop_count += 1;
                };
            };
            i += 1;
        };

        event::emit(
            VotingResolved {
                result: if (continue_count > 0) {
                    VOTE_CONTINUE
                } else {
                    VOTE_STOP
                },
                continue_count,
                stop_count
            }
        );

        if (continue_count > 0) {
            setup_next_round(game);
        } else {
            split_prize_equally(game);
            game.status = STATUS_ENDED;
        }
    }

    public entry fun reset_game(admin: &signer) acquires Game {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        game.round = 0;
        game.status = STATUS_PENDING;
        game.players = vector::empty();
        game.elimination_count = 0;
        game.bao_assignments.clear();
        game.player_to_bao.clear();
        game.total_bao = 0;
        game.bomb_indices = vector::empty();
        game.round_deadline = 0;
        // Keep prize_pool unchanged (admin can modify separately)
        game.spent_amount = 0;
        // Keep consolation_bps unchanged
        game.votes.clear();
        game.vote_deadline = 0;

        event::emit(GameReset { timestamp: timestamp::now_seconds() });
    }

    #[view]
    public fun get_players_count(): u64 acquires Game {
        borrow_global<Game>(@lucky_survivor).players.length()
    }

    #[view]
    public fun get_status(): u8 acquires Game {
        borrow_global<Game>(@lucky_survivor).status
    }

    #[view]
    public fun get_elimination_count(): u64 acquires Game {
        borrow_global<Game>(@lucky_survivor).elimination_count
    }

    #[view]
    public fun get_round(): u8 acquires Game {
        borrow_global<Game>(@lucky_survivor).round
    }

    #[view]
    public fun get_bao_owner(bao_index: u64): (bool, address) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        if (game.bao_assignments.contains(bao_index)) {
            (true, *game.bao_assignments.borrow(bao_index))
        } else {
            (false, @0x0)
        }
    }

    #[view]
    public fun get_bomb_indices(): vector<u64> acquires Game {
        borrow_global<Game>(@lucky_survivor).bomb_indices
    }

    #[view]
    public fun get_vote(player: address): (bool, u8) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        if (game.votes.contains(player)) {
            (true, *game.votes.borrow(player))
        } else {
            (false, 0)
        }
    }

    #[view]
    public fun get_player_bao(player: address): (bool, u64) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        if (game.player_to_bao.contains(player)) {
            (true, *game.player_to_bao.borrow(player))
        } else {
            (false, 0)
        }
    }

    #[view]
    public fun get_round_prizes(): (u64, u64) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let consolation_bps =
            if (game.round == 0) {
                game.consolation_bps[0]
            } else {
                get_consolation_bps(game.round, &game.consolation_bps)
            };
        let consolation_prize =
            full_math::mul_div_u64(game.prize_pool, consolation_bps, 10000);
        let remaining_pool = game.prize_pool - game.spent_amount;
        (consolation_prize, remaining_pool)
    }

    #[view]
    public fun get_consolation_prize_for_round(round: u8): u64 acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let consolation_bps = get_consolation_bps(round, &game.consolation_bps);
        full_math::mul_div_u64(game.prize_pool, consolation_bps, 10000)
    }

    #[view]
    public fun get_deadlines(): (u64, u64) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        (game.round_deadline, game.vote_deadline)
    }

    #[view]
    public fun get_voting_state(): (u64, u64, u64) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let stop_count: u64 = 0;
        let continue_count: u64 = 0;
        let missing_count: u64 = 0;
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            if (game.votes.contains(player)) {
                let v = *game.votes.borrow(player);
                if (v == VOTE_CONTINUE) {
                    continue_count += 1;
                } else {
                    stop_count += 1;
                };
            } else {
                missing_count += 1;
            };
            i += 1;
        };
        (stop_count, continue_count, missing_count)
    }

    #[view]
    public fun get_all_bao_owners(): vector<address> acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let result = vector[];
        let i: u64 = 0;
        while (i < game.total_bao) {
            if (game.bao_assignments.contains(i)) {
                result.push_back(*game.bao_assignments.borrow(i));
            } else {
                result.push_back(@0x0);
            };
            i += 1;
        };
        result
    }

    fun calculate_winner_prize(game: &Game): u64 {
        // Return remaining prize after consolation payments
        game.prize_pool - game.spent_amount
    }

    fun setup_next_round(game: &mut Game) {
        game.bao_assignments.clear();
        game.player_to_bao.clear();
        game.bomb_indices = vector[];
        game.round += 1;
        game.total_bao = game.players.length();
        game.status = STATUS_SELECTION;
    }

    fun remove_players(
        players: &mut vector<address>, to_remove: &vector<address>
    ) {
        let i = 0;
        while (i < to_remove.length()) {
            let addr = to_remove[i];
            let (found, idx) = players.index_of(&addr);
            if (found) {
                players.remove(idx);
            };
            i += 1;
        };
    }

    fun get_consolation_bps(round: u8, bps_list: &vector<u64>): u64 {
        let idx = ((round as u64) - 1);
        let len = bps_list.length();
        if (idx < len) {
            bps_list[idx]
        } else {
            bps_list[len - 1]
        }
    }

    fun min(a: u64, b: u64): u64 {
        if (a < b) { a }
        else { b }
    }

    fun split_prize_equally(game: &Game) {
        let count = game.players.length();
        if (count == 0) return;
        let metadata = *option::borrow(&game.asset_metadata);
        let remaining = game.prize_pool - game.spent_amount;
        let per_person = remaining / count;
        let i = 0;
        while (i < count) {
            vault::record_prize(game.players[i], metadata, per_person);
            i += 1;
        };

        event::emit(PrizeSplit { survivors: game.players, prize_per_person: per_person })
    }

    fun start_voting_phase(game: &mut Game) {
        game.votes.clear();
        game.vote_deadline = timestamp::now_seconds() + 60;
        game.status = STATUS_VOTING;

        event::emit(
            VotingStarted {
                round: game.round,
                survivors_count: game.players.length(),
                deadline: game.vote_deadline
            }
        )
    }

    #[test_only]
    public fun init_for_test(admin: &signer, prize_pool: u64) {
        initialize(admin, prize_pool);
    }

    #[test_only]
    public fun set_asset_for_test(metadata: Object<Metadata>) acquires Game {
        let game = borrow_global_mut<Game>(@lucky_survivor);
        game.asset_metadata = option::some(metadata);
    }

    #[test_only]
    public fun set_voting_status_for_test() acquires Game {
        let game = borrow_global_mut<Game>(@lucky_survivor);
        game.status = STATUS_VOTING;
    }

    #[test_only]
    public fun set_players_for_test(players: vector<address>) acquires Game {
        let game = borrow_global_mut<Game>(@lucky_survivor);
        game.players = players;
    }
}


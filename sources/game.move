module lucky_survivor::game {
    use std::vector;
    use std::signer;
    use std::string::String;
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
    use lucky_survivor::whitelist;

    friend lucky_survivor::router;

    const STATUS_PENDING: u8 = 0;
    const STATUS_SELECTION: u8 = 1;
    const STATUS_REVEALING: u8 = 2;
    const STATUS_REVEALED: u8 = 3;
    const STATUS_VOTING: u8 = 4;
    const STATUS_ENDED: u8 = 5;

    const VOTE_STOP: u8 = 0;
    const VOTE_CONTINUE: u8 = 1;

    const E_GAME_NOT_PENDING: u64 = 2001;
    const E_PLAYER_ALREADY_JOINED: u64 = 2002;
    const E_NOT_ENOUGH_PLAYERS: u64 = 2003;
    const E_PLAYER_ALREADY_ACTED: u64 = 2005;
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
    const E_TARGET_NOT_ACTIVE: u64 = 2017;
    const E_NOT_REGISTERED: u64 = 2018;
    const E_INVALID_CODE: u64 = 2019;
    const E_NAME_NOT_SET: u64 = 2020;
    const E_NOT_IN_REVEALED: u64 = 2021;

    struct Player has store, drop, copy {
        name: String,
        acted: bool,
        initial_bao_id: Option<u64>
    }

    struct Game has key {
        round: u8,
        status: u8,
        players: vector<address>,
        fixed_players: vector<address>,
        player_data: SmartTable<address, Player>,
        pending_names: SmartTable<address, String>,
        elimination_count: u64,
        // Maps bao_id -> final owner (after selection completes)
        bao_assignments: SmartTable<u64, address>,
        total_bao: u64,
        bomb_indices: vector<u64>,
        prize_pool: u64,
        spent_amount: u64,
        consolation_bps: vector<u64>,
        votes: SmartTable<address, u8>,
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
        elimination_count: u64
    }

    #[event]
    struct BaoAssigned has drop, store {
        player: address,
        bao_index: u64,
        assigned_to: address
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
        survivors_count: u64
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

    /// Friend function for router to initialize
    public(friend) fun initialize_friend(admin: &signer, prize_pool: u64) {
        ensure_admin(admin);
        let resource_signer = package_manager::get_signer();
        move_to(
            &resource_signer,
            Game {
                round: 0,
                status: STATUS_PENDING,
                players: vector::empty(),
                fixed_players: vector::empty(),
                player_data: smart_table::new(),
                pending_names: smart_table::new(),
                elimination_count: 0,
                bao_assignments: smart_table::new(),
                total_bao: 0,
                bomb_indices: vector::empty(),
                prize_pool,
                spent_amount: 0,
                consolation_bps: vector[25, 50, 75, 100],
                votes: smart_table::new(),
                asset_metadata: option::none()
            }
        );
    }

    /// Friend function for router to set asset
    public(friend) fun set_asset_friend(admin: &signer, metadata: Object<Metadata>) acquires Game {
        ensure_admin(admin);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_ALREADY_STARTED);
        assert!(vault::is_valid_payment_fa(metadata), E_INVALID_PAYMENT_ASSET);
        game.asset_metadata = option::some(metadata);
    }

    /// Set display name before joining (can be called multiple times)
    /// Requires valid whitelist registration and code
    public entry fun set_display_name(user: &signer, code: String, name: String) acquires Game {
        let addr = signer::address_of(user);

        // Verify user is registered and code is valid
        assert!(whitelist::is_registered(addr), E_NOT_REGISTERED);
        assert!(whitelist::verify_code(addr, code), E_INVALID_CODE);

        let game = borrow_global_mut<Game>(@lucky_survivor);

        // Set or update pending name (allows multiple updates)
        if (game.pending_names.contains(addr)) {
            *game.pending_names.borrow_mut(addr) = name;
        } else {
            game.pending_names.add(addr, name);
        };
    }

    public entry fun join_game(user: &signer, code: String) acquires Game {
        let addr = signer::address_of(user);

        // Verify user is registered in whitelist
        assert!(whitelist::is_registered(addr), E_NOT_REGISTERED);

        // Verify code belongs to this user
        assert!(whitelist::verify_code(addr, code), E_INVALID_CODE);

        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_NOT_PENDING);
        assert!(!game.players.contains(&addr), E_PLAYER_ALREADY_JOINED);

        // MUST have set name first
        assert!(game.pending_names.contains(addr), E_NAME_NOT_SET);
        let display_name = *game.pending_names.borrow(addr);

        game.players.push_back(addr);
        game.player_data.add(addr, Player {
            name: display_name,
            acted: false,
            initial_bao_id: option::none()
        });

        // Remove from pending after joining (cleanup)
        game.pending_names.remove(addr);

        event::emit(PlayerJoined { player: addr, total_players: game.players.length() })
    }

    public entry fun start_game(admin: &signer) acquires Game {
        ensure_admin(admin);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_PENDING, E_GAME_NOT_PENDING);
        let num_players = game.players.length();
        assert!(num_players >= 5, E_NOT_ENOUGH_PLAYERS);
        assert!(game.asset_metadata.is_some(), E_ASSET_NOT_SET);
        let metadata = *game.asset_metadata.borrow();
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

        // Snapshot all players at game start (for leaderboard after eliminations)
        game.fixed_players = game.players;

        // Pre-assign each player their initial bao (player i gets bao i)
        let i = 0;
        while (i < num_players) {
            let player = game.players[i];
            let player_info = game.player_data.borrow_mut(player);
            player_info.initial_bao_id = option::some(i);
            player_info.acted = false;
            i += 1;
        };

        event::emit(
            GameStarted {
                round: game.round,
                num_players,
                elimination_count: game.elimination_count
            }
        )
    }

    /// Assign your pre-assigned bao to a target.
    /// If target == caller, this is "keep". If target != caller, this is "give".
    public entry fun choose_bao(user: &signer, target: address) acquires Game {
        let addr = signer::address_of(user);
        let game = borrow_global_mut<Game>(@lucky_survivor);

        assert!(game.status == STATUS_SELECTION, E_ROUND_NOT_IN_SELECTION);
        assert!(game.players.contains(&addr), E_PLAYER_NOT_ACTIVE);
        assert!(game.players.contains(&target), E_TARGET_NOT_ACTIVE);

        let player_info = game.player_data.borrow_mut(addr);
        assert!(!player_info.acted, E_PLAYER_ALREADY_ACTED);
        assert!(player_info.initial_bao_id.is_some(), E_PLAYER_NOT_ACTIVE);

        let bao_id = *player_info.initial_bao_id.borrow();
        player_info.acted = true;

        game.bao_assignments.add(bao_id, target);

        event::emit(BaoAssigned { player: addr, bao_index: bao_id, assigned_to: target })
    }

    public entry fun finalize_selection(admin: &signer) acquires Game {
        ensure_admin(admin);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_SELECTION, E_ROUND_NOT_IN_SELECTION);

        // Auto-keep: players who haven't acted keep their own bao
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            let player_info = game.player_data.borrow_mut(player);
            if (!player_info.acted) {
                let bao_id = *player_info.initial_bao_id.borrow();
                game.bao_assignments.add(bao_id, player);
                player_info.acted = true;
            };
            i += 1;
        };

        game.status = STATUS_REVEALING;
    }

    #[randomness]
    entry fun reveal_bombs(admin: &signer) acquires Game {
        ensure_admin(admin);
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
            // Stay in REVEALED status - admin will manually start voting
            game.status = STATUS_REVEALED;
        }
    }

    /// Admin manually starts voting phase after reveal
    public entry fun start_voting(admin: &signer) acquires Game {
        ensure_admin(admin);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        assert!(game.status == STATUS_REVEALED, E_NOT_IN_REVEALED);

        start_voting_phase(game);
        event::emit(RoundEnded { round: game.round, survivors_count: game.players.length() });
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
        ensure_admin(admin);
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
        ensure_admin(admin);
        let game = borrow_global_mut<Game>(@lucky_survivor);
        game.round = 0;
        game.status = STATUS_PENDING;
        game.players = vector::empty();
        game.fixed_players = vector::empty();
        game.player_data.clear();
        game.pending_names.clear();
        game.elimination_count = 0;
        game.bao_assignments.clear();
        game.total_bao = 0;
        game.bomb_indices = vector::empty();
        // Keep prize_pool unchanged (admin can modify separately)
        game.spent_amount = 0;
        // Keep consolation_bps unchanged
        game.votes.clear();

        event::emit(GameReset { timestamp: timestamp::now_seconds() });
    }

    #[view]
    public fun get_players_count(): u64 acquires Game {
        borrow_global<Game>(@lucky_survivor).players.length()
    }

    #[view]
    public fun get_players(): vector<address> acquires Game {
        borrow_global<Game>(@lucky_survivor).players
    }

    #[view]
    public fun get_player_name(player: address): String acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        game.player_data.borrow(player).name
    }

    #[view]
    public fun get_player_info(player: address): (String, bool, Option<u64>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let info = game.player_data.borrow(player);
        (info.name, info.acted, info.initial_bao_id)
    }

    #[view]
    public fun get_all_players(): (vector<address>, vector<String>, vector<bool>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let names = vector[];
        let statuses = vector[];
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            let info = game.player_data.borrow(player);
            names.push_back(info.name);
            statuses.push_back(info.acted);
            i += 1;
        };
        (game.players, names, statuses)
    }

    #[view]
    public fun get_all_players_with_seats(): (vector<address>, vector<String>, vector<bool>, vector<u64>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let names = vector[];
        let statuses = vector[];
        let seats = vector[];
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            let info = game.player_data.borrow(player);
            names.push_back(info.name);
            statuses.push_back(info.acted);
            let seat = if (info.initial_bao_id.is_some()) {
                *info.initial_bao_id.borrow()
            } else {
                0
            };
            seats.push_back(seat);
            i += 1;
        };
        (game.players, names, statuses, seats)
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
    public fun get_vote(player: address): (bool, u8) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        if (game.votes.contains(player)) {
            (true, *game.votes.borrow(player))
        } else {
            (false, 0)
        }
    }

    #[view]
    public fun has_selected(player: address): bool acquires Game {
        borrow_global<Game>(@lucky_survivor).player_data.borrow(player).acted
    }

    #[view]
    public fun has_joined(player: address): bool acquires Game {
        borrow_global<Game>(@lucky_survivor).players.contains(&player)
    }

    #[view]
    public fun get_pending_name(player: address): String acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        assert!(game.pending_names.contains(player), E_NAME_NOT_SET);
        *game.pending_names.borrow(player)
    }

    #[view]
    public fun has_pending_name(player: address): bool acquires Game {
        if (!exists<Game>(@lucky_survivor)) return false;
        let game = borrow_global<Game>(@lucky_survivor);
        game.pending_names.contains(player)
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

    // @deprecated Use get_round_victims_with_seats() instead
    #[view]
    public fun get_round_victims(): vector<address> acquires Game {
        let _game = borrow_global<Game>(@lucky_survivor);
        vector[]
    }

    // @deprecated Use get_round_victims_with_seats() instead
    #[view]
    public fun get_round_victims_with_names(): (vector<address>, vector<String>) acquires Game {
        let _game = borrow_global<Game>(@lucky_survivor);
        (vector[], vector[])
    }

    #[view]
    public fun get_round_victims_with_seats(): (vector<address>, vector<String>, vector<u64>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let victims = vector[];
        let names = vector[];
        let seats = vector[];
        let i = 0;
        let len = game.bomb_indices.length();
        while (i < len) {
            let bomb_idx = game.bomb_indices[i];
            if (game.bao_assignments.contains(bomb_idx)) {
                let victim_addr = *game.bao_assignments.borrow(bomb_idx);
                victims.push_back(victim_addr);
                let info = game.player_data.borrow(victim_addr);
                names.push_back(info.name);
                // Seat number (initial_bao_id is 0-indexed)
                let seat = if (info.initial_bao_id.is_some()) {
                    *info.initial_bao_id.borrow()
                } else {
                    0
                };
                seats.push_back(seat);
            };
            i += 1;
        };
        (victims, names, seats)
    }

    #[view]
    public fun get_all_players_with_targets(): (vector<address>, vector<String>, vector<u64>, vector<bool>, vector<bool>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);

        // First, collect all targets from bao_assignments
        let targets = vector[];
        let i: u64 = 0;
        while (i < game.total_bao) {
            if (game.bao_assignments.contains(i)) {
                let target = *game.bao_assignments.borrow(i);
                if (!targets.contains(&target)) {
                    targets.push_back(target);
                };
            };
            i += 1;
        };

        // Then build the response arrays
        let names = vector[];
        let seats = vector[];
        let statuses = vector[];
        let is_targets = vector[];
        let j = 0;
        let len = game.players.length();
        while (j < len) {
            let player = game.players[j];
            let info = game.player_data.borrow(player);
            names.push_back(info.name);
            let seat = if (info.initial_bao_id.is_some()) {
                *info.initial_bao_id.borrow()
            } else {
                0
            };
            seats.push_back(seat);
            statuses.push_back(info.acted);
            is_targets.push_back(targets.contains(&player));
            j += 1;
        };
        (game.players, names, seats, statuses, is_targets)
    }

    #[view]
    public fun get_all_players_with_votes(): (vector<address>, vector<String>, vector<u64>, vector<bool>, vector<u8>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let names = vector[];
        let seats = vector[];
        let has_voted = vector[];
        let votes = vector[];
        let i = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            let info = game.player_data.borrow(player);
            names.push_back(info.name);
            let seat = if (info.initial_bao_id.is_some()) {
                *info.initial_bao_id.borrow()
            } else {
                0
            };
            seats.push_back(seat);
            if (game.votes.contains(player)) {
                has_voted.push_back(true);
                votes.push_back(*game.votes.borrow(player));
            } else {
                has_voted.push_back(false);
                votes.push_back(0);
            };
            i += 1;
        };
        (game.players, names, seats, has_voted, votes)
    }

    #[view]
    public fun get_all_players_with_prizes(): (vector<address>, vector<String>, vector<u64>, vector<bool>, vector<u64>) acquires Game {
        let game = borrow_global<Game>(@lucky_survivor);
        let metadata = *game.asset_metadata.borrow();
        let names = vector[];
        let seats = vector[];
        let is_eliminated = vector[];
        let prizes = vector[];
        let i = 0;
        let len = game.fixed_players.length();
        while (i < len) {
            let player = game.fixed_players[i];
            let info = game.player_data.borrow(player);
            names.push_back(info.name);
            let seat = if (info.initial_bao_id.is_some()) {
                *info.initial_bao_id.borrow()
            } else {
                0
            };
            seats.push_back(seat);
            // Check if player is eliminated (not in current players list)
            is_eliminated.push_back(!game.players.contains(&player));
            let prize = vault::get_claimable_balance(player, metadata);
            prizes.push_back(prize);
            i += 1;
        };
        (game.fixed_players, names, seats, is_eliminated, prizes)
    }

    fun calculate_winner_prize(game: &Game): u64 {
        // Return remaining prize after consolation payments
        game.prize_pool - game.spent_amount
    }

    fun setup_next_round(game: &mut Game) {
        game.bao_assignments.clear();
        game.bomb_indices = vector[];
        game.round += 1;
        game.total_bao = game.players.length();

        // Re-assign initial baos for the new round and reset acted status
        let i: u64 = 0;
        let len = game.players.length();
        while (i < len) {
            let player = game.players[i];
            let player_info = game.player_data.borrow_mut(player);
            player_info.initial_bao_id = option::some(i);
            player_info.acted = false;
            i += 1;
        };

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

    fun split_prize_equally(game: &Game) {
        let count = game.players.length();
        if (count == 0) return;
        let metadata = *game.asset_metadata.borrow();
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
        game.status = STATUS_VOTING;

        event::emit(
            VotingStarted { round: game.round, survivors_count: game.players.length() }
        )
    }

    inline fun ensure_admin(admin: &signer) {
        assert!(signer::address_of(admin) == @deployer, E_ACCESS_DENIED);
    }

    #[test_only]
    public fun init_for_test(admin: &signer, prize_pool: u64) {
        initialize_friend(admin, prize_pool);
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

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public entry fun reveal_bombs_for_test(admin: &signer) acquires Game {
        reveal_bombs(admin);
    }
}


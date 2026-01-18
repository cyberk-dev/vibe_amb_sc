import { Account } from "@aptos-labs/ts-sdk";
import { accountHelpers, transactionHelpers } from "./test-helpers";
import { aptos, VAULT_MODULE, APT_METADATA } from "./CONFIG";

const GameStatus = {
  PENDING: 0,
  SELECTION: 1,
  REVEALING: 2,
  VOTING: 3,
  ENDED: 4,
};

const VoteChoice = {
  STOP: 0,
  CONTINUE: 1,
};

describe("Lucky Survivor - Full Game Flow", () => {
  let admin: Account;
  let players: Account[];
  let survivingPlayers: Account[] = [];
  let eliminatedPlayers: Account[] = [];

  beforeAll(async () => {
    admin = accountHelpers.getAdmin();
    await transactionHelpers.executeEntry(admin, "reset_game").catch(() => {});
    await transactionHelpers.executeEntry(admin, "fund_vault", [APT_METADATA, 1000000], VAULT_MODULE);
    players = accountHelpers.generatePlayers(5);
  });

  afterAll(async () => {
    await accountHelpers.clawback(players, admin);
    await transactionHelpers.executeEntry(admin, "withdraw_all", [APT_METADATA], VAULT_MODULE).catch(() => {});
  });

  it("should join game with 5 players", async () => {
    for (let i = 0; i < players.length; i++) {
      const player = players[i]!;
      await accountHelpers.registerAndJoin(player, admin, `Player${i + 1}`);
    }
    const [count] = await transactionHelpers.view("get_players_count");
    expect(Number(count)).toBe(5);
  });

  it("should start game", async () => {
    await transactionHelpers.executeEntry(admin, "start_game");
    const [status] = await transactionHelpers.view("get_status");
    const [round] = await transactionHelpers.view("get_round");
    const [eliminationCount] = await transactionHelpers.view("get_elimination_count");

    expect(Number(status)).toBe(GameStatus.SELECTION);
    expect(Number(round)).toBe(1);
    expect(Number(eliminationCount)).toBe(1);
  });

  it("should choose bao (keep) and finalize selection", async () => {
    // Each player keeps their pre-assigned bao (target = self)
    for (const player of players) {
      await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "choose_bao",
        [player.accountAddress.toString()]
      );
    }

    // Verify all players have acted using get_all_players
    const [addresses, , statuses] = await transactionHelpers.view("get_all_players");
    expect((addresses as string[]).length).toBe(5);
    expect((statuses as boolean[]).every(s => s === true)).toBe(true);

    await transactionHelpers.executeEntry(admin, "finalize_selection");
    const [status] = await transactionHelpers.view("get_status");
    expect(Number(status)).toBe(GameStatus.REVEALING);
  });

  it("should reveal bombs and eliminate players", async () => {
    await transactionHelpers.executeEntry(admin, "reveal_bombs");

    const [status] = await transactionHelpers.view("get_status");
    const [victims] = await transactionHelpers.view("get_round_victims");
    const [survivorCount] = await transactionHelpers.view("get_players_count");

    expect((victims as string[]).length).toBe(1); // elimination_count == 1
    expect(Number(survivorCount)).toBe(4);
    expect([GameStatus.VOTING, GameStatus.ENDED]).toContain(Number(status));
  });

  it("should have valid voting state", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) return;

    const [stopCount, continueCount, missingCount] = await transactionHelpers.view("get_voting_state");
    const [survivorCount] = await transactionHelpers.view("get_players_count");

    expect(Number(stopCount)).toBe(0);
    expect(Number(continueCount)).toBe(0);
    expect(Number(missingCount)).toBe(Number(survivorCount));
  });

  it("should allow survivors to vote", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) return;

    for (const player of players) {
      try {
        await transactionHelpers.executeWithFeePayer(player, admin, "vote", [VoteChoice.CONTINUE]);
        survivingPlayers.push(player);
      } catch {
        eliminatedPlayers.push(player);
      }
    }

    const [stopCount, continueCount, missingCount] = await transactionHelpers.view("get_voting_state");
    expect(Number(continueCount)).toBe(survivingPlayers.length);
    expect(Number(missingCount)).toBe(0);
  });

  it("should finalize voting and proceed to next round", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) return;

    await transactionHelpers.executeEntry(admin, "finalize_voting");

    const [newStatus] = await transactionHelpers.view("get_status");
    const [round] = await transactionHelpers.view("get_round");

    expect(Number(newStatus)).toBe(GameStatus.SELECTION);
    expect(Number(round)).toBe(2);
  });

  it("should record claimable prizes for eliminated players", async () => {
    const [round1Consolation] = await transactionHelpers.view("get_consolation_prize_for_round", [1]);
    const eliminatedCount = eliminatedPlayers.length;

    let totalClaimable = 0;
    for (const player of players) {
      const [claimable] = await transactionHelpers.view(
        "get_claimable_balance",
        [player.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );
      totalClaimable += Number(claimable);
    }

    const expectedClaimable = Number(round1Consolation) * eliminatedCount;
    expect(totalClaimable).toBe(expectedClaimable);
  });

  it("should allow eliminated players to claim prizes", async () => {
    if (eliminatedPlayers.length === 0) return;

    const [vaultBalanceBefore] = await transactionHelpers.view("get_balance", [APT_METADATA], VAULT_MODULE);

    for (const player of eliminatedPlayers) {
      const [claimableBefore] = await transactionHelpers.view(
        "get_claimable_balance",
        [player.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );

      if (Number(claimableBefore) === 0) continue;

      await transactionHelpers.executeWithFeePayer(player, admin, "claim_prizes", [APT_METADATA], VAULT_MODULE);

      const [claimableAfter] = await transactionHelpers.view(
        "get_claimable_balance",
        [player.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );

      expect(Number(claimableAfter)).toBe(0);

      const playerBalance = await aptos.getAccountAPTAmount({
        accountAddress: player.accountAddress,
      });
      expect(playerBalance).toBe(Number(claimableBefore));
    }

    const [vaultBalanceAfter] = await transactionHelpers.view("get_balance", [APT_METADATA], VAULT_MODULE);
    const [round1Consolation] = await transactionHelpers.view("get_consolation_prize_for_round", [1]);
    const expectedDecrease = Number(round1Consolation) * eliminatedPlayers.length;

    expect(Number(vaultBalanceBefore) - Number(vaultBalanceAfter)).toBe(expectedDecrease);
  });
});

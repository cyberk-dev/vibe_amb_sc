import { Account } from "@aptos-labs/ts-sdk";
import { accountHelpers, transactionHelpers } from "./test-helpers";
import { VAULT_MODULE, APT_METADATA, GAME_MODULE } from "./CONFIG";

// ============================================================================
// CONSTANTS
// ============================================================================

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

const PRIZE_POOL = 2_000_000;
const PLAYER_COUNT = 20;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Calculate expected elimination count.
 * Contract logic: min(elimination_count, remaining - 1)
 */
function getExpectedEliminations(eliminationCount: number, remainingPlayers: number): number {
  return Math.min(eliminationCount, remainingPlayers - 1);
}

// ============================================================================
// TEST SUITE - Using Contract View Functions for Assertions
// ============================================================================

describe("Lucky Survivor - Formula-Based Verification", () => {
  let admin: Account;
  let players: Account[];
  let activePlayers: Account[] = [];
  let eliminatedPlayers: Account[] = [];

  beforeAll(async () => {
    admin = accountHelpers.getAdmin();
    await transactionHelpers.executeEntry(admin, "reset_game").catch(() => {});
    await transactionHelpers.executeEntry(admin, "fund_vault", [APT_METADATA, PRIZE_POOL], VAULT_MODULE);
    players = accountHelpers.generatePlayers(PLAYER_COUNT);
    activePlayers = [...players];
  }, 60000);

  afterAll(async () => {
    await accountHelpers.clawback(players, admin);
    await transactionHelpers.executeEntry(admin, "withdraw_all", [APT_METADATA], VAULT_MODULE).catch(() => {});
  }, 60000);

  // ==========================================================================
  // SETUP TESTS
  // ==========================================================================

  it("should join game with correct player count", async () => {
    for (let i = 0; i < players.length; i++) {
      const player = players[i]!;
      await accountHelpers.registerAndJoin(player, admin, `Player${i + 1}`);
    }
    const [count] = await transactionHelpers.view("get_players_count");
    expect(Number(count)).toBe(PLAYER_COUNT);
  }, 120000);

  it("should start game with correct elimination count formula", async () => {
    await transactionHelpers.executeEntry(admin, "start_game");

    const [status] = await transactionHelpers.view("get_status");
    const [round] = await transactionHelpers.view("get_round");
    const [eliminationCount] = await transactionHelpers.view("get_elimination_count");

    // Formula: elimination_count = num_players / 4
    const expectedEliminationCount = Math.floor(PLAYER_COUNT / 4);

    expect(Number(status)).toBe(GameStatus.SELECTION);
    expect(Number(round)).toBe(1);
    expect(Number(eliminationCount)).toBe(expectedEliminationCount);
  });

  // ==========================================================================
  // ROUND TESTS
  // ==========================================================================

  it("Round 1: should eliminate correct count and pay exact consolation", async () => {
    await executeRoundWithAssertions(1, VoteChoice.CONTINUE);
  }, 120000);

  it("Round 2: should eliminate correct count and pay exact consolation", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) {
      console.log("Game ended early - skipping Round 2");
      return;
    }
    await executeRoundWithAssertions(2, VoteChoice.CONTINUE);
  }, 120000);

  it("Round 3: should eliminate correct count and pay exact consolation", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) {
      console.log("Game ended early - skipping Round 3");
      return;
    }
    await executeRoundWithAssertions(3, VoteChoice.CONTINUE);
  }, 120000);

  it("Round 4: should end game with STOP vote and split remaining prize", async () => {
    const [status] = await transactionHelpers.view("get_status");
    if (Number(status) === GameStatus.ENDED) {
      console.log("Game ended early - skipping Round 4");
      return;
    }
    await executeRoundWithAssertions(4, VoteChoice.STOP);
  }, 120000);

  // ==========================================================================
  // FINAL VERIFICATION TESTS
  // ==========================================================================

  it("should have game in ENDED status", async () => {
    const [status] = await transactionHelpers.view("get_status");
    expect(Number(status)).toBe(GameStatus.ENDED);
  });

  it("should give winners the correct remaining prize (using view function)", async () => {
    // Get remaining pool from contract view function
    const [, remainingPool] = await transactionHelpers.view("get_round_prizes");

    console.log("\n=== FINAL PRIZE VERIFICATION ===");
    console.log(`Remaining Pool (from contract): ${remainingPool}`);
    console.log(`Winners (survivors): ${activePlayers.length}`);

    // Calculate expected per-winner prize (split equally among survivors)
    const expectedPerWinner = activePlayers.length > 0
      ? Math.floor(Number(remainingPool) / activePlayers.length)
      : 0;

    console.log(`Expected Per-Winner Prize: ${expectedPerWinner}`);

    let actualTotalWinnerPrize = 0;

    for (const winner of activePlayers) {
      const [claimable] = await transactionHelpers.view(
        "get_claimable_balance",
        [winner.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );
      const amount = Number(claimable);
      actualTotalWinnerPrize += amount;

      // ASSERTION: Each winner gets exact expected amount
      expect(amount).toBe(expectedPerWinner);
      console.log(`  Winner ${winner.accountAddress.toString().slice(0, 10)}... : ${amount} (expected: ${expectedPerWinner}) ✓`);
    }

    // ASSERTION: Total winner prize matches expected
    const expectedTotalWinnerPrize = expectedPerWinner * activePlayers.length;
    expect(actualTotalWinnerPrize).toBe(expectedTotalWinnerPrize);
  });

  it("should allow all players to claim and vault decreases correctly", async () => {
    console.log("\n=== CLAIM VERIFICATION ===");

    for (const player of players) {
      const [claimable] = await transactionHelpers.view(
        "get_claimable_balance",
        [player.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );

      const claimAmount = Number(claimable);
      if (claimAmount === 0) continue;

      // Get vault balance before claim
      const [vaultBefore] = await transactionHelpers.view(
        "get_balance",
        [APT_METADATA],
        VAULT_MODULE
      );

      // Execute claim
      await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "claim_prizes",
        [APT_METADATA],
        VAULT_MODULE
      );

      // Get vault balance after claim
      const [vaultAfter] = await transactionHelpers.view(
        "get_balance",
        [APT_METADATA],
        VAULT_MODULE
      );

      // ASSERTION: Vault decreased by exact claim amount
      const vaultDecrease = Number(vaultBefore) - Number(vaultAfter);
      expect(vaultDecrease).toBe(claimAmount);

      // ASSERTION: Claimable balance is now zero
      const [claimableAfter] = await transactionHelpers.view(
        "get_claimable_balance",
        [player.accountAddress.toString(), APT_METADATA],
        VAULT_MODULE
      );
      expect(Number(claimableAfter)).toBe(0);

      console.log(`  ${player.accountAddress.toString().slice(0, 10)}... claimed ${claimAmount}, vault decreased by ${vaultDecrease} ✓`);
    }
  }, 120000);

  // ==========================================================================
  // HELPER: Execute round with assertions using view functions
  // ==========================================================================

  async function executeRoundWithAssertions(roundNumber: number, voteChoice: number): Promise<void> {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`ROUND ${roundNumber} - Formula-Based Verification`);
    console.log("=".repeat(60));

    const [statusBefore] = await transactionHelpers.view("get_status");

    if (Number(statusBefore) !== GameStatus.SELECTION) {
      console.log(`Not in SELECTION phase (status=${statusBefore}), skipping round`);
      return;
    }

    // Get expected values from contract view functions
    const survivorsBeforeReveal = activePlayers.length;
    const [eliminationCount] = await transactionHelpers.view("get_elimination_count");
    const expectedEliminated = getExpectedEliminations(Number(eliminationCount), survivorsBeforeReveal);

    // Get consolation prize from contract view function
    const [expectedConsolation] = await transactionHelpers.view("get_consolation_prize_for_round", [roundNumber]);

    console.log(`Survivors before reveal: ${survivorsBeforeReveal}`);
    console.log(`Elimination count (base): ${eliminationCount}`);
    console.log(`Expected eliminations: ${expectedEliminated} (min(${eliminationCount}, ${survivorsBeforeReveal} - 1))`);
    console.log(`Expected consolation per victim (from contract): ${expectedConsolation}`);

    // Selection Phase: All active players keep their bao
    for (const player of activePlayers) {
      try {
        await transactionHelpers.executeWithFeePayer(
          player,
          admin,
          "choose_bao",
          [player.accountAddress.toString()]
        );
      } catch (e) {
        // Player might already have acted
      }
    }

    // Finalize Selection
    await transactionHelpers.executeEntry(admin, "finalize_selection");
    const [statusAfterSelection] = await transactionHelpers.view("get_status");
    expect(Number(statusAfterSelection)).toBe(GameStatus.REVEALING);

    // Reveal Bombs (use higher gas for randomness)
    await transactionHelpers.executeEntry(admin, "reveal_bombs", [], GAME_MODULE, 100000);

    const [statusAfterReveal] = await transactionHelpers.view("get_status");
    const [victims] = await transactionHelpers.view("get_round_victims");
    const victimAddresses = victims as string[];
    const actualEliminated = victimAddresses.length;

    console.log(`Actual eliminations: ${actualEliminated}`);

    // ASSERTION 1: Correct elimination count
    expect(actualEliminated).toBe(expectedEliminated);
    console.log(`✓ Elimination count assertion passed: ${actualEliminated} === ${expectedEliminated}`);

    // ASSERTION 2: Each victim has correct consolation prize (verified via view function)
    for (const victimAddr of victimAddresses) {
      const [claimable] = await transactionHelpers.view(
        "get_claimable_balance",
        [victimAddr, APT_METADATA],
        VAULT_MODULE
      );

      // ASSERTION: Claimable matches expected consolation from contract
      expect(Number(claimable)).toBe(Number(expectedConsolation));
      console.log(`✓ Victim ${victimAddr.slice(0, 10)}... consolation: ${claimable} === ${expectedConsolation}`);
    }

    // Update active/eliminated player lists
    const victimSet = new Set(victimAddresses.map(v => v.toLowerCase()));
    const newActivePlayers: Account[] = [];

    for (const player of activePlayers) {
      const addr = player.accountAddress.toString().toLowerCase();
      if (victimSet.has(addr)) {
        eliminatedPlayers.push(player);
      } else {
        newActivePlayers.push(player);
      }
    }
    activePlayers = newActivePlayers;

    console.log(`Survivors after round: ${activePlayers.length}`);

    // Check if game ended (only 1 or 0 survivors)
    if (Number(statusAfterReveal) === GameStatus.ENDED) {
      console.log("Game ended after reveal (winner determined)");
      return;
    }

    expect(Number(statusAfterReveal)).toBe(GameStatus.VOTING);

    // Voting Phase
    for (const player of activePlayers) {
      try {
        await transactionHelpers.executeWithFeePayer(player, admin, "vote", [voteChoice]);
      } catch (e) {
        // Player might have already voted
      }
    }

    // Finalize Voting
    await transactionHelpers.executeEntry(admin, "finalize_voting");

    const [statusAfterVoting] = await transactionHelpers.view("get_status");

    if (voteChoice === VoteChoice.STOP) {
      expect(Number(statusAfterVoting)).toBe(GameStatus.ENDED);
      console.log("Game ended by STOP vote - prize split among survivors");
    } else if (Number(statusAfterVoting) === GameStatus.ENDED) {
      console.log("Game ended (all eliminated or single winner)");
    } else {
      expect(Number(statusAfterVoting)).toBe(GameStatus.SELECTION);
      const [nextRound] = await transactionHelpers.view("get_round");
      console.log(`Proceeding to Round ${nextRound}`);
    }
  }
});

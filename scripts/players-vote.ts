/**
 * Players vote - make test players call vote
 *
 * Batch mode (specific players):
 *   npx tsx scripts/players-vote.ts --players 0,3,4 [choice=1]
 *
 * Legacy mode (first N players):
 *   npx tsx scripts/players-vote.ts [count=5] [choice=1]
 *
 * choice: 0=STOP, 1=CONTINUE
 */
import { accountHelpers, transactionHelpers } from "./test-helpers";

async function voteForPlayers(playerIndices: number[], choice: number) {
  const choiceName = choice === 0 ? "STOP" : "CONTINUE";
  const admin = accountHelpers.getAdmin();

  console.log(`\n🗳️  Batch vote for players: [${playerIndices.join(", ")}] → ${choiceName}`);
  console.log(`Admin: ${admin.accountAddress.toString()}\n`);

  let successCount = 0;

  for (const idx of playerIndices) {
    const player = accountHelpers.getPlayer(idx);
    const playerAddr = player.accountAddress.toString();

    console.log(`\n=== Player ${idx + 1} (TestPlayer${idx + 1}) voting ${choiceName} ===`);
    console.log(`Address: ${playerAddr}`);

    try {
      const result = await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "vote",
        [choice]
      );

      console.log(`✅ Voted ${choiceName}`);
      console.log(`   Tx: ${result.hash}`);
      successCount++;
    } catch (error: any) {
      if (error.message?.includes("PLAYER_ALREADY_VOTED")) {
        console.log(`⚠️  Already voted`);
      } else if (error.message?.includes("PLAYER_NOT_ACTIVE")) {
        console.log(`⚠️  Player eliminated (not active)`);
      } else {
        console.error(`❌ Error: ${error.message}`);
      }
    }
  }

  console.log(`\n========================================`);
  console.log(`✅ ${successCount}/${playerIndices.length} players voted ${choiceName}`);
  console.log(`========================================\n`);
}

async function main() {
  const arg1 = process.argv[2];

  // Batch mode: --players 0,3,4 [choice]
  if (arg1 === "--players") {
    const indicesStr = process.argv[3];
    if (!indicesStr) {
      console.error("Usage: npx tsx scripts/players-vote.ts --players 0,3,4 [choice]");
      console.error("  choice: 0=STOP, 1=CONTINUE (default: 1)");
      process.exit(1);
    }
    const indices = indicesStr.split(",").map((s) => parseInt(s.trim(), 10));
    const choice = parseInt(process.argv[4] || "1");
    await voteForPlayers(indices, choice);
    return;
  }

  // Legacy mode: [count] [choice]
  const count = Math.min(parseInt(arg1 || "5"), 5);
  const choice = parseInt(process.argv[3] || "1");
  const indices = Array.from({ length: count }, (_, i) => i);
  await voteForPlayers(indices, choice);
}

main().catch(console.error);

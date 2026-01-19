/**
 * Setup test players for Lucky Survivor game
 * Usage: npx tsx scripts/setup-test-players.ts [count=5]
 *
 * This script:
 * 1. Uses saved player accounts (player1-5)
 * 2. Registers each in whitelist (admin pays gas)
 * 3. Sets display name (admin pays gas)
 * 4. Joins game (admin pays gas)
 */

import { Account } from "@aptos-labs/ts-sdk";
import { accountHelpers, transactionHelpers } from "./test-helpers";
import { WHITELIST_MODULE } from "./CONFIG";

async function main() {
  const count = Math.min(parseInt(process.argv[2] || "5"), 5);
  console.log(`\n🎮 Setting up ${count} test players (reusing saved accounts)...\n`);

  const admin = accountHelpers.getAdmin();
  console.log(`Admin: ${admin.accountAddress.toString()}`);

  const players: { account: Account; name: string }[] = [];

  for (let i = 0; i < count; i++) {
    const player = accountHelpers.getPlayer(i);
    const name = `TestPlayer${i + 1}`;

    console.log(`\n=== Player ${i + 1}: ${name} ===`);
    console.log(`Address: ${player.accountAddress.toString()}`);

    try {
      // 1. Register in whitelist (may already be registered)
      console.log("1. Registering in whitelist...");
      try {
        await transactionHelpers.executeWithFeePayer(
          player,
          admin,
          "register",
          [],
          WHITELIST_MODULE
        );
        console.log("   ✅ Registered");
      } catch (e: any) {
        if (e.message?.includes("ALREADY_REGISTERED")) {
          console.log("   ✅ Already registered");
        } else {
          throw e;
        }
      }

      // 2. Get invite code
      console.log("2. Getting invite code...");
      const [code] = await transactionHelpers.view(
        "get_invite_code",
        [player.accountAddress.toString()],
        WHITELIST_MODULE
      );
      console.log(`   ✅ Code: ${code}`);

      // 3. Set display name (new API)
      console.log("3. Setting display name...");
      await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "set_display_name",
        [code, name]
      );
      console.log("   ✅ Name set");

      // 4. Join game
      console.log("4. Joining game...");
      await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "join_game",
        [code]
      );
      console.log("   ✅ Joined!");

      players.push({ account: player, name });
    } catch (error: any) {
      console.error(`   ❌ Error: ${error.message}`);
    }
  }

  console.log(`\n========================================`);
  console.log(`✅ Successfully set up ${players.length}/${count} players`);
  console.log(`========================================\n`);

  // Print player addresses for reference
  console.log("Player addresses:");
  players.forEach((p, i) => {
    console.log(`  ${i + 1}. ${p.name}: ${p.account.accountAddress.toString()}`);
  });
}

main().catch(console.error);

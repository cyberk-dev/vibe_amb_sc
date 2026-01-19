/**
 * Players choose bao - make test players call choose_bao
 *
 * Batch mode (all keep their own bao):
 *   npx tsx scripts/players-choose-bao.ts --players 0,1,3,4
 *
 * Single player mode:
 *   npx tsx scripts/players-choose-bao.ts <privateKey> [targetAddress]
 */
import { Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import { accountHelpers, transactionHelpers } from "./test-helpers";

async function batchChooseBao(playerIndices: number[]) {
  const admin = accountHelpers.getAdmin();
  console.log(`\n🎮 Batch choose_bao for players: [${playerIndices.join(", ")}]`);
  console.log(`Admin: ${admin.accountAddress.toString()}\n`);

  let successCount = 0;

  for (const idx of playerIndices) {
    const player = accountHelpers.getPlayer(idx);
    const playerAddr = player.accountAddress.toString();

    console.log(`\n=== Player ${idx + 1} (TestPlayer${idx + 1}) ===`);
    console.log(`Address: ${playerAddr}`);
    console.log(`Mode: KEEP (self)`);

    try {
      const result = await transactionHelpers.executeWithFeePayer(
        player,
        admin,
        "choose_bao",
        [playerAddr] // Keep own bao
      );

      console.log(`✅ Success!`);
      console.log(`Transaction: https://explorer.aptoslabs.com/txn/${result.hash}?network=testnet`);
      successCount++;
    } catch (error: any) {
      console.error(`❌ Error: ${error.message}`);
    }
  }

  console.log(`\n========================================`);
  console.log(`✅ ${successCount}/${playerIndices.length} players chose bao`);
  console.log(`========================================\n`);
}

async function singleChooseBao(privateKey: string, targetAddress?: string) {
  const admin = accountHelpers.getAdmin();
  const player = Account.fromPrivateKey({
    privateKey: new Ed25519PrivateKey(privateKey),
  });

  const playerAddr = player.accountAddress.toString();
  const target = targetAddress || playerAddr; // Default: keep own bao

  console.log(`\n🎯 Player choosing bao...`);
  console.log(`Player: ${playerAddr}`);
  console.log(`Target: ${target}`);
  console.log(`Mode: ${target === playerAddr ? "KEEP (self)" : "GIVE (to other)"}\n`);

  try {
    const result = await transactionHelpers.executeWithFeePayer(
      player,
      admin,
      "choose_bao",
      [target]
    );

    console.log(`✅ Success!`);
    console.log(`Transaction: https://explorer.aptoslabs.com/txn/${result.hash}?network=testnet`);
  } catch (error: any) {
    console.error(`❌ Error: ${error.message}`);
    process.exit(1);
  }
}

async function main() {
  const arg1 = process.argv[2];

  // Batch mode: --players 0,1,3,4
  if (arg1 === "--players") {
    const indicesStr = process.argv[3];
    if (!indicesStr) {
      console.error("Usage: npx tsx scripts/players-choose-bao.ts --players 0,1,3,4");
      process.exit(1);
    }
    const indices = indicesStr.split(",").map((s) => parseInt(s.trim(), 10));
    await batchChooseBao(indices);
    return;
  }

  // Single player mode
  if (!arg1) {
    console.error("Usage:");
    console.error("  Batch:  npx tsx scripts/players-choose-bao.ts --players 0,1,3,4");
    console.error("  Single: npx tsx scripts/players-choose-bao.ts <privateKey> [targetAddress]");
    process.exit(1);
  }

  await singleChooseBao(arg1, process.argv[3]);
}

main();

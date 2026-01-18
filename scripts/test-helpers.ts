import { Account, Ed25519PrivateKey, UserTransactionResponse } from "@aptos-labs/ts-sdk";
import { aptos, CONFIG, GAME_MODULE } from "./CONFIG";

export const accountHelpers = {
  getAdmin() {
    if (!CONFIG.ADMIN_PRIVATE_KEY) throw new Error("ADMIN_PRIVATE_KEY not set");
    return Account.fromPrivateKey({
      privateKey: new Ed25519PrivateKey(CONFIG.ADMIN_PRIVATE_KEY),
    });
  },

  generatePlayer() {
    return Account.generate()
  },

  generatePlayers(count: number): Account[] {
    return Array(count).fill(0).map(() => Account.generate());
  },

  async clawback(players: Account[], admin: Account): Promise<void> {
    for (const player of players) {
      try {
        const balance = await aptos.getAccountAPTAmount({
          accountAddress: player.accountAddress,
        });
        if (balance > 0) {
          await transactionHelpers.executeWithFeePayer(
            player,
            admin,
            "transfer",
            [admin.accountAddress.toString(), balance],
            "0x1::aptos_account"
          );
        }
      } catch {
        // player has no balance or account doesn't exist
      }
    }
  },
}

export const transactionHelpers = {
  async executeEntry(
    signer: Account,
    functionName: string,
    args: any[] = [],
    module = GAME_MODULE
  ): Promise<UserTransactionResponse> {
    const tx = await aptos.transaction.build.simple({
      sender: signer.accountAddress,
      data: {
        function: `${module}::${functionName}` as `${string}::${string}::${string}`,
        functionArguments: args,
      },
    });

    const [simResult] = await aptos.transaction.simulate.simple({
      signerPublicKey: signer.publicKey,
      transaction: tx,
    });

    if (!simResult || !simResult.success) {
      throw new Error(`Simulation failed: ${simResult?.vm_status}`);
    }

    const result = await aptos.signAndSubmitTransaction({ signer, transaction: tx });
    const response = await aptos.waitForTransaction({ transactionHash: result.hash });

    return response as UserTransactionResponse;
  },

  async executeWithFeePayer(
    player: Account,
    admin: Account,
    functionName: string,
    args: any[] = [],
    module = GAME_MODULE
  ): Promise<UserTransactionResponse> {
    const tx = await aptos.transaction.build.simple({
      sender: player.accountAddress,
      withFeePayer: true,
      data: {
        function: `${module}::${functionName}` as `${string}::${string}::${string}`,
        functionArguments: args,
      },
    });

    const playerSig = aptos.transaction.sign({ signer: player, transaction: tx });
    const feePayerSig = aptos.transaction.signAsFeePayer({ signer: admin, transaction: tx });

    const result = await aptos.transaction.submit.simple({
      transaction: tx,
      senderAuthenticator: playerSig,
      feePayerAuthenticator: feePayerSig,
    });

    const response = await aptos.waitForTransaction({ transactionHash: result.hash });
    return response as UserTransactionResponse;
  },

  view(functionName: string, args: any[] = [], module = GAME_MODULE) {
    return aptos.view({
      payload: {
        function: `${module}::${functionName}` as `${string}::${string}::${string}`,
        functionArguments: args,
      },
    })
  }
}
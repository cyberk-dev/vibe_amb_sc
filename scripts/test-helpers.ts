import { Account, Ed25519PrivateKey, UserTransactionResponse } from "@aptos-labs/ts-sdk";
import { aptos, CONFIG, GAME_MODULE, WHITELIST_MODULE } from "./CONFIG";

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

  // Saved player private keys (from .aptos/config.yaml profiles player1-5)
  PLAYER_KEYS: [
    "0xf3a4585dcb08ffd8e824373efb805aea85f081bda1d9c35f040ba9c3308e23b8", // player1
    "0x66e3cbaf87e41af69888d919965c373b2d14b41f3ec61cded36b6b6959128c64", // player2
    "0x78239ebaf16cf5e759adc505486ceeb20ef968ef8af1cb4ea7a7994184173f2d", // player3
    "0xdf56399bfa2fa517ce62beef2e582e58bca2e0ab62b718b021bc179bc30f72d1", // player4
    "0x6e70a79caf12135984eb76029111f49cb764b73e83b78a033f485b6d5a228438", // player5
  ],

  getPlayer(index: number): Account {
    if (index < 0 || index >= this.PLAYER_KEYS.length) {
      throw new Error(`Player index ${index} out of range (0-${this.PLAYER_KEYS.length - 1})`);
    }
    return Account.fromPrivateKey({
      privateKey: new Ed25519PrivateKey(this.PLAYER_KEYS[index]),
    });
  },

  getPlayers(count: number): Account[] {
    return Array(Math.min(count, this.PLAYER_KEYS.length))
      .fill(0)
      .map((_, i) => this.getPlayer(i));
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

  /** Register in whitelist and join game with display name */
  async registerAndJoin(player: Account, admin: Account, displayName: string): Promise<void> {
    // Register in whitelist
    await transactionHelpers.executeWithFeePayer(player, admin, "register", [], WHITELIST_MODULE);

    // Get invite code
    const [code] = await transactionHelpers.view(
      "get_invite_code",
      [player.accountAddress.toString()],
      WHITELIST_MODULE
    );

    // Join game with code and name
    await transactionHelpers.executeWithFeePayer(player, admin, "join_game", [code, displayName]);
  },
}

export const transactionHelpers = {
  async executeEntry(
    signer: Account,
    functionName: string,
    args: any[] = [],
    module = GAME_MODULE,
    maxGasAmount = 100000
  ): Promise<UserTransactionResponse> {
    const tx = await aptos.transaction.build.simple({
      sender: signer.accountAddress,
      data: {
        function: `${module}::${functionName}` as `${string}::${string}::${string}`,
        functionArguments: args,
      },
      options: {
        maxGasAmount,
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
import { Account } from "@aptos-labs/ts-sdk";
import { accountHelpers, transactionHelpers } from "./test-helpers";

const GameStatus = {
  PENDING: 0,
  SELECTION: 1,
  REVEALING: 2,
  VOTING: 3,
  ENDED: 4,
};

describe("Lucky Survivor - Full Game Flow", () => {
  let admin: Account;
  let players: Account[];

  beforeAll(async () => {
    admin = accountHelpers.getAdmin();
    await transactionHelpers.executeEntry(admin, "reset_game").catch(() => { });
    players = accountHelpers.generatePlayers(5);
  });

  it("should join game with 5 players", async () => {
    for (let i = 0; i < players.length; i++) {
      await transactionHelpers.executeWithFeePayer(players[i]!, admin, "join_game");
    }
    const [count] = await transactionHelpers.view("get_players_count");
    expect(Number(count)).toBe(5);
  });

  it("should start game", async () => {
    await transactionHelpers.executeEntry(admin, "start_game", [120]);
    const [status] = await transactionHelpers.view("get_status");
    console.log('start_game.status=', status)
    expect(Number(status)).toBe(GameStatus.SELECTION);
  });

  it("should choose bao and finalize selection", async () => {
    for (let i = 0; i < players.length; i++) {
      await transactionHelpers.executeWithFeePayer(players[i]!, admin, "choose_bao", [i]);
    }
    await transactionHelpers.executeEntry(admin, "finalize_selection");
    const [status] = await transactionHelpers.view("get_status");
    console.log('finalize_selection.status=', status)
    expect(Number(status)).toBe(GameStatus.REVEALING);
  });

  it("should reveal bombs", async () => {
    await transactionHelpers.executeEntry(admin, "reveal_bombs");
    const [status] = await transactionHelpers.view("get_status");
    const [count] = await transactionHelpers.view("get_elimination_count");
    console.log('reveal_bombs.status=', status)
    console.log('reveal_bombs.elimination_count=', count)
    expect([GameStatus.VOTING, GameStatus.ENDED]).toContain(Number(status));
  });
});
import dotenv from "dotenv";
import path from "path";
dotenv.config({ path: path.join(process.cwd(), ".env") });

import { Aptos, AptosConfig, Network } from '@aptos-labs/ts-sdk'

export const CONFIG = {
  NETWORK: process.env.APTOS_NETWORK as Network || Network.TESTNET,
  API_KEY: process.env.APTOS_API_KEY!,
  CONTRACT_ADDRESS: process.env.CONTRACT_ADDRESS,
  ADMIN_PRIVATE_KEY: process.env.ADMIN_PRIVATE_KEY,
}
export const aptos = new Aptos(
  new AptosConfig({
    network: CONFIG.NETWORK,
    ...(CONFIG.API_KEY && {
      clientConfig: {
        HEADERS: { Authorization: `Bearer ${CONFIG.API_KEY}` }
      }
    })
  })
)
export const GAME_MODULE = `${CONFIG.CONTRACT_ADDRESS}::game`;
export const VAULT_MODULE = `${CONFIG.CONTRACT_ADDRESS}::vault`;
export const WHITELIST_MODULE = `${CONFIG.CONTRACT_ADDRESS}::whitelist`;
export const APT_METADATA = "0xa";
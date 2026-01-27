import { BlockfrostProvider } from "@meshsdk/core";

const BLOCKFROST_API_KEY = process.env.NEXT_PUBLIC_BLOCKFROST_API_KEY || "";

if (!BLOCKFROST_API_KEY) {
  console.warn(
    "NEXT_PUBLIC_BLOCKFROST_API_KEY is not set. Mesh SDK transactions will fail."
  );
}

export const provider = new BlockfrostProvider(BLOCKFROST_API_KEY);

/**
 * Get network ID from environment variable
 * preview/preprod = 0 (testnet), mainnet = 1
 */
export function getNetworkId(): 0 | 1 {
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";
  return network === "mainnet" ? 1 : 0;
}

/**
 * Get network name from environment variable
 */
export function getNetworkName(): "preview" | "preprod" | "mainnet" {
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";
  if (network === "mainnet" || network === "preprod" || network === "preview") {
    return network;
  }
  return "preview";
}
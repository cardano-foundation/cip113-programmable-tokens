/**
 * Re-export useWallet from wallet context.
 * This is the import path all components should use.
 */
export { useWallet } from "@/contexts/wallet-context";
export type { WalletApi, WalletContextValue } from "@/contexts/wallet-context";

/**
 * Type alias for backward compatibility with code that used
 * Mesh SDK's IWallet type. Our WalletApi matches the CIP-30 surface.
 */
export type { WalletApi as IWallet } from "@/contexts/wallet-context";

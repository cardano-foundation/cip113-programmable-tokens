/**
 * Wallet Components Module
 *
 * Cardano wallet integration components using Mesh SDK.
 * These components handle CIP-30 wallet connections and display.
 *
 * ## Available Components
 * - **ConnectButton**: Modal-based wallet connection with multiple wallets
 * - **WalletInfo**: Displays connected wallet address, balance, and network
 *
 * ## Supported Wallets
 * - Nami, Eternl, Lace, Flint
 *
 * ## Client-Side Only
 * These components must be rendered client-side due to Mesh SDK
 * requirements. Use dynamic imports or 'use client' directive.
 *
 * @module components/wallet
 *
 * @example
 * ```tsx
 * import { ConnectButton, WalletInfo } from '@/components/wallet';
 *
 * // In header
 * <ConnectButton />
 *
 * // In sidebar when connected
 * {connected && <WalletInfo />}
 * ```
 */

export { ConnectButton } from "./connect-button";
export { WalletInfo } from "./wallet-info";

/**
 * Utility functions for formatting Cardano addresses, amounts, and other data
 */

/**
 * Truncate a Cardano address for display
 * @param address - Full Cardano address
 * @param startChars - Number of characters to show at start (default: 8)
 * @param endChars - Number of characters to show at end (default: 8)
 * @returns Truncated address like "addr1qx...yz123"
 */
export function truncateAddress(
  address: string,
  startChars: number = 8,
  endChars: number = 8
): string {
  if (!address) return "";
  if (address.length <= startChars + endChars) return address;
  return `${address.slice(0, startChars)}...${address.slice(-endChars)}`;
}

/**
 * Format lovelace amount to ADA with proper decimals
 * @param lovelace - Amount in lovelace (1 ADA = 1,000,000 lovelace)
 * @param decimals - Number of decimal places (default: 2)
 * @returns Formatted ADA amount
 */
export function formatADA(lovelace: number | string, decimals: number = 2): string {
  const amount = typeof lovelace === "string" ? parseInt(lovelace, 10) : lovelace;
  const ada = amount / 1_000_000;
  return ada.toFixed(decimals);
}

/**
 * Format ADA amount with symbol
 * @param lovelace - Amount in lovelace
 * @param decimals - Number of decimal places (default: 2)
 * @returns Formatted string like "123.45 ₳"
 */
export function formatADAWithSymbol(lovelace: number | string, decimals: number = 2): string {
  return `${formatADA(lovelace, decimals)} ₳`;
}

/**
 * Format a number with thousand separators
 * @param num - Number to format
 * @returns Formatted string like "1,234,567"
 */
export function formatNumber(num: number): string {
  return num.toLocaleString("en-US");
}

/**
 * Format token amount with unit
 * @param amount - Token amount
 * @param unit - Token unit/name
 * @param decimals - Number of decimal places (default: 0)
 * @returns Formatted string like "100 TOKENS"
 */
export function formatTokenAmount(
  amount: number | string,
  unit: string,
  decimals: number = 0
): string {
  const num = typeof amount === "string" ? parseFloat(amount) : amount;
  return `${num.toFixed(decimals)} ${unit}`;
}

/**
 * Get network display name
 * @param network - Network identifier (preview, preprod, mainnet)
 * @returns Capitalized network name
 */
export function getNetworkDisplayName(network: string): string {
  const names: Record<string, string> = {
    preview: "Preview",
    preprod: "Preprod",
    mainnet: "Mainnet",
  };
  return names[network.toLowerCase()] || network;
}

/**
 * Get network color for badges/indicators
 * @param network - Network identifier
 * @returns Tailwind color class
 */
export function getNetworkColor(network: string): string {
  const colors: Record<string, string> = {
    preview: "bg-blue-500",
    preprod: "bg-yellow-500",
    mainnet: "bg-green-500",
  };
  return colors[network.toLowerCase()] || "bg-gray-500";
}

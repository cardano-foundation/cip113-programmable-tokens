/**
 * Global type declarations for browser APIs and extensions
 */

// CIP-30 Cardano Wallet API
interface CardanoWallet {
  name: string;
  icon: string;
  apiVersion: string;
  enable: (extensions?: { extensions: { cip: number }[] }) => Promise<any>;
  isEnabled: () => Promise<boolean>;
}

interface Window {
  cardano?: {
    [key: string]: CardanoWallet;
  };
}

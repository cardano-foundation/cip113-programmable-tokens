/**
 * Header Component
 *
 * The main navigation header for the CIP-113 application. Provides:
 * - Logo and branding
 * - Navigation links to main pages
 * - Network indicator badge
 * - Wallet connection button (dynamically loaded)
 *
 * ## Navigation Items
 * - Home - Landing page
 * - Deploy - Protocol deployment (coming soon)
 * - Mint - Token minting
 * - Transfer - Token transfers
 * - Dashboard - Portfolio view
 *
 * ## SSR Considerations
 * The ConnectButton is dynamically imported with SSR disabled
 * since wallet APIs require browser context.
 *
 * @module components/layout/header
 */

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import dynamic from "next/dynamic";
import { Badge } from "@/components/ui/badge";
import { getNetworkDisplayName, getNetworkColor } from "@/lib/utils";
import { cn } from "@/lib/utils";

/**
 * Dynamically import ConnectButton to avoid SSR issues with wallet APIs.
 */
const ConnectButton = dynamic(
  () => import("@/components/wallet").then((mod) => ({ default: mod.ConnectButton })),
  { ssr: false }
);

/**
 * Navigation configuration for header links.
 */
const navigation = [
  { name: "Home", href: "/" },
  { name: "Deploy", href: "/deploy" },
  { name: "Mint", href: "/mint" },
  { name: "Transfer", href: "/transfer" },
  { name: "Dashboard", href: "/dashboard" },
];

/**
 * Main application header with navigation and wallet connection.
 *
 * @returns React component
 */
export function Header() {
  const pathname = usePathname();
  const network = process.env.NEXT_PUBLIC_NETWORK || "preview";

  return (
    <header className="sticky top-0 z-40 w-full border-b border-dark-700 bg-dark-900/95 backdrop-blur supports-[backdrop-filter]:bg-dark-900/75">
      <div className="container mx-auto px-4">
        <div className="flex h-16 items-center justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="flex items-center gap-2">
              <div className="h-8 w-8 rounded-lg bg-gradient-primary flex items-center justify-center">
                <span className="text-white font-bold text-lg">PT</span>
              </div>
              <span className="hidden sm:inline-block font-bold text-white text-lg">
                Programmable Tokens
              </span>
            </Link>

            <nav className="hidden md:flex items-center gap-1">
              {navigation.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "px-3 py-2 rounded-md text-sm font-medium transition-colors",
                    pathname === item.href
                      ? "bg-dark-800 text-primary-400"
                      : "text-dark-300 hover:text-white hover:bg-dark-800"
                  )}
                >
                  {item.name}
                </Link>
              ))}
            </nav>
          </div>

          <div className="flex items-center gap-3">
            <Badge variant="info" size="sm" className="hidden sm:inline-flex">
              <span className={cn("w-2 h-2 rounded-full mr-1.5", getNetworkColor(network))} />
              {getNetworkDisplayName(network)}
            </Badge>
            <ConnectButton />
          </div>
        </div>
      </div>
    </header>
  );
}

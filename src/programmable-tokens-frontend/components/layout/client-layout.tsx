/**
 * Client Layout Component
 *
 * This component wraps the application with client-side providers that cannot
 * be rendered on the server (SSR). It uses Next.js dynamic imports with
 * `ssr: false` to ensure wallet-related code only runs in the browser.
 *
 * ## Why Client-Only?
 * The Mesh SDK wallet providers require browser APIs (window, localStorage)
 * that are not available during server-side rendering. Using dynamic imports
 * prevents hydration mismatches and SSR errors.
 *
 * ## Provider Hierarchy
 * ```
 * ClientLayout
 *   └── AppProviders (dynamic, client-only)
 *         ├── MeshProvider (wallet context)
 *         ├── ToastProvider (notifications)
 *         └── {children}
 * ```
 *
 * @module components/layout/client-layout
 */

"use client";

import { ReactNode } from "react";
import dynamic from "next/dynamic";

/**
 * Dynamically import AppProviders with SSR disabled.
 * This ensures wallet-related code only runs in the browser.
 * A loading spinner is shown while the providers are being loaded.
 */
const AppProviders = dynamic(
  () => import("@/components/providers/app-providers").then((mod) => ({ default: mod.AppProviders })),
  {
    ssr: false,
    loading: () => (
      <div className="min-h-screen bg-dark-900 flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-dark-400">Loading wallet providers...</p>
        </div>
      </div>
    ),
  }
);

/**
 * Props for the ClientLayout component.
 */
interface ClientLayoutProps {
  /** Child components to render within providers */
  children: ReactNode;
}

/**
 * Client-side layout wrapper for wallet and provider context.
 *
 * Wraps children with dynamically-loaded providers that require
 * browser APIs. Must be used for any pages that need wallet access.
 *
 * @param props - Component props
 * @returns React component
 *
 * @example
 * ```tsx
 * // In app/layout.tsx
 * export default function RootLayout({ children }) {
 *   return (
 *     <html>
 *       <body>
 *         <ClientLayout>{children}</ClientLayout>
 *       </body>
 *     </html>
 *   );
 * }
 * ```
 */
export function ClientLayout({ children }: ClientLayoutProps) {
  return <AppProviders>{children}</AppProviders>;
}

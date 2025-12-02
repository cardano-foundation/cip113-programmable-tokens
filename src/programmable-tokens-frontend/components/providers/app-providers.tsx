/**
 * Application Providers Component
 *
 * Root provider wrapper that sets up all required context providers
 * for the CIP-113 application. This includes:
 * - MeshProvider for Cardano wallet connectivity
 * - Toast notifications (Toaster)
 * - Layout structure (Header, Footer)
 *
 * ## Provider Hierarchy
 * ```
 * MeshProvider
 *   └── Layout Container
 *         ├── Header
 *         ├── Main Content ({children})
 *         ├── Footer
 *         └── Toaster
 * ```
 *
 * @module components/providers/app-providers
 */

"use client";

import { ReactNode, useState, useEffect } from "react";
import { Header } from "@/components/layout/header";
import { Footer } from "@/components/layout/footer";
import { Toaster } from "@/components/ui/toast";

/**
 * Props for AppProviders component.
 */
interface AppProvidersProps {
  /** Application content to wrap with providers */
  children: ReactNode;
}

/**
 * Root provider component with layout structure.
 *
 * Wraps the application with MeshProvider for wallet access
 * and provides the common layout elements. Uses lazy loading
 * for MeshProvider to handle WebAssembly initialization.
 *
 * @param props - Component props
 * @returns React component
 */
export function AppProviders({ children }: AppProvidersProps) {
  const [MeshProviderComponent, setMeshProviderComponent] = useState<React.ComponentType<{ children: ReactNode }> | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // Dynamically import MeshProvider only on client side
    import("@meshsdk/react")
      .then((mod) => {
        setMeshProviderComponent(() => mod.MeshProvider);
        setIsLoading(false);
      })
      .catch((err) => {
        console.error("Failed to load MeshProvider:", err);
        setIsLoading(false);
      });
  }, []);

  // Show loading spinner while MeshProvider is loading
  if (isLoading) {
    return (
      <div className="min-h-screen bg-dark-900 flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-primary-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-dark-400">Initializing wallet...</p>
        </div>
      </div>
    );
  }

  // Render layout - MeshProvider wraps if loaded, otherwise just layout
  const content = (
    <div className="flex flex-col min-h-screen bg-dark-900">
      <Header />
      <main className="flex-1">{children}</main>
      <Footer />
      <Toaster />
    </div>
  );

  if (MeshProviderComponent) {
    return <MeshProviderComponent>{content}</MeshProviderComponent>;
  }

  return content;
}

/**
 * Mesh Provider Wrapper Component
 *
 * A simple wrapper around MeshProvider from @meshsdk/react.
 * Provides Cardano wallet connectivity context to child components.
 *
 * ## Features Provided by MeshProvider
 * - `useWallet` hook for wallet state and operations
 * - CIP-30 wallet detection and connection
 * - Transaction signing and submission
 *
 * @module components/providers/mesh-provider-wrapper
 */

"use client";

import { ReactNode } from "react";
import { MeshProvider } from "@meshsdk/react";

/**
 * Props for MeshProviderWrapper component.
 */
interface MeshProviderWrapperProps {
  /** Child components that need wallet access */
  children: ReactNode;
}

/**
 * Wrapper component for Mesh SDK wallet provider.
 *
 * @param props - Component props
 * @returns React component
 */
export function MeshProviderWrapper({ children }: MeshProviderWrapperProps) {
  return <MeshProvider>{children}</MeshProvider>;
}

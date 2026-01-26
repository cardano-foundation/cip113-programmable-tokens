/**
 * Flow Registry
 * Central registry for registration flows by substandard
 */

import type { RegistrationFlow } from '@/types/registration';

// ============================================================================
// Registry
// ============================================================================

const flowRegistry = new Map<string, RegistrationFlow>();

/**
 * Register a flow for a substandard
 */
export function registerFlow(flow: RegistrationFlow): void {
  flowRegistry.set(flow.id, flow);
}

/**
 * Get a flow by substandard ID
 */
export function getFlow(substandardId: string): RegistrationFlow | undefined {
  return flowRegistry.get(substandardId);
}

/**
 * Get all registered flows
 */
export function getAllFlows(): RegistrationFlow[] {
  return Array.from(flowRegistry.values());
}

/**
 * Get all registered flow IDs
 */
export function getFlowIds(): string[] {
  return Array.from(flowRegistry.keys());
}

/**
 * Check if a flow exists for a substandard
 */
export function hasFlow(substandardId: string): boolean {
  return flowRegistry.has(substandardId);
}

/**
 * Clear all registered flows (useful for testing)
 */
export function clearFlows(): void {
  flowRegistry.clear();
}

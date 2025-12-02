/**
 * Protocol Version API Client
 * Handles fetching protocol version information
 */

import { apiGet } from './client';
import { ProtocolVersionInfo } from '@/types/api';

/**
 * Get all protocol versions
 * Returns list of all protocol versions with default marked
 *
 * @returns Promise<ProtocolVersionInfo[]> List of protocol versions
 */
export async function getProtocolVersions(): Promise<ProtocolVersionInfo[]> {
  return apiGet<ProtocolVersionInfo[]>('/protocol-params/versions');
}

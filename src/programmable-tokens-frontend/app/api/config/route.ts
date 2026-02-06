/**
 * Runtime Configuration API
 *
 * This endpoint reads environment variables at runtime (server-side),
 * making it work with Kubernetes ConfigMaps and deployment env vars
 * without requiring a rebuild.
 */

import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic'; // Disable caching

export async function GET() {
  // Read flow enablement from server-side env vars
  // These are NOT replaced at build time, so they work with Kubernetes
  const config = {
    flows: {
      dummy: getEnvBoolean('FLOW_DUMMY_ENABLED', true),
      'freeze-and-seize': getEnvBoolean('FLOW_FREEZE_AND_SEIZE_ENABLED', true),
    },
  };

  return NextResponse.json(config);
}

/**
 * Parse boolean from environment variable
 * Supports: 'true', 'false', '1', '0', 'yes', 'no'
 */
function getEnvBoolean(key: string, defaultValue: boolean): boolean {
  const value = process.env[key];

  if (value === undefined || value === '') {
    return defaultValue;
  }

  const normalized = value.toLowerCase().trim();
  return normalized === 'true' || normalized === '1' || normalized === 'yes';
}

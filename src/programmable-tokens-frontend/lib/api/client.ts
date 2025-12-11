/**
 * Base API Client for CIP-0113 Backend Communication
 *
 * This module provides a typed HTTP client for communicating with the
 * CIP-0113 Java backend. It wraps the native fetch API with:
 *
 * - Automatic timeout handling
 * - Consistent error transformation
 * - JSON serialization/deserialization
 * - Support for both JSON and plain text responses
 *
 * ## Configuration
 *
 * The client is configured via environment variables:
 * - `NEXT_PUBLIC_API_BASE_URL`: Backend URL (default: http://localhost:8080)
 *
 * ## Error Handling
 *
 * All errors are wrapped in `ApiException` for consistent handling:
 * ```typescript
 * try {
 *   const data = await apiGet('/endpoint');
 * } catch (error) {
 *   if (error instanceof ApiException) {
 *     console.log(`HTTP ${error.status}: ${error.message}`);
 *   }
 * }
 * ```
 *
 * @module lib/api/client
 */

import { ApiException } from '@/types/api';

/**
 * Base URL for all API requests.
 * Override via NEXT_PUBLIC_API_BASE_URL environment variable.
 */
const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8080';

/**
 * API version prefix for all endpoints.
 */
const API_PREFIX = '/api/v1';

/**
 * Default request timeout in milliseconds (30 seconds).
 */
const DEFAULT_TIMEOUT = 30000;

/**
 * Extended fetch options with timeout support.
 */
export interface FetchOptions extends RequestInit {
  /**
   * Request timeout in milliseconds.
   * Defaults to 30 seconds if not specified.
   */
  timeout?: number;
}

/**
 * Fetch wrapper with timeout and error handling.
 *
 * Uses AbortController to implement request timeouts, which are not
 * natively supported by fetch.
 *
 * @param url - The URL to fetch
 * @param options - Fetch options including timeout
 * @returns Promise resolving to the Response
 * @throws {ApiException} If request times out or fails
 * @internal
 */
async function fetchWithTimeout(
  url: string,
  options: FetchOptions = {}
): Promise<Response> {
  const { timeout = DEFAULT_TIMEOUT, ...fetchOptions } = options;

  // Use AbortController for timeout implementation
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      ...fetchOptions,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...fetchOptions.headers,
      },
    });

    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    // Convert AbortError (timeout) to ApiException
    if (error instanceof Error && error.name === 'AbortError') {
      throw new ApiException('Request timeout', 408);
    }
    throw error;
  }
}

/**
 * Perform a GET request to the API.
 *
 * Automatically handles JSON parsing and error wrapping.
 *
 * @typeParam T - Expected response type
 * @param endpoint - API endpoint path (e.g., "/substandards")
 * @param options - Optional fetch configuration
 * @returns Promise resolving to the typed response
 * @throws {ApiException} If request fails or returns non-2xx status
 *
 * @example
 * ```typescript
 * interface Substandard { id: string; name: string; }
 * const substandards = await apiGet<Substandard[]>('/substandards');
 * ```
 */
export async function apiGet<T>(endpoint: string, options?: FetchOptions): Promise<T> {
  const url = `${API_BASE_URL}${API_PREFIX}${endpoint}`;

  try {
    const response = await fetchWithTimeout(url, {
      ...options,
      method: 'GET',
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new ApiException(
        errorText || `API request failed: ${response.statusText}`,
        response.status
      );
    }

    return await response.json();
  } catch (error) {
    if (error instanceof ApiException) {
      throw error;
    }
    throw new ApiException(
      error instanceof Error ? error.message : 'Unknown error occurred',
      500,
      error
    );
  }
}

// ============================================================================
// POST Request Handler
// ============================================================================

/**
 * Perform a POST request to the API.
 *
 * Handles both JSON and plain text responses. The CIP-0113 backend
 * returns unsigned transaction CBOR as plain text (not JSON), which
 * this function detects via Content-Type header.
 *
 * @typeParam T - Request body type
 * @typeParam R - Expected response type (defaults to unknown)
 * @param endpoint - API endpoint path (e.g., "/issue-token/mint")
 * @param data - Request body data
 * @param options - Optional fetch configuration
 * @returns Promise resolving to the typed response
 * @throws {ApiException} If request fails or returns non-2xx status
 *
 * @example
 * ```typescript
 * // JSON response
 * const result = await apiPost<CreateRequest, CreateResponse>(
 *   '/create',
 *   { name: 'example' }
 * );
 *
 * // Plain text response (CBOR hex)
 * const cborHex = await apiPost<MintRequest, string>(
 *   '/issue-token/mint',
 *   mintRequest
 * );
 * ```
 */
export async function apiPost<T, R = unknown>(
  endpoint: string,
  data: T,
  options?: FetchOptions
): Promise<R> {
  const url = `${API_BASE_URL}${API_PREFIX}${endpoint}`;

  try {
    const response = await fetchWithTimeout(url, {
      ...options,
      method: 'POST',
      body: JSON.stringify(data),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new ApiException(
        errorText || `API request failed: ${response.statusText}`,
        response.status
      );
    }

    // Determine response format from Content-Type header
    // JSON responses: application/json
    // CBOR hex responses: text/plain (unsigned transaction bytes)
    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      return await response.json();
    } else {
      // Return text for CBOR hex responses
      return (await response.text()) as R;
    }
  } catch (error) {
    if (error instanceof ApiException) {
      throw error;
    }
    throw new ApiException(
      error instanceof Error ? error.message : 'Unknown error occurred',
      500,
      error
    );
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Get the configured API base URL.
 *
 * Useful for debugging or displaying connection information to users.
 *
 * @returns The base URL string (e.g., "http://localhost:8080")
 *
 * @example
 * ```typescript
 * console.log(`Connecting to: ${getApiBaseUrl()}`);
 * ```
 */
export function getApiBaseUrl(): string {
  return API_BASE_URL;
}

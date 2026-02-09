/**
 * Base API client for backend communication
 */

import { ApiException } from '@/types/api';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8081';
const API_PREFIX = '/api/v1';
const DEFAULT_TIMEOUT = 30000; // 30 seconds

export interface FetchOptions extends RequestInit {
  timeout?: number;
}

/**
 * Base fetch wrapper with error handling and timeout
 */
async function fetchWithTimeout(
  url: string,
  options: FetchOptions = {}
): Promise<Response> {
  const { timeout = DEFAULT_TIMEOUT, ...fetchOptions } = options;

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
    if (error instanceof Error && error.name === 'AbortError') {
      throw new ApiException('Request timeout', 408);
    }
    throw error;
  }
}

/**
 * GET request
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
      
      // Try to parse as JSON to extract error message from TransactionContext
      let errorMessage = errorText;
      try {
        const errorJson = JSON.parse(errorText);
        // Check if it's a TransactionContext error response
        if (errorJson.error) {
          errorMessage = errorJson.error;
        } else if (errorJson.message) {
          errorMessage = errorJson.message;
        } else if (typeof errorJson === 'string') {
          errorMessage = errorJson;
        }
      } catch {
        // Not JSON, use text as-is
      }
      
      throw new ApiException(
        errorMessage || `API request failed: ${response.statusText}`,
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

/**
 * POST request
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
      
      // Try to parse as JSON to extract error message from TransactionContext
      let errorMessage = errorText;
      try {
        const errorJson = JSON.parse(errorText);
        // Check if it's a TransactionContext error response
        if (errorJson.error) {
          errorMessage = errorJson.error;
        } else if (errorJson.message) {
          errorMessage = errorJson.message;
        } else if (typeof errorJson === 'string') {
          errorMessage = errorJson;
        }
      } catch {
        // Not JSON, use text as-is
      }
      
      throw new ApiException(
        errorMessage || `API request failed: ${response.statusText}`,
        response.status
      );
    }

    // Check if response is JSON or plain text (CBOR hex)
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

/**
 * Get full API base URL (useful for debugging)
 */
export function getApiBaseUrl(): string {
  return API_BASE_URL;
}

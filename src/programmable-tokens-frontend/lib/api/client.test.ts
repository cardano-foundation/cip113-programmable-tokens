import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { apiGet, apiPost } from './client';
import { ApiException } from '@/types/api';

// Store original fetch
const originalFetch = global.fetch;

describe('apiGet', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('should make GET request to correct URL', async () => {
    const mockResponse = { data: 'test' };
    global.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });

    const result = await apiGet('/substandards');

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/v1/substandards'),
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          'Content-Type': 'application/json',
        }),
      })
    );
    expect(result).toEqual(mockResponse);
  });

  it('should throw ApiException on non-OK response', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 404,
      statusText: 'Not Found',
      text: () => Promise.resolve('Resource not found'),
    });

    await expect(apiGet('/nonexistent')).rejects.toThrow(ApiException);
  });

  it('should throw ApiException on network error', async () => {
    global.fetch = vi.fn().mockRejectedValueOnce(new Error('Network error'));

    await expect(apiGet('/test')).rejects.toThrow(ApiException);
  });

  it('should handle timeout', async () => {
    global.fetch = vi.fn().mockImplementationOnce(() => {
      const error = new Error('AbortError');
      error.name = 'AbortError';
      return Promise.reject(error);
    });

    await expect(apiGet('/slow', { timeout: 1000 })).rejects.toThrow('Request timeout');
  });
});

describe('apiPost', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('should make POST request with JSON body', async () => {
    const requestData = { name: 'test' };
    const mockResponse = { id: '123' };

    global.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: () => Promise.resolve(mockResponse),
    });

    const result = await apiPost('/mint', requestData);

    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining('/mint'),
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify(requestData),
      })
    );
    expect(result).toEqual(mockResponse);
  });

  it('should handle plain text response (CBOR hex)', async () => {
    const requestData = { name: 'test' };
    const cborHex = '84a400818258203b40265111d8bb3c3c608d95b3a0bf83';

    global.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      headers: new Headers({ 'content-type': 'text/plain' }),
      text: () => Promise.resolve(cborHex),
    });

    const result = await apiPost('/mint', requestData);
    expect(result).toBe(cborHex);
  });

  it('should throw ApiException on server error', async () => {
    global.fetch = vi.fn().mockResolvedValueOnce({
      ok: false,
      status: 500,
      statusText: 'Internal Server Error',
      text: () => Promise.resolve('Server error'),
    });

    await expect(apiPost('/test', {})).rejects.toThrow(ApiException);
  });
});

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useSubstandards } from './use-substandards';
import * as api from '@/lib/api';
import { Substandard } from '@/types/api';

// Mock the API module
vi.mock('@/lib/api', () => ({
  getSubstandards: vi.fn(),
}));

const mockSubstandards: Substandard[] = [
  {
    id: 'freeze-and-seize',
    validators: [
      {
        title: 'freeze_and_seize_transfer',
        script_bytes: '4d01000033222220051',
        script_hash: 'abcd1234',
      },
    ],
  },
  {
    id: 'simple-transfer',
    validators: [
      {
        title: 'simple_transfer',
        script_bytes: '4d01000033222220052',
        script_hash: 'efgh5678',
      },
    ],
  },
];

describe('useSubstandards', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should start with loading state', () => {
    vi.mocked(api.getSubstandards).mockImplementation(
      () => new Promise(() => { }) // Never resolves
    );

    const { result } = renderHook(() => useSubstandards());

    expect(result.current.isLoading).toBe(true);
    expect(result.current.substandards).toEqual([]);
    expect(result.current.error).toBeNull();
  });

  it('should fetch and return substandards', async () => {
    vi.mocked(api.getSubstandards).mockResolvedValueOnce(mockSubstandards);

    const { result } = renderHook(() => useSubstandards());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.substandards).toEqual(mockSubstandards);
    expect(result.current.error).toBeNull();
  });

  it('should handle fetch error', async () => {
    const errorMessage = 'Failed to fetch substandards';
    vi.mocked(api.getSubstandards).mockRejectedValueOnce(new Error(errorMessage));

    const { result } = renderHook(() => useSubstandards());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.substandards).toEqual([]);
    expect(result.current.error).toBe(errorMessage);
  });

  it('should provide refetch function', async () => {
    vi.mocked(api.getSubstandards)
      .mockResolvedValueOnce([mockSubstandards[0]])
      .mockResolvedValueOnce(mockSubstandards);

    const { result } = renderHook(() => useSubstandards());

    // Wait for initial fetch
    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.substandards).toHaveLength(1);

    // Refetch
    await result.current.refetch();

    await waitFor(() => {
      expect(result.current.substandards).toHaveLength(2);
    });
  });

  it('should handle non-Error rejection', async () => {
    vi.mocked(api.getSubstandards).mockRejectedValueOnce('String error');

    const { result } = renderHook(() => useSubstandards());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.error).toBe('Failed to load substandards');
  });
});

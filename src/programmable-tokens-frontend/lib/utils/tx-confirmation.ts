/**
 * Transaction Confirmation Utility
 * Uses Blockfrost API to poll for transaction confirmation
 */

const BLOCKFROST_URL = process.env.NEXT_PUBLIC_BLOCKFROST_URL || 'https://cardano-preview.blockfrost.io/api/v0';
const BLOCKFROST_API_KEY = process.env.NEXT_PUBLIC_BLOCKFROST_API_KEY || '';

export interface TxConfirmationResult {
  confirmed: boolean;
  txHash: string;
  block?: string;
  blockHeight?: number;
  error?: string;
}

export interface TxConfirmationOptions {
  /** Polling interval in milliseconds (default: 10000 = 10 seconds) */
  pollInterval?: number;
  /** Maximum time to wait in milliseconds (default: 300000 = 5 minutes) */
  timeout?: number;
  /** Callback for each poll attempt */
  onPoll?: (attempt: number, elapsed: number) => void;
  /** Callback when confirmed */
  onConfirmed?: (result: TxConfirmationResult) => void;
  /** Abort signal to cancel polling */
  signal?: AbortSignal;
}

/**
 * Check if a transaction exists on-chain via Blockfrost
 * @param txHash Transaction hash to check
 * @returns Transaction info if found, null otherwise
 */
export async function checkTxOnChain(txHash: string): Promise<TxConfirmationResult | null> {
  if (!BLOCKFROST_API_KEY) {
    console.warn('[TxConfirmation] Blockfrost API key not configured');
    return null;
  }

  try {
    console.log(`[TxConfirmation] Checking tx: ${txHash.slice(0, 16)}...`);

    const response = await fetch(`${BLOCKFROST_URL}/txs/${txHash}`, {
      headers: {
        'project_id': BLOCKFROST_API_KEY,
      },
    });

    console.log(`[TxConfirmation] Response status: ${response.status}`);

    // 404 means tx not found yet - this is expected while waiting
    if (response.status === 404) {
      console.log('[TxConfirmation] Tx not found yet (404) - will keep polling');
      return null;
    }

    // Other error statuses
    if (response.status >= 400) {
      let errorText = '';
      try {
        errorText = await response.text();
      } catch {
        errorText = 'Could not read error body';
      }
      console.error(`[TxConfirmation] Blockfrost error ${response.status}: ${errorText}`);
      // Return null to continue polling - might be a temporary error
      return null;
    }

    // Success - parse the response
    const data = await response.json();
    console.log('[TxConfirmation] Tx CONFIRMED!', data.hash);

    return {
      confirmed: true,
      txHash: data.hash,
      block: data.block,
      blockHeight: data.block_height,
    };
  } catch (error) {
    console.error('[TxConfirmation] Network/fetch error:', error);
    // Return null on error - don't throw, so polling continues
    return null;
  }
}

/**
 * Wait for a transaction to be confirmed on-chain
 * Polls Blockfrost API at regular intervals until tx is found or timeout
 *
 * @param txHash Transaction hash to wait for
 * @param options Polling options
 * @returns Promise that resolves when tx is confirmed or rejects on timeout/abort
 */
export async function waitForTxConfirmation(
  txHash: string,
  options: TxConfirmationOptions = {}
): Promise<TxConfirmationResult> {
  const {
    pollInterval = 10000, // 10 seconds
    timeout = 300000, // 5 minutes
    onPoll,
    onConfirmed,
    signal,
  } = options;

  console.log(`[TxConfirmation] Starting to poll for tx: ${txHash}`);
  console.log(`[TxConfirmation] Poll interval: ${pollInterval}ms, Timeout: ${timeout}ms`);

  const startTime = Date.now();
  let attempt = 0;

  return new Promise((resolve, reject) => {
    // Check if already aborted
    if (signal?.aborted) {
      console.log('[TxConfirmation] Already aborted');
      reject(new Error('Aborted'));
      return;
    }

    // Listen for abort
    const abortHandler = () => {
      console.log('[TxConfirmation] Abort signal received');
      reject(new Error('Aborted'));
    };
    signal?.addEventListener('abort', abortHandler);

    const poll = async () => {
      // Check abort signal
      if (signal?.aborted) {
        console.log('[TxConfirmation] Aborted during poll');
        signal?.removeEventListener('abort', abortHandler);
        return;
      }

      attempt++;
      const elapsed = Date.now() - startTime;

      console.log(`[TxConfirmation] Poll attempt ${attempt}, elapsed: ${elapsed}ms`);

      // Notify poll attempt
      try {
        onPoll?.(attempt, elapsed);
      } catch (e) {
        console.error('[TxConfirmation] Error in onPoll callback:', e);
      }

      // Check timeout
      if (elapsed >= timeout) {
        console.log('[TxConfirmation] Timeout reached');
        signal?.removeEventListener('abort', abortHandler);
        reject(new Error(`Timeout waiting for transaction ${txHash} after ${timeout}ms`));
        return;
      }

      // Check if tx is on-chain
      try {
        const result = await checkTxOnChain(txHash);

        if (result?.confirmed) {
          console.log('[TxConfirmation] Transaction confirmed!');
          signal?.removeEventListener('abort', abortHandler);
          try {
            onConfirmed?.(result);
          } catch (e) {
            console.error('[TxConfirmation] Error in onConfirmed callback:', e);
          }
          resolve(result);
          return;
        }
      } catch (error) {
        // Log but continue polling
        console.error('[TxConfirmation] Error during check, will retry:', error);
      }

      // Schedule next poll (only if not aborted)
      if (!signal?.aborted) {
        console.log(`[TxConfirmation] Scheduling next poll in ${pollInterval}ms`);
        setTimeout(poll, pollInterval);
      }
    };

    // Start first poll immediately
    poll();
  });
}

/**
 * Hook-friendly version that returns control functions
 * Useful for React components that need to start/stop/check status
 */
export function createTxConfirmationPoller(txHash: string, options: TxConfirmationOptions = {}) {
  let abortController: AbortController | null = null;
  let isPolling = false;
  let result: TxConfirmationResult | null = null;

  return {
    /** Start polling for confirmation */
    start: async (): Promise<TxConfirmationResult> => {
      if (isPolling) {
        throw new Error('Already polling');
      }

      abortController = new AbortController();
      isPolling = true;

      try {
        result = await waitForTxConfirmation(txHash, {
          ...options,
          signal: abortController.signal,
        });
        return result;
      } finally {
        isPolling = false;
      }
    },

    /** Stop polling */
    stop: () => {
      if (abortController) {
        abortController.abort();
        abortController = null;
      }
      isPolling = false;
    },

    /** Check if currently polling */
    isPolling: () => isPolling,

    /** Get the result if confirmed */
    getResult: () => result,
  };
}

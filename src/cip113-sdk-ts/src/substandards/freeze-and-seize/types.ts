/**
 * FES deployment parameters — provided at init time.
 *
 * These come from the DB or config after the token has been registered
 * and its blacklist infrastructure initialized.
 */

import type { HexString, TxInput } from "../../types.js";

export interface FESDeploymentParams {
  /** Admin's payment key hash (hex) */
  adminPkh: HexString;

  /** Hex-encoded asset name of the programmable token */
  assetName: HexString;

  /** Policy ID of the blacklist node NFTs (from blacklist init tx) */
  blacklistNodePolicyId: HexString;

  /** Bootstrap UTxO used to initialize the blacklist (one-shot) */
  blacklistInitTxInput: TxInput;
}

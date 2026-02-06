package org.cardanofoundation.cip113.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;

import java.util.List;
import java.util.Map;

/**
 * Response for wallet balance endpoint
 * Contains merged balances from all programmable token addresses controlled by the wallet
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WalletBalanceResponse {

    /**
     * The original wallet address provided
     */
    private String walletAddress;

    /**
     * Payment hash extracted from the wallet address
     */
    private String paymentHash;

    /**
     * Stake key hash extracted from the wallet address (may be null)
     */
    private String stakeHash;

    /**
     * Merged list of balance entries from all programmable token addresses
     * Each entry represents the latest balance for one programmable token address
     */
    private List<BalanceLogEntity> balances;

    /**
     * Map of asset unit to blacklist status
     * Key: unit (policyId + assetName hex)
     * Value: true if blacklisted/frozen, false otherwise
     * Only populated for freeze-and-seize tokens with blacklist capability
     */
    private Map<String, Boolean> blacklistStatuses;
}

package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.Tx;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.TransactionContext;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Service for checking and registering script stake addresses.
 * Script stake addresses must be registered on-chain before they can be used
 * with the "withdraw 0" trick for validator invocation.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ScriptRegistrationService {

    private final BFBackendService bfBackendService;
    private final QuickTxBuilder quickTxBuilder;
    private final AccountService accountService;

    /**
     * Check if a stake address is registered on-chain.
     *
     * @param stakeAddress The stake address to check (e.g., stake_test1...)
     * @return true if registered (active), false otherwise
     */
    public boolean isStakeAddressRegistered(String stakeAddress) {
        try {
            var accountInfo = bfBackendService.getAccountService().getAccountInformation(stakeAddress);

            if (!accountInfo.isSuccessful()) {
                log.warn("Failed to get account info for {}: {}", stakeAddress, accountInfo.getResponse());
                return false;
            }

            boolean isActive = accountInfo.getValue().getActive();
            log.info("Stake address {} is registered: {}", stakeAddress, isActive);
            return isActive;

        } catch (Exception e) {
            log.error("Error checking stake address registration for {}: {}", stakeAddress, e.getMessage());
            return false;
        }
    }

    /**
     * Build a transaction to register one or more stake addresses.
     *
     * @param stakeAddresses List of stake addresses to register
     * @param feePayerAddress The address that will pay for the transaction
     * @return Transaction context with unsigned CBOR tx
     */
    public TransactionContext<Void> buildRegisterStakeAddressTransaction(
            List<String> stakeAddresses,
            String feePayerAddress) {

        try {
            if (stakeAddresses == null || stakeAddresses.isEmpty()) {
                return TransactionContext.error("No stake addresses provided");
            }

            log.info("Building stake address registration tx for {} addresses, fee payer: {}",
                    stakeAddresses.size(), feePayerAddress);

            // Get UTxOs for fee payer
            var feePayerUtxos = accountService.findAdaOnlyUtxo(feePayerAddress, 10_000_000L);
            if (feePayerUtxos.isEmpty()) {
                return TransactionContext.error("No UTxOs found for fee payer address");
            }

            // Build the registration transaction
            var tx = new Tx()
                    .from(feePayerAddress)
                    .withChangeAddress(feePayerAddress);

            // Add each stake address to register
            for (String stakeAddress : stakeAddresses) {
                log.debug("Adding stake address to register: {}", stakeAddress);
                tx.registerStakeAddress(stakeAddress);
            }

            // Build the unsigned transaction
            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(feePayerAddress)
                    .build();

            var unsignedCborHex = transaction.serializeToHex();
            log.info("Built stake registration tx: {}", unsignedCborHex);

            return TransactionContext.ok(unsignedCborHex);

        } catch (Exception e) {
            log.error("Error building stake address registration tx: {}", e.getMessage(), e);
            return TransactionContext.error("Failed to build registration transaction: " + e.getMessage());
        }
    }
}

package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.yaci.helper.model.Transaction;
import com.bloxbean.cardano.yaci.store.common.domain.Amt;
import com.bloxbean.cardano.yaci.store.events.TransactionEvent;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.util.AmountUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.model.TransactionType;
import org.cardanofoundation.cip113.util.AddressUtil;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.util.*;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
public class BalanceEventListener {

    private final BalanceService balanceService;
    private final ProtocolParamsService protocolParamsService;
    private final UtxoRepository utxoRepository;

    @EventListener
    public void processEvent(TransactionEvent transactionEvent) {
        log.debug("Processing AddressUtxoEvent for balance indexing");

        // Get all protocol params to know all programmableLogicBaseScriptHashes
        List<ProtocolParamsEntity> allProtocolParams = protocolParamsService.getAll();
        if (allProtocolParams.isEmpty()) {
            log.debug("No protocol params loaded yet, skipping balance indexing");
            return;
        }

        // Get all programmable token base script hashes
        Set<String> progLogicScriptHashes = allProtocolParams.stream()
                .map(ProtocolParamsEntity::getProgLogicScriptHash)
                .collect(Collectors.toSet());

        log.debug("Monitoring {} programmable logic script hashes: {}",
                progLogicScriptHashes.size(), String.join(", ", progLogicScriptHashes));

        var slot = transactionEvent.getMetadata().getSlot();
        var blockHeight = transactionEvent.getMetadata().getBlock();

        // Process each transaction
        transactionEvent.getTransactions()
                .forEach(transaction -> {
                    String txHash = transaction.getTxHash();

                    // Track balance changes per address using Value objects
                    // Key: address, Value: net balance change
                    Map<String, BalanceAggregator> balanceChanges = new HashMap<>();

                    // Process inputs (subtractions) - need to look up UTxOs
                    transaction.getBody()
                            .getInputs()
                            .forEach(input -> {
                                String inputTxHash = input.getTransactionId();
                                int outputIndex = input.getIndex();

                                // Look up the UTxO
                                var utxoOpt = utxoRepository.findById(new UtxoId(inputTxHash, outputIndex));

                                if (utxoOpt.isEmpty()) {
                                    log.debug("UTxO not found for input: {}:{}", inputTxHash, outputIndex);
                                    return;
                                }

                                var utxo = utxoOpt.get();
                                String address = utxo.getOwnerAddr();

                                AddressUtil.AddressComponents components = AddressUtil.decompose(address);
                                if (components != null && progLogicScriptHashes.contains(components.getPaymentScriptHash())) {
                                    // Convert UTxO amounts to Value and subtract
                                    Value inputValue = amountsToValue(utxo.getAmounts());

                                    BalanceAggregator aggregator = balanceChanges.computeIfAbsent(address,
                                            k -> new BalanceAggregator(address, components));
                                    aggregator.subtractInput(inputValue);
                                }
                            });

                    // Process outputs (additions)
                    transaction.getBody()
                            .getOutputs()
                            .forEach(output -> {
                                String address = output.getAddress();

                                AddressUtil.AddressComponents components = AddressUtil.decompose(address);
                                if (components != null && progLogicScriptHashes.contains(components.getPaymentScriptHash())) {
                                    // Convert output amounts to Value and add
                                    var outputValue = output.getAmounts()
                                            .stream()
                                            .map(AmountUtil::toValue)
                                            .reduce(Value::add)
                                            .orElse(Value.builder().build());

                                    BalanceAggregator aggregator = balanceChanges.computeIfAbsent(address,
                                            k -> new BalanceAggregator(address, components));
                                    aggregator.addOutput(outputValue);
                                }
                            });

                    // Save balance changes to database
                    balanceChanges.forEach((address, aggregator) -> {

                        var netChange = aggregator.getNetChange();
                        // Get previous balance
                        Value previousBalance = balanceService.getCurrentBalanceAsValue(address);

                        // Calculate new balance: previous + outputs - inputs
                        Value newBalance = previousBalance.add(netChange);

                        // Calculate signed balance difference
                        Map<String, String> balanceDiff = calculateSignedDiff(aggregator.getNetChange());

                        TransactionType transactionType = detectTransactionType(netChange, transaction);

                        // Convert new balance to map for service method
                        Map<String, BigInteger> balanceMap = BalanceValueHelper.toMap(newBalance);

                        // Save using new service method with transaction type and diff
                        balanceService.append(
                                address,
                                txHash,
                                slot,
                                blockHeight,
                                balanceMap,
                                transactionType,
                                balanceDiff
                        );

                        log.info("Recorded balance change: address={}, tx={}, type={}, new_balance={}",
                                address, txHash, transactionType, BalanceValueHelper.toJson(newBalance));
                    });
                });
    }

    /**
     * Convert list of Amt to Value object
     */
    private Value amountsToValue(List<Amt> amounts) {
        return amounts.stream().map(AmountUtil::toValue).reduce(Value.builder().build(), Value::add);
    }

    /**
     * Calculate signed balance difference from net change
     * Converts Value to map with signed string amounts ("+1000", "-50")
     *
     * @param netChange the net balance change (outputs - inputs)
     * @return map of unit to signed amount string
     */
    private Map<String, String> calculateSignedDiff(Value netChange) {
        Map<String, String> signedDiff = new LinkedHashMap<>();

        // Convert Value to unit map
        Map<String, String> unitMap = BalanceValueHelper.toUnitMap(netChange);

        // Add sign prefix to each amount
        unitMap.forEach((unit, amountStr) -> {
            BigInteger amount = new BigInteger(amountStr);
            String signedAmount;

            if (amount.compareTo(BigInteger.ZERO) > 0) {
                signedAmount = "+" + amountStr;
            } else if (amount.compareTo(BigInteger.ZERO) < 0) {
                signedAmount = amountStr; // Already has minus sign
            } else {
                signedAmount = "0"; // No change
            }

            signedDiff.put(unit, signedAmount);
        });

        return signedDiff;
    }

    /**
     * Detect transaction type based on balance changes and transaction data
     * <p>
     * TODO: Implement transaction type detection logic
     * <p>
     * Detection should be based on:
     * 1. Balance changes (positive = mint/receive, negative = burn/send)
     * 2. Input/output analysis
     * - If outputs > inputs: MINT (new tokens created)
     * - If outputs < inputs: BURN (tokens destroyed)
     * - If outputs == inputs: TRANSFER (tokens moved)
     * 3. Registry lookups for REGISTER operations
     * - Check if transaction registers a new token policy in the registry
     * 4. Mint field in transaction body
     * - Presence of mint field indicates MINT or BURN operation
     *
     * @param netChange   the net change (outputs - inputs)
     * @param transaction the transaction data
     * @return the detected transaction type (currently returns null)
     */
    private TransactionType detectTransactionType(Value netChange, Transaction transaction) {

        var netChangePolicies = netChange.getMultiAssets().stream().map(MultiAsset::getPolicyId).toList();

        var mintDetails = transaction.getBody()
                .getMint()
                .stream()
                .filter(amount -> netChangePolicies.contains(amount.getPolicyId()))
                .toList();

        if (mintDetails.isEmpty()) {
            return TransactionType.TRANSFER;
        } else {
            var mintAmount = mintDetails.getFirst().getQuantity();
            if (mintAmount.compareTo(BigInteger.ZERO) > 0) {
                return TransactionType.MINT;
            } else {
                return TransactionType.BURN;
            }
        }
    }

    /**
     * Helper class to aggregate balance changes per address
     */
    private static class BalanceAggregator {
        private final String address;
        private final AddressUtil.AddressComponents components;
        private Value netChange;

        BalanceAggregator(String address, AddressUtil.AddressComponents components) {
            this.address = address;
            this.components = components;
            this.netChange = BalanceValueHelper.empty();
        }

        void addOutput(Value value) {
            netChange = netChange.add(value);
        }

        void subtractInput(Value value) {
            netChange = netChange.subtract(value);
        }

        Value getNetChange() {
            return netChange;
        }

        AddressUtil.AddressComponents getComponents() {
            return components;
        }
    }
}

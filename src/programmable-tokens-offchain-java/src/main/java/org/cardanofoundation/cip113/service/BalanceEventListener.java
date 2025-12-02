package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.yaci.store.common.domain.Amt;
import com.bloxbean.cardano.yaci.store.utxo.domain.AddressUtxoEvent;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.util.AmountUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.util.AddressUtil;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Event listener for tracking programmable token balances at script addresses.
 *
 * <p>This listener processes blockchain events from Yaci Store to track balance changes
 * for addresses holding CIP-0113 programmable tokens. It specifically monitors the
 * programmable logic base script address where all programmable tokens are held.</p>
 *
 * <h2>Event Processing</h2>
 * <p>When a new block is processed by Yaci Store, this listener:</p>
 * <ol>
 *   <li>Identifies UTxOs at known programmable logic addresses</li>
 *   <li>Extracts owner credentials from datum</li>
 *   <li>Computes current balance from all UTxOs for that owner</li>
 *   <li>Appends a balance log entry for audit trail</li>
 * </ol>
 *
 * <h2>Balance Computation</h2>
 * <p>Balances are computed by aggregating all UTxOs at the programmable address
 * that belong to the same owner (determined by datum content). This provides
 * accurate "effective balance" even though tokens are at a shared script address.</p>
 *
 * @see BalanceService
 * @see AddressUtxoEvent
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class BalanceEventListener {

    private final BalanceService balanceService;
    private final ProtocolParamsService protocolParamsService;
    private final UtxoRepository utxoRepository;

    @EventListener
    public void processEvent(AddressUtxoEvent addressUtxoEvent) {
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

        var slot = addressUtxoEvent.getEventMetadata().getSlot();
        var blockHeight = addressUtxoEvent.getEventMetadata().getBlock();

        // Process each transaction
        addressUtxoEvent.getTxInputOutputs()
                .forEach(txInputOutputs -> {
                    String txHash = txInputOutputs.getTxHash();

                    // Track balance changes per address using Value objects
                    // Key: address, Value: net balance change
                    Map<String, BalanceAggregator> balanceChanges = new HashMap<>();

                    // Process inputs (subtractions) - need to look up UTxOs
                    txInputOutputs.getInputs().forEach(input -> {
                        String inputTxHash = input.getTxHash();
                        int outputIndex = input.getOutputIndex();

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
                    txInputOutputs.getOutputs().forEach(output -> {
                        String address = output.getOwnerAddr();

                        AddressUtil.AddressComponents components = AddressUtil.decompose(address);
                        if (components != null && progLogicScriptHashes.contains(components.getPaymentScriptHash())) {
                            // Convert output amounts to Value and add
                            Value outputValue = amountsToValue(output.getAmounts());

                            BalanceAggregator aggregator = balanceChanges.computeIfAbsent(address,
                                    k -> new BalanceAggregator(address, components));
                            aggregator.addOutput(outputValue);
                        }
                    });

                    // Save balance changes to database
                    balanceChanges.forEach((address, aggregator) -> {
                        // Get previous balance
                        Value previousBalance = balanceService.getCurrentBalanceAsValue(address);

                        // Calculate new balance: previous + outputs - inputs
                        Value newBalance = previousBalance.plus(aggregator.getNetChange());

                        // Convert to JSON
                        String balanceJson = BalanceValueHelper.toJson(newBalance);

                        // Create balance log entry
                        BalanceLogEntity entity = BalanceLogEntity.builder()
                                .address(address)
                                .paymentScriptHash(aggregator.getComponents().getPaymentScriptHash())
                                .stakeKeyHash(aggregator.getComponents().getStakeKeyHash())
                                .txHash(txHash)
                                .slot(slot)
                                .blockHeight(blockHeight)
                                .balance(balanceJson)
                                .build();

                        balanceService.append(entity);

                        log.info("Recorded balance change: address={}, tx={}, new_balance={}",
                                address, txHash, balanceJson);
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

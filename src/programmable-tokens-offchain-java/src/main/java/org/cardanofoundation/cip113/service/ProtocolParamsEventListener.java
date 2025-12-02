package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.yaci.store.utxo.domain.AddressUtxoEvent;
import com.easy1staking.cardano.model.AssetType;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.model.onchain.ProtocolParamsParser;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

/**
 * Event listener for detecting and indexing CIP-0113 protocol parameter deployments.
 *
 * <p>This listener monitors the blockchain for protocol parameter NFT transactions
 * to detect new CIP-0113 protocol deployments. Protocol parameters are the root
 * configuration that defines all script hashes and policy IDs for a deployment.</p>
 *
 * <h2>Detection Mechanism</h2>
 * <p>Protocol parameters are identified by:</p>
 * <ul>
 *   <li>Matching against configured transaction IDs (from protocolBootstrap.json)</li>
 *   <li>Presence of a "ProtocolParams" token in the UTxO</li>
 *   <li>Valid inline datum containing ProgrammableLogicGlobalParams</li>
 * </ul>
 *
 * <h2>Indexed Data</h2>
 * <p>When a protocol params UTxO is found, the following are extracted:</p>
 * <ul>
 *   <li>Registry node policy ID - for tracking registered tokens</li>
 *   <li>Programmable logic script hashes - base and global validators</li>
 *   <li>Blacklist node policy ID - for sanction list management</li>
 *   <li>Transaction metadata (slot, block, tx hash)</li>
 * </ul>
 *
 * @see ProtocolParamsService
 * @see ProtocolParamsParser
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class ProtocolParamsEventListener {

    private final ProtocolParamsService protocolParamsService;
    private final ProtocolParamsParser protocolParamsParser;
    private final AppConfig.ProtocolParamsConfig protocolParamsConfig;

    @EventListener
    @Transactional
    public void processEvent(AddressUtxoEvent addressUtxoEvent) {
        log.debug("Processing AddressUtxoEvent with {} transactions", addressUtxoEvent.getTxInputOutputs().size());

        var slot = addressUtxoEvent.getEventMetadata().getSlot();
        var blockHeight = addressUtxoEvent.getEventMetadata().getBlock();

        addressUtxoEvent.getTxInputOutputs()
                .stream()
                .filter(txInputOutput -> protocolParamsConfig.getTransactionIds().contains(txInputOutput.getTxHash()))
                .flatMap(txInputOutputs -> txInputOutputs.getOutputs().stream())
                .filter(addressUtxo -> addressUtxo.getInlineDatum() != null && addressUtxo.getAmounts()
                        .stream().anyMatch(amt -> "ProtocolParams".equals(AssetType.fromUnit(amt.getUnit()).unsafeHumanAssetName())))
                .forEach(addressUtxo -> {

                    var txHash = addressUtxo.getTxHash();

                    log.info("Found protocol params transaction: txHash={}, slot={}", txHash, slot);

                    // Parse inline datum
                    protocolParamsParser.parse(addressUtxo.getInlineDatum())
                            .ifPresentOrElse(protocolParams -> {
                                        // Create entity and save
                                        ProtocolParamsEntity entity = ProtocolParamsEntity.builder()
                                                .registryNodePolicyId(protocolParams.registryNodePolicyId())
                                                .progLogicScriptHash(protocolParams.programmableLogicBaseScriptHash())
                                                .txHash(addressUtxo.getTxHash())
                                                .slot(slot)
                                                .blockHeight(blockHeight)
                                                .build();

                                        protocolParamsService.save(entity);
                                        log.info("Successfully saved protocol params from txHash={}", txHash);
                                    },
                                    () -> log.error("Failed to parse protocol params from txHash={}", txHash)
                            );
                });
    }
}

package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.yaci.store.utxo.domain.AddressUtxoEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.model.onchain.ProtocolParamsParser;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProtocolParamsEventListener {

    private final ProtocolParamsService protocolParamsService;
    private final ProtocolParamsParser protocolParamsParser;
    private final AppConfig.ProtocolParamsConfig protocolParamsConfig;

    @EventListener
    public void processEvent(AddressUtxoEvent addressUtxoEvent) {
        log.info("Processing AddressUtxoEvent with {} transactions", addressUtxoEvent.getTxInputOutputs().size());

        var txIds = String.join(",", protocolParamsConfig.getTransactionIds());

        log.info("txIds: {}", txIds);

        var slot = addressUtxoEvent.getEventMetadata().getSlot();
        var blockHeight = addressUtxoEvent.getEventMetadata().getBlock();

        addressUtxoEvent.getTxInputOutputs()
                .stream()
                .filter(txInputOutput -> {
                    log.info("tx: {}", txInputOutput.getTxHash());
                    return protocolParamsConfig.getTransactionIds().contains(txInputOutput.getTxHash());
                })
                .flatMap(txInputOutputs -> txInputOutputs.getOutputs().stream())
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

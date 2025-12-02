package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.yaci.store.utxo.domain.AddressUtxoEvent;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Event listener for synchronizing the programmable token registry from blockchain.
 *
 * <p>This listener processes blockchain events to maintain a local copy of the
 * CIP-0113 token registry. The registry is a sorted linked list of registered
 * programmable tokens stored on-chain as UTxOs with NFT markers.</p>
 *
 * <h2>Registry Structure</h2>
 * <p>Each registry node UTxO contains:</p>
 * <ul>
 *   <li>An NFT with the registry policy ID marking ownership</li>
 *   <li>A datum containing the token's policy ID (key) and next pointer</li>
 *   <li>Configuration for the token's transfer logic</li>
 * </ul>
 *
 * <h2>Synchronization Process</h2>
 * <p>When UTxO events are received:</p>
 * <ol>
 *   <li>Filter for UTxOs containing registry node NFTs</li>
 *   <li>Parse the registry node datum using CBOR decoder</li>
 *   <li>Upsert the node into local database (handles inserts and updates)</li>
 * </ol>
 *
 * @see RegistryService
 * @see RegistryNodeParser
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class RegistryEventListener {

    private final RegistryService registryService;
    private final RegistryNodeParser registryNodeParser;
    private final ProtocolParamsService protocolParamsService;

    @EventListener
    public void processEvent(AddressUtxoEvent addressUtxoEvent) {
        log.debug("Processing AddressUtxoEvent for registry nodes");

        // Get all protocol params to know all registryNodePolicyIds
        List<ProtocolParamsEntity> allProtocolParams = protocolParamsService.getAll();
        if (allProtocolParams.isEmpty()) {
            log.debug("No protocol params loaded yet, skipping registry indexing");
            return;
        }

        // Create map of registryNodePolicyId -> ProtocolParamsEntity for quick lookup
        Map<String, ProtocolParamsEntity> policyIdToProtocolParams = allProtocolParams.stream()
                .collect(Collectors.toMap(
                        ProtocolParamsEntity::getRegistryNodePolicyId,
                        pp -> pp,
                        (existing, replacement) -> existing // Keep first if duplicates
                ));

        var directoryNfts = policyIdToProtocolParams.keySet().stream().map(AssetType::fromUnit).map(AssetType::policyId).toList();

        log.debug("Monitoring {} registry policy IDs: {}",
                policyIdToProtocolParams.size(),
                String.join(", ", policyIdToProtocolParams.keySet()));

        var slot = addressUtxoEvent.getEventMetadata().getSlot();
        var blockHeight = addressUtxoEvent.getEventMetadata().getBlock();

        // Process each transaction's outputs
        addressUtxoEvent.getTxInputOutputs()
                .stream()
                .flatMap(txInputOutputs -> txInputOutputs.getOutputs().stream())
                .flatMap(output -> {
                    if (output.getInlineDatum() != null) {
                        return output.getAmounts()
                                .stream()
                                .filter(amt -> amt.getQuantity().equals(BigInteger.ONE) && directoryNfts.contains(AssetType.fromUnit(amt.getUnit()).policyId()))
                                .map(amt -> new Pair<>(output, amt))
                                .findAny()
                                .stream();
                    } else {
                        return Stream.empty();
                    }
                })
                .forEach(pair -> {
                    var output = pair.first();
                    var amt = AssetType.fromUnit(pair.second().getUnit());
                    String txHash = output.getTxHash();

                    var protocolParams = policyIdToProtocolParams.get(amt.policyId());

                    log.info("Found registry node UTxO: txHash={}, slot={}, protocolParamsId={}",
                            txHash, slot, protocolParams.getId());

                    // Parse inline datum to RegistryNode
                    registryNodeParser.parse(output.getInlineDatum())
                            .ifPresentOrElse(registryNode -> {

                                        log.info("registryNode: {}", registryNode);

                                        // Skip sentinel/head node (key = "")
                                        if (registryNode.key().isEmpty()) {
                                            log.info("Skipping sentinel node (key is empty)");
                                            return;
                                        }

                                        // Create entity
                                        RegistryNodeEntity entity = RegistryNodeEntity.builder()
                                                .key(registryNode.key())
                                                .next(registryNode.next())
                                                .transferLogicScript(registryNode.transferLogicScript())
                                                .thirdPartyTransferLogicScript(registryNode.thirdPartyTransferLogicScript())
                                                .globalStatePolicyId(registryNode.globalStatePolicyId())
                                                .protocolParams(protocolParams)
                                                .lastTxHash(txHash)
                                                .lastSlot(slot)
                                                .lastBlockHeight(blockHeight)
                                                .build();

                                        // Upsert to database
                                        registryService.upsert(entity);
                                        log.info("Successfully upserted registry node: key={}, next={}, tx={}", registryNode.key(), registryNode.next(), txHash);
                                    },
                                    () -> log.error("Failed to parse registry node from txHash={}", txHash)
                            );
                });
    }
}

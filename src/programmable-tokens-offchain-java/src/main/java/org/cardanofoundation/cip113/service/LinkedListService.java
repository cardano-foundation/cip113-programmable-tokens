package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.api.model.Utxo;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.LinkedListNode;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.function.Function;

@Service
@RequiredArgsConstructor
@Slf4j
public class LinkedListService {

    private final UtxoProvider utxoProvider;

    public boolean nodeAlreadyPresent(String progTokenPolicyId, String linkedListAddress, Function<Utxo, Optional<String>> datumToKeyParse) {
        return this.nodeAlreadyPresent(progTokenPolicyId, utxoProvider.findUtxos(linkedListAddress), datumToKeyParse);
    }

    public boolean nodeAlreadyPresent(String progTokenPolicyId, List<Utxo> linkedListNodes, Function<Utxo, Optional<String>> datumToKeyParse) {
        return linkedListNodes
                .stream()
                .anyMatch(addressUtxoEntity -> datumToKeyParse.apply(addressUtxoEntity)
                        .map(key -> key.equals(progTokenPolicyId))
                        .orElse(false)
                );
    }

    public Optional<Utxo> findNodeToReplace(String progTokenPolicyId, String linkedListNodes, Function<Utxo, Optional<LinkedListNode>> datumToNode) {
        return this.findNodeToReplace(progTokenPolicyId, utxoProvider.findUtxos(linkedListNodes), datumToNode);
    }


    public Optional<Utxo> findNodeToReplace(String progTokenPolicyId, List<Utxo> linkedListNodes, Function<Utxo, Optional<LinkedListNode>> datumToNode) {
        return linkedListNodes.stream()
                .filter(utxo -> datumToNode.apply(utxo)
                        .map(node -> node.key().compareTo(progTokenPolicyId) < 0 &&
                                progTokenPolicyId.compareTo(node.next()) < 0)
                        .orElse(false))
                .findAny();
    }

}

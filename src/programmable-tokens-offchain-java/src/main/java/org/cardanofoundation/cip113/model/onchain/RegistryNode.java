package org.cardanofoundation.cip113.model.onchain;

import lombok.Builder;

@Builder(toBuilder = true)
public record RegistryNode(String key,
                           String next,
                           String transferLogicScript,
                           String thirdPartyTransferLogicScript,
                           String globalStatePolicyId) {


}

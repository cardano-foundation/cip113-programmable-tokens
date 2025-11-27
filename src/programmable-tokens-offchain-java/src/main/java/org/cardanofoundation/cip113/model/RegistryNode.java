package org.cardanofoundation.cip113.model;

import org.cardanofoundation.cip113.entity.RegistryNodeEntity;

public record RegistryNode(String key,
                           String next,
                           String transferLogicScript,
                           String thirdPartyTransferLogicScript,
                           String globalStatePolicyId) {

    public static RegistryNode from(RegistryNodeEntity registryNodeEntity) {
        return new RegistryNode(registryNodeEntity.getKey(),
                registryNodeEntity.getNext(),
                registryNodeEntity.getTransferLogicScript(),
                registryNodeEntity.getThirdPartyTransferLogicScript(),
                registryNodeEntity.getGlobalStatePolicyId());
    }

}

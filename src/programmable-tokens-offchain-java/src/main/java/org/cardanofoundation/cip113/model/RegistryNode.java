package org.cardanofoundation.cip113.model;

import org.cardanofoundation.cip113.entity.RegistryNodeEntity;

/**
 * DTO representing a registry node in the sorted linked list.
 *
 * <p>Maps from the JPA entity to an API-friendly format. Contains
 * the token identifier (key), pointer to the next node, and associated
 * script references for transfer logic.</p>
 *
 * @param key                         unique token identifier (policy ID + asset name hash)
 * @param next                        key of the next node in sorted order
 * @param transferLogicScript         script hash for owner-initiated transfers
 * @param thirdPartyTransferLogicScript script hash for third-party transfers
 * @param globalStatePolicyId         policy ID for global state management
 */
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

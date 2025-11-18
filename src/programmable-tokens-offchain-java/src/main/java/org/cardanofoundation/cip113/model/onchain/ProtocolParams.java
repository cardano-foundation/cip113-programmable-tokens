package org.cardanofoundation.cip113.model.onchain;

import lombok.Builder;

@Builder(toBuilder = true)
public record ProtocolParams(String registryNodePolicyId, String programmableLogicBaseScriptHash) {


}

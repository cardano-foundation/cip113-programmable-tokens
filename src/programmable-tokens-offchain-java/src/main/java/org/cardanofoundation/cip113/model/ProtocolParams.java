package org.cardanofoundation.cip113.model;

/**
 * DTO representing CIP-113 protocol parameters.
 *
 * <p>Contains the essential script references needed for token operations.
 * These parameters are set during protocol bootstrap and define the
 * on-chain infrastructure for programmable tokens.</p>
 *
 * @param registryNodePolicyId              policy ID for minting registry node NFTs
 * @param programmableLogicBaseScriptHash   script hash of the base programmable logic validator
 */
public record ProtocolParams(String registryNodePolicyId, String programmableLogicBaseScriptHash) {
}

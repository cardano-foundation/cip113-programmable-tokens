package org.cardanofoundation.cip113.model;

/**
 * Request to register a token in the backend DB after SDK-built on-chain registration.
 * This is a DB-only callback — no transaction building.
 */
public record TokenRegistrationRequest(
        /** Policy ID of the programmable token */
        String policyId,
        /** Substandard identifier (e.g., "dummy", "freeze-and-seize") */
        String substandardId,
        /** Hex-encoded asset name */
        String assetName,
        /** Issuer admin PKH (FES only, nullable) */
        String issuerAdminPkh,
        /** Blacklist node policy ID (FES only, nullable) */
        String blacklistNodePolicyId
) {}

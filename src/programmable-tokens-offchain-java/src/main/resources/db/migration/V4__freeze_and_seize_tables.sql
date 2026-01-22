-- ============================================================================
-- Programmable Token Registry (Unified - All Substandards)
-- ============================================================================

-- Unified registry mapping policy IDs to their substandard
-- All substandards insert here during token registration
CREATE TABLE programmable_token_registry (
    policy_id VARCHAR(56) PRIMARY KEY,
    substandard_id VARCHAR(50) NOT NULL
);

COMMENT ON TABLE programmable_token_registry IS 'Unified registry mapping programmable token policy IDs to their substandard';
COMMENT ON COLUMN programmable_token_registry.policy_id IS 'Policy ID of the programmable token (primary key)';
COMMENT ON COLUMN programmable_token_registry.substandard_id IS 'Substandard identifier (e.g., dummy, freeze-and-seize)';

-- ============================================================================
-- Freeze-and-Seize Substandard Tables
-- ============================================================================

-- Create table to store freeze-and-seize blacklist initialization data
-- This is used to build the FreezeAndSeizeContext for compliance operations
CREATE TABLE freeze_and_seize_blacklist_init (
    blacklist_node_policy_id VARCHAR(56) PRIMARY KEY,
    admin_pkh VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL,
    output_index INTEGER NOT NULL,
    CONSTRAINT uk_admin_tx_output UNIQUE (admin_pkh, tx_hash, output_index)
);

COMMENT ON TABLE freeze_and_seize_blacklist_init IS 'Stores freeze-and-seize substandard blacklist initialization data for building context';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.blacklist_node_policy_id IS 'Policy ID of the blacklist node NFTs (primary key)';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.admin_pkh IS 'Public key hash of the admin who manages this blacklist';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.tx_hash IS 'Transaction hash where the blacklist was initialized';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.output_index IS 'Output index of the blacklist init UTxO';

-- Create table to store freeze-and-seize token registration data
CREATE TABLE freeze_and_seize_token_registration (
    programmable_token_policy_id VARCHAR(56) PRIMARY KEY,
    issuer_admin_pkh VARCHAR(56) NOT NULL,
    blacklist_node_policy_id VARCHAR(56) NOT NULL,
    CONSTRAINT fk_blacklist_init FOREIGN KEY (blacklist_node_policy_id)
        REFERENCES freeze_and_seize_blacklist_init(blacklist_node_policy_id)
);

COMMENT ON TABLE freeze_and_seize_token_registration IS 'Stores freeze-and-seize token registration data linking tokens to their blacklist';
COMMENT ON COLUMN freeze_and_seize_token_registration.programmable_token_policy_id IS 'Policy ID of the programmable token (primary key)';
COMMENT ON COLUMN freeze_and_seize_token_registration.issuer_admin_pkh IS 'Public key hash of the issuer admin';
COMMENT ON COLUMN freeze_and_seize_token_registration.blacklist_node_policy_id IS 'Foreign key to the blacklist init record';

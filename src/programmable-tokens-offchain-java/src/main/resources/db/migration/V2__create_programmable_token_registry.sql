-- ============================================================================
-- Programmable Token Registry (Unified - All Substandards)
-- ============================================================================

-- Unified registry mapping policy IDs to their substandard
-- All substandards insert here during token registration
CREATE TABLE programmable_token_registry (
    policy_id VARCHAR(56) PRIMARY KEY,
    substandard_id VARCHAR(50) NOT NULL,
    asset_name VARCHAR(64) NOT NULL
);

COMMENT ON TABLE programmable_token_registry IS 'Unified registry mapping programmable token policy IDs to their substandard';
COMMENT ON COLUMN programmable_token_registry.policy_id IS 'Policy ID of the programmable token (primary key)';
COMMENT ON COLUMN programmable_token_registry.substandard_id IS 'Substandard identifier (e.g., dummy, freeze-and-seize)';
COMMENT ON COLUMN programmable_token_registry.asset_name IS 'Hex-encoded asset name of the programmable token';

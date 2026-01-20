-- Create table to store freeze-and-seize blacklist initialization data
-- This is used to build the FreezeAndSeizeContext for compliance operations
CREATE TABLE freeze_and_seize_blacklist_init (
    blacklist_node_policy_id VARCHAR(56) PRIMARY KEY,
    admin_pkh VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL,
    output_index INTEGER NOT NULL,
    CONSTRAINT uk_admin_tx_output UNIQUE (admin_pkh, tx_hash, output_index)
);

-- Add comments
COMMENT ON TABLE freeze_and_seize_blacklist_init IS 'Stores freeze-and-seize substandard blacklist initialization data for building context';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.blacklist_node_policy_id IS 'Policy ID of the blacklist node NFTs (primary key)';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.admin_pkh IS 'Public key hash of the admin who manages this blacklist';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.tx_hash IS 'Transaction hash where the blacklist was initialized';
COMMENT ON COLUMN freeze_and_seize_blacklist_init.output_index IS 'Output index of the blacklist init UTxO';

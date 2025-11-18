-- Create protocol_params table to store versioned protocol parameters
CREATE TABLE protocol_params (
    id BIGSERIAL PRIMARY KEY,
    registry_node_policy_id VARCHAR(56) NOT NULL,
    prog_logic_script_hash VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL UNIQUE,
    slot BIGINT NOT NULL,
    block_height BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    CONSTRAINT uk_tx_hash UNIQUE (tx_hash)
);

-- Create indexes for efficient querying
CREATE INDEX idx_tx_hash ON protocol_params(tx_hash);
CREATE INDEX idx_slot ON protocol_params(slot);

-- Add comment to table
COMMENT ON TABLE protocol_params IS 'Stores versioned protocol parameters from the Cardano blockchain';
COMMENT ON COLUMN protocol_params.registry_node_policy_id IS 'Currency symbol (PolicyId) of the registry node NFTs';
COMMENT ON COLUMN protocol_params.prog_logic_script_hash IS 'The programmable logic base credential script hash';
COMMENT ON COLUMN protocol_params.tx_hash IS 'Transaction hash where this version was published';
COMMENT ON COLUMN protocol_params.slot IS 'Cardano slot number (time indicator)';
COMMENT ON COLUMN protocol_params.block_height IS 'Block height where this version was published';

-- Create registry_node table to store programmable token directory/registry
CREATE TABLE registry_node (
    id BIGSERIAL PRIMARY KEY,

    -- Token Policy ID (lexicographic ordering key)
    key VARCHAR(64) NOT NULL UNIQUE,

    -- Linked list structure - next pointer
    next VARCHAR(64) NOT NULL,

    -- Token configuration
    transfer_logic_script VARCHAR(56) NOT NULL,
    third_party_transfer_logic_script VARCHAR(56) NOT NULL,
    global_state_policy_id VARCHAR(56),

    -- Foreign key to protocol params (which registry this belongs to)
    protocol_params_id BIGINT NOT NULL,

    -- Last modification tracking
    last_tx_hash VARCHAR(64) NOT NULL,
    last_slot BIGINT NOT NULL,
    last_block_height BIGINT NOT NULL,

    -- Timestamps
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,

    -- Foreign key constraint
    CONSTRAINT fk_registry_protocol_params FOREIGN KEY (protocol_params_id)
        REFERENCES protocol_params(id) ON DELETE CASCADE
);

-- Create indexes for efficient querying
CREATE INDEX idx_registry_key ON registry_node(key);
CREATE INDEX idx_registry_next ON registry_node(next);
CREATE INDEX idx_registry_protocol_params ON registry_node(protocol_params_id);
CREATE INDEX idx_registry_last_slot ON registry_node(last_slot);

-- Add comments to table
COMMENT ON TABLE registry_node IS 'Stores programmable token registry nodes (directory) as a linked list structure';
COMMENT ON COLUMN registry_node.key IS 'Token policy ID (empty string for sentinel/head node)';
COMMENT ON COLUMN registry_node.next IS 'Pointer to next node in lexicographic order';
COMMENT ON COLUMN registry_node.transfer_logic_script IS 'Script hash for transfer validation';
COMMENT ON COLUMN registry_node.third_party_transfer_logic_script IS 'Script hash for third-party transfer validation';
COMMENT ON COLUMN registry_node.global_state_policy_id IS 'Global state currency symbol';
COMMENT ON COLUMN registry_node.protocol_params_id IS 'Which protocol params version this registry belongs to';
COMMENT ON COLUMN registry_node.last_tx_hash IS 'Transaction hash of last modification';
COMMENT ON COLUMN registry_node.last_slot IS 'Slot of last modification';

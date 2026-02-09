-- Create registry_node table as an immutable append-only log
-- This table stores the history of all registry node states (directory) representing
-- a linked list structure that evolves over time.
--
-- Design: Append-only log prevents race conditions during bulk block processing
-- and aligns with blockchain's immutable nature.
CREATE TABLE registry_node (
    id BIGSERIAL PRIMARY KEY,

    -- Token Policy ID (lexicographic ordering key)
    -- NOTE: In the rare edge case where multiple transactions in the same slot modify
    -- the same key, we won't know which one is "latest" within that slot.
    -- This is unlikely in practice. The composite unique constraint (key, slot, tx_hash)
    -- prevents race conditions during bulk processing.
    key VARCHAR(64) NOT NULL,

    -- Linked list structure - next pointer
    next VARCHAR(64) NOT NULL,

    -- Token configuration
    transfer_logic_script VARCHAR(56) NOT NULL,
    third_party_transfer_logic_script VARCHAR(56) NOT NULL,
    global_state_policy_id VARCHAR(56),

    -- Foreign key to protocol params (which registry this belongs to)
    protocol_params_id BIGINT NOT NULL,

    -- Transaction/block information where this state was created
    tx_hash VARCHAR(64) NOT NULL,
    slot BIGINT NOT NULL,
    block_height BIGINT NOT NULL,

    -- Whether this UTxO was spent/burned (node removed from linked list)
    is_deleted BOOLEAN NOT NULL DEFAULT false,

    -- Timestamps
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,

    -- Composite unique constraint to prevent duplicates while allowing multiple states
    CONSTRAINT uq_registry_key_slot_tx UNIQUE (key, slot, tx_hash),

    -- Foreign key constraint
    CONSTRAINT fk_registry_protocol_params FOREIGN KEY (protocol_params_id)
        REFERENCES protocol_params(id) ON DELETE CASCADE
);

-- Create indexes for efficient log-based querying
-- Queries use DISTINCT ON (key) with ORDER BY key, slot DESC, block_height DESC to get latest state
CREATE INDEX idx_registry_key ON registry_node(key);
CREATE INDEX idx_registry_next ON registry_node(next);
CREATE INDEX idx_registry_protocol_params ON registry_node(protocol_params_id);
CREATE INDEX idx_registry_slot ON registry_node(slot);
CREATE INDEX idx_registry_is_deleted ON registry_node(is_deleted);
CREATE INDEX idx_registry_key_slot_deleted ON registry_node(key, slot DESC, is_deleted);

-- Add comments to table
COMMENT ON TABLE registry_node IS 'Immutable append-only log of registry node states (directory) representing linked list structure over time';
COMMENT ON COLUMN registry_node.key IS 'Token policy ID (empty string for sentinel/head node)';
COMMENT ON COLUMN registry_node.next IS 'Pointer to next node in lexicographic order';
COMMENT ON COLUMN registry_node.transfer_logic_script IS 'Script hash for transfer validation';
COMMENT ON COLUMN registry_node.third_party_transfer_logic_script IS 'Script hash for third-party transfer validation';
COMMENT ON COLUMN registry_node.global_state_policy_id IS 'Global state currency symbol';
COMMENT ON COLUMN registry_node.protocol_params_id IS 'Which protocol params version this registry belongs to';
COMMENT ON COLUMN registry_node.tx_hash IS 'Transaction hash where this state was created';
COMMENT ON COLUMN registry_node.slot IS 'Slot where this state was created';
COMMENT ON COLUMN registry_node.block_height IS 'Block height where this state was created';
COMMENT ON COLUMN registry_node.is_deleted IS 'Whether this UTxO was spent/burned (node removed from linked list)';

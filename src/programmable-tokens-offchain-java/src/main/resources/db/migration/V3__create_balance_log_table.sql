-- Create balance_log table to store balance history for programmable token addresses
CREATE TABLE balance_log (
    id BIGSERIAL PRIMARY KEY,

    -- Address Information
    address VARCHAR(200) NOT NULL,
    payment_script_hash VARCHAR(56) NOT NULL,
    stake_key_hash VARCHAR(56),

    -- Transaction Context
    tx_hash VARCHAR(64) NOT NULL,
    slot BIGINT NOT NULL,
    block_height BIGINT NOT NULL,

    -- Balance State (after this transaction) - JSON format: {"lovelace": "1000000", "unit": "amount"}
    balance TEXT NOT NULL,

    created_at TIMESTAMP NOT NULL,

    -- Unique constraint: one entry per address/tx
    CONSTRAINT unique_balance_entry UNIQUE(address, tx_hash)
);

-- Create indexes for efficient querying
CREATE INDEX idx_balance_address ON balance_log(address);
CREATE INDEX idx_balance_payment_script ON balance_log(payment_script_hash);
CREATE INDEX idx_balance_stake_key ON balance_log(stake_key_hash);
CREATE INDEX idx_balance_payment_stake ON balance_log(payment_script_hash, stake_key_hash);
CREATE INDEX idx_balance_tx_hash ON balance_log(tx_hash);
CREATE INDEX idx_balance_slot ON balance_log(slot);

-- Add comments to table
COMMENT ON TABLE balance_log IS 'Append-only log of full balance snapshots for programmable token addresses';
COMMENT ON COLUMN balance_log.address IS 'Full bech32 address';
COMMENT ON COLUMN balance_log.payment_script_hash IS 'Payment credential hash (must match programmable token base script)';
COMMENT ON COLUMN balance_log.stake_key_hash IS 'Optional stake credential hash';
COMMENT ON COLUMN balance_log.tx_hash IS 'Transaction hash that caused this balance change';
COMMENT ON COLUMN balance_log.slot IS 'Cardano slot number';
COMMENT ON COLUMN balance_log.balance IS 'Complete balance as JSON map: {"lovelace": "1000000", "policyId+assetName": "amount"}';

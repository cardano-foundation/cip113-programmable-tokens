-- Create enum type for transaction types
--- CREATE TYPE transaction_type AS ENUM ('MINT', 'BURN', 'TRANSFER', 'REGISTER');

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

    -- Transaction Type and Balance Difference
    transaction_type TEXT NOT NULL,
    balance_diff TEXT,

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
CREATE INDEX idx_balance_transaction_type ON balance_log(transaction_type);
CREATE INDEX idx_balance_payment_type ON balance_log(payment_script_hash, transaction_type);

-- Add comments to table
COMMENT ON TABLE balance_log IS 'Append-only log of full balance snapshots for programmable token addresses';
COMMENT ON COLUMN balance_log.address IS 'Full bech32 address';
COMMENT ON COLUMN balance_log.payment_script_hash IS 'Payment credential hash (must match programmable token base script)';
COMMENT ON COLUMN balance_log.stake_key_hash IS 'Optional stake credential hash';
COMMENT ON COLUMN balance_log.tx_hash IS 'Transaction hash that caused this balance change';
COMMENT ON COLUMN balance_log.slot IS 'Cardano slot number';
COMMENT ON COLUMN balance_log.balance IS 'Complete balance as JSON map: {"lovelace": "1000000", "blacklistNodePolicyId+assetName": "amount"}';
COMMENT ON COLUMN balance_log.transaction_type IS 'Type of transaction: MINT, BURN, TRANSFER, or REGISTER';
COMMENT ON COLUMN balance_log.balance_diff IS 'Balance difference as JSON map with signed amounts: {"lovelace": "+2000000", "unit": "-100"}';

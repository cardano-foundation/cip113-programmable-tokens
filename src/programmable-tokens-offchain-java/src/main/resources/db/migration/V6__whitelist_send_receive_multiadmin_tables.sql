-- ============================================================================
-- Whitelist-Send-Receive-Multiadmin Substandard Tables
-- ============================================================================

-- Manager Signatures Initialization Table
-- Tracks the one-shot NFT policy used for the ManagerConfig (super-admin credential list)
CREATE TABLE whitelist_manager_signatures_init (
    manager_sigs_policy_id VARCHAR(56) PRIMARY KEY,
    admin_pkh VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL,
    output_index INTEGER NOT NULL,
    super_admin_pkhs TEXT,
    CONSTRAINT uk_mgr_sigs_admin_tx_output UNIQUE (admin_pkh, tx_hash, output_index)
);

COMMENT ON TABLE whitelist_manager_signatures_init IS 'Stores manager signatures initialization data for whitelist substandard';
COMMENT ON COLUMN whitelist_manager_signatures_init.manager_sigs_policy_id IS 'Policy ID of the manager signatures NFTs (primary key)';
COMMENT ON COLUMN whitelist_manager_signatures_init.admin_pkh IS 'Public key hash of the super-admin who initialized this manager config';
COMMENT ON COLUMN whitelist_manager_signatures_init.tx_hash IS 'Transaction hash of the seed UTxO consumed to initialize';
COMMENT ON COLUMN whitelist_manager_signatures_init.output_index IS 'Output index of the seed UTxO consumed to initialize';
COMMENT ON COLUMN whitelist_manager_signatures_init.super_admin_pkhs IS 'JSON array of super-admin public key hashes';

-- Manager List Initialization Table
-- Tracks the linked-list NFT policy used for manager credential nodes
CREATE TABLE whitelist_manager_list_init (
    manager_list_policy_id VARCHAR(56) PRIMARY KEY,
    manager_sigs_policy_id VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL,
    output_index INTEGER NOT NULL,
    CONSTRAINT uk_mgr_list_tx_output UNIQUE (tx_hash, output_index),
    CONSTRAINT fk_manager_sigs_init FOREIGN KEY (manager_sigs_policy_id)
        REFERENCES whitelist_manager_signatures_init(manager_sigs_policy_id)
);

COMMENT ON TABLE whitelist_manager_list_init IS 'Stores manager list initialization data for whitelist substandard';
COMMENT ON COLUMN whitelist_manager_list_init.manager_list_policy_id IS 'Policy ID of the manager list node NFTs (primary key)';
COMMENT ON COLUMN whitelist_manager_list_init.manager_sigs_policy_id IS 'Foreign key to the manager signatures init record';
COMMENT ON COLUMN whitelist_manager_list_init.tx_hash IS 'Transaction hash of the seed UTxO consumed to initialize';
COMMENT ON COLUMN whitelist_manager_list_init.output_index IS 'Output index of the seed UTxO consumed to initialize';

-- Whitelist Initialization Table
-- Tracks the linked-list NFT policy used for whitelisted address nodes
CREATE TABLE whitelist_init (
    whitelist_policy_id VARCHAR(56) PRIMARY KEY,
    manager_auth_hash VARCHAR(56) NOT NULL,
    tx_hash VARCHAR(64) NOT NULL,
    output_index INTEGER NOT NULL,
    CONSTRAINT uk_whitelist_tx_output UNIQUE (tx_hash, output_index)
);

COMMENT ON TABLE whitelist_init IS 'Stores whitelist initialization data for whitelist substandard';
COMMENT ON COLUMN whitelist_init.whitelist_policy_id IS 'Policy ID of the whitelist node NFTs (primary key)';
COMMENT ON COLUMN whitelist_init.manager_auth_hash IS 'Script hash of the manager_auth withdraw validator';
COMMENT ON COLUMN whitelist_init.tx_hash IS 'Transaction hash of the seed UTxO consumed to initialize';
COMMENT ON COLUMN whitelist_init.output_index IS 'Output index of the seed UTxO consumed to initialize';

-- Whitelist Token Registration Table
-- Links programmable tokens to their whitelist, manager list, and manager signatures
CREATE TABLE whitelist_token_registration (
    programmable_token_policy_id VARCHAR(56) PRIMARY KEY,
    issuer_admin_pkh VARCHAR(56) NOT NULL,
    whitelist_policy_id VARCHAR(56) NOT NULL,
    manager_list_policy_id VARCHAR(56) NOT NULL,
    manager_sigs_policy_id VARCHAR(56) NOT NULL,
    CONSTRAINT fk_whitelist_init FOREIGN KEY (whitelist_policy_id)
        REFERENCES whitelist_init(whitelist_policy_id),
    CONSTRAINT fk_manager_list_init FOREIGN KEY (manager_list_policy_id)
        REFERENCES whitelist_manager_list_init(manager_list_policy_id),
    CONSTRAINT fk_manager_sigs_init_reg FOREIGN KEY (manager_sigs_policy_id)
        REFERENCES whitelist_manager_signatures_init(manager_sigs_policy_id)
);

COMMENT ON TABLE whitelist_token_registration IS 'Stores whitelist token registration data linking tokens to their whitelist, manager list, and manager signatures';
COMMENT ON COLUMN whitelist_token_registration.programmable_token_policy_id IS 'Policy ID of the programmable token (primary key)';
COMMENT ON COLUMN whitelist_token_registration.issuer_admin_pkh IS 'Public key hash of the issuer admin';
COMMENT ON COLUMN whitelist_token_registration.whitelist_policy_id IS 'Foreign key to the whitelist init record';
COMMENT ON COLUMN whitelist_token_registration.manager_list_policy_id IS 'Foreign key to the manager list init record';
COMMENT ON COLUMN whitelist_token_registration.manager_sigs_policy_id IS 'Foreign key to the manager signatures init record';

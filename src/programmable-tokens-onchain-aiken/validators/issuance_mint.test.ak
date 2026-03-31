//// Tests for the issuance_mint validator.
////
//// Tests invoke the validator's mint handler directly, covering:
//// - Happy path (mint with RefInput and OutputIndex registry proofs)
//// - Registry node verification (CIP PR 444 Point 3 security fix)
//// - Minting logic invocation checks
//// - Output validation (PLB address, stake credential)
//// - Single mint credential enforcement

use cardano/address.{Address, Credential, Inline, Script}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Transaction,
}
use issuance_mint
use registry_node.{RegistryNode}
use types.{OutputIndex, RefInput, SmartTokenMintingAction}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_plb_cred: Credential =
  Script(#"11111111111111111111111111111111111111111111111111111111")

const test_registry_cs: PolicyId =
  #"22222222222222222222222222222222222222222222222222222222"

const test_ml_cred: Credential =
  Script(#"33333333333333333333333333333333333333333333333333333333")

const test_own_policy: PolicyId =
  #"44444444444444444444444444444444444444444444444444444444"

const test_token_name = #"746f6b656e"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn registry_node_output(key: ByteArray) -> Output {
  Output {
    address: Address {
      payment_credential: Script(
        #"88888888888888888888888888888888888888888888888888888888",
      ),
      stake_credential: None,
    },
    value: min_ada
      |> assets.add(test_registry_cs, key, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

fn mint_output(qty: Int) -> Output {
  Output {
    address: Address {
      payment_credential: test_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"77777777777777777777777777777777777777777777777777777777"),
        ),
      ),
    },
    value: min_ada
      |> assets.add(test_own_policy, test_token_name, qty),
    datum: NoDatum,
    reference_script: None,
  }
}

fn some_ref_input(output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output,
  }
}

fn valid_redeemer() -> SmartTokenMintingAction {
  SmartTokenMintingAction {
    minting_logic_cred: test_ml_cred,
    minting_registry_proof: RefInput(0),
  }
}

fn valid_mint_tx() -> Transaction {
  let rdmr = valid_redeemer()
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    outputs: [mint_output(100)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
}

fn call_validator(rdmr: SmartTokenMintingAction, tx: Transaction) -> Bool {
  issuance_mint.issuance_mint.mint(
    test_plb_cred,
    test_registry_cs,
    test_ml_cred,
    rdmr,
    test_own_policy,
    tx,
  )
}

// ========================================================================
// Happy path — all conditions met
// ========================================================================

test valid_mint_with_ref_input() {
  call_validator(valid_redeemer(), valid_mint_tx())
}

test valid_mint_with_output_index() {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: OutputIndex(1),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      outputs: [mint_output(100), registry_node_output(test_own_policy)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

test valid_burn() {
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [],
      mint: from_asset(test_own_policy, test_token_name, -50),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Registry node verification — CIP PR 444 Point 3 security fix
//
// Without these checks, an attacker could provide a registry node for a
// DIFFERENT policy and successfully mint tokens for a policy that is not
// actually registered, bypassing the registry entirely.
// ========================================================================

// SECURITY: registry node key doesn't match own_policy
test wrong_registry_key_fails() fail {
  let wrong_key = #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(wrong_key))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// No NFT under registry_node_cs in the reference input
test registry_nft_missing_fails() fail {
  let output_without_nft =
    Output {
      address: Address {
        payment_credential: Script(
          #"88888888888888888888888888888888888888888888888888888888",
        ),
        stake_credential: None,
      },
      // Value has only ADA — no registry NFT
      value: min_ada,
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: test_own_policy,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: Script(
              #"55555555555555555555555555555555555555555555555555555555",
            ),
            third_party_transfer_logic_script: Script(
              #"66666666666666666666666666666666666666666666666666666666",
            ),
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(output_without_nft)],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// NFT under wrong policy (not registry_node_cs)
test wrong_registry_cs_nft_fails() fail {
  let wrong_cs = #"dddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let output_wrong_cs =
    Output {
      address: Address {
        payment_credential: Script(
          #"88888888888888888888888888888888888888888888888888888888",
        ),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(wrong_cs, test_own_policy, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: test_own_policy,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: Script(
              #"55555555555555555555555555555555555555555555555555555555",
            ),
            third_party_transfer_logic_script: Script(
              #"66666666666666666666666666666666666666666666666666666666",
            ),
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(output_wrong_cs)],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// No inline datum on registry node output
test registry_no_datum_fails() fail {
  let output_no_datum =
    Output {
      address: Address {
        payment_credential: Script(
          #"88888888888888888888888888888888888888888888888888888888",
        ),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(test_registry_cs, test_own_policy, 1),
      datum: NoDatum,
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(output_no_datum)],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// Reference input index out of bounds
test ref_input_out_of_bounds_fails() fail {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: RefInput(99),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Minting logic validation
// ========================================================================

// Minting logic script not invoked (not in withdrawals)
test minting_logic_not_invoked_fails() fail {
  let other_cred =
    Script(#"99999999999999999999999999999999999999999999999999999999")
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(other_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// Redeemer minting_logic_cred doesn't match validator parameter
test wrong_minting_logic_cred_in_redeemer_fails() fail {
  let wrong_cred =
    Script(#"99999999999999999999999999999999999999999999999999999999")
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: wrong_cred,
      minting_registry_proof: RefInput(0),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Output validation
// ========================================================================

// First output not at programmable_logic_base address
test output_not_at_plb_fails() fail {
  let wrong_output =
    Output {
      address: Address {
        payment_credential: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 100),
      datum: NoDatum,
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [wrong_output],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// First output missing stake credential
test output_missing_stake_cred_fails() fail {
  let no_stake_output =
    Output {
      address: Address {
        payment_credential: test_plb_cred,
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 100),
      datum: NoDatum,
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [no_stake_output],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// First output has wrong token quantity
test output_wrong_token_quantity_fails() fail {
  let wrong_qty_output =
    Output {
      address: Address {
        payment_credential: test_plb_cred,
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      // Output has 50 but mint is 100
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 50),
      datum: NoDatum,
      reference_script: None,
    }
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [wrong_qty_output],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Single mint with credential enforcement
// ========================================================================

// Two minting redeemers with same data — prevents concurrent mints
test duplicate_mint_redeemer_fails() fail {
  let rdmr = valid_redeemer()
  let other_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [
        Pair(Mint(test_own_policy), as_data(rdmr)),
        Pair(Mint(other_policy), as_data(rdmr)),
      ],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Multiple token names not allowed (POC constraint)
// ========================================================================

test multiple_token_names_fails() fail {
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(100)],
      mint: from_asset(test_own_policy, test_token_name, 100)
        |> assets.add(test_own_policy, #"6f74686572", 50),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// ========================================================================
// Four minting scenarios — output validation logic
//
// Case 1: First mint (OutputIndex registry proof, no PLB spend)
// Case 2: Subsequent mint-only (RefInput registry proof, no PLB spend)
// Case 3: Spend different token + first mint (OutputIndex, PLB input exists)
// Case 4: Spend + mint same token (RefInput, PLB input exists)
// ========================================================================

// --- Case 1: First mint (registry as output) ---

// Happy path: all minted tokens go to PLB
test case1_first_mint_valid() {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: OutputIndex(1),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      outputs: [mint_output(100), registry_node_output(test_own_policy)],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// First mint: multiple outputs, all at PLB
test case1_first_mint_multiple_outputs() {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: OutputIndex(2),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      outputs: [
        mint_output(60),
        mint_output(40),
        registry_node_output(test_own_policy),
      ],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// First mint: tokens sent to non-PLB address — must fail
test case1_first_mint_tokens_to_non_plb_fails() fail {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: OutputIndex(1),
    }
  let non_plb_output =
    Output {
      address: Address {
        payment_credential: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 25),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      outputs: [
        mint_output(75),
        registry_node_output(test_own_policy),
        non_plb_output,
      ],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// --- Case 2: Subsequent mint-only (RefInput, no PLB spend) ---

// Happy path: subsequent mint, all tokens to PLB
test case2_subsequent_mint_valid() {
  call_validator(valid_redeemer(), valid_mint_tx())
}

// Subsequent mint: multiple outputs at PLB
test case2_subsequent_mint_multiple_outputs() {
  let tx =
    Transaction {
      ..valid_mint_tx(),
      outputs: [mint_output(50), mint_output(50)],
    }
  call_validator(valid_redeemer(), tx)
}

// Subsequent mint: tokens sent to non-PLB — must fail
test case2_subsequent_mint_tokens_to_non_plb_fails() fail {
  let non_plb_output =
    Output {
      address: Address {
        payment_credential: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 25),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    Transaction {
      ..valid_mint_tx(),
      outputs: [mint_output(75), non_plb_output],
    }
  call_validator(valid_redeemer(), tx)
}

// --- Case 3: Spend different token + first mint (OutputIndex, PLB input) ---
// PLGlobal doesn't know the new token → issuance_mint must validate outputs

// First mint with PLB input present: tokens to non-PLB must still fail
test case3_first_mint_with_plb_spend_tokens_escape_fails() fail {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: test_ml_cred,
      minting_registry_proof: OutputIndex(1),
    }
  let non_plb_output =
    Output {
      address: Address {
        payment_credential: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 25),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      // PLB input exists (spending a different programmable token)
      inputs: [
        Input {
          output_reference: OutputReference {
            transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
            output_index: 0,
          },
          output: mint_output(50),
        },
      ],
      outputs: [
        mint_output(75),
        registry_node_output(test_own_policy),
        non_plb_output,
      ],
      mint: from_asset(test_own_policy, test_token_name, 100),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// --- Case 4: Spend + mint same token (RefInput, PLB input) ---
// PLGlobal validates all invariants including mint accounting → defer to PLB

// Spend 100 existing + mint 50 new → 150 in outputs, all at PLB
test case4_spend_and_mint_same_token_valid() {
  let rdmr = valid_redeemer()
  let tx =
    Transaction {
      ..transaction.placeholder,
      // Spending existing PLB UTxO with 100 tokens
      inputs: [
        Input {
          output_reference: OutputReference {
            transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
            output_index: 0,
          },
          output: mint_output(100),
        },
      ],
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      // 150 total in outputs (100 spent + 50 minted) — all at PLB
      outputs: [mint_output(150)],
      mint: from_asset(test_own_policy, test_token_name, 50),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  call_validator(rdmr, tx)
}

// Spend + mint same token: tokens escaping to non-PLB — deferred to PLGlobal.
// issuance_mint allows it because PLGlobal (invoked via PLB spend) will reject.
// This test documents that issuance_mint trusts PLGlobal in this case.
test case4_spend_and_mint_defers_to_plglobal() {
  let rdmr = valid_redeemer()
  let non_plb_output =
    Output {
      address: Address {
        payment_credential: Script(
          #"99999999999999999999999999999999999999999999999999999999",
        ),
        stake_credential: Some(
          Inline(
            Script(#"77777777777777777777777777777777777777777777777777777777"),
          ),
        ),
      },
      value: min_ada
        |> assets.add(test_own_policy, test_token_name, 25),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [
        Input {
          output_reference: OutputReference {
            transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
            output_index: 0,
          },
          output: mint_output(100),
        },
      ],
      reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
      outputs: [mint_output(75), non_plb_output],
      mint: from_asset(test_own_policy, test_token_name, 50),
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  // This passes at issuance_mint level — PLGlobal would reject it on-chain
  call_validator(rdmr, tx)
}

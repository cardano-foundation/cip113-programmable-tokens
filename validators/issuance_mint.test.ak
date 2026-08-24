//// Tests for the issuance_mint validator.
////
//// Tests invoke the validator's mint handler directly, covering:
//// - Happy path (mint with RefInput and OutputIndex registry proofs)
//// - Registry node verification (CIP PR 444 Point 3 security fix)
//// - Minting logic invocation checks
//// - Output validation (PLB address, stake credential)
//// - Single mint credential enforcement

use aiken/fuzz
use cardano/address.{Address, Credential, Inline, Script}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Spend,
  Transaction, Withdraw,
}
use issuance_mint
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use programmable_logic_base
use registry_node.{RegistryNode, empty_vkey}
use third_party
use types.{
  BaseSpendRedeemer, MintingRegistryProof, OutputIndex, RefInput,
  SpendViaThirdParty, ThirdPartyRedeemer, TokenExists, TransferRedeemer,
}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_plb_cred: Credential =
  Script(#"11111111111111111111111111111111111111111111111111111111")

const test_registry_cs: PolicyId =
  #"22222222222222222222222222222222222222222222222222222222"

const test_ml_cred: Credential =
  Script(#"33333333333333333333333333333333333333333333333333333333")

const test_transfer_cred: Credential =
  Script(#"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1")

/// The standalone third_party (seize) validator credential carried by the
/// coordination datum (field 3, `third_party_cred`) — the delegate a mint
/// co-occurring with a seize defers custody to.
const test_tp_cred: Credential =
  Script(#"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3")

/// The live transfer-validator credential AFTER a simulated in-place upgrade — what the
/// coordination datum carries once `test_transfer_cred` has been retired.
const test_transfer_cred_v2: Credential =
  Script(#"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2")

/// One-shot protocol-params NFT policy — the validator's 4th parameter.
const test_params_policy: PolicyId =
  #"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"

const test_own_policy: PolicyId =
  #"44444444444444444444444444444444444444444444444444444444"

const test_token_name = #"746f6b656e"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The ISSUER's third-party transfer logic credential registered in our node
/// (`third_party_transfer_logic_script`). Its withdraw-0 is what the
/// `third_party` validator requires on a seize of our policy.
const test_issuer_3p_cred: Credential =
  Script(#"66666666666666666666666666666666666666666666666666666666")

fn registry_node_output(key: ByteArray) -> Output {
  registry_node_output_with_3p(key, test_issuer_3p_cred)
}

/// Same node with an explicit issuer third-party logic credential — the
/// composed seize tests vary it to move the framework `third_party`
/// credential around the ledger-sorted withdrawal map.
fn registry_node_output_with_3p(
  key: ByteArray,
  issuer_3p_cred: Credential,
) -> Output {
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
          third_party_transfer_logic_script: issuer_3p_cred,
          // Must match the validator's `minting_logic_cred` parameter
          // (= `test_ml_cred` via `call_validator`). Defense-in-depth #3.
          minting_logic_script: test_ml_cred,
          unfracking_logic_script: empty_vkey,
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

fn mint_output_named(token_name: ByteArray, qty: Int) -> Output {
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
      |> assets.add(test_own_policy, token_name, qty),
    datum: NoDatum,
    reference_script: None,
  }
}

/// An output holding `qty` of `(test_own_policy, token_name)` at a NON-PLB
/// address — used by tests that exercise the "tokens escape programmable
/// custody" failure paths.
fn non_plb_output_named(token_name: ByteArray, qty: Int) -> Output {
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
      |> assets.add(test_own_policy, token_name, qty),
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

/// Wrap an output as a placeholder input (mirror of `some_ref_input` for the
/// spending side).
fn some_input(output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output,
  }
}

/// The coordination UTxO as a reference input: carries the protocol-params
/// NFT (under `test_params_policy`) and the protocol-params datum whose
/// field 2 (`transfer_cred`) is the LIVE transfer-validator credential the
/// validator must resolve. `unfracking_cred` / `upgrade_cred` are
/// never read by issuance_mint, so any placeholder credential is fine.
fn coordination_ref_input(transfer_cred: Credential) -> Input {
  some_ref_input(
    Output {
      address: Address {
        payment_credential: Script(
          #"88888888888888888888888888888888888888888888888888888888",
        ),
        stake_credential: None,
      },
      value: min_ada
        |> assets.add(test_params_policy, "ProtocolParams", 1),
      datum: InlineDatum(
        as_data(
          ProgrammableLogicGlobalParams {
            registry_node_cs: test_registry_cs,
            prog_logic_cred: test_plb_cred,
            unfracking_cred: test_ml_cred,
            transfer_cred,
            upgrade_cred: test_ml_cred,
            max_inline_datum_bytes: 1024,
            third_party_cred: test_tp_cred,
          },
        ),
      ),
      reference_script: None,
    },
  )
}

fn valid_redeemer() -> MintingRegistryProof {
  RefInput(0)
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

fn call_validator(rdmr: MintingRegistryProof, tx: Transaction) -> Bool {
  issuance_mint.issuance_mint.mint(
    test_plb_cred,
    test_registry_cs,
    test_ml_cred,
    test_params_policy,
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

// A minted PLB output carrying a datum HASH is rejected: such a UTxO is
// `reference_inputs` is deliberately absent — this test is the proof that
// the OutputIndex path needs no coordination ref input (the coordination
// read is lazy: only the RefInput delegation branch performs it).

// A minted PLB output carrying a datum HASH is rejected: such a UTxO is
// unspendable without the preimage, so it could never be seized.
test mint_rejects_datum_hash_output() fail {
  let bad = Output {
    ..mint_output(100),
    datum: DatumHash(
      #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00",
    ),
  }
  let tx = Transaction { ..valid_mint_tx(), outputs: [bad] }
  call_validator(valid_redeemer(), tx)
}

// A minted PLB output carrying a reference script is rejected: it would bloat
// the mandatory seizure continuing-output.
test mint_rejects_reference_script_output() fail {
  let bad = Output {
    ..mint_output(100),
    reference_script: Some(
      #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
    ),
  }
  let tx = Transaction { ..valid_mint_tx(), outputs: [bad] }
  call_validator(valid_redeemer(), tx)
}

test valid_mint_with_output_index() {
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [mint_output(100), registry_node_output(test_own_policy)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// Burning requires PLB inputs (tokens to burn live at PLB addresses).
// the transfer validator under a transfer validates the burn's balance; issuance_mint
// delegates iff the transfer validator's redeemer names the same registry node we did
// (`TokenExists { node_idx: 0 }` against our `RefInput { index: 0 }`).
test valid_burn() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: OutputReference {
          transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
          output_index: 0,
        },
        output: mint_output(50),
      },
    ],
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    outputs: [],
    mint: from_asset(test_own_policy, test_token_name, -50),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
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
  let tx = Transaction {
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
  let output_without_nft = Output {
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
          minting_logic_script: test_ml_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
  let rdmr = valid_redeemer()
  let tx = Transaction {
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
  let output_wrong_cs = Output {
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
          minting_logic_script: test_ml_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
  let rdmr = valid_redeemer()
  let tx = Transaction {
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
  let output_no_datum = Output {
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
  let tx = Transaction {
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
  let rdmr = RefInput(99)
  let tx = Transaction {
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
  let other_cred = Script(
    #"99999999999999999999999999999999999999999999999999999999",
  )
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    outputs: [mint_output(100)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(other_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// ========================================================================
// Output validation
// ========================================================================

// First output not at programmable_logic_base address
test output_not_at_plb_fails() fail {
  let wrong_output = Output {
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
  let tx = Transaction {
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
  let no_stake_output = Output {
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
  let tx = Transaction {
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
// no_escape delegates "the full mint lands at PLB" to the ledger's value
// conservation — it does NOT re-check quantities. What it DOES reject is any
// `own_policy` token at a non-PLB output. So the old ledger-impossible
// under-quantity case (mint 100, only 50 in outputs) is now the ledger's job;
// here we mint 100, keep 50 at PLB and route the other 50 to a non-PLB
// address — a ledger-valid tx that no_escape must reject.
test output_partial_escape_to_non_plb_fails() fail {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    outputs: [mint_output(50), non_plb_output_named(test_token_name, 50)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// ========================================================================
// Multi-token minting under same policy
//
// These tests express desired multi-token behavior.
// Use cases: share classes, soulbound DIDs, auth NFTs, programmable NFTs.
// See: https://github.com/cardano-foundation/cip113-programmable-tokens/pull/45#discussion_r3019195411
// ========================================================================

const test_token_name_2 = #"746f6b656e32"

fn multi_mint_output(qty1: Int, qty2: Int) -> Output {
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
      |> assets.add(test_own_policy, test_token_name, qty1)
      |> assets.add(test_own_policy, test_token_name_2, qty2),
    datum: NoDatum,
    reference_script: None,
  }
}

// Multi-token mint: two token names, both to PLB, RefInput proof
test multi_token_mint_ref_input() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    outputs: [multi_mint_output(100, 50)],
    mint: from_asset(test_own_policy, test_token_name, 100)
      |> assets.add(test_own_policy, test_token_name_2, 50),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// Multi-token first mint: two token names, OutputIndex proof
test multi_token_mint_output_index() {
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [multi_mint_output(100, 50), registry_node_output(test_own_policy)],
    mint: from_asset(test_own_policy, test_token_name, 100)
      |> assets.add(test_own_policy, test_token_name_2, 50),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// Multi-token mint: split across two PLB outputs
test multi_token_mint_split_outputs() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    outputs: [mint_output(100), mint_output_named(test_token_name_2, 50)],
    mint: from_asset(test_own_policy, test_token_name, 100)
      |> assets.add(test_own_policy, test_token_name_2, 50),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// Multi-token mint: one token escapes to non-PLB — must fail
test multi_token_mint_partial_escape_fails() fail {
  let rdmr = valid_redeemer()
  let non_plb_output = Output {
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
      |> assets.add(test_own_policy, test_token_name_2, 50),
    datum: NoDatum,
    reference_script: None,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    // tokenA goes to PLB, tokenB escapes to non-PLB
    outputs: [mint_output(100), non_plb_output],
    mint: from_asset(test_own_policy, test_token_name, 100)
      |> assets.add(test_own_policy, test_token_name_2, 50),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// Multi-token burn: burn two token names
// Burning requires PLB inputs → plb_spent = True → delegates to the transfer validator
test multi_token_burn() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: OutputReference {
          transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
          output_index: 0,
        },
        output: multi_mint_output(100, 50),
      },
    ],
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    outputs: [],
    mint: from_asset(test_own_policy, test_token_name, -100)
      |> assets.add(test_own_policy, test_token_name_2, -50),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// Phase-4 (PR #110 validator split): a mint that co-occurs with a third-party SEIZE of the
// same policy delegates custody to the standalone `third_party` validator, whose
// redeemer (at `third_party_cred`, field 3) names our registry node. To isolate
// the delegation DECISION, the minted subject tokens go to a NON-PLB output —
// local `no_escape` alone would reject this, but delegation short-circuits it.
// This is deliberately NOT a valid transaction end to end: the composed
// `composed_seize_mint_*` tests below run issuance_mint + PLB + third_party
// on one coherent tx and show `third_party` catching exactly this escape.
// (`params_idx: 1` matches the coordination UTxO's position — issuance_mint
// never reads it, but the redeemer must be the one a real tx would carry.)
test refinput_mint_delegates_to_third_party_seize() {
  let rdmr = valid_redeemer()
  let escaping_output = Output {
    address: Address {
      payment_credential: Script(
        #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      ),
      stake_credential: None,
    },
    value: min_ada |> assets.add(test_own_policy, test_token_name, 100),
    datum: NoDatum,
    reference_script: None,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [
      // index 0 — our registry node (RefInput(0))
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    outputs: [escaping_output],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_tp_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_tp_cred),
        as_data(
          ThirdPartyRedeemer {
            params_idx: 1,
            registry_node_idx: 0,
            outputs_start_idx: 0,
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// Negative: same escaping mint, but the third_party redeemer names a DIFFERENT
// registry node (index 1, not our 0). Delegation is denied — precise
// delegation (Finding 04) — so local custody runs and catches the escape.
test refinput_mint_third_party_wrong_node_no_delegation_fails() fail {
  let rdmr = valid_redeemer()
  let escaping_output = Output {
    address: Address {
      payment_credential: Script(
        #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      ),
      stake_credential: None,
    },
    value: min_ada |> assets.add(test_own_policy, test_token_name, 100),
    datum: NoDatum,
    reference_script: None,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    outputs: [escaping_output],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_tp_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_tp_cred),
        as_data(
          ThirdPartyRedeemer {
            params_idx: 1,
            registry_node_idx: 1,
            outputs_start_idx: 0,
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// Multi-token spend + mint (RefInput, PLB input) → defers to the transfer validator
test multi_token_spend_and_mint_defers() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      Input {
        output_reference: OutputReference {
          transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
          output_index: 0,
        },
        output: multi_mint_output(100, 50),
      },
    ],
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    outputs: [multi_mint_output(200, 100)],
    mint: from_asset(test_own_policy, test_token_name, 100)
      |> assets.add(test_own_policy, test_token_name_2, 50),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
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
  let rdmr = OutputIndex(1)
  let tx = Transaction {
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
  let rdmr = OutputIndex(2)
  let tx = Transaction {
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
  let rdmr = OutputIndex(1)
  let non_plb_output = Output {
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
  let tx = Transaction {
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

// First mint with shared transfer logic: another token uses the same transfer
// logic script, and that script is invoked in this tx (for the other token's
// transfer). The old anti-abuse check (!list.has(invoked_scripts, transfer_logic))
// would have blocked this legitimate scenario.
test case1_first_mint_with_shared_transfer_logic() {
  // The transfer logic for this new token is the same as test_ml_cred
  // (which IS in invoked_scripts because it's the minting logic)
  let shared_cred = test_ml_cred
  let registry_with_shared_logic = Output {
    address: Address {
      payment_credential: Script(
        #"88888888888888888888888888888888888888888888888888888888",
      ),
      stake_credential: None,
    },
    value: min_ada
      |> assets.add(test_registry_cs, test_own_policy, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: test_own_policy,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: shared_cred,
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          minting_logic_script: test_ml_cred,
          unfracking_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [mint_output(100), registry_with_shared_logic],
    mint: from_asset(test_own_policy, test_token_name, 100),
    // minting logic (== transfer logic) is invoked — old check would reject this
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// First mint where transfer logic of another already-registered token happens
// to be invoked in the same tx. This is a legitimate multi-token scenario.
test case1_first_mint_with_other_tokens_transfer_logic_invoked() {
  let other_transfer_logic = Script(
    #"55555555555555555555555555555555555555555555555555555555",
  )
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [mint_output(100), registry_node_output(test_own_policy)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    // Both minting logic AND another token's transfer logic are invoked
    // The registry_node_output uses #"5555..." as transfer_logic_script
    // Old anti-abuse check would reject because #"5555..." is in withdrawals
    withdrawals: [Pair(test_ml_cred, 0), Pair(other_transfer_logic, 0)],
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
  let tx = Transaction {
    ..valid_mint_tx(),
    outputs: [mint_output(50), mint_output(50)],
  }
  call_validator(valid_redeemer(), tx)
}

// Subsequent mint: tokens sent to non-PLB — must fail
test case2_subsequent_mint_tokens_to_non_plb_fails() fail {
  let non_plb_output = Output {
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
  let tx = Transaction {
    ..valid_mint_tx(),
    outputs: [mint_output(75), non_plb_output],
  }
  call_validator(valid_redeemer(), tx)
}

// --- Case 3: Spend different token + first mint (OutputIndex, PLB input) ---
// the transfer validator doesn't know the new token → issuance_mint must validate outputs

// First mint with PLB input present: tokens to non-PLB must still fail
test case3_first_mint_with_plb_spend_tokens_escape_fails() fail {
  let rdmr = OutputIndex(1)
  let non_plb_output = Output {
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
  let tx = Transaction {
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
// the transfer validator validates all invariants including mint accounting → defer to PLB

// Spend 100 existing + mint 50 new → 150 in outputs, all at PLB
test case4_spend_and_mint_same_token_valid() {
  let rdmr = valid_redeemer()
  let tx = Transaction {
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
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(test_transfer_cred),
    ],
    // 150 total in outputs (100 spent + 50 minted) — all at PLB
    outputs: [mint_output(150)],
    mint: from_asset(test_own_policy, test_token_name, 50),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// Shared base transaction for the case-4 (RefInput proof + PLB input) tests.
// Spends a 100-token PLB UTxO, mints 50 more, sends 75 to PLB and 25 to a
// non-PLB address. Withdrawals include both the minting logic credential
// AND the transfer validator stake credential — so when consumed as-is, delegation
// triggers and issuance_mint defers output custody to the transfer validator. The
// coordination ref input (appended AFTER the registry node, so
// `RefInput(0)` still resolves) carries the datum whose field 2 is the
// LIVE the transfer validator credential the validator resolves delegation against.
//
// The companion negative test below overrides ONLY `withdrawals` (removing
// the transfer cred), documenting "coordination present but transfer redeemer absent
// ⇒ no delegation". Any future change to inputs/outputs/mint/refs must
// keep both tests in lockstep — that's the entire point of building both
// from this single fixture.
//
// `transfer_cred` parameterises BOTH the coordination datum and the withdrawal,
// so the in-place-upgrade tests below can swap the live credential while
// every existing spread of `case4_defers_tx()` stays untouched.
fn case4_defers_tx_with(transfer_cred: Credential) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [some_input(mint_output(100))],
    reference_inputs: [
      some_ref_input(registry_node_output(test_own_policy)),
      coordination_ref_input(transfer_cred),
    ],
    outputs: [mint_output(75), non_plb_output_named(test_token_name, 25)],
    mint: from_asset(test_own_policy, test_token_name, 50),
    withdrawals: [Pair(test_ml_cred, 0), Pair(transfer_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(valid_redeemer()))],
  }
}

fn case4_defers_tx() -> Transaction {
  case4_defers_tx_with(test_transfer_cred)
}

// Spend + mint same token: tokens escaping to non-PLB — deferred to the transfer validator.
// issuance_mint allows it because the transfer validator (invoked via the transfer cred in
// withdrawals) will reject it on-chain. This test documents that
// issuance_mint trusts the transfer validator in this case.
test case4_spend_and_mint_defers_to_plglobal() {
  // Spread `case4_defers_tx()` and override `redeemers` to include the
  // the transfer validator Withdraw redeemer. This is the single delta from the helper —
  // we add the transfer validator redeemer entry so `find_plgl_redeemer` returns
  // `Some(TransferRedeemer { ... })`, the scope check sees
  // `TokenExists { node_idx: 0 }` (matching our `RefInput { index: 0 }`),
  // and issuance_mint delegates. The sibling `_does_not_delegate_fails`
  // test deliberately omits this override so the helper's redeemer list
  // stays minimal and absence of the transfer validator redeemer (post-`withdrawals`
  // override) blocks delegation.
  let tx = Transaction {
    ..case4_defers_tx(),
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// Finding 09 regression. Same exact transaction as the test above EXCEPT
// the transfer validator stake credential is removed from `tx.withdrawals` — so the
// `..case4_defers_tx()` spread plus a single field override is the entire
// delta visible in the source. Pre-fix, the delegation signal was "any PLB
// input in `self.inputs`" — so this tx would have passed at issuance_mint
// level by short-circuiting `validate_mint_outputs`. Post-fix, the signal
// is "transfer-validator stake credential in `tx.withdrawals`" — and since that's absent
// here, delegation does NOT trigger, `validate_mint_outputs` runs, and the
// escape to non-PLB is correctly rejected.
test case4_plb_input_without_transfer_cred_does_not_delegate_fails() fail {
  let tx = Transaction {
    ..case4_defers_tx(),
    withdrawals: [Pair(test_ml_cred, 0)],
  }
  call_validator(valid_redeemer(), tx)
}

// ========================================================================
// Live transfer-validator delegation via the coordination datum (in-place upgradability)
//
// The validator's 4th parameter is now `params_policy` (the protocol-params
// NFT policy), not a frozen transfer-validator credential. Delegation resolves the LIVE
// the transfer validator credential from the coordination UTxO's datum (field 2), so an
// in-place transfer-validator upgrade automatically retires the old credential as a
// mint-custody delegate.
// ========================================================================

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// the OutputIndex path performs NO coordination read — a first mint with
// ZERO reference inputs must validate. Proof that the coordination lookup
// is lazy (confined to the RefInput delegation branch).
test outputindex_mint_without_coordination_ref_input_validates() {
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [],
    outputs: [mint_output(100), registry_node_output(test_own_policy)],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// delegation keys on the credential the coordination datum names. Custody
// is violated in the fixture (25 tokens at a non-PLB output), so this can
// only pass because the datum-resolved credential (`test_transfer_cred`) is
// invoked with a covering proof and issuance_mint defers to the transfer validator.
test delegation_uses_live_transfer_cred_from_coordination_datum() {
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred),
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// after an in-place transfer-validator upgrade (coordination datum rewritten to carry
// `test_transfer_cred_v2`), the NEW credential delegates — no issuance_mint
// redeploy needed. Same shape as the test above with the v2 credential in
// both the datum and the invocation.
test delegation_survives_in_place_transfer_validator_upgrade() {
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred_v2),
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred_v2),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// THE falsification test. The coordination datum names `test_transfer_cred_v2`
// as the live the transfer validator, but the tx invokes only the launch-era
// `test_transfer_cred` (withdrawal + covering `TokenExists { node_idx: 0 }`),
// with custody violated. The retired credential must NOT delegate: the
// lookup keyed on the datum-resolved v2 finds no redeemer, delegation is
// denied, `no_escape` runs and rejects the 25-token escape.
//
// Verified to PASS (exploit succeeds) against pre-fix code on 2026-08-13
// per testing convention 6 — via a pre-edit scratch test of this exact
// shape run BEFORE the validator edit (a plain `git stash` re-run does not
// typecheck, since the 4th parameter's type changed from Credential to
// PolicyId), observed `pass` under the frozen-parameter validator.
//
// Isolation note per convention 3: this test intentionally has two
// deviations from `delegation_uses_live_transfer_cred_from_coordination_datum`
// (the datum credential is swapped to v2 AND the old credential is the one
// invoked) because the invariant under test is precisely their
// disagreement — datum says v2, tx invokes v1.
test launch_era_transfer_cred_cannot_delegate_after_upgrade_fails() fail {
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred_v2),
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// same old-cred-invoked-after-upgrade shape as the `fail` test above, but
// with custody intact (all `own_policy` outputs at the PLB). Denied
// delegation falls back to the local `no_escape` check, which passes —
// a stale delegate makes the mint self-custodied, not invalid.
test stale_transfer_cred_delegation_denied_falls_back_to_custody() {
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred_v2),
    outputs: [mint_output(150)],
    withdrawals: [Pair(test_ml_cred, 0), Pair(test_transfer_cred, 0)],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// a RefInput mint with NO coordination ref input (and no the transfer validator invoked)
// must still validate under local custody — the coordination locate is
// non-failing (`list.find` + `has_nft_strict`), so its absence means "no
// delegation", never a crash. Pins the fail-safe locate semantics.
test refinput_mint_without_coordination_ref_input_falls_back_to_custody() {
  call_validator(valid_redeemer(), valid_mint_tx())
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// the coordination LOCATE itself is load-bearing. The transfer-validator credential is
// invoked with a covering proof (withdrawal + `TokenExists { node_idx: 0 }`
// redeemer) and custody is violated, but the coordination ref input is
// ABSENT — so there is no datum to resolve a delegate from, delegation is
// denied, and `no_escape` rejects the escape. Pre-fix this exact shape
// delegated successfully: the frozen transfer-credential parameter needed no
// coordination UTxO at all.
//
// Isolation note per convention 3: single delta against
// `delegation_uses_live_transfer_cred_from_coordination_datum` — the
// coordination ref input is dropped from `reference_inputs`; the
// invocation and the custody violation are identical.
test transfer_delegation_impossible_without_coordination_ref_input_fails() fail {
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred),
    reference_inputs: [some_ref_input(registry_node_output(test_own_policy))],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(valid_redeemer())),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 0 }],
          },
        ),
      ),
    ],
  }
  call_validator(valid_redeemer(), tx)
}

// In-place upgradability follow-up (2026-08-13 naming review, finding 2):
// the params NFT check (`has_nft_strict`), not the datum shape, is what
// authenticates the coordination UTxO — the locate is keyed on VALUE only.
// This tx plants a ref input carrying a well-formed params datum naming
// the invoked credential but whose value LACKS the protocol-params NFT,
// AHEAD of the registry node (position 0). Position 0 matters: a mutant
// locate that ignores the NFT check finds the plant FIRST and delegates —
// this test kills that mutant directly — while the real value-keyed
// locate skips the plant position-independently, denies delegation, and
// `no_escape` rejects the custody violation. Guards against an attacker
// planting a forged params-shaped datum to resurrect a retired delegate
// (or nominate an arbitrary one).
//
// Isolation note per convention 3: the index pair (`RefInput(1)` /
// `TokenExists { node_idx: 1 }`) moves in lockstep with the reordered
// `reference_inputs` — a single conceptual delta against
// `delegation_uses_live_transfer_cred_from_coordination_datum` (the NFT-less
// plant shadows position 0) even though three literals change.
test coordination_datum_without_params_nft_cannot_delegate_fails() fail {
  let nftless_coordination_plant = some_ref_input(
    Output {
      ..coordination_ref_input(test_transfer_cred).output,
      value: min_ada,
    },
  )
  let rdmr = RefInput(1)
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred),
    reference_inputs: [
      nftless_coordination_plant,
      some_ref_input(registry_node_output(test_own_policy)),
    ],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 1 }],
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// In-place upgradability follow-up (2026-08-13 cross-provider review):
// order-independent coordination discovery on the SUCCESS path. Every
// other positive delegation fixture places the registry node at
// reference-input position 0 with the coordination UTxO after it; here
// the AUTHENTIC coordination UTxO (params NFT + datum naming the invoked
// credential) sits at position 0 and the registry node at position 1.
// Custody is violated (case-4 shape, 25 tokens at a non-PLB output), so
// this can only pass because (a) the value-keyed locate finds the
// coordination UTxO regardless of its position and (b) the registry-index
// binding (RefInput 1 / node_idx 1) is untouched by the reorder —
// delegation fires against the datum-resolved credential.
//
// Isolation note per convention 3: the index pair (`RefInput(1)` /
// `TokenExists { node_idx: 1 }`) moves in lockstep with the reordered
// `reference_inputs` — a single conceptual delta against
// `delegation_uses_live_transfer_cred_from_coordination_datum` (the two
// reference inputs are swapped) even though three literals change.
test delegation_locates_coordination_ahead_of_registry_node() {
  let rdmr = RefInput(1)
  let tx = Transaction {
    ..case4_defers_tx_with(test_transfer_cred),
    reference_inputs: [
      coordination_ref_input(test_transfer_cred),
      some_ref_input(registry_node_output(test_own_policy)),
    ],
    redeemers: [
      Pair(Mint(test_own_policy), as_data(rdmr)),
      Pair(
        Withdraw(test_transfer_cred),
        as_data(
          TransferRedeemer {
            params_idx: 0,
            proofs: [TokenExists { node_idx: 1 }],
          },
        ),
      ),
    ],
  }
  call_validator(rdmr, tx)
}

// ========================================================================
// CIP-68 metadata token minting
//
// CIP-68 uses CIP-67 label prefixes on asset names:
//   - Label 333 (FT user token):  0x000f4141 + asset_name
//   - Label 100 (reference token): 0x000643b0 + asset_name
//
// Both tokens share the same policy ID (issuance_mint). The validator
// should allow minting both in the same transaction since it does NOT
// inspect asset name structure — only checks that all minted tokens
// go to PLB addresses.
// ========================================================================

// "MyToken" in hex

// CIP-67 label 333 (FT) prefix + asset name
const cip68_ft_name = #"000f41414d79546f6b656e"

// CIP-67 label 100 (reference) prefix + asset name
const cip68_ref_name = #"000643b04d79546f6b656e"

fn cip68_ft_output(qty: Int) -> Output {
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
      |> assets.add(test_own_policy, cip68_ft_name, qty),
    // Void datum — same as SDK's voidData() for user token outputs
    datum: InlineDatum(Void),
    reference_script: None,
  }
}

fn cip68_ref_output() -> Output {
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
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    // CIP-68 metadata datum — validator doesn't inspect datum content,
    // just that the token goes to a PLB address. Use Void as placeholder.
    datum: InlineDatum(Void),
    reference_script: None,
  }
}

// CIP-68 first mint: FT (label 333) + reference token (label 100), OutputIndex
test cip68_first_mint_ft_and_ref_token() {
  let rdmr = OutputIndex(3)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [
      // Output 0: FT user tokens to PLB
      cip68_ft_output(1_000_000),
      // Output 1: CIP-68 reference token to PLB (issuer)
      cip68_ref_output(),
      // Output 2: updated covering registry node (no own_policy tokens)
      registry_node_output(
        #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      // Output 3: new registry node for this token
      registry_node_output(test_own_policy),
    ],
    mint: from_asset(test_own_policy, cip68_ft_name, 1_000_000)
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// CIP-68 first mint: split FT + ref across separate PLB outputs
test cip68_first_mint_split_outputs() {
  let rdmr = OutputIndex(2)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [
      cip68_ft_output(500),
      cip68_ref_output(),
      registry_node_output(test_own_policy),
    ],
    mint: from_asset(test_own_policy, cip68_ft_name, 500)
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// CIP-68 first mint: both tokens in single PLB output (combined)
test cip68_first_mint_combined_output() {
  let combined_output = Output {
    address: Address {
      payment_credential: test_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"77777777777777777777777777777777777777777777777777777777"),
        ),
      ),
    },
    value: min_ada
      |> assets.add(test_own_policy, cip68_ft_name, 500)
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    datum: NoDatum,
    reference_script: None,
  }
  let rdmr = OutputIndex(1)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [combined_output, registry_node_output(test_own_policy)],
    mint: from_asset(test_own_policy, cip68_ft_name, 500)
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// CIP-68: ref token escapes to non-PLB — must fail
test cip68_ref_token_escapes_non_plb_fails() fail {
  let non_plb_ref = Output {
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
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    datum: NoDatum,
    reference_script: None,
  }
  let rdmr = OutputIndex(2)
  let tx = Transaction {
    ..transaction.placeholder,
    outputs: [
      cip68_ft_output(500),
      non_plb_ref,
      registry_node_output(test_own_policy),
    ],
    mint: from_asset(test_own_policy, cip68_ft_name, 500)
      |> assets.add(test_own_policy, cip68_ref_name, 1),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// ==========================================================================
// Re-audit R-04, case-2 escape (OutputIndex via an insert's covering node).
//
// The registry node reaches the OutputIndex branch as a RE-EMITTED COVERING
// NODE during an insert — not a first mint — so the policy is already
// registered and pre-existing supply can sit at the PLB. A co-occurring
// ThirdPartyAct on an UNRELATED policy preserves that supply (100 at PLB,
// referencing neither this node nor this policy), while the freshly minted 100
// is routed to a NON-PLB output. The tx conserves value (100 in + 100 mint =
// 100 PLB + 100 non-PLB out), so the ledger accepts it.
//
// This unit test exercises the issuance_mint-visible shape of that tx: an
// OutputIndex proof pointing at the (re-emitted) node output, a PLB input
// holding the preserved 100, and the minted 100 at a non-PLB output.
//
// The OLD output-only check would PASS this (PLB total 100 == mint delta 100)
// — that is the escape. `no_escape` REJECTS it (own_policy at a non-PLB
// output), regardless of how the node came to be an output.
test outputindex_covering_node_mint_escape_fails() fail {
  let rdmr = OutputIndex(2)
  let tx = Transaction {
    ..transaction.placeholder,
    // Pre-existing 100 P at a PLB input (what ThirdPartyAct would preserve).
    inputs: [some_input(mint_output(100))],
    outputs: [
      // 100 P preserved at the PLB.
      mint_output(100),
      // 100 freshly minted P escaping to a non-PLB address.
      non_plb_output_named(test_token_name, 100),
      // The re-emitted covering node carrying P's registry NFT (index 2).
      registry_node_output(test_own_policy),
    ],
    mint: from_asset(test_own_policy, test_token_name, 100),
    withdrawals: [Pair(test_ml_cred, 0)],
    redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
  }
  call_validator(rdmr, tx)
}

// ===========================================================================
// Composed transaction: issuance_mint × programmable_logic_base × third_party
// ===========================================================================
//
// PR #110 review: the isolated delegation tests above only run issuance_mint.
// These run all three validators on ONE coherent transaction — a seize of our
// policy that also mints (or burns) it — with every index (RefInput,
// params_idx, registry_node_idx, wdrl_idx) derived from the same layout, and
// show that a one-token escape is caught by `third_party` specifically:
// issuance_mint has delegated, PLB has dispatched, and the conservation check
// in `validate_3rd_party` is what says no.

/// A PLB output in the seizing authority's custody (stake credential of the
/// substandard's escrow logic) holding `qty` subject tokens.
fn seized_output(qty: Int) -> Output {
  Output {
    address: Address {
      payment_credential: test_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"adadadadadadadadadadadadadadadadadadadadadadadadadadadad"),
        ),
      ),
    },
    value: min_ada |> assets.add(test_own_policy, test_token_name, qty),
    datum: NoDatum,
    reference_script: None,
  }
}

/// ONE subject-policy token at a non-PLB address — the escape.
fn escaped_token_output() -> Output {
  non_plb_output_named(test_token_name, 1)
}

/// An issuer third-party logic credential that sorts AFTER the framework
/// `third_party` credential (c3c3…) in the ledger's withdrawal order, moving
/// `wdrl_idx` from 2 to 1 (`test_issuer_3p_cred`, 6666…, sorts before it).
const test_issuer_3p_cred_late: Credential =
  Script(#"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd")

/// Everything the three validators need for one composed seize-with-mint tx.
type Composed {
  tx: Transaction,
  mint_redeemer: MintingRegistryProof,
  base_redeemer: BaseSpendRedeemer,
  tp_redeemer: ThirdPartyRedeemer,
}

/// Build the composed transaction:
///   * ONE holder PLB input with `held` subject tokens is fully seized — its
///     paired output (outputs_start_idx = 0) keeps address, datum and
///     lovelace but no subject tokens;
///   * `delta` subject tokens are minted (or burned, if negative);
///   * `custody_outputs` follow the paired output — where `held + delta` is
///     expected to land (one PLB custody output in the positive case);
///   * the registry node and the coordination UTxO sit in either order
///     (`coordination_first`), so RefInput / params_idx / registry_node_idx
///     all come from the same layout;
///   * withdrawals are listed in LEDGER order (`fixture.ledger_sorted_withdrawals`);
///     `issuer_3p_cred` (the node's third-party logic) decides whether the
///     framework `third_party` credential sorts at index 1 or 2, and
///     `wdrl_idx` is computed from that order, as a builder would.
fn composed_seize_mint(
  held: Int,
  delta: Int,
  coordination_first: Bool,
  issuer_3p_cred: Credential,
  custody_outputs: List<Output>,
) -> Composed {
  let node = some_ref_input(
    registry_node_output_with_3p(test_own_policy, issuer_3p_cred),
  )
  let coordination = coordination_ref_input(test_transfer_cred)
  let (reference_inputs, node_idx, params_idx) = if coordination_first {
    ([coordination, node], 1, 0)
  } else {
    ([node, coordination], 0, 1)
  }
  let withdrawals = fixture.ledger_sorted_withdrawals(
    [Pair(test_ml_cred, 0), Pair(issuer_3p_cred, 0), Pair(test_tp_cred, 0)],
  )
  let wdrl_idx = fixture.withdrawal_index_of(withdrawals, test_tp_cred)
  let holder_input = some_input(mint_output(held))
  let mint_redeemer = RefInput(node_idx)
  let base_redeemer = SpendViaThirdParty { params_idx, wdrl_idx }
  let tp_redeemer = ThirdPartyRedeemer {
    params_idx,
    registry_node_idx: node_idx,
    outputs_start_idx: 0,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [holder_input],
    reference_inputs,
    outputs: [mint_output(0), ..custody_outputs],
    mint: from_asset(test_own_policy, test_token_name, delta),
    withdrawals,
    redeemers: [
      Pair(Spend(holder_input.output_reference), as_data(base_redeemer)),
      Pair(Mint(test_own_policy), as_data(mint_redeemer)),
      Pair(Withdraw(test_tp_cred), as_data(tp_redeemer)),
    ],
  }
  Composed { tx, mint_redeemer, base_redeemer, tp_redeemer }
}

fn mint_ok(c: Composed) -> Bool {
  call_validator(c.mint_redeemer, c.tx)
}

fn base_ok(c: Composed) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    test_params_policy,
    None,
    c.base_redeemer,
    Void,
    c.tx,
  )
}

fn third_party_ok(c: Composed) -> Bool {
  third_party.third_party.withdraw(
    test_params_policy,
    c.tp_redeemer,
    test_tp_cred,
    c.tx,
  )
}

// Positive: seize 40 + mint 100 → 140 in PLB custody; all three pass.
test composed_seize_mint_all_three_validators_pass() {
  let c = composed_seize_mint(
    40,
    100,
    False,
    test_issuer_3p_cred,
    [seized_output(140)],
  )
  and {
    mint_ok(c),
    base_ok(c),
    third_party_ok(c),
  }
}

// Mutation: ONE of the 140 tokens escapes to a non-PLB output. issuance_mint
// still delegates (the third_party redeemer names our node) and PLB still
// dispatches (the witnessed withdrawal IS the third_party credential) — the
// rejection comes from `third_party` alone: its conservation check finds 139
// at PLB against 40 seized + 100 minted, and returns False (no abort), so
// the other two verdicts are asserted in the same expression.
test composed_seize_mint_one_token_escape_rejected_by_third_party() {
  let c = composed_seize_mint(
    40,
    100,
    False,
    test_issuer_3p_cred,
    [seized_output(139), escaped_token_output()],
  )
  and {
    mint_ok(c),
    base_ok(c),
    !third_party_ok(c),
  }
}

/// Random seize-with-mint shape: `held` 1..1e9; `delta` in (-held, 1e9] minus
/// zero (a burn never empties the custody output, so the conservation check
/// keeps a non-trivial target); either reference-input order; and an issuer
/// credential that sorts the framework third_party credential to withdrawal
/// index 1 or 2.
fn composed_shape() -> Fuzzer<(Int, Int, Bool, Credential)> {
  let held <- fuzz.and_then(fuzz.int_between(1, 1_000_000_000))
  let delta <- fuzz.and_then(
    fuzz.such_that(fuzz.int_between(1 - held, 1_000_000_000), fn(d) { d != 0 }),
  )
  let coordination_first <- fuzz.and_then(fuzz.bool())
  let issuer_late <- fuzz.map(fuzz.bool())
  let issuer_3p_cred = if issuer_late {
    test_issuer_3p_cred_late
  } else {
    test_issuer_3p_cred
  }
  (held, delta, coordination_first, issuer_3p_cred)
}

// For any quantities and any index placement, the composed positive tx passes
// all three validators.
test composed_seize_mint_holds_for_any_quantities_and_placement(
  (held, delta, coordination_first, issuer_3p_cred) via composed_shape(),
) {
  let c = composed_seize_mint(
    held,
    delta,
    coordination_first,
    issuer_3p_cred,
    [seized_output(held + delta)],
  )
  and {
    mint_ok(c),
    base_ok(c),
    third_party_ok(c),
  }
}

// ...and for any of those shapes, a one-token escape is rejected by
// `third_party` while issuance_mint and PLB still pass.
test composed_seize_mint_escape_rejected_for_any_quantities_and_placement(
  (held, delta, coordination_first, issuer_3p_cred) via composed_shape(),
) {
  let c = composed_seize_mint(
    held,
    delta,
    coordination_first,
    issuer_3p_cred,
    [seized_output(held + delta - 1), escaped_token_output()],
  )
  and {
    mint_ok(c),
    base_ok(c),
    !third_party_ok(c),
  }
}

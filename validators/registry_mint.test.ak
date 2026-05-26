//// Tests for the registry_mint validator.
//// Invokes the validator's mint handler directly, covering both
//// RegistryInit and RegistryInsert redeemer paths.

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Transaction,
}
use issuance_mint
use registry_mint
use registry_node.{RegistryNode, empty_vkey, origin_node_tn}
use types.{
  IssuanceCborHex, RefInput, RegisterAndMint, RegisterOnly, RegistryInit,
  RegistryInsert, RegistryRedeemer, SmartTokenMintingAction,
}
use utils.{apply_hashed_parameter}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref = OutputReference { transaction_id: #"00", output_index: 0 }

/// A fake issuance_cbor_hex currency symbol (28 bytes)
const test_issuance_cbor_hex_cs: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

/// The registry policy id (what registry_mint mints under)
const test_policy_id: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

/// Address for node outputs (simulates the registry script address)
const test_node_address =
  Address { payment_credential: Script(#"cccccccc"), stake_credential: None }

/// Address for a generic input
const test_input_address =
  Address { payment_credential: Script(#"dddddddd"), stake_credential: None }

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

/// Prefix / postfix for issuance script reconstruction
const test_prefix = #"0102"

const test_postfix = #"0304"

/// The 28-byte hash that the issuance template is parameterised with.
/// Doubles as:
///   * the inner hash of `test_inserted_minting_logic_cred` (see below),
///   * the `hashed_param` value used by `apply_hashed_parameter` to derive
///     `computed_key()`.
/// Keeping a single constant for both forces the cryptographic-binding
/// invariant `hash(minting_logic_script) == apply_hashed_parameter input`
/// to hold by construction in every test.
const test_hashed_param =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

/// Substandard minting-logic credential placed in the new RegistryNode's
/// `minting_logic_script` field AND in the matching `RegistryInsert`
/// redeemer. Its inner 28-byte hash equals `test_hashed_param`, so the
/// `is_programmable_token_id_valid` check passes.
const test_inserted_minting_logic_cred: Credential = Script(test_hashed_param)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build the 28-byte key that `is_programmable_token_id_valid` expects.
fn computed_key() -> ByteArray {
  apply_hashed_parameter(test_prefix, test_postfix, test_hashed_param)
}

/// Origin node output: key=#"", next=0xff…ff, empty credentials
fn origin_node_output() -> Output {
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(test_policy_id, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Build a covering node input (origin node as input)
fn covering_node_input() -> Input {
  Input {
    output_reference: OutputReference { transaction_id: #"01", output_index: 0 },
    output: Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(test_policy_id, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"",
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// Updated covering node output after insert: next → computed_key
fn updated_covering_node_output() -> Output {
  let key = computed_key()
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(test_policy_id, origin_node_tn, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: #"",
          next: key,
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: empty_vkey,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Inserted node output: key=computed_key, next=0xff…ff
fn inserted_node_output() -> Output {
  let key = computed_key()
  Output {
    address: test_node_address,
    value: min_ada
      |> assets.add(test_policy_id, key, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: Script(
            #"55555555555555555555555555555555555555555555555555555555",
          ),
          third_party_transfer_logic_script: Script(
            #"66666666666666666666666666666666666666666666666666666666",
          ),
          minting_logic_script: test_inserted_minting_logic_cred,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

/// Reference input carrying the IssuanceCborHex NFT
fn issuance_ref_input() -> Input {
  Input {
    output_reference: OutputReference { transaction_id: #"02", output_index: 0 },
    output: Output {
      address: test_input_address,
      value: min_ada
        |> assets.add(test_issuance_cbor_hex_cs, #"00", 1),
      datum: InlineDatum(
        as_data(
          IssuanceCborHex {
            prefix_cbor_hex: test_prefix,
            postfix_cbor_hex: test_postfix,
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// A basic input that spends test_utxo_ref (for one-shot check)
fn utxo_ref_input() -> Input {
  Input {
    output_reference: test_utxo_ref,
    output: Output {
      address: test_input_address,
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn call_init_validator(tx: Transaction) -> Bool {
  registry_mint.registry_mint.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    Script(#"cccccccc"),
    RegistryInit,
    test_policy_id,
    tx,
  )
}

fn call_insert_validator(redeemer: RegistryRedeemer, tx: Transaction) -> Bool {
  registry_mint.registry_mint.mint(
    test_utxo_ref,
    test_issuance_cbor_hex_cs,
    Script(#"cccccccc"),
    redeemer,
    test_policy_id,
    tx,
  )
}

// =========================================================================
// RegistryInit tests
// =========================================================================

// Shared base transaction for the RegistryInit pair. Used by:
//   * registry_init_valid             — positive
//   * registry_init_fails_wrong_origin_address — Finding 03 negative, spread
//     with the `outputs` field overridden.
// Anything that would change for one of those two tests must be edited here
// so they stay in lockstep.
fn valid_init_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [utxo_ref_input()],
    outputs: [origin_node_output()],
    mint: from_asset(test_policy_id, origin_node_tn, 1),
  }
}

// Happy path: consume utxo_ref, one origin node output, mint origin token
test registry_init_valid() {
  call_init_validator(valid_init_tx())
}

// utxo_ref not consumed in inputs
test registry_init_fails_utxo_not_consumed() fail {
  let other_input =
    Input {
      output_reference: OutputReference {
        transaction_id: #"ff",
        output_index: 99,
      },
      output: Output {
        address: test_input_address,
        value: min_ada,
        datum: NoDatum,
        reference_script: None,
      },
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [other_input],
      outputs: [origin_node_output()],
      mint: from_asset(test_policy_id, origin_node_tn, 1),
    }
  call_init_validator(tx)
}

// Origin node has non-empty key
test registry_init_fails_wrong_origin_key() fail {
  let bad_origin =
    Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(test_policy_id, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"aa",
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: empty_vkey,
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [utxo_ref_input()],
      outputs: [bad_origin],
      mint: from_asset(test_policy_id, origin_node_tn, 1),
    }
  call_init_validator(tx)
}

// No origin token minted
test registry_init_fails_no_mint() fail {
  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [utxo_ref_input()],
      outputs: [origin_node_output()],
      mint: assets.zero,
    }
  call_init_validator(tx)
}

// Finding 03 regression: origin output sent to an address other than the
// configured registry_spend credential. Pre-fix this would have passed
// (validate_directory_init did not bind the address), allowing the origin
// registry NFT to live at an attacker-controlled address.
//
// Companion to registry_init_valid — the only delta visible at the test
// body is the `outputs` override (wrong-address origin).
test registry_init_fails_wrong_origin_address() fail {
  let wrong_address_origin =
    Output { ..origin_node_output(), address: test_input_address }
  let tx = Transaction { ..valid_init_tx(), outputs: [wrong_address_origin] }
  call_init_validator(tx)
}

// =========================================================================
// RegistryInsert tests
// =========================================================================

fn valid_insert_redeemer() -> RegistryRedeemer {
  RegistryInsert {
    key: computed_key(),
    minting_logic_script: test_inserted_minting_logic_cred,
    mode: RegisterAndMint,
  }
}

fn valid_insert_tx() -> Transaction {
  let key = computed_key()
  Transaction {
    ..transaction.placeholder,
    inputs: [covering_node_input()],
    outputs: [updated_covering_node_output(), inserted_node_output()],
    reference_inputs: [issuance_ref_input()],
    // Must mint both the registry node token AND a programmable token under `key` as policy
    mint: from_asset(test_policy_id, key, 1)
      |> assets.add(key, #"746f6b656e", 100),
    // The substandard's withdraw-0 logic MUST be invoked at registration
    // (always required by registry_mint, both modes).
    withdrawals: [Pair(test_inserted_minting_logic_cred, 0)],
  }
}

// Happy path: valid covering node, computed key, both outputs, issuance ref input
test registry_insert_valid() {
  call_insert_validator(valid_insert_redeemer(), valid_insert_tx())
}

// No reference input with issuance_cbor_hex_cs token
test registry_insert_fails_no_issuance_ref_input() fail {
  let tx = Transaction { ..valid_insert_tx(), reference_inputs: [] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Key not covered: covering node key >= insert key
test registry_insert_fails_key_not_covered() fail {
  let key = computed_key()
  // Covering node with key > insert key, so insert key is NOT covered
  let bad_covering =
    Input {
      output_reference: OutputReference {
        transaction_id: #"01",
        output_index: 0,
      },
      output: Output {
        address: test_node_address,
        value: min_ada
          |> assets.add(test_policy_id, key, 1),
        datum: InlineDatum(
          as_data(
            RegistryNode {
              key,
              next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
              transfer_logic_script: Script(
                #"55555555555555555555555555555555555555555555555555555555",
              ),
              third_party_transfer_logic_script: Script(
                #"66666666666666666666666666666666666666666666666666666666",
              ),
              minting_logic_script: test_inserted_minting_logic_cred,
              global_state_cs: #"",
            },
          ),
        ),
        reference_script: None,
      },
    }
  let tx = Transaction { ..valid_insert_tx(), inputs: [bad_covering] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Key not 28 bytes
test registry_insert_fails_wrong_key_length() fail {
  let short_key = #"aabb"
  let rdmr =
    RegistryInsert {
      key: short_key,
      minting_logic_script: test_inserted_minting_logic_cred,
      mode: RegisterAndMint,
    }
  call_insert_validator(rdmr, valid_insert_tx())
}

// Covering node's transfer_logic_script changed in output (NEW-1 fix)
test registry_insert_fails_updated_node_modified() fail {
  let key = computed_key()
  // Updated covering output with modified transfer_logic_script
  let tampered_output =
    Output {
      address: test_node_address,
      value: min_ada
        |> assets.add(test_policy_id, origin_node_tn, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: #"",
            next: key,
            // Changed from empty_vkey to a different script!
            transfer_logic_script: Script(
              #"99999999999999999999999999999999999999999999999999999999",
            ),
            third_party_transfer_logic_script: empty_vkey,
            minting_logic_script: empty_vkey,
            global_state_cs: #"",
          },
        ),
      ),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [tampered_output, inserted_node_output()],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// RegisterAndMint redeemer applied to a tx with empty mint. Fails the
// mode ↔ tx.mint consistency check: `mint_has_policy(self.mint, key)` is
// False, so the `RegisterAndMint ⇒ mint_has_policy(...) == True` branch
// rejects.
test registry_insert_fails_no_token_minted() fail {
  let tx = Transaction { ..valid_insert_tx(), mint: assets.zero }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Only one node output instead of two
test registry_insert_fails_single_output() fail {
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output()],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 03 regression (Insert side): one of the new node outputs sits at
// a different address than the covering input. Pre-fix the address binding
// only kicked in at Init; the Insert path's inductive chain was undocumented
// and untested. Post-fix `validate_directory_node_output` asserts
// `output.address == covering_input.output.address`, so any drift fails.
test registry_insert_fails_wrong_output_address() fail {
  let wrong_inserted =
    Output { ..inserted_node_output(), address: test_input_address }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output(), wrong_inserted],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// RegistrationMode tests
//
// `RegistryInsert` carries a `mode: RegistrationMode` field that selects
// between:
//   * `RegisterAndMint` — registration + first mint in one tx (the existing
//     `valid_insert_tx` / `valid_insert_redeemer` flow, covered above).
//   * `RegisterOnly`    — substandard authorises registration but no
//     programmable tokens of `key` are minted. Useful for RWA, supply-aware
//     substandards that need to initialise global state before any token
//     exists, etc.
//
// In BOTH modes the substandard's `minting_logic_script` MUST appear in
// `tx.withdrawals` (proof of instance, always required). The two modes
// differ only in the `tx.mint` shape under the new policy.
//
// Coverage in this block:
//   1. Mode A happy path (mirror of the Mode B happy path above).
//   2. Mode A vs Mode B mint-shape mismatches (both directions of the
//      mode ↔ tx.mint consistency check).
//   3. Substandard-not-invoked failures (per mode).
//   4. Datum-vs-redeemer mismatch on the new `minting_logic_script` field
//      (defense-in-depth #2).
//   5. Cryptographic binding failure (correct field shape, wrong content).
// =========================================================================

/// Mode A redeemer — same shape as `valid_insert_redeemer` but
/// `mode = RegisterOnly`.
fn valid_register_only_redeemer() -> RegistryRedeemer {
  RegistryInsert {
    key: computed_key(),
    minting_logic_script: test_inserted_minting_logic_cred,
    mode: RegisterOnly,
  }
}

/// Mode A transaction — same shape as `valid_insert_tx` but the mint
/// value carries ONLY the registry NFT (no entries under `key`).
fn valid_register_only_tx() -> Transaction {
  let key = computed_key()
  Transaction {
    ..valid_insert_tx(),
    // RegisterOnly: only the registry node NFT is minted; no programmable
    // tokens of `key`.
    mint: from_asset(test_policy_id, key, 1),
  }
}

// Mode A happy path: substandard invoked via withdraw-0, no programmable
// tokens of `key` in mint, mode ↔ tx.mint consistency holds.
test registry_insert_register_only_valid() {
  call_insert_validator(
    valid_register_only_redeemer(),
    valid_register_only_tx(),
  )
}

// Mode ↔ tx.mint consistency: the redeemer claims RegisterOnly but the
// transaction also mints programmable tokens of `key`. `registry_mint`
// MUST reject — this catches "I said register-only but actually I'm
// minting" misuse.
test registry_insert_mode_a_fails_with_tokens_minted() fail {
  // Mode A redeemer applied to a Mode B tx (mints tokens under `key`).
  call_insert_validator(valid_register_only_redeemer(), valid_insert_tx())
}

// Mode ↔ tx.mint consistency, other direction: the redeemer claims
// RegisterAndMint but the transaction mints no tokens of `key`. Catches
// "I said register-and-mint but actually no tokens are being minted"
// misuse.
test registry_insert_mode_b_fails_without_tokens_minted() fail {
  // Mode B redeemer applied to a Mode A tx (no tokens under `key`).
  call_insert_validator(valid_insert_redeemer(), valid_register_only_tx())
}

// Substandard withdraw-0 not invoked (Mode A): registry_mint MUST reject
// even though all other invariants hold. Without this check the registrar
// could pin any substandard credential into a registry node the
// substandard itself never authorised.
test registry_insert_mode_a_fails_substandard_not_invoked() fail {
  let tx = Transaction { ..valid_register_only_tx(), withdrawals: [] }
  call_insert_validator(valid_register_only_redeemer(), tx)
}

// Substandard withdraw-0 not invoked (Mode B): same protection in Mode B.
// In a real Mode B tx `issuance_mint` would also require the substandard
// withdrawal (transitively, because tokens are minted), but `registry_mint`
// MUST enforce it directly so the protection doesn't depend on
// `issuance_mint` behaviour or on tokens actually being minted.
test registry_insert_mode_b_fails_substandard_not_invoked() fail {
  let tx = Transaction { ..valid_insert_tx(), withdrawals: [] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Defense-in-depth #2: the new node's datum `minting_logic_script` MUST
// equal the redeemer's `minting_logic_script`. A registrar that claims
// one credential in the redeemer but writes a different one into the
// datum is rejected.
test registry_insert_fails_datum_minting_logic_mismatch() fail {
  let key = computed_key()
  let wrong_cred =
    Script(#"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead")
  let mismatched_inserted =
    Output {
      ..inserted_node_output(),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            minting_logic_script: wrong_cred,
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
    }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output(), mismatched_inserted],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Cryptographic binding: the redeemer's `minting_logic_script`'s inner
// hash MUST be the value `apply_hashed_parameter` produces the policy id
// from. Here we supply a credential whose hash ≠ `test_hashed_param`;
// `is_programmable_token_id_valid` rejects.
//
// Both the redeemer AND the datum carry the wrong credential — that
// keeps defense-in-depth #2 satisfied so this test isolates the binding
// failure (not the datum/redeemer mismatch).
test registry_insert_fails_wrong_minting_logic_for_key() fail {
  let wrong_cred =
    Script(#"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead")
  let inserted_with_wrong_cred =
    Output {
      ..inserted_node_output(),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: computed_key(),
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            minting_logic_script: wrong_cred,
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
    }
  let rdmr =
    RegistryInsert {
      key: computed_key(),
      minting_logic_script: wrong_cred,
      mode: RegisterAndMint,
    }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output(), inserted_with_wrong_cred],
      // wrong_cred must be invoked too, otherwise the test would fail
      // at the substandard-invocation check instead of the binding check.
      withdrawals: [Pair(wrong_cred, 0)],
    }
  call_insert_validator(rdmr, tx)
}

// Finding 07: the substandard-invocation check matches BY credential —
// having *some* other substandard withdraw in the same tx does not
// authorise this registration. Companion to
// `registry_insert_mode_b_fails_substandard_not_invoked` (which uses
// `withdrawals: []`) — this test uses a non-empty withdrawals list
// containing the WRONG credential, isolating the "must match
// minting_logic_script" property.
test registry_insert_fails_wrong_substandard_in_withdrawals() fail {
  let other_cred =
    Script(#"abababababababababababababababababababababababababababab")
  let tx =
    Transaction { ..valid_insert_tx(), withdrawals: [Pair(other_cred, 0)] }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 07: the substandard-invocation check uses `list.any`
// semantics — the substandard's withdrawal must be PRESENT, not SOLE.
// Multiple reward addresses withdrawing in the same tx are fine;
// registration succeeds as long as `minting_logic_script` appears
// somewhere in `tx.withdrawals`. Locks in that the new check composes
// with unrelated stake activity in the same block.
test registry_insert_succeeds_substandard_among_other_withdrawals() {
  let other_cred =
    Script(#"abababababababababababababababababababababababababababab")
  let other_vk_cred =
    VerificationKey(#"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd")
  let tx =
    Transaction {
      ..valid_insert_tx(),
      withdrawals: [
        Pair(other_cred, 0), Pair(test_inserted_minting_logic_cred, 0),
        Pair(other_vk_cred, 1_000_000),
      ],
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// Finding 07 + post-fix tightening: substandards MUST be `Script`
// credentials. A `VerificationKey`-credentialed redeemer is rejected
// by `is_programmable_token_id_valid` (lib/utils.ak) even when all
// structural invariants are otherwise satisfied — datum/redeemer
// equality holds (both carry the same VK), the credential appears in
// `tx.withdrawals`, the inner hash equals `test_hashed_param` so the
// hash-derivation would compute the correct policy id. The only
// failure point is the `expect Script(_)` in
// `is_programmable_token_id_valid`.
test registry_insert_fails_verification_key_substandard() fail {
  let vk_cred: Credential = VerificationKey(test_hashed_param)
  let inserted_with_vk =
    Output {
      ..inserted_node_output(),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: computed_key(),
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            minting_logic_script: vk_cred,
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
    }
  let rdmr =
    RegistryInsert {
      key: computed_key(),
      minting_logic_script: vk_cred,
      mode: RegisterAndMint,
    }
  let tx =
    Transaction {
      ..valid_insert_tx(),
      outputs: [updated_covering_node_output(), inserted_with_vk],
      withdrawals: [Pair(vk_cred, 0)],
    }
  call_insert_validator(rdmr, tx)
}

// =========================================================================
// CIP-68 multi-asset registration
//
// registry_mint allows multiple asset names under the same policy in
// `tx.mint` to support CIP-68 (FT label 333 + ref token label 100).
// `mint_has_policy` (lib/utils.ak) checks policy presence only — asset
// name and quantity are unconstrained — so additional CIP-68 companion
// assets minted in the same tx do not affect the registration check.
// =========================================================================

// CIP-67 label 333 (FT) prefix + "MyToken" hex
const cip68_ft_name = #"000f41414d79546f6b656e"

// CIP-67 label 100 (reference) prefix + "MyToken" hex
const cip68_ref_name = #"000643b04d79546f6b656e"

// Happy path: register with CIP-68 dual-token mint (FT + ref token)
test registry_insert_cip68_dual_token_mint() {
  let key = computed_key()
  let tx =
    Transaction {
      ..valid_insert_tx(),
      mint: from_asset(test_policy_id, key, 1)
        |> assets.add(key, cip68_ft_name, 1_000_000)
        |> assets.add(key, cip68_ref_name, 1),
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// Mint-shape edge cases under RegisterAndMint
//
// `mint_has_policy` (the unified primitive) returns True iff `tx.mint`
// contains ANY entry under the new policy id, regardless of sign. This is
// a looser check than the previous "at least one positive quantity" — and
// is safe because burn-only of a brand-new policy is ledger-impossible
// (no prior tokens exist to burn). See `lib/utils.ak` for the rationale.
//
// Consequence: a transaction whose only entry under `key` is a burn now
// passes the mode-consistency check at the on-chain level. The ledger
// will reject it anyway when no inputs balance the burn. The previously
// explicit `registry_insert_fails_burn_only` test is therefore obsolete
// and has been removed; the property it tested is enforced by the
// ledger, not by registry_mint.
// =========================================================================

// Mixed mint+burn under the new policy: at least one entry exists — passes
// `mint_has_policy`. (Was also passing under the old `> 0` check
// because the FT name has positive quantity; kept here as a sanity check
// that mixed-sign entries don't break the new primitive.)
test registry_insert_mixed_mint_and_burn() {
  let key = computed_key()
  let tx =
    Transaction {
      ..valid_insert_tx(),
      mint: from_asset(test_policy_id, key, 1)
        |> assets.add(key, cip68_ft_name, 1_000_000)
        |> assets.add(key, #"6f6c64746f6b656e", -50),
    }
  call_insert_validator(valid_insert_redeemer(), tx)
}

// =========================================================================
// CIP-68 subsequent mint (RefInput registry proof) in issuance_mint
//
// Exercises issuance_mint with CIP-68 dual-token mint + RefInput proof,
// covering the path where the registry already exists from a prior insert.
// =========================================================================

// issuance_mint validator params
const ism_plb_cred: Credential =
  Script(#"aa11111111111111111111111111111111111111111111111111111111")

const ism_registry_cs: PolicyId =
  #"aa22222222222222222222222222222222222222222222222222222222"

const ism_ml_cred: Credential =
  Script(#"aa33333333333333333333333333333333333333333333333333333333")

const ism_plg_cred: Credential =
  Script(#"aa55555555555555555555555555555555555555555555555555555555")

const ism_own_policy: PolicyId =
  #"aa44444444444444444444444444444444444444444444444444444444"

fn ism_registry_node_output() -> Output {
  Output {
    address: Address {
      payment_credential: Script(
        #"aa88888888888888888888888888888888888888888888888888888888",
      ),
      stake_credential: None,
    },
    value: min_ada
      |> assets.add(ism_registry_cs, ism_own_policy, 1),
    datum: InlineDatum(
      as_data(
        RegistryNode {
          key: ism_own_policy,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: Script(
            #"aa66666666666666666666666666666666666666666666666666666666",
          ),
          third_party_transfer_logic_script: Script(
            #"aa77777777777777777777777777777777777777777777777777777777",
          ),
          // Must match the `ism_ml_cred` parameter passed to call_issuance_validator
          // (defense-in-depth #3: issuance_mint asserts this equals its
          // `minting_logic_cred` parameter).
          minting_logic_script: ism_ml_cred,
          global_state_cs: #"",
        },
      ),
    ),
    reference_script: None,
  }
}

fn ism_ref_input() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output: ism_registry_node_output(),
  }
}

fn ism_plb_output(value: assets.Value) -> Output {
  Output {
    address: Address {
      payment_credential: ism_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"aa99999999999999999999999999999999999999999999999999999999"),
        ),
      ),
    },
    value,
    datum: InlineDatum(Void),
    reference_script: None,
  }
}

fn call_issuance_validator(
  rdmr: SmartTokenMintingAction,
  tx: Transaction,
) -> Bool {
  issuance_mint.issuance_mint.mint(
    ism_plb_cred,
    ism_registry_cs,
    ism_ml_cred,
    ism_plg_cred,
    rdmr,
    ism_own_policy,
    tx,
  )
}

// CIP-68 subsequent mint with RefInput: FT + ref token, registry already exists
test cip68_subsequent_mint_ref_input() {
  let rdmr =
    SmartTokenMintingAction {
      minting_logic_cred: ism_ml_cred,
      minting_registry_proof: RefInput(0),
    }
  let tx =
    Transaction {
      ..transaction.placeholder,
      reference_inputs: [ism_ref_input()],
      outputs: [
        ism_plb_output(
          min_ada
            |> assets.add(ism_own_policy, cip68_ft_name, 500),
        ),
        ism_plb_output(
          min_ada
            |> assets.add(ism_own_policy, cip68_ref_name, 1),
        ),
      ],
      mint: from_asset(ism_own_policy, cip68_ft_name, 500)
        |> assets.add(ism_own_policy, cip68_ref_name, 1),
      withdrawals: [Pair(ism_ml_cred, 0)],
      redeemers: [Pair(Mint(ism_own_policy), as_data(rdmr))],
    }
  call_issuance_validator(rdmr, tx)
}

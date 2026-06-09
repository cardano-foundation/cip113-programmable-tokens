//// End-to-end benchmarks for the issuance_mint validator.
////
//// Issuance_mint isn't exercised by `programmable_logic/benchmarks.ak`
//// (which only invokes PLGlobal). This file measures the per-tx cost of
//// the precise delegation check (Finding 04 fix): the scope walk over
//// PLGlobal's TransferAct `proofs` list to decide "is the same registry
//// node named?" before delegating to PLGlobal.
////
//// The sampler scales the size of PLGlobal's `proofs` list while placing
//// our match (`TokenExists { node_idx: 0 }`) at the END — worst case for
//// `list.any` short-circuit. Slope tells us cost per non-matching proof
//// entry. Y-intercept tells us the constant cost of the precise check
//// (redeemer lookup + decode + index compare).
////
//// Run with `aiken bench -m issuance_mint_benchmarks`.

use aiken/collection/list
use aiken/fuzz
use cardano/address.{Address, Inline, Script}
use cardano/assets.{
  ada_asset_name, ada_policy_id, from_asset,
}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Transaction,
  Withdraw,
}
use issuance_mint
use registry_node.{RegistryNode, empty_vkey}
use types.{MintingRegistryProof, RefInput, TokenExists, TransferAct}

// ---------------------------------------------------------------------------
// Test constants (mirrored from issuance_mint.test.ak)
// ---------------------------------------------------------------------------

const test_plb_cred = Script(#"11111111111111111111111111111111111111111111111111111111")

const test_registry_cs =
  #"22222222222222222222222222222222222222222222222222222222"

const test_ml_cred =
  Script(#"33333333333333333333333333333333333333333333333333333333")

const test_plg_cred =
  Script(#"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1")

const test_own_policy: ByteArray =
  #"44444444444444444444444444444444444444444444444444444444"

const test_token_name = #"746f6b656e"

const dummy_other_policy: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

const min_ada =
  assets.zero |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

const dummy_oref =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

/// Registry node ref input for `test_own_policy`, at position 0.
fn registry_node_ref_input() -> Input {
  Input {
    output_reference: dummy_oref,
    output: Output {
      address: Address {
        payment_credential: Script(
          #"88888888888888888888888888888888888888888888888888888888",
        ),
        stake_credential: None,
      },
      value: min_ada |> assets.add(test_registry_cs, test_own_policy, 1),
      datum: InlineDatum(
        RegistryNode {
          key: test_own_policy,
          next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          transfer_logic_script: empty_vkey,
          third_party_transfer_logic_script: empty_vkey,
          minting_logic_script: test_ml_cred,
          global_state_cs: #"",
        },
      ),
      reference_script: None,
    },
  }
}

fn plb_input_with_policy() -> Input {
  Input {
    output_reference: dummy_oref,
    output: Output {
      address: Address {
        payment_credential: test_plb_cred,
        stake_credential: Some(
          Inline(
            Script(
              #"77777777777777777777777777777777777777777777777777777777",
            ),
          ),
        ),
      },
      value: min_ada |> assets.add(test_own_policy, test_token_name, 100),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn plb_output_with_policy(qty: Int) -> Output {
  Output {
    address: Address {
      payment_credential: test_plb_cred,
      stake_credential: Some(
        Inline(
          Script(#"77777777777777777777777777777777777777777777777777777777"),
        ),
      ),
    },
    value: min_ada |> assets.add(test_own_policy, test_token_name, qty),
    datum: NoDatum,
    reference_script: None,
  }
}

fn invoke_issuance(self: Transaction, redeemer: MintingRegistryProof) -> Bool {
  issuance_mint.issuance_mint.mint(
    test_plb_cred,
    test_registry_cs,
    test_ml_cred,
    test_plg_cred,
    redeemer,
    test_own_policy,
    self,
  )
}

// ---------------------------------------------------------------------------
// Sampler: scale PLGlobal's TransferAct `proofs` list with the match at the
// END (worst case for `list.any` short-circuit). One PLB input + one PLB
// output + +50 mint of our policy. issuance_mint delegates iff the proofs
// list contains `TokenExists { node_idx: 0 }`.
// ---------------------------------------------------------------------------

fn sample_delegate_transferact(
  size: Int,
) -> Fuzzer<(Transaction, MintingRegistryProof)> {
  // Build proofs = [dummy, dummy, ..., dummy, match] of length `size + 1`.
  // `dummy` proofs point at a different (unrelated) ref-input index;
  // PLGlobal would never accept them at runtime, but issuance_mint doesn't
  // care about that — we're only measuring its scope walk.
  let dummy_proof = TokenExists { node_idx: 9999 }
  let extra_proofs = list.repeat(dummy_proof, size)
  let match_proof = TokenExists { node_idx: 0 }
  let proofs = list.concat(extra_proofs, [match_proof])

  let rdmr = RefInput { index: 0 }

  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [plb_input_with_policy()],
      reference_inputs: [registry_node_ref_input()],
      outputs: [plb_output_with_policy(150)],
      mint: from_asset(test_own_policy, test_token_name, 50),
      withdrawals: [Pair(test_ml_cred, 0), Pair(test_plg_cred, 0)],
      redeemers: [
        Pair(Mint(test_own_policy), as_data(rdmr)),
        Pair(Withdraw(test_plg_cred), as_data(TransferAct { proofs })),
      ],
    }
  fuzz.constant((tx, rdmr))
}

bench delegate_transferact_many_proofs(
  (tx, redeemer) via sample_delegate_transferact,
) {
  invoke_issuance(tx, redeemer)
}

// ---------------------------------------------------------------------------
// Sampler: PLGlobal not invoked at all (no Withdraw redeemer). issuance_mint
// falls through to `validate_mint_outputs` which walks `tx.outputs`. Scale
// the output count to measure that fallback path.
// ---------------------------------------------------------------------------

fn sample_no_delegate_many_outputs(
  size: Int,
) -> Fuzzer<(Transaction, MintingRegistryProof)> {
  // Distribute the +50 mint across (size + 1) PLB outputs, varying the
  // qty per output so the totals add up.
  let n = size + 1
  let qty_per_output = 50 / n
  let remainder = 50 % n
  let outputs =
    list.repeat(plb_output_with_policy(qty_per_output), n - 1)
      |> list.concat([plb_output_with_policy(qty_per_output + remainder)])

  let rdmr = RefInput { index: 0 }

  let tx =
    Transaction {
      ..transaction.placeholder,
      inputs: [],
      reference_inputs: [registry_node_ref_input()],
      outputs: outputs,
      mint: from_asset(test_own_policy, test_token_name, 50),
      // Only minting-logic withdrawal — no PLGlobal.
      withdrawals: [Pair(test_ml_cred, 0)],
      redeemers: [Pair(Mint(test_own_policy), as_data(rdmr))],
    }
  fuzz.constant((tx, rdmr))
}

bench no_delegate_many_outputs(
  (tx, redeemer) via sample_no_delegate_many_outputs,
) {
  invoke_issuance(tx, redeemer)
}

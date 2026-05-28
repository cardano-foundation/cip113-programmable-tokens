//// # Finding 02 — `transfer_logic_script` enforced for PURELY minted tokens
////
//// Run only this module:
////
//// ```sh
//// aiken build
//// aiken check -m finding_02       # the two finding_02_* regression guards
//// aiken check -m _mint_           # the positives + true negative
//// ```
////
//// ---------------------------------------------------------------------------
//// ## What Finding 02 said, and how the fix realigned the code
//// ---------------------------------------------------------------------------
////
//// `programmable_logic_global.validate_transfer` used to fold `tx.mint` into
//// the same accumulator as PLB inputs in `collect_input_assets`, so
//// `verify_proofs` ran the per-policy `transfer_logic_script` enforcement on
//// every policy in that accumulator — INCLUDING policies that only appeared
//// in `tx.mint`. Pure mints were therefore wrongly required to invoke a
//// transfer-logic script and to carry a `TransferAct` proof.
////
//// The fix (`lib/programmable_logic/transfer.ak` —
//// `apply_mint_to_known_policies`) makes `collect_input_assets` seed empty
//// and then folds mint deltas in only for policies that already appear in
//// PLB inputs. Mint-only policies are dropped: they belong to
//// `issuance_mint`, not the transfer path.
////
//// ## Two facets of the new contract that the tests below pin
////
////   1. Pure mints PASS through PLGlobal regardless of whether the
////      `transfer_logic` withdraw-0 is present.
////   2. Pure mints must NOT carry a TransferAct proof — strict 1:1
////      proof-to-input-policy is preserved, so a stale proof for a
////      pure-mint policy is now leftover and rejected.
////
//// ## Test layout (per CLAUDE.md conventions: spread + one delta per failure)
////
////   * 3 positive tests pin the fixed behaviour:
////       - `mint_and_transfer_ideal_succeeds`
////         (the cross-validator "both run" ideal)
////       - `finding_02_pure_mint_succeeds`
////         (the clean post-fix demo: no transfer_logic, no proof)
////       - `finding_02_pure_mint_succeeds_with_transfer_logic_invoked`
////         (the previous workaround is still tolerated — extra withdrawals
////          are harmless)
////
////   * 2 `fail` guardrails (both stay failing — these are CORRECT rejections):
////       - `pure_mint_with_stale_transfer_proof_rejected`
////         (strict proof contract preserved)
////       - `mint_without_minting_logic_invocation_rejected`
////         (issuance_mint contract unchanged)

use cardano/address.{Address, Credential, Inline, Script}
use cardano/assets.{PolicyId, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use issuance_mint
use programmable_logic/fixture
use programmable_logic_global
use registry_node.{RegistryNode}
use types.{
  MintingRegistryProof, ProgrammableLogicGlobalRedeemer, RefInput, TokenExists,
  TransferAct,
}

// ===========================================================================
// Constants
// ===========================================================================

/// The programmable token policy under test ("FOO").
const foo_policy: PolicyId =
  #"00000000000000000000000000000000000000000000000000000f00"

const foo_name: ByteArray = "FOO"

const linked_list_end: ByteArray =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

/// The credential issuance_mint is parameterised with as `minting_logic_cred`.
const credential_minting_logic: Credential =
  Script(#"000000000000000000000000000000000000000000000000000a1d0c")

/// Any 28-byte script credential; address of the registry-node ref input.
const registry_holder_address_cred: Credential =
  Script(#"00000000000000000000000000000000000000000000000000beef00")

const dummy_oref: OutputReference =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }

// ===========================================================================
// Fixtures
//
// Two named base transactions:
//   * `ideal_tx`       — transfer + mint of the same policy (the "both run"
//                        ideal happy path).
//   * `pure_mint_tx`   — minimal pure-mint base that PASSES under the fix:
//                        only `global` + `minting_logic` withdrawals, no
//                        `transfer_logic` (not needed for a pure mint).
//
// Every other test spreads one of these and overrides EXACTLY one field.
// ===========================================================================

/// Registry node ref input for `foo_policy`, crafted to satisfy BOTH
/// validators (NFT name == own_policy == datum.key).
fn foo_registry_node() -> Input {
  Input {
    output_reference: dummy_oref,
    output: Output {
      address: Address {
        payment_credential: registry_holder_address_cred,
        stake_credential: None,
      },
      value: fixture.min_ada_value
        |> assets.add(fixture.policy_tokens_registry, foo_policy, 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key: foo_policy,
            next: linked_list_end,
            minting_logic_script: credential_minting_logic,
            transfer_logic_script: fixture.credential_transfer_logic,
            third_party_transfer_logic_script: fixture.credential_3rd_party_logic,
            global_state_cs: "",
          },
        ),
      ),
      reference_script: None,
    },
  }
}

fn base_ref_inputs() -> List<Input> {
  [
    fixture.some_reference_input_protocol_params(fixture.protocol_params, "pp"),
    foo_registry_node(),
  ]
}

/// IDEAL scenario: transfer 100 FOO from PLB + mint +50 FOO, yielding
/// 150 FOO at PLB. Exercises BOTH validators on the canonical happy path.
fn ideal_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(foo_policy, foo_name, 100)],
        "transfer input",
      ),
    ],
    mint: from_asset(foo_policy, foo_name, 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(foo_policy, foo_name, 150)],
      ),
    ],
    reference_inputs: base_ref_inputs(),
    withdrawals: [
      Pair(fixture.credential_validator_logic_global, 0),
      Pair(fixture.credential_transfer_logic, 0),
      Pair(credential_minting_logic, 0),
    ],
  }
}

/// PURE-MINT base, minimal post-fix shape: no FOO in inputs, +50 FOO minted,
/// routed to PLB. Withdrawals carry ONLY `global` + `minting_logic`
/// (transfer_logic is no longer required for pure mints).
fn pure_mint_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [],
    mint: from_asset(foo_policy, foo_name, 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(foo_policy, foo_name, 50)],
      ),
    ],
    reference_inputs: base_ref_inputs(),
    withdrawals: [
      Pair(fixture.credential_validator_logic_global, 0),
      Pair(credential_minting_logic, 0),
    ],
  }
}

/// Redeemer for the IDEAL tx: one proof for the transferred (and co-minted)
/// FOO policy.
fn transfer_redeemer() -> ProgrammableLogicGlobalRedeemer {
  TransferAct { proofs: [TokenExists { node_idx: 1 }] }
}

/// Redeemer for the PURE-MINT tx: no proofs (FOO is now invisible to the
/// transfer path because the fix drops mint-only policies from input_assets).
fn no_proofs_redeemer() -> ProgrammableLogicGlobalRedeemer {
  TransferAct { proofs: [] }
}

fn mint_redeemer() -> MintingRegistryProof {
  // Index 1 in reference_inputs = foo_registry_node().
  RefInput(1)
}

/// Run BOTH validators against the same transaction and AND the results.
fn run_both(
  tx: Transaction,
  transfer_rdmr: ProgrammableLogicGlobalRedeemer,
) -> Bool {
  and {
    issuance_mint.issuance_mint.mint(
      fixture.credential_validator_logic_base,
      fixture.policy_tokens_registry,
      credential_minting_logic,
      fixture.credential_validator_logic_global,
      mint_redeemer(),
      foo_policy,
      tx,
    ),
    programmable_logic_global.programmable_logic_global.withdraw(
      fixture.policy_protocol_params,
      transfer_rdmr,
      fixture.credential_validator_logic_global,
      tx,
    ),
  }
}

// ===========================================================================
// POSITIVE tests
// ===========================================================================

/// The "ideal" happy path: 100 FOO transferred + 50 FOO minted, 150 FOO at
/// PLB. Mint deltas merge into the transferred policy via the new
/// `apply_mint_to_known_policies`; transfer_logic is invoked normally; both
/// validators accept.
test mint_and_transfer_ideal_succeeds() {
  run_both(ideal_tx(), transfer_redeemer())
}

/// Finding 02 — the clean post-fix demonstration. A pure mint routed to PLB
/// is accepted with NO transfer_logic withdraw-0 and NO TransferAct proof.
/// The mint-only policy is dropped from `input_assets`, so `verify_proofs`
/// has nothing to enforce. issuance_mint authorises the mint itself.
test finding_02_pure_mint_succeeds() {
  run_both(pure_mint_tx(), no_proofs_redeemer())
}

/// Finding 02 — extra withdrawals remain harmless. Spread of `pure_mint_tx`
/// with ONE delta: ADD a `transfer_logic` withdraw-0. The previous workaround
/// pattern (always invoke transfer_logic) is now unnecessary, but if a tx
/// builder still does it the tx is accepted (the withdraw is just not
/// consulted by `verify_proofs`).
test finding_02_pure_mint_succeeds_with_transfer_logic_invoked() {
  let tx =
    Transaction {
      ..pure_mint_tx(),
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
        Pair(credential_minting_logic, 0),
      ],
    }
  run_both(tx, no_proofs_redeemer())
}

// ===========================================================================
// `fail` guardrails — CORRECT rejections, must stay failing.
// ===========================================================================

/// Strict-proof contract preserved. Spread of `pure_mint_tx` with ONE delta:
/// the redeemer carries a `TokenExists` proof for FOO. Because FOO is now a
/// pure mint and dropped from `input_assets`, that proof is leftover; the
/// final `[] == verify_proofs(...)` check rejects. Prevents callers from
/// quietly handing PLGlobal proofs it has no business consuming.
test pure_mint_with_stale_transfer_proof_rejected() fail {
  run_both(pure_mint_tx(), transfer_redeemer())
}

/// issuance_mint contract unchanged. Spread of `pure_mint_tx` with ONE
/// delta: drop the `minting_logic` withdraw-0. issuance_mint's
/// `minting_logic_invoked` check fails. Provided as a contrast so that
/// `pure_mint_with_stale_transfer_proof_rejected` above is recognised as the
/// transfer-side guardrail and this one as the issuance-side guardrail.
test mint_without_minting_logic_invocation_rejected() fail {
  let tx =
    Transaction {
      ..pure_mint_tx(),
      withdrawals: [Pair(fixture.credential_validator_logic_global, 0)],
    }
  run_both(tx, no_proofs_redeemer())
}

//// # Finding 02 — `transfer_logic_script` enforced for PURELY minted tokens
////
//// Run only this module:
////
//// ```sh
//// aiken build
//// aiken check -m finding_02       # runs the two bug-pinning tests
//// aiken check -m _mint_           # runs the positives + true negative
//// ```
////
//// ---------------------------------------------------------------------------
//// ## What Finding 02 says
//// ---------------------------------------------------------------------------
////
//// `programmable_logic_global.validate_transfer` (via `collect_input_assets`)
//// folds `tx.mint` into the same accumulator as PLB inputs and then
//// `verify_proofs` runs `choose_registered_token_with` for EVERY policy in
//// that accumulator, including policies that only appear in `tx.mint`. That
//// means a purely-minted token is forced to:
////
////   1. carry a TransferAct proof, and
////   2. invoke its `transfer_logic_script` (the `expect has_withdrawal(...)`),
////
//// even though nothing of that policy is being transferred out of any smart
//// wallet. `issuance_mint` has already authorised the mint; this enforcement
//// is redundant at best and contradicts the intended separation of concerns.
////
//// ---------------------------------------------------------------------------
//// ## How this module proves it (and verifies the fix later)
//// ---------------------------------------------------------------------------
////
//// Every test calls BOTH validators (issuance_mint AND programmable_logic_global)
//// against the SAME transaction via `run_both`. Tests are derived from named
//// fixtures (`ideal_tx`, `pure_mint_tx`) using the spread operator with ONE
//// delta each, so the diff between a passing test and a failing test is the
//// invariant under test.
////
////   * POSITIVE tests — currently green and stay green after the fix:
////       - `mint_and_transfer_ideal_succeeds`
////       - `pure_mint_with_transfer_logic_invoked_succeeds`
////
////   * `Finding 02:` BUG tests — marked `fail`. They currently pass because
////     PLGlobal wrongly rejects. When the finding is fixed, PLGlobal will
////     accept and these `fail` tests will START FAILING — that flip is the
////     fix-verification signal. Then delete `fail` to keep them as positive
////     regression guards.
////       - `finding_02_pure_mint_rejected_without_transfer_logic`
////       - `finding_02_pure_mint_requires_redundant_proof`
////
////   * TRUE-NEGATIVE guardrail — marked `fail` and CORRECT to stay failing
////     after the fix. Provided as a contrast so the bug tests are not
////     confused with legitimate rejections.
////       - `mint_without_minting_logic_invocation_rejected`

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
/// issuance_mint requires a withdraw-0 under this credential — proof that the
/// substandard's minting logic ran. Distinct from the transfer-logic cred so
/// our tests can drop one without affecting the other.
const credential_minting_logic: Credential =
  Script(#"000000000000000000000000000000000000000000000000000a1d0c")

/// Any 28-byte script credential, used as the payment address of the
/// registry-node ref input. PLGlobal's getter and issuance_mint's
/// `verify_registry_node` both ignore this field.
const registry_holder_address_cred: Credential =
  Script(#"00000000000000000000000000000000000000000000000000beef00")

/// A throwaway OutputReference for fixtures — content irrelevant to validators.
const dummy_oref: OutputReference =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: 0,
  }

// ===========================================================================
// Fixtures
//
// Per CLAUDE.md testing conventions: named helpers + spread with ONE delta per
// failure test. The two base transactions are `ideal_tx` (transfer + mint) and
// `pure_mint_tx` (pure mint with the contradictory transfer-logic withdrawal
// still in place). Every other test spreads one of these and overrides exactly
// one field.
// ===========================================================================

/// Registry node ref input for `foo_policy`. Crafted to satisfy BOTH validators
/// in a single ref input:
///
///   * issuance_mint.verify_registry_node — NFT (registry_cs, foo_policy, 1)
///     via `has_nft_strict`, and `registry.key == foo_policy`.
///   * programmable_logic_global getter   — `peek_first` (first non-ada policy)
///     equals registry_cs, datum is InlineDatum; transfer path reads
///     `datum.key` and `transfer_logic_script` via the `with_...` continuation.
///
/// The repo's existing `fixture.some_reference_input_tokens_registry_node`
/// stores the NFT under `blake2b_256(key)`, which would fail issuance_mint's
/// strict name check. This local fixture stores it under `foo_policy` so both
/// validators accept it.
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

/// Reference-input list shared by every test:
///   [0] protocol params NFT (read by `with_programmable_logic_params`)
///   [1] foo registry node   (used by both validators; `node_idx: 1`)
fn base_ref_inputs() -> List<Input> {
  [
    fixture.some_reference_input_protocol_params(fixture.protocol_params, "pp"),
    foo_registry_node(),
  ]
}

/// Withdrawals for a fully-satisfied tx:
///   * PLGlobal stake (delegation signal AND `withdraw-0` invocation)
///   * transfer_logic_script (the one Finding 02 wrongly forces for pure mints)
///   * minting_logic_script  (substandard mint logic proof for issuance_mint)
fn full_withdrawals() -> Pairs<Credential, Int> {
  [
    Pair(fixture.credential_validator_logic_global, 0),
    Pair(fixture.credential_transfer_logic, 0),
    Pair(credential_minting_logic, 0),
  ]
}

/// IDEAL scenario: a transfer of 100 FOO from PLB combined with a +50 FOO
/// mint, yielding 150 FOO at PLB. Exercises BOTH validators on a legitimate
/// happy path.
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
    withdrawals: full_withdrawals(),
  }
}

/// PURE-MINT scenario (with the contradictory transfer-logic withdrawal still
/// present): no FOO in any input, only a +50 FOO mint routed to PLB. This is
/// the base for the bug tests below — each spreads it and drops one delta.
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
    withdrawals: full_withdrawals(),
  }
}

fn transfer_redeemer() -> ProgrammableLogicGlobalRedeemer {
  TransferAct { proofs: [TokenExists { node_idx: 1 }] }
}

fn mint_redeemer() -> MintingRegistryProof {
  // RefInput points into `reference_inputs` (index 1 = foo_registry_node).
  RefInput(1)
}

/// Run BOTH validators against the same transaction and AND the results.
/// This is the "ideal scenario" composition: a real CIP-113 transfer-plus-mint
/// is only valid if BOTH issuance_mint AND programmable_logic_global accept it.
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
// POSITIVE tests — pass today and after the fix.
// ===========================================================================

/// The "ideal" happy path: 100 FOO transferred from PLB + 50 FOO minted,
/// yielding 150 FOO at PLB. Both validators run and accept.
test mint_and_transfer_ideal_succeeds() {
  run_both(ideal_tx(), transfer_redeemer())
}

/// A pure mint DOES work today — but only because we ALSO invoke the
/// `transfer_logic_script` (the `credential_transfer_logic` withdraw-0).
/// That requirement is itself the contradiction Finding 02 describes; the
/// next test removes the withdrawal to expose it.
test pure_mint_with_transfer_logic_invoked_succeeds() {
  run_both(pure_mint_tx(), transfer_redeemer())
}

// ===========================================================================
// `Finding 02:` BUG tests — `fail` today, will FLIP RED when the fix lands.
// ===========================================================================

/// Finding 02: a PURELY minted token is wrongly subjected to transfer_logic
/// enforcement. Spread of `pure_mint_tx` with ONE delta — drop the
/// `transfer_logic` withdraw-0. issuance_mint still authorises the mint, but
/// PLGlobal aborts on `expect has_withdrawal(transfer_logic_script)`.
/// Intended design: this tx SHOULD succeed (nothing is being transferred).
/// When Finding 02 is fixed, `run_both` will return True and this `fail` test
/// will start failing — that flip is the verification signal.
test finding_02_pure_mint_rejected_without_transfer_logic() fail {
  let tx =
    Transaction {
      ..pure_mint_tx(),
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(credential_minting_logic, 0),
      ],
    }
  run_both(tx, transfer_redeemer())
}

/// Finding 02 (second facet): even WITH transfer_logic invoked, the purely
/// minted policy is forced to carry a TransferAct proof. Spread of
/// `pure_mint_tx` with ONE delta — empty proofs. `verify_proofs` calls
/// `list.head(proofs)` for the minted policy and aborts.
///
/// NOTE: whether this specific rejection disappears after the fix depends on
/// how the balance-check half of `verify_proofs` is redesigned. The
/// transfer-logic facet above is the unambiguous flip; this one tracks the
/// redundant-proof complaint in the finding and may or may not flip.
test finding_02_pure_mint_requires_redundant_proof() fail {
  run_both(pure_mint_tx(), TransferAct { proofs: [] })
}

// ===========================================================================
// TRUE-NEGATIVE guardrail — `fail` today and PERMANENTLY correct.
// ===========================================================================

/// Correct rejection (NOT the bug). Spread of `pure_mint_tx` with ONE delta —
/// drop the `minting_logic` withdraw-0. issuance_mint's `minting_logic_invoked`
/// check fails. This rejection must REMAIN after Finding 02 is fixed; if it
/// ever flips, something else broke. Provided as a contrast so the
/// `finding_02_*` rejections are not confused with legitimate ones.
test mint_without_minting_logic_invocation_rejected() fail {
  let tx =
    Transaction {
      ..pure_mint_tx(),
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }
  run_both(tx, transfer_redeemer())
}

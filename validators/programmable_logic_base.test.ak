//// Tests for the programmable_logic_base validator.
//// PLB is parameterized by the protocol-params NFT policy: on every
//// spend it locates the params reference input, reads the CURRENT
//// delegate credential the redeemer arm names (`transfer_cred` field 2,
//// `third_party_cred` field 3, `unfracking_cred` field 4), and requires
//// that credential's withdraw-0 at the witnessed index. These tests verify
//// the trampoline check, the three-way dispatch, and the datum-driven
//// indirection that makes every delegate swappable in place.

use aiken/collection/list
use aiken/fuzz
use aiken/primitive/bytearray
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/fuzz as cardano
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use programmable_logic_base
use types.{SpendViaThirdParty, SpendViaTransfer, SpendViaUnfracking}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

/// The transfer-validator credential carried by `fixture.protocol_params`
/// (field 2).
const transfer_cred: Credential = fixture.credential_validator_transfer

const other_cred: Credential =
  Script(#"11223344112233441122334411223344112233441122334411223344")

/// A replacement transfer-validator credential, as an upgrade transaction
/// would write into the coordination datum.
const upgraded_transfer_cred: Credential =
  Script(#"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd")

/// The protocol-params datum shape BEFORE this refactor appended
/// `transfer_cred` — used to prove PLB rejects a datum that
/// lacks its field.
type LegacyThreeFieldParams {
  registry_node_cs: PolicyId,
  prog_logic_cred: Credential,
  unfracking_cred: Credential,
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    fixture.protocol_params,
    "protocol params",
  )
}

/// Params reference input whose datum carries `upgraded_transfer_cred` in
/// field 2 — the coordination UTxO after an in-place transfer-validator upgrade.
fn upgraded_params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    ProgrammableLogicGlobalParams {
      ..fixture.protocol_params,
      transfer_cred: upgraded_transfer_cred,
    },
    "protocol params",
  )
}

fn valid_plb_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [params_ref_input()],
    withdrawals: [Pair(transfer_cred, 0)],
  }
}

/// Happy-path harness: dispatch via the transfer arm with the params UTxO
/// and the transfer withdrawal both at index 0.
fn call_validator(tx: Transaction) -> Bool {
  call_transfer_at(tx, 0, 0)
}

/// SpendViaTransfer with explicit indices — for tests where the params UTxO is
/// not the first reference input, or the transfer withdrawal is not the first entry.
fn call_transfer_at(tx: Transaction, params_idx: Int, wdrl_idx: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    SpendViaTransfer { params_idx, wdrl_idx },
    Void,
    tx,
  )
}

/// SpendViaThirdParty with explicit indices — dispatch via the standalone
/// third_party validator's credential (params datum field 3).
fn call_third_party_at(tx: Transaction, params_idx: Int, wdrl_idx: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    SpendViaThirdParty { params_idx, wdrl_idx },
    Void,
    tx,
  )
}

// ---------------------------------------------------------------------------
// Trampoline check
// ---------------------------------------------------------------------------

// Passes when the transfer credential read from the params datum is in withdrawals
test plb_passes_when_datum_transfer_cred_in_withdrawals() {
  call_validator(valid_plb_tx())
}

// Fails when the transfer credential is absent from withdrawals
test plb_fails_when_transfer_cred_not_in_withdrawals() fail {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(other_cred, 0)] }
  call_validator(tx)
}

// Fails with empty withdrawals list
test plb_fails_with_empty_withdrawals() fail {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [] }
  call_validator(tx)
}

// Passes when the transfer credential is among multiple withdrawal entries — the
// redeemer witnesses its index (1), so no scan is needed.
test plb_passes_with_multiple_withdrawals() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [
      Pair(other_cred, 0),
      Pair(transfer_cred, 0),
      Pair(
        Script(#"99999999999999999999999999999999999999999999999999999999"),
        0,
      ),
    ],
  }
  // transfer withdrawal is the SECOND entry here → wdrl_idx = 1
  call_transfer_at(tx, 0, 1)
}

// The witnessed index is load-bearing: pointing it at a DIFFERENT (valid)
// withdrawal entry than the transfer credential fails. Here it sits at index 1 but
// the redeemer witnesses index 0 (other_cred), so the equality fails — a
// dishonest index can only invalidate the spend, never authorise a wrong one.
test plb_fails_when_wdrl_idx_points_at_wrong_entry() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(other_cred, 0), Pair(transfer_cred, 0)],
  }
  call_transfer_at(tx, 0, 0)
}

// Fails when credential type differs (VerificationKey vs Script)
test plb_fails_with_wrong_credential_type() fail {
  let vkey_cred: Credential = VerificationKey(
    #"0000000000000000000000000000000000000000000000000001091c",
  )
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(vkey_cred, 0)] }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// Params-reference-input resolution
// ---------------------------------------------------------------------------

// Passes when the params NFT input is not first among reference inputs
test plb_passes_when_params_ref_not_first() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [
      fixture.some_reference_input_tokens_registry_node(
        "",
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "node",
      ),
      params_ref_input(),
    ],
  }
  // params UTxO is the SECOND reference input here → params_idx = 1
  call_transfer_at(tx, 1, 0)
}

// Fails when no reference input carries the params NFT policy
test plb_fails_without_params_reference_input() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [
      fixture.some_reference_input_tokens_registry_node(
        "",
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "node",
      ),
    ],
  }
  call_validator(tx)
}

// Fails when the params datum predates the transfer_cred field
// (3-field layout): PLB must reject rather than authorise via garbage
test plb_fails_on_legacy_three_field_params_datum() fail {
  let modern = params_ref_input()
  let legacy = Input {
    ..modern,
    output: Output {
      ..modern.output,
      datum: InlineDatum(
        as_data(
          LegacyThreeFieldParams {
            registry_node_cs: fixture.policy_tokens_registry,
            prog_logic_cred: fixture.credential_validator_logic_base,
            unfracking_cred: fixture.credential_validator_unfracking,
          },
        ),
      ),
    },
  }
  let tx = Transaction { ..valid_plb_tx(), reference_inputs: [legacy] }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// In-place upgradability: the datum drives the authorising credential
// ---------------------------------------------------------------------------

// After an upgrade rewrites field 2, PLB authorises via the NEW credential
test plb_authorises_via_upgraded_transfer_cred() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(upgraded_transfer_cred, 0)],
  }
  call_validator(tx)
}

// After an upgrade, the OLD transfer credential no longer authorises a spend.
// Two deltas vs the happy path on purpose: the upgraded datum is the
// setup, the stale withdrawal is the invariant under test (one delta vs
// plb_authorises_via_upgraded_transfer_cred).
test plb_rejects_stale_transfer_cred_after_upgrade() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(transfer_cred, 0)],
  }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// Dispatch: SpendViaThirdParty arm
// ---------------------------------------------------------------------------

/// The third_party validator credential carried by `fixture.protocol_params`
/// (field 3).
const third_party_cred: Credential = fixture.credential_validator_third_party

// A SpendViaThirdParty spend authorises via the third_party credential (datum
// field 3), NOT the transfer credential — so a third-party (seize) transaction
// need never invoke the transfer validator.
test plb_passes_via_third_party_arm() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(third_party_cred, 0)],
  }
  call_third_party_at(tx, 0, 0)
}

// Wrong arm: a SpendViaThirdParty redeemer whose witnessed withdrawal is the
// transfer credential (not third_party) fails — the arm names the wrong delegate.
test plb_fails_third_party_arm_witnessing_transfer_cred() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(transfer_cred, 0)],
  }
  call_third_party_at(tx, 0, 0)
}

// Wrong arm the other way: a SpendViaTransfer redeemer whose witnessed
// withdrawal is the third_party credential fails.
test plb_fails_transfer_arm_witnessing_third_party_cred() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(third_party_cred, 0)],
  }
  call_transfer_at(tx, 0, 0)
}

// ---------------------------------------------------------------------------
// Dispatch: the distinct-credentials ASSUMPTION (documented, not enforced)
// ---------------------------------------------------------------------------

// The arm of `BaseSpendRedeemer` is only meaningful while the params datum
// carries `transfer_cred != third_party_cred`. Neither `protocol_params_mint`
// nor `coordination_spend` enforces that distinctness — it is the deployer's
// (and later the upgrade authority's) responsibility. With EQUAL credentials
// both arms resolve to the same script, so a SpendViaThirdParty spend is
// satisfied by that one script's withdrawal exactly as SpendViaTransfer is: the
// single delegate must then dispatch internally (the pre-split, monolithic
// shape). This test pins that consequence so the "wrong arm rejects" claim
// elsewhere is read with its hypothesis. See 02-ARCHITECTURE.md.
test plb_equal_delegate_creds_collapse_the_arms() {
  let collapsed = fixture.some_reference_input_protocol_params(
    ProgrammableLogicGlobalParams {
      ..fixture.protocol_params,
      third_party_cred: transfer_cred,
    },
    "protocol params",
  )
  let tx = Transaction { ..valid_plb_tx(), reference_inputs: [collapsed] }
  and {
    call_transfer_at(tx, 0, 0),
    call_third_party_at(tx, 0, 0),
  }
}

// ---------------------------------------------------------------------------
// Witnessed index: bounds
// ---------------------------------------------------------------------------

// `list.expect_at` past the end of the withdrawal map aborts — there is no
// entry to compare, so an out-of-range witness can never authorise a spend.
test plb_fails_when_wdrl_idx_out_of_range() fail {
  call_transfer_at(valid_plb_tx(), 0, 1)
}

// A negative witness is out of range too (`list.at` is None for index < 0).
test plb_fails_when_wdrl_idx_negative() fail {
  call_transfer_at(valid_plb_tx(), 0, -1)
}

// ---------------------------------------------------------------------------
// Witnessed index: arbitrary widths and positions (properties)
// ---------------------------------------------------------------------------

/// A random transaction layout for one PLB arm:
///   * a withdrawal map of random width (1..12) in LEDGER order — random
///     Script AND VerificationKey credentials around `delegate`, optionally
///     joined by `other_delegate` (the framework credential of the OTHER arm,
///     so the cross-arm case is exercised at its real sorted position);
///   * the params UTxO at a random reference-input position (0..4), behind
///     registry-node fillers.
/// Returns (reference_inputs, params_idx, withdrawals, wdrl_idx) with the two
/// indices computed exactly as an off-chain builder would.
fn layout_around(
  delegate: Credential,
  other_delegate: Credential,
) -> Fuzzer<(List<Input>, Int, Pairs<Credential, Int>, Int)> {
  let others <- fuzz.and_then(fuzz.list_between(cardano.credential(), 0, 10))
  let with_other <- fuzz.and_then(fuzz.bool())
  let params_idx <- fuzz.map(fuzz.int_between(0, 4))
  let creds = list.filter(
    others,
    fn(c) { c != delegate && c != other_delegate },
  )
    |> fn(cs) {
        if with_other {
          [other_delegate, ..cs]
        } else {
          cs
        }
      }
  let withdrawals = fixture.ledger_sorted_withdrawals(
    list.map([delegate, ..creds], fn(c) { Pair(c, 0) }),
  )
  let filler = fn(i: Int) {
    fixture.some_reference_input_tokens_registry_node(
      "",
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      bytearray.from_int_big_endian(i, 1),
    )
  }
  let reference_inputs = list.concat(
    list.map(list.range(1, params_idx), filler),
    [params_ref_input(), filler(0)],
  )
  (
    reference_inputs,
    params_idx,
    withdrawals,
    fixture.withdrawal_index_of(withdrawals, delegate),
  )
}

// SpendViaTransfer: the recomputed (params_idx, wdrl_idx) is accepted and EVERY
// other in-range withdrawal index is rejected (each resolves to some other
// credential, so the equality fails) — for any width, any Script/VKey mix of
// neighbours, with or without the third_party credential in the map.
test plb_transfer_arm_accepts_only_the_recomputed_index(
  (reference_inputs, params_idx, withdrawals, wdrl_idx) via layout_around(
    transfer_cred,
    third_party_cred,
  ),
) {
  let tx = Transaction { ..valid_plb_tx(), reference_inputs, withdrawals }
  and {
    call_transfer_at(tx, params_idx, wdrl_idx),
    list.all(
      list.range(0, list.length(withdrawals) - 1),
      fn(i) { i == wdrl_idx || !call_transfer_at(tx, params_idx, i) },
    ),
  }
}

// SpendViaThirdParty: same property for the other arm.
test plb_third_party_arm_accepts_only_the_recomputed_index(
  (reference_inputs, params_idx, withdrawals, wdrl_idx) via layout_around(
    third_party_cred,
    transfer_cred,
  ),
) {
  let tx = Transaction { ..valid_plb_tx(), reference_inputs, withdrawals }
  and {
    call_third_party_at(tx, params_idx, wdrl_idx),
    list.all(
      list.range(0, list.length(withdrawals) - 1),
      fn(i) { i == wdrl_idx || !call_third_party_at(tx, params_idx, i) },
    ),
  }
}

// ---------------------------------------------------------------------------
// Dispatch: SpendViaUnfracking arm
// ---------------------------------------------------------------------------

/// The unfracking validator credential carried by `fixture.protocol_params`
/// (field 4).
const unfracking_cred: Credential = fixture.credential_validator_unfracking

/// SpendViaUnfracking with explicit indices — dispatch via the standalone
/// unfracking validator's credential (params datum field 4).
fn call_unfracking_at(tx: Transaction, params_idx: Int, wdrl_idx: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    SpendViaUnfracking { params_idx, wdrl_idx },
    Void,
    tx,
  )
}

// A SpendViaUnfracking spend authorises via the unfracking credential (datum
// field 4) — neither the transfer nor the third_party credential — so an
// unfracking transaction loads only PLB + unfracking, never the transfer
// validator it used to be trampolined through.
test plb_passes_via_unfracking_arm() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(unfracking_cred, 0)],
  }
  call_unfracking_at(tx, 0, 0)
}

// Wrong arm: a SpendViaUnfracking redeemer whose witnessed withdrawal is the
// transfer credential fails — the transfer validator no longer gates
// unfracking, so its presence authorises nothing on this arm.
test plb_fails_unfracking_arm_witnessing_transfer_cred() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(transfer_cred, 0)],
  }
  call_unfracking_at(tx, 0, 0)
}

// Wrong arm the other way: a SpendViaTransfer redeemer whose witnessed
// withdrawal is the unfracking credential fails.
test plb_fails_transfer_arm_witnessing_unfracking_cred() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(unfracking_cred, 0)],
  }
  call_transfer_at(tx, 0, 0)
}

// Cross-arm between the two cold paths: SpendViaUnfracking witnessing the
// third_party credential fails.
test plb_fails_unfracking_arm_witnessing_third_party_cred() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [Pair(third_party_cred, 0)],
  }
  call_unfracking_at(tx, 0, 0)
}

// SpendViaUnfracking: same witnessed-index property as the other two arms —
// the recomputed (params_idx, wdrl_idx) is accepted, every other in-range
// withdrawal index is rejected, with the transfer credential present or not.
test plb_unfracking_arm_accepts_only_the_recomputed_index(
  (reference_inputs, params_idx, withdrawals, wdrl_idx) via layout_around(
    unfracking_cred,
    transfer_cred,
  ),
) {
  let tx = Transaction { ..valid_plb_tx(), reference_inputs, withdrawals }
  and {
    call_unfracking_at(tx, params_idx, wdrl_idx),
    list.all(
      list.range(0, list.length(withdrawals) - 1),
      fn(i) { i == wdrl_idx || !call_unfracking_at(tx, params_idx, i) },
    ),
  }
}

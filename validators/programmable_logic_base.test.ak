//// Tests for the programmable_logic_base validator.
////
//// PLB is parameterized by the protocol-params NFT policy. On every spend it
//// locates the params reference input, reads ONE credential out of its datum
//// — `plg_cred`, FIELD 0, the `programmable_logic_global` dispatcher — and
//// requires that credential's withdraw-0 at the witnessed index. There is no
//// arm and no choice of accessor: which ACTION is performed is the
//// dispatcher's business, not PLB's.
////
////   PLB --reads--> params[plg_cred] --requires--> PLG --requires--> delegate
////
//// These tests cover the three things PLB actually does — resolve the params
//// reference input, read field 0, compare it against the witnessed withdrawal
//// — plus the in-place upgradability the indirection exists for.
////
//// Note on `fail` vs `!call_…`: PLB's final check is a `?`-annotated equality,
//// so a credential MISMATCH makes it return False (`!call_…`), while a bad
//// index, an unauthenticated params UTxO or a datum whose field 0 is not a
//// `Credential` makes it ABORT (`test … fail`). The distinction is kept per
//// test on purpose, and it MOVED when `plg_cred` moved to field 0: a legacy
//// params datum used to put some other Credential there (silent wrong value,
//// caught as False) and now puts a `ByteArray` there (loud decode abort).

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
use types.{BaseSpendRedeemer}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

/// The dispatcher credential carried by `fixture.protocol_params` (field 0) —
/// the ONLY credential PLB reads.
const plg_cred: Credential = fixture.credential_validator_plg

const other_cred: Credential =
  Script(#"11223344112233441122334411223344112233441122334411223344")

/// A script credential sorting immediately BEFORE `plg_cred` in the ledger's
/// withdrawal order (Script credentials first, bytewise within), so a
/// hand-built withdrawal list can place the dispatcher at a NON-zero index
/// without lying about that order. Deliberately not of the `00…00 ‖ small`
/// shape used by the filler families in `wdrl_idx_cost.test.ak`.
const cred_below_plg: Credential =
  Script(#"00000000000000000000000000000000000000000000000000000100")

/// A replacement dispatcher credential, as an upgrade transaction would write
/// into the protocol-params datum.
const upgraded_plg_cred: Credential =
  Script(#"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd")

/// The protocol-params datum shape THIS slice retires: six fields, led by the
/// two frozen values (`registry_node_cs`, `prog_logic_cred`) that have since
/// become compile-time parameters of the delegates. `plg_cred` sat at field 2.
/// This is the shape an ALREADY-DEPLOYED protocol-params UTxO actually carries,
/// so it is the one legacy datum PLB can realistically meet on-chain.
type LegacySixFieldParams {
  registry_node_cs: PolicyId,
  prog_logic_cred: Credential,
  plg_cred: Credential,
  transfer_cred: Credential,
  third_party_cred: Credential,
  upgrade_cred: Credential,
}

/// The protocol-params datum shape from BEFORE the delegate credentials were
/// added at all — the earlier shape change this file has always pinned.
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

/// Params reference input whose datum carries `upgraded_plg_cred` in field 0 —
/// the protocol-params UTxO after an in-place dispatch-layer upgrade.
fn upgraded_params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    ProgrammableLogicGlobalParams {
      ..fixture.protocol_params,
      plg_cred: upgraded_plg_cred,
    },
    "protocol params",
  )
}

/// Params reference input built on top of a datum whose OTHER delegate fields
/// have been rewritten — used to show PLB's outcome does not depend on them.
fn params_ref_input_with_delegates(
  transfer_cred: Credential,
  third_party_cred: Credential,
) -> Input {
  fixture.some_reference_input_protocol_params(
    ProgrammableLogicGlobalParams {
      ..fixture.protocol_params,
      transfer_cred,
      third_party_cred,
    },
    "protocol params",
  )
}

/// A params reference input carrying an arbitrary (typically legacy-shaped)
/// datum in place of the current four-field one.
fn params_ref_input_with_datum(datum: Data) -> Input {
  let modern = params_ref_input()
  Input {
    ..modern,
    output: Output { ..modern.output, datum: InlineDatum(datum) },
  }
}

fn valid_plb_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [params_ref_input()],
    withdrawals: [Pair(plg_cred, 0)],
  }
}

/// Happy-path harness: the params UTxO and the dispatcher's withdrawal are
/// both the first entry of their list.
fn call_validator(tx: Transaction) -> Bool {
  call_plb_at(tx, 0, 0)
}

/// PLB with explicit indices — for tests where the params UTxO is not the
/// first reference input, or the dispatcher's withdrawal not the first entry.
fn call_plb_at(tx: Transaction, params_idx: Int, wdrl_idx: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    BaseSpendRedeemer { params_idx, wdrl_idx },
    Void,
    tx,
  )
}

// ---------------------------------------------------------------------------
// The dispatcher check
// ---------------------------------------------------------------------------

// Passes when the dispatcher credential read from the params datum is the
// witnessed withdrawal.
test plb_passes_when_datum_plg_cred_in_withdrawals() {
  call_validator(valid_plb_tx())
}

// The witnessed entry must BE the dispatcher: any other credential there is a
// mismatch, so the spend is denied.
test plb_fails_when_plg_cred_not_in_withdrawals() {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(other_cred, 0)] }
  !call_validator(tx)
}

// With no withdrawals at all there is no entry to resolve, so the indexed
// lookup aborts before any comparison.
test plb_fails_with_empty_withdrawals() fail {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [] }
  call_validator(tx)
}

// The dispatcher need not sit first: the redeemer witnesses its index, so no
// scan is needed. Ledger order here is `cred_below_plg` < `plg_cred` <
// `other_cred`, putting the dispatcher at index 1.
test plb_passes_with_multiple_withdrawals() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [
      Pair(cred_below_plg, 0), Pair(plg_cred, 0), Pair(other_cred, 0),
    ],
  }
  call_plb_at(tx, 0, 1)
}

// The witnessed index is load-bearing: pointing it at a DIFFERENT (valid)
// withdrawal entry than the dispatcher's is denied. One delta vs
// `plb_passes_with_multiple_withdrawals` — the same transaction, witnessed at
// index 0 instead of 1 — so a dishonest index can only invalidate the spend,
// never authorise a wrong one.
test plb_fails_when_wdrl_idx_points_at_wrong_entry() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [
      Pair(cred_below_plg, 0), Pair(plg_cred, 0), Pair(other_cred, 0),
    ],
  }
  !call_plb_at(tx, 0, 0)
}

// The credential CONSTRUCTOR is part of the comparison: a verification key
// carrying the dispatcher's 28 bytes is not the dispatcher.
test plb_fails_with_wrong_credential_type() {
  let vkey_cred: Credential = VerificationKey(fixture.hash_validator_plg)
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(vkey_cred, 0)] }
  !call_validator(tx)
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
  call_plb_at(tx, 1, 0)
}

// The addressed reference input must carry the params NFT policy: a UTxO that
// merely sits at the witnessed index cannot stand in for the params datum.
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

// A `params_idx` past the end of the reference inputs aborts — there is no
// UTxO to authenticate, so no datum can be read.
test plb_fails_when_params_idx_out_of_range() fail {
  call_plb_at(valid_plb_tx(), 1, 0)
}

// PLB reads field 0 POSITIONALLY, and the read is `expect _: Credential`.
// Every legacy params layout led with `registry_node_cs`, a `ByteArray`, so
// field 0 does not decode as a `Credential` and PLB ABORTS.
//
// That is the point of these two tests, and it is what CHANGED when `plg_cred`
// moved to field 0: while the dispatcher sat at field 2 a legacy datum merely
// named the WRONG SCRIPT there and PLB returned False — a silent-shaped
// failure that an off-chain builder could mistake for an authorisation
// problem. Now the shape mismatch is LOUD: script failure, not denial. These
// are `test … fail` for that reason, not for convenience.
//
// The 3-field layout, from before the delegate credentials existed at all.
test plb_fails_on_legacy_three_field_params_datum() fail {
  let legacy = params_ref_input_with_datum(
    as_data(
      LegacyThreeFieldParams {
        registry_node_cs: fixture.policy_tokens_registry,
        prog_logic_cred: fixture.credential_validator_logic_base,
        unfracking_cred: fixture.credential_validator_unfracking,
      },
    ),
  )
  let tx = Transaction { ..valid_plb_tx(), reference_inputs: [legacy] }
  call_validator(tx)
}

// The 6-field layout this slice retires — the shape a protocol-params UTxO
// deployed BEFORE this change actually carries, and therefore the only legacy
// datum PLB can realistically meet on-chain. It puts `registry_node_cs`
// (`ByteArray`) at field 0 where a `Credential` is now expected, so it aborts
// on the same `expect` as the 3-field case.
test plb_fails_on_legacy_six_field_params_datum() fail {
  let legacy = params_ref_input_with_datum(
    as_data(
      LegacySixFieldParams {
        registry_node_cs: fixture.policy_tokens_registry,
        prog_logic_cred: fixture.credential_validator_logic_base,
        plg_cred: fixture.credential_validator_plg,
        transfer_cred: fixture.credential_validator_transfer,
        third_party_cred: fixture.credential_validator_third_party,
        upgrade_cred: fixture.credential_upgrade_authority,
      },
    ),
  )
  let tx = Transaction { ..valid_plb_tx(), reference_inputs: [legacy] }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// In-place upgradability: the datum drives the authorising credential
// ---------------------------------------------------------------------------

// The property the whole design exists for: rewriting field 0 re-points PLB at
// a new dispatch layer, without moving PLB's hash and therefore without moving
// a single token address.
test plb_authorises_via_upgraded_plg_cred() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(upgraded_plg_cred, 0)],
  }
  call_validator(tx)
}

// The other half of that pair: after the rewrite the OLD dispatcher no longer
// authorises a spend. Two deltas vs the happy path on purpose — the upgraded
// datum is the setup, the stale withdrawal is the invariant under test (one
// delta vs `plb_authorises_via_upgraded_plg_cred`).
test plb_rejects_stale_plg_cred_after_upgrade() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(plg_cred, 0)],
  }
  !call_validator(tx)
}

// ---------------------------------------------------------------------------
// The pairwise-distinctness hazard, designed out
// ---------------------------------------------------------------------------

// PLB used to choose between `transfer_cred`, `third_party_cred` and
// `unfracking_cred` on a three-constructor redeemer. That arm selection was
// only sound while those credentials were pairwise DISTINCT — an assumption
// nothing on-chain enforced, and which an earlier test in this file
// (`plb_equal_delegate_creds_collapse_the_arms`) pinned as a documented
// consequence rather than a defect.
//
// The hazard is now GONE, not merely untested: exactly one credential is read
// on the spend path, so there is nothing left to collide. This test
// characterises that — the other delegate fields are set equal to each other,
// once at `plg_cred`'s own value and once at a third value, and PLB's outcome
// is unchanged in both directions because only field 0 is ever read.
test plb_dispatch_is_independent_of_the_other_delegate_creds() {
  let collapsed_onto_plg = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [params_ref_input_with_delegates(plg_cred, plg_cred)],
  }
  let collapsed_elsewhere = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [params_ref_input_with_delegates(other_cred, other_cred)],
  }
  and {
    // the dispatcher still authorises, whatever the other two fields hold
    call_validator(collapsed_onto_plg),
    call_validator(collapsed_elsewhere),
    // and a colliding delegate credential still authorises nothing
    !call_validator(
      Transaction { ..collapsed_elsewhere, withdrawals: [Pair(other_cred, 0)] },
    ),
  }
}

// ---------------------------------------------------------------------------
// Witnessed index: bounds
// ---------------------------------------------------------------------------

// `list.expect_at` past the end of the withdrawal map aborts — there is no
// entry to compare, so an out-of-range witness can never authorise a spend.
test plb_fails_when_wdrl_idx_out_of_range() fail {
  call_plb_at(valid_plb_tx(), 0, 1)
}

// A negative witness is out of range too (`list.expect_at` aborts for index < 0).
test plb_fails_when_wdrl_idx_negative() fail {
  call_plb_at(valid_plb_tx(), 0, -1)
}

// ---------------------------------------------------------------------------
// Witnessed index: arbitrary widths and positions (property)
// ---------------------------------------------------------------------------

/// A random transaction layout around the dispatcher credential:
///   * a withdrawal map of random width (1..12) in LEDGER order — random
///     Script AND VerificationKey credentials around `plg_cred`, optionally
///     joined by the `transfer` delegate's credential (a decoy at its real
///     sorted position: it is named by the params datum, but not by the field
///     PLB reads, so it must never authorise);
///   * the params UTxO at a random reference-input position (0..4), behind
///     registry-node fillers.
/// Returns (reference_inputs, params_idx, withdrawals, wdrl_idx) with the two
/// indices computed exactly as an off-chain builder would.
fn layout_around_plg_cred() -> Fuzzer<
  (List<Input>, Int, Pairs<Credential, Int>, Int),
> {
  let decoy = fixture.credential_validator_transfer
  let others <- fuzz.and_then(fuzz.list_between(cardano.credential(), 0, 10))
  let with_decoy <- fuzz.and_then(fuzz.bool())
  let params_idx <- fuzz.map(fuzz.int_between(0, 4))
  let creds = list.filter(others, fn(c) { c != plg_cred && c != decoy })
    |> fn(cs) {
        if with_decoy {
          [decoy, ..cs]
        } else {
          cs
        }
      }
  let withdrawals = fixture.ledger_sorted_withdrawals(
    list.map([plg_cred, ..creds], fn(c) { Pair(c, 0) }),
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
    fixture.withdrawal_index_of(withdrawals, plg_cred),
  )
}

// The recomputed (params_idx, wdrl_idx) is accepted and EVERY other in-range
// withdrawal index is rejected (each resolves to some other credential, so the
// equality fails) — for any width, any Script/VKey mix of neighbours, with or
// without the transfer delegate's credential in the map.
test plb_accepts_only_the_recomputed_wdrl_idx(
  (reference_inputs, params_idx, withdrawals, wdrl_idx) via layout_around_plg_cred(),
) {
  let tx = Transaction { ..valid_plb_tx(), reference_inputs, withdrawals }
  and {
    call_plb_at(tx, params_idx, wdrl_idx),
    list.all(
      list.range(0, list.length(withdrawals) - 1),
      fn(i) { i == wdrl_idx || !call_plb_at(tx, params_idx, i) },
    ),
  }
}

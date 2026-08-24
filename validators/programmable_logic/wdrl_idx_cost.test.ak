//// Cost record: PLB's witnessed withdrawal index vs the pre-split scan
//// (PR #110 validator split, PR #110).
////
//// `programmable_logic_base` locates the delegate's withdrawal with
//// `list.expect_at(self.withdrawals, wdrl_idx)`. That is NOT O(1): stdlib
//// drops one list cell per step, so the lookup is O(`wdrl_idx`) cell drops
//// — but with NO credential comparison on the way. The pre-split check,
//// `pairs.has_key_or_fail(self.withdrawals, cred)`, walked the same cells
//// AND compared a credential at each one. The saving per PLB input is
//// therefore the comparisons skipped, and it grows with the delegate's
//// position; at position 0 the two are equivalent and the indexed path pays
//// only for decoding its redeemer.
////
//// The rows below measure the REAL validator at (width, position) against a
//// local reproduction of the pre-split scan over the same params read, so
//// the two columns share every cost except the lookup itself.
////
//// Representative run (aiken v1.1.23; mem / cpu per test, ABSOLUTE):
////
////   width  position   indexed (PLB as shipped)     scan (pre-split check)
////   -----  --------   ------------------------     ----------------------
////     1       0      297.9k /  93.07M            286.7k /  90.00M
////     4       0      320.3k / 102.91M            309.1k /  99.83M
////     4       3      333.0k / 106.78M            323.0k / 107.88M
////     8       0      350.2k / 116.02M            338.9k / 112.95M
////     8       4      364.6k / 120.48M            357.4k / 123.68M
////     8       7      377.3k / 124.35M            371.3k / 131.73M
////    16       0      409.8k / 142.25M            398.6k / 139.18M
////    16      15      465.9k / 159.50M            468.0k / 179.42M
////
//// (Absolute figures include building the fixture transaction, which is why
//// both columns grow with width; compare rows, not totals.)
////
//// Per position, the indexed path grows ~1.2M cpu (one cell drop) and the
//// scan ~2.7M cpu (cell drop + credential comparison). The indexed path pays
//// a fixed ~3.1M cpu at position 0 for decoding its redeemer and the 3-arm
//// dispatch, so the two cross at position ~2; by width 16 / position 15 the
//// witness saves ~20M cpu and the memory difference has vanished.
////
//// Read the indexed column down a width: cost rises with `position`, which
//// is the O(`wdrl_idx`) growth. Read across a row: the gap to the scan is
//// the comparison work the witness removes, also growing with position.
//// Off-chain builders that control the withdrawal set cannot generally place
//// the framework credential first — the issuer's logic script hash is not
//// theirs to choose, and every Script credential sorts before every
//// VerificationKey one — so positions > 0 are the common seize case.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Credential, Script}
use cardano/transaction.{Transaction}
use pairs
use programmable_logic/fixture
use programmable_logic/params.{transfer_cred_field, with_protocol_params_fields}
use programmable_logic_base
use types.{SpendViaTransfer}

/// The delegate under test (params datum field 2, hash `…01091c`).
const transfer_cred: Credential = fixture.credential_validator_transfer

/// Filler credential sorting BEFORE the delegate (`00…00 0i`, differs from
/// the delegate's hash at byte 25).
fn below(i: Int) -> Credential {
  Script(
    bytearray.concat(
      #"000000000000000000000000000000000000000000000000000000",
      bytearray.from_int_big_endian(i, 1),
    ),
  )
}

/// Filler credential sorting AFTER the delegate (`ff…ff 0i`).
fn above(i: Int) -> Credential {
  Script(
    bytearray.concat(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      bytearray.from_int_big_endian(i, 1),
    ),
  )
}

/// A ledger-ordered withdrawal map of `width` entries with the delegate at
/// `position` (0-based).
fn withdrawals_with_delegate_at(
  width: Int,
  position: Int,
) -> Pairs<Credential, Int> {
  list.concat(
    list.map(list.range(1, position), fn(i) { Pair(below(i), 0) }),
    [
      Pair(transfer_cred, 0),
      ..list.map(
        list.range(1, width - 1 - position),
        fn(i) { Pair(above(i), 0) },
      )
    ],
  )
}

fn tx_with(width: Int, position: Int) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
    ],
    withdrawals: withdrawals_with_delegate_at(width, position),
  }
}

/// As shipped: the real validator, SpendViaTransfer witnessing `position`.
fn indexed(width: Int, position: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    SpendViaTransfer { params_idx: 0, wdrl_idx: position },
    Void,
    tx_with(width, position),
  )
}

/// The pre-split check, reproduced over the same params read: locate the
/// params UTxO, read `transfer_cred`, then scan the withdrawal map for it
/// (what PLB ran before PR #110; a `pairs.has_key_or_fail` over
/// `self.withdrawals`).
fn scanned(width: Int, position: Int) -> Bool {
  let tx = tx_with(width, position)
  let fields <- with_protocol_params_fields(
    tx.reference_inputs,
    fixture.policy_protocol_params,
    0,
  )
  pairs.has_key_or_fail(tx.withdrawals, transfer_cred_field(fields))
}

// --------------------------------------------------------------- width 1

test cost_wdrl_indexed_w1_p0() {
  indexed(1, 0)
}

test cost_wdrl_scan_w1_p0() {
  scanned(1, 0)
}

// --------------------------------------------------------------- width 4

test cost_wdrl_indexed_w4_p0() {
  indexed(4, 0)
}

test cost_wdrl_scan_w4_p0() {
  scanned(4, 0)
}

test cost_wdrl_indexed_w4_p3() {
  indexed(4, 3)
}

test cost_wdrl_scan_w4_p3() {
  scanned(4, 3)
}

// --------------------------------------------------------------- width 8

test cost_wdrl_indexed_w8_p0() {
  indexed(8, 0)
}

test cost_wdrl_scan_w8_p0() {
  scanned(8, 0)
}

test cost_wdrl_indexed_w8_p4() {
  indexed(8, 4)
}

test cost_wdrl_scan_w8_p4() {
  scanned(8, 4)
}

test cost_wdrl_indexed_w8_p7() {
  indexed(8, 7)
}

test cost_wdrl_scan_w8_p7() {
  scanned(8, 7)
}

// -------------------------------------------------------------- width 16

test cost_wdrl_indexed_w16_p0() {
  indexed(16, 0)
}

test cost_wdrl_scan_w16_p0() {
  scanned(16, 0)
}

test cost_wdrl_indexed_w16_p15() {
  indexed(16, 15)
}

test cost_wdrl_scan_w16_p15() {
  scanned(16, 15)
}

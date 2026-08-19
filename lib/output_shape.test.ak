//// Tests for the PLB-output seizability guard (`is_seizable_output_shape`)
//// and its enforcement at the transfer creation gate (`collect_output_assets`).
////
//// A programmable-token UTxO must stay seizable by a third party:
////   * no datum HASH — spending a datum-hash UTxO requires the datum preimage
////     in the tx witness (ledger phase-1), so a holder could pin one with a
////     secret preimage and make it unspendable by anyone but themselves; a
////     seizure could never be built;
////   * no reference script — a seizure must reproduce the paired input's
////     reference script byte-for-byte, so a large one bloats the mandatory
////     (per-UTxO-atomic) seizure transaction past maxTxSize.

use assets
use cardano/address.{Address, Credential, Inline, Script}
use cardano/assets.{ada_asset_name, ada_policy_id} as value
use cardano/transaction.{Datum, DatumHash, InlineDatum, NoDatum, Output}

const prog_cred: Credential =
  Script(#"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1")

const datum_hash_32: ByteArray =
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00"

const ref_script_28: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

/// A PLB output (payment credential = prog_cred, inline stake credential) with
/// the given datum and reference script.
fn plb_output(datum: Datum, reference_script: Option<ByteArray>) -> Output {
  Output {
    address: Address {
      payment_credential: prog_cred,
      stake_credential: Some(
        Inline(
          Script(#"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"),
        ),
      ),
    },
    value: value.zero |> value.add(ada_policy_id, ada_asset_name, 2_000_000),
    datum,
    reference_script,
  }
}

// -------------------------------------------------------- predicate: accepts

test seizable_accepts_no_datum() {
  assets.is_seizable_output_shape(plb_output(NoDatum, None))
}

test seizable_accepts_inline_datum() {
  assets.is_seizable_output_shape(plb_output(InlineDatum(as_data(0)), None))
}

// -------------------------------------------------------- predicate: rejects

test seizable_rejects_datum_hash() {
  !assets.is_seizable_output_shape(plb_output(DatumHash(datum_hash_32), None))
}

test seizable_rejects_reference_script() {
  !assets.is_seizable_output_shape(plb_output(NoDatum, Some(ref_script_28)))
}

// ------------------------------------------- transfer gate: collect rejects

// The transfer creation gate aborts on a datum-hash PLB output. (Comparing the
// result forces the collect call to run — a discarded pure result would be
// optimized away, and the abort with it.)
test collect_output_assets_rejects_datum_hash() fail {
  assets.collect_output_assets(
    [plb_output(DatumHash(datum_hash_32), None)],
    prog_cred,
  ) == []
}

// ... and on a reference-script PLB output.
test collect_output_assets_rejects_reference_script() fail {
  assets.collect_output_assets(
    [plb_output(NoDatum, Some(ref_script_28))],
    prog_cred,
  ) == []
}

// Control: inline-datum and no-datum PLB outputs pass the gate (ada-only, so
// the collected token set is empty).
test collect_output_assets_accepts_clean_outputs() {
  assets.collect_output_assets(
    [plb_output(NoDatum, None), plb_output(InlineDatum(as_data(1)), None)],
    prog_cred,
  ) == []
}

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
////     (per-UTxO-atomic) seizure transaction past maxTxSize;
////   * an inline datum no larger than `max_inline_datum_bytes` — seizure
////     must reproduce that byte-for-byte too (issue #106, vector 3). The
////     bound is the live protocol-params field, threaded in by the caller.
////
//// Note the bound is on the SERIALISED length, which exceeds the raw payload:
//// Plutus chunks bytestrings over 64 bytes, so a 64-byte ByteArray serialises
//// to 66 and a 128-byte one to 134. The tests below pin that arithmetic.

use aiken/builtin
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

/// Generous bound used wherever a test is not exercising the size rule.
const unbounded: Int = 1_000_000

/// A 64-byte payload. `serialise_data` wraps it as a single CBOR chunk:
/// 2 bytes of header + 64 = 66 serialised bytes.
const payload_64: ByteArray =
  #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"

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

// Issue #106 vector 3: an inline datum exactly ON the bound is accepted —
// `<=`, not `<`. 64 raw bytes serialise to 66, so 66 is the tight bound.
test seizable_accepts_inline_datum_at_the_bound() {
  assets.is_seizable_output_shape_bounded(
    plb_output(InlineDatum(as_data(payload_64)), None),
    66,
  )
}

// A NoDatum output is unaffected by the bound, even at zero — there is no
// datum to reproduce, so nothing to charge a seizure for.
test seizable_accepts_no_datum_under_zero_bound() {
  assets.is_seizable_output_shape_bounded(plb_output(NoDatum, None), 0)
}

// The unit datum every off-chain builder writes (`Constr(0, [])`, 3 bytes
// serialised) survives a tight bound — the bound must never break the
// universal case.
test seizable_accepts_unit_datum_under_tight_bound() {
  assets.is_seizable_output_shape_bounded(
    plb_output(InlineDatum(builtin.constr_data(0, [])), None),
    8,
  )
}

// -------------------------------------------------------- predicate: rejects

test seizable_rejects_datum_hash() {
  !assets.is_seizable_output_shape(plb_output(DatumHash(datum_hash_32), None))
}

test seizable_rejects_reference_script() {
  !assets.is_seizable_output_shape(plb_output(NoDatum, Some(ref_script_28)))
}

// Issue #106 vector 3: one byte over the bound is rejected. Same payload as
// `seizable_accepts_inline_datum_at_the_bound`, bound lowered by one — the
// single delta between the two tests is the bound itself.
test seizable_rejects_inline_datum_over_the_bound() {
  !assets.is_seizable_output_shape_bounded(
    plb_output(InlineDatum(as_data(payload_64)), None),
    65,
  )
}

// ------------------------------------------- transfer gate: collect rejects

// The transfer creation gate aborts on a datum-hash PLB output. (Comparing the
// result forces the collect call to run — a discarded pure result would be
// optimized away, and the abort with it.)
test collect_output_assets_rejects_datum_hash() fail {
  assets.collect_output_assets(
    [plb_output(DatumHash(datum_hash_32), None)],
    prog_cred,
    unbounded,
  ) == []
}

// ... and on a reference-script PLB output.
test collect_output_assets_rejects_reference_script() fail {
  assets.collect_output_assets(
    [plb_output(NoDatum, Some(ref_script_28))],
    prog_cred,
    unbounded,
  ) == []
}

// Control: inline-datum and no-datum PLB outputs pass the gate (ada-only, so
// the collected token set is empty).
test collect_output_assets_accepts_clean_outputs() {
  assets.collect_output_assets(
    [plb_output(NoDatum, None), plb_output(InlineDatum(as_data(1)), None)],
    prog_cred,
    unbounded,
  ) == []
}

// ------------------------------------- transfer gate: the size bound applies

// The transfer creation gate aborts on an over-sized inline datum, so an
// unseizable UTxO can never be created in the first place.
test collect_output_assets_rejects_oversized_inline_datum() fail {
  assets.collect_output_assets(
    [plb_output(InlineDatum(as_data(payload_64)), None)],
    prog_cred,
    65,
  ) == []
}

// Control for the above: the same output passes once the bound admits it.
// The only delta against the failure case is the bound.
test collect_output_assets_accepts_inline_datum_within_bound() {
  assets.collect_output_assets(
    [plb_output(InlineDatum(as_data(payload_64)), None)],
    prog_cred,
    66,
  ) == []
}

// -------------------------------------------- mint path: bound NOT applied

// The unbounded predicate is what `issuance_mint`'s `no_escape` uses: a mint
// is gated by the substandard's minting logic, so the party choosing the datum
// is the issuing side, not the holder. A large mint datum (CIP-68 reference
// token metadata, say) is accepted where the holder-driven transfer gate would
// reject it. Same output as `seizable_rejects_inline_datum_over_the_bound`;
// the delta is only WHICH predicate the creation site calls.
test seizable_unbounded_accepts_large_inline_datum() {
  assets.is_seizable_output_shape(
    plb_output(InlineDatum(as_data(payload_64)), None),
  )
}
// (`seizable_rejects_datum_hash` / `seizable_rejects_reference_script` above
// already pin that the mint path still rejects vectors 1 and 2 — they call
// this same unbounded predicate. Only the SIZE rule is relaxed for minting.)

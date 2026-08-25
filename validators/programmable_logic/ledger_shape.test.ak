//// Tests for the ledger-shape predicates AND the fixture realism audit:
//// a test transaction should be one a real node could have produced (see
//// the `ledger_shape` module docs for the rules and the wsc-poc/Lean-audit
//// provenance). One delta per negative, per CLAUDE.md.
////
//// The canonical fixtures in `programmable_logic/fixture` are ledger-shaped
//// AT SOURCE: `some_transfer` and `some_unfracking` set a realistic fee, list
//// their withdrawals in ledger order, clear the min-UTxO floor and carry
//// strictly ascending outrefs. `transfer_fixture_is_ledger_shaped` and
//// `unfracking_fixture_is_ledger_shaped` below audit them unrepaired, so a
//// regression in `fixture.ak` is caught where it is introduced.
////
//// `into_ledger_shape` is kept as belt-and-braces normalisation for the
//// negatives: each one mutates a base that must genuinely satisfy every rule,
//// so the `!is_ledger_shaped` it asserts is attributable to the one field it
//// changed and not to a violation the base already carried. Keeping the
//// normalisation means that stays true even if a future `fixture.ak` edit
//// reintroduces a violation — the guard tests would fail, but the negatives
//// would not silently turn into false positives.

use aiken/collection/list
use aiken/fuzz
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{
  ada_asset_name, ada_policy_id, from_asset, lovelace_of, merge,
}
use cardano/transaction.{Input, Output, Transaction}
use programmable_logic/fixture
use programmable_logic/ledger_shape.{
  is_ledger_shaped, min_ada_per_output, realistic_fee, sort_withdrawals,
  with_sequential_outrefs, withdrawals_ledger_ordered,
}

/// A registered policy for the audited transfer fixture.
const policy_x: ByteArray =
  #"00000000000000000000000000000000000000000000000000000c00"

/// Shared transaction ids for `with_sequential_outrefs`: inputs and
/// reference inputs are DISJOINT sets, so each gets its own id.
const inputs_txid: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const ref_inputs_txid: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

// --------------------------------------------------------------- repair

/// Top an output up to the min-UTxO floor (rule 3). A no-op on the canonical
/// fixtures, whose `min_ada_value` is pinned to `min_ada_per_output`.
fn top_up(output: Output) -> Output {
  let shortfall = min_ada_per_output - lovelace_of(output.value)
  if shortfall > 0 {
    Output {
      ..output,
      value: output.value
        |> merge(from_asset(ada_policy_id, ada_asset_name, shortfall)),
    }
  } else {
    output
  }
}

fn top_up_input(input: Input) -> Input {
  Input { ..input, output: top_up(input.output) }
}

/// Normalise a transaction into one a node could have produced. The canonical
/// fixtures already satisfy every rule, so on them this is a no-op — it is
/// kept so the negatives below mutate a base that is shaped by construction
/// rather than by assumption, and so ad-hoc transactions can be normalised
/// the same way. Each step covers one rule:
///
///   1. FEE — `transaction.placeholder` leaves `fee` at 0.
///   2. WITHDRAWALS — into the ledger's `Ord Credential` order, which puts
///      every Script credential before every VerificationKey one.
///   3. MIN-UTXO — tops outputs and resolved inputs up to the floor.
///   4. OUTREFS — rewrites inputs and reference inputs to strictly ascending
///      `OutputReference`s (fuzzer-seeded outrefs are arbitrary).
///
/// Rule 5 (signatories) needs no repair: the fixtures leave
/// `extra_signatories` empty, which is trivially a sorted set.
fn into_ledger_shape(tx: Transaction) -> Transaction {
  Transaction {
    ..tx,
    fee: realistic_fee,
    withdrawals: sort_withdrawals(tx.withdrawals),
    inputs: with_sequential_outrefs(
      list.map(tx.inputs, top_up_input),
      inputs_txid,
    ),
    reference_inputs: with_sequential_outrefs(
      list.map(tx.reference_inputs, top_up_input),
      ref_inputs_txid,
    ),
    outputs: list.map(tx.outputs, top_up),
  }
}

// ------------------------------------------------------- fixture audits

/// The canonical transfer fixture, repaired into ledger shape. This is
/// the base every negative below mutates.
fn shaped_tx() -> Transaction {
  let (tx, _) = fixture.some_transfer([(policy_x, "FOO", 100)])
  into_ledger_shape(tx)
}

// GUARD: the canonical transfer fixture is a transaction a real node could
// have produced, with NO repair applied — non-zero fee, withdrawals in the
// ledger's credential order, every output and resolved input over the
// min-UTxO floor, strictly ascending outrefs. If a `fixture.ak` edit breaks
// any of those, this fails and names the rule (each clause is `?`-traced).
test transfer_fixture_is_ledger_shaped() {
  let (tx, _) = fixture.some_transfer([(policy_x, "FOO", 100)])
  is_ledger_shaped(tx)
}

// GUARD: likewise for the canonical unfracking fixture, unrepaired. This one
// carries three withdrawals and two reference inputs, so it exercises the
// ordering rules over lists long enough for a mis-sort to show.
test unfracking_fixture_is_ledger_shaped() {
  let (tx, _) = fixture.some_unfracking(
    policy_x,
    [(policy_x, "FOO", 100)],
    [],
    [(policy_x, "FOO", 100)],
  )
  is_ledger_shaped(tx)
}

// The repaired transfer fixture is a transaction a node could produce — so the
// negatives below start from a genuinely shaped base. With the fixtures shaped
// at source this agrees with `transfer_fixture_is_ledger_shaped`; it stays as
// the negatives' contract, independent of what `fixture.ak` happens to do.
test transfer_fixture_is_ledger_shaped_after_repair() {
  is_ledger_shaped(shaped_tx())
}

// The repaired unfracking fixture likewise satisfies every rule.
test unfracking_fixture_is_ledger_shaped_after_repair() {
  let (tx, _) = fixture.some_unfracking(
    policy_x,
    [(policy_x, "FOO", 100)],
    [],
    [(policy_x, "FOO", 100)],
  )
  is_ledger_shaped(into_ledger_shape(tx))
}

// --------------------------------------------------- predicate negatives

// A zero-fee transaction cannot exist on chain (rule 1).
test ledger_shape_rejects_zero_fee() {
  !is_ledger_shaped(Transaction { ..shaped_tx(), fee: 0 })
}

// Withdrawals in Aiken/Plutus derived order but NOT ledger order are
// rejected (rule 2) — the exact bug class Phil's Lean audit found.
// `credential_transfer_logic` (…0b0b) sorts before
// `credential_validator_transfer` (…1091c), so listing them the other way
// round is descending.
test ledger_shape_rejects_unordered_withdrawals() {
  !is_ledger_shaped(
    Transaction {
      ..shaped_tx(),
      withdrawals: [
        Pair(fixture.credential_validator_transfer, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    },
  )
}

// A vkey withdrawal sorting before a script withdrawal violates the
// ledger's ScriptHashObj < KeyHashObj constructor order (rule 2).
test ledger_shape_rejects_vkey_before_script_withdrawal() {
  !is_ledger_shaped(
    Transaction {
      ..shaped_tx(),
      withdrawals: [
        Pair(
          VerificationKey(
            #"00000000000000000000000000000000000000000000000000000000",
          ),
          0,
        ),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    },
  )
}

// Duplicated (thus non-ascending) input outrefs are rejected (rule 4).
test ledger_shape_rejects_unsorted_input_outrefs() {
  let tx = shaped_tx()
  let doubled = when tx.inputs is {
    [input, ..] -> [input, input]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, inputs: doubled })
}

// Duplicated (thus non-ascending) reference input outrefs are rejected
// (rule 4).
test ledger_shape_rejects_unsorted_reference_input_outrefs() {
  let tx = shaped_tx()
  let doubled = when tx.reference_inputs is {
    [input, ..] -> [input, input]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, reference_inputs: doubled })
}

// An output below the min-UTxO floor is rejected (rule 3).
test ledger_shape_rejects_sub_min_ada_output() {
  let tx = shaped_tx()
  let dusted = when tx.outputs is {
    [output, ..rest] ->
      [
        Output {
          ..output,
          value: output.value
            |> merge(
                from_asset(
                  ada_policy_id,
                  ada_asset_name,
                  1 - lovelace_of(output.value),
                ),
              ),
        },
        ..rest
      ]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, outputs: dusted })
}

// A resolved input's output below the min-UTxO floor is rejected (rule 3)
// — inputs are themselves outputs of earlier transactions.
test ledger_shape_rejects_sub_min_ada_resolved_input() {
  let tx = shaped_tx()
  let dusted = when tx.inputs is {
    [input, ..rest] ->
      [
        Input {
          ..input,
          output: Output {
            ..input.output,
            value: input.output.value
              |> merge(
                  from_asset(
                    ada_policy_id,
                    ada_asset_name,
                    1 - lovelace_of(input.output.value),
                  ),
                ),
          },
        },
        ..rest
      ]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, inputs: dusted })
}

// A resolved reference input's output below the min-UTxO floor is
// rejected (rule 3) — reference inputs are themselves outputs of earlier
// transactions.
test ledger_shape_rejects_sub_min_ada_resolved_reference_input() {
  let tx = shaped_tx()
  let dusted = when tx.reference_inputs is {
    [input, ..rest] ->
      [
        Input {
          ..input,
          output: Output {
            ..input.output,
            value: input.output.value
              |> merge(
                  from_asset(
                    ada_policy_id,
                    ada_asset_name,
                    1 - lovelace_of(input.output.value),
                  ),
                ),
          },
        },
        ..rest
      ]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, reference_inputs: dusted })
}

// Unsorted extra_signatories are rejected (rule 5).
test ledger_shape_rejects_unsorted_signatories() {
  !is_ledger_shaped(
    Transaction { ..shaped_tx(), extra_signatories: [#"bb", #"aa"] },
  )
}

// ------------------------------------------------------------ properties

/// Bounded fuzzer for a withdrawal credential: script or vkey over a
/// small hash domain so collisions and both constructor mixes occur.
fn any_credential() -> Fuzzer<Pair<Credential, Int>> {
  let hash <- fuzz.and_then(fuzz.bytearray_between(1, 4))
  let is_script <- fuzz.map(fuzz.bool())
  if is_script {
    Pair(Script(hash), 0)
  } else {
    Pair(VerificationKey(hash), 0)
  }
}

// ∀ withdrawal lists (bounded): sorting yields ledger order — so fixtures
// built through `sort_withdrawals` always satisfy rule 2. (Duplicate
// credentials cannot occur in a real map; sorted duplicates fail the
// STRICT ordering, so restrict the claim to the deduped case by checking
// implication.)
test prop_sort_withdrawals_yields_ledger_order(
  wdrl via fuzz.list_between(any_credential(), 0, 5),
) {
  let sorted = sort_withdrawals(wdrl)
  withdrawals_ledger_ordered(sorted) || has_duplicate_credential(sorted)
}

fn has_duplicate_credential(wdrl: Pairs<Credential, Int>) -> Bool {
  when wdrl is {
    [] | [_] -> False
    [Pair(a, _), Pair(b, _) as second, ..rest] ->
      a == b || has_duplicate_credential([second, ..rest])
  }
}

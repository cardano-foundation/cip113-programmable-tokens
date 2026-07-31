//// Tests for the ledger-shape predicates AND the fixture realism audit:
//// the canonical fixtures must build transactions a real node could have
//// produced (see `ledger_shape` module docs for the rules and the
//// wsc-poc/Lean-audit provenance). One delta per negative, per CLAUDE.md.

use aiken/fuzz
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{ada_asset_name, ada_policy_id, from_asset, merge}
use cardano/transaction.{Output, Transaction}
use programmable_logic/fixture
use programmable_logic/ledger_shape.{
  is_ledger_shaped, min_ada_per_output, sort_withdrawals,
  withdrawals_ledger_ordered,
}

/// A registered policy for the audited transfer fixture.
const policy_x: ByteArray =
  #"00000000000000000000000000000000000000000000000000000c00"

// ------------------------------------------------------- fixture audits

// The canonical transfer fixture is a transaction a node could produce.
test transfer_fixture_is_ledger_shaped() {
  let (tx, _) = fixture.some_transfer([(policy_x, "FOO", 100)])
  is_ledger_shaped(tx)
}

// The canonical unfracking fixture is a transaction a node could produce.
test unfracking_fixture_is_ledger_shaped() {
  let (tx, _, _) = fixture.some_unfracking(
    policy_x,
    [(policy_x, "FOO", 100)],
    [],
    [(policy_x, "FOO", 100)],
  )
  is_ledger_shaped(tx)
}

// --------------------------------------------------- predicate negatives

fn shaped_tx() -> Transaction {
  let (tx, _) = fixture.some_transfer([(policy_x, "FOO", 100)])
  tx
}

// A zero-fee transaction cannot exist on chain (rule 1).
test ledger_shape_rejects_zero_fee() {
  !is_ledger_shaped(Transaction { ..shaped_tx(), fee: 0 })
}

// Withdrawals in Aiken/Plutus derived order but NOT ledger order are
// rejected (rule 2) — the exact bug class Phil's Lean audit found.
test ledger_shape_rejects_unordered_withdrawals() {
  let tx = shaped_tx()
  !is_ledger_shaped(
    Transaction {
      ..tx,
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    },
  )
}

// A vkey withdrawal sorting before a script withdrawal violates the
// ledger's ScriptHashObj < KeyHashObj constructor order (rule 2).
test ledger_shape_rejects_vkey_before_script_withdrawal() {
  let tx = shaped_tx()
  !is_ledger_shaped(
    Transaction {
      ..tx,
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
                  1 - min_ada_per_output,
                ),
              ),
        },
        ..rest
      ]
    [] -> fail
  }
  !is_ledger_shaped(Transaction { ..tx, outputs: dusted })
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

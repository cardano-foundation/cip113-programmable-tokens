//// Ledger-shape predicates for test transactions.
////
//// A test transaction that no Cardano node could ever produce proves
//// nothing about mainnet behaviour — and can actively hide bugs: the
//// Plutarch reference implementation's Lean audit (wsc-poc PR #112,
//// `WSC/LR-CTX-AUDIT.md` in CardanoLedgerApiBlaster) found ALL 13 of its
//// golden ScriptContexts violating a ledger rule, which had masked a
//// +708% cost mis-measurement and mis-ordered withdrawal indexes.
////
//// This module encodes the ledger invariants a real transaction
//// satisfies, so canonical fixtures can be AUDITED against them
//// (`is_ledger_shaped`) and built with them (`sort_withdrawals`,
//// `with_sequential_outrefs`). Rules and their provenance
//// (`[LEDGER-RULE]` blocks in wsc-poc's
//// `ProgrammableTokens/Test/ScriptContext/Builder.hs`, ported here):
////
////   1. FEE — `tx.fee` is positive. A fee-0 transaction cannot exist;
////      0.5 ada is inside the range real script transactions pay.
////   2. WITHDRAWALS — ascending in the LEDGER's credential order:
////      `cardano-ledger`'s derived `Ord Credential` puts `ScriptHashObj`
////      BEFORE `KeyHashObj` (then bytewise on the hash) — the OPPOSITE
////      of the Plutus/Aiken `Credential` constructor order, where
////      `VerificationKey` comes first. `txInfoWdrl` is built from a
////      `Map RewardAccount Coin` in that order.
////   3. MIN-UTXO — every output carries at least `min_ada_per_output`
////      lovelace (`coinsPerUTxOByte` rule; the real minimum for a small
////      multi-asset output is ~1.2-1.5 ada, 2 ada is a safe
////      over-approximation). Applies to resolved inputs and reference
////      inputs too: they are outputs of earlier transactions.
////   4. INPUTS / REFERENCE INPUTS — strictly ascending by
////      `OutputReference` (transaction id bytewise, then output index):
////      both are SETS in the transaction body, and the ledger hands
////      them to scripts in sorted order. Positional index redeemers
////      (`registry_node_idx`, `outputs_start_idx` pairing) must be
////      written against this order. The two sets are disjoint — a UTxO
////      cannot be both spent and referenced in one transaction.
////   5. SIGNATORIES — `extra_signatories` is a set: strictly ascending
////      bytewise, no duplicates.
////
//// Not representable in the Aiken `Transaction` type but relevant when
//// exporting golden vectors (documented for completeness): the redeemer
//// MAP order is `Spending < Minting < Certifying < Rewarding` (Conway
//// `PlutusPurpose` tag order — note Spending sorts BEFORE Minting, the
//// opposite of the Plutus `ScriptPurpose` constructor order), with ties
//// broken by the purpose's index in its canonically-sorted ledger list.
//// Aiken's `tx.redeemers` field carries this shape when populated.

use aiken/builtin.{less_than_bytearray}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{lovelace_of}
use cardano/transaction.{Input, Output, OutputReference, Transaction}

/// Rule 1 — a fee no ledger would reject as absurd. 0.5 ada.
pub const realistic_fee: Int = 500_000

/// Rule 3 — safe over-approximation of the min-UTxO floor for the small
/// multi-asset outputs these tests build (mainnet `coinsPerUTxOByte`
/// 4310 puts the real floor at ~1.2-1.5 ada).
pub const min_ada_per_output: Int = 2_000_000

/// The full audit predicate: True iff `tx` satisfies every ledger rule
/// this module encodes. Each clause is `?`-traced so a violation names
/// itself in the test failure.
pub fn is_ledger_shaped(tx: Transaction) -> Bool {
  and {
    (tx.fee > 0)?,
    withdrawals_ledger_ordered(tx.withdrawals)?,
    outrefs_strictly_ascending(tx.inputs)?,
    outrefs_strictly_ascending(tx.reference_inputs)?,
    outputs_meet_min_ada(tx.outputs)?,
    resolved_outputs_meet_min_ada(tx.inputs)?,
    resolved_outputs_meet_min_ada(tx.reference_inputs)?,
    signatories_strictly_ascending(tx.extra_signatories)?,
  }
}

/// Rule 2 — `cardano-ledger` credential order: Script < VerificationKey
/// (constructor), then bytewise on the hash. NOT the Aiken/Plutus
/// derived order.
pub fn credential_ledger_lt(a: Credential, b: Credential) -> Bool {
  when a is {
    Script(ha) ->
      when b is {
        Script(hb) -> less_than_bytearray(ha, hb)
        VerificationKey(_) -> True
      }
    VerificationKey(ha) ->
      when b is {
        Script(_) -> False
        VerificationKey(hb) -> less_than_bytearray(ha, hb)
      }
  }
}

pub fn withdrawals_ledger_ordered(wdrl: Pairs<Credential, Int>) -> Bool {
  when wdrl is {
    [] | [_] -> True
    [Pair(a, _), Pair(b, _) as second, ..rest] ->
      credential_ledger_lt(a, b) && withdrawals_ledger_ordered([second, ..rest])
  }
}

/// Sort a withdrawal list into ledger order (rule 2). Insertion sort —
/// fixture withdrawal lists carry at most a handful of entries.
pub fn sort_withdrawals(wdrl: Pairs<Credential, Int>) -> Pairs<Credential, Int> {
  when wdrl is {
    [] -> []
    [head, ..tail] -> insert_withdrawal(sort_withdrawals(tail), head)
  }
}

fn insert_withdrawal(
  sorted: Pairs<Credential, Int>,
  entry: Pair<Credential, Int>,
) -> Pairs<Credential, Int> {
  when sorted is {
    [] -> [entry]
    [head, ..tail] ->
      if credential_ledger_lt(entry.1st, head.1st) {
        [entry, ..sorted]
      } else {
        [head, ..insert_withdrawal(tail, entry)]
      }
  }
}

/// Rule 4 — strict `OutputReference` order: transaction id bytewise,
/// then output index.
pub fn outref_lt(a: OutputReference, b: OutputReference) -> Bool {
  if a.transaction_id == b.transaction_id {
    a.output_index < b.output_index
  } else {
    less_than_bytearray(a.transaction_id, b.transaction_id)
  }
}

pub fn outrefs_strictly_ascending(inputs: List<Input>) -> Bool {
  when inputs is {
    [] | [_] -> True
    [a, b, ..rest] ->
      outref_lt(a.output_reference, b.output_reference) && outrefs_strictly_ascending(
        [b, ..rest],
      )
  }
}

/// Rewrite a fixture input list so its declared order IS the ledger's
/// sorted order: every input gets the shared `transaction_id` and its
/// list position as `output_index`. Realistic (several UTxOs born in one
/// transaction) and keeps positional pairing/index redeemers valid.
/// Use DISTINCT transaction ids for inputs vs reference inputs — the
/// two sets must be disjoint.
pub fn with_sequential_outrefs(
  inputs: List<Input>,
  transaction_id: ByteArray,
) -> List<Input> {
  do_sequential_outrefs(inputs, transaction_id, 0)
}

fn do_sequential_outrefs(
  inputs: List<Input>,
  transaction_id: ByteArray,
  index: Int,
) -> List<Input> {
  when inputs is {
    [] -> []
    [head, ..tail] ->
      [
        Input {
          ..head,
          output_reference: OutputReference {
            transaction_id,
            output_index: index,
          },
        },
        ..do_sequential_outrefs(tail, transaction_id, index + 1)
      ]
  }
}

/// Rule 3 — every output meets the min-UTxO floor.
pub fn outputs_meet_min_ada(outputs: List<Output>) -> Bool {
  when outputs is {
    [] -> True
    [head, ..tail] ->
      lovelace_of(head.value) >= min_ada_per_output && outputs_meet_min_ada(
        tail,
      )
  }
}

fn resolved_outputs_meet_min_ada(inputs: List<Input>) -> Bool {
  when inputs is {
    [] -> True
    [head, ..tail] ->
      lovelace_of(head.output.value) >= min_ada_per_output && resolved_outputs_meet_min_ada(
        tail,
      )
  }
}

/// Rule 5 — `extra_signatories` is a set: strictly ascending, deduped.
pub fn signatories_strictly_ascending(signatories: List<ByteArray>) -> Bool {
  when signatories is {
    [] | [_] -> True
    [a, b, ..rest] ->
      less_than_bytearray(a, b) && signatories_strictly_ascending([b, ..rest])
  }
}

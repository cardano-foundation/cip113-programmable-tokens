//// Tests for the Finding 17 Unfracking action.
////
//// The fixtures sit at the top of the file (per CLAUDE.md), every test
//// is built by spreading a known-good fixture and overriding one field
//// to expose the invariant under test. Names read as specs:
////
////   * unfracking_<scenario>_succeeds / _fails — describes the shape.
////
//// Authorisation: the default fixture uses `credential_transfer_logic`
//// (a Script) as the PLB stake credential — same as the rest of the
//// programmable_logic fixtures. So a valid Unfracking tx invokes that
//// script's withdraw-0; a vkey-only Unfracking tx wires
//// `VerificationKey(pkh)` and signs as that pkh.

use cardano/address.{Address, VerificationKey}
use cardano/assets.{ada_asset_name, ada_policy_id, from_asset, merge}
use cardano/transaction.{Input, NoDatum, Output, Transaction}
use programmable_logic/fixture
use programmable_logic_global
use types.{UnfrackingAct}

// --------------------------------------------------------------------- types

/// Two policies used across the Unfracking tests; the whole point of
/// Unfracking is to split tokens of multiple policies into separate
/// UTxOs, so all the interesting scenarios involve at least two.
const policy_a: ByteArray =
  #"00000000000000000000000000000000000000000000000000000a00"

const policy_b: ByteArray =
  #"00000000000000000000000000000000000000000000000000000b00"

/// A non-programmable / unregistered policy. Unfracking does not consult
/// the registry at all, so its handling has to be value-conservation
/// only: it goes in, it must come out at PLB.
const policy_unrelated: ByteArray =
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"

/// A second authorised vkey holder, used to exercise the "user owns
/// two of their own credentials and shuffles between them" case.
const second_vkey_pkh: ByteArray =
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

/// A third-party (Eve) credential the user has NOT authorised. Used
/// to pin the back-door-closure: tokens MUST NOT be routable to a
/// stake credential not present in the input set.
const eve_vkey_pkh: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const redeemer = UnfrackingAct

// ----------------------------------------------------------------- fixtures

/// The canonical "happy path" Unfracking input: one PLB UTxO at the
/// default `credential_transfer_logic` script stake credential, holding
/// 100 A + 100 B + min_ada. This is the multi-policy "fracked" state
/// the action exists to break apart.
fn valid_fracked_input() -> Input {
  fixture.some_input_with_programmable_tokens(
    [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
    "fracked input",
  )
}

/// Two outputs at PLB, each holding one of the two policies — the
/// canonical "unfracked" shape. Both inherit `credential_transfer_logic`
/// from `fixture.some_output_with_programmable_tokens`.
fn unfracked_outputs() -> List<Output> {
  [
    fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
    fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
  ]
}

/// The valid Unfracking transaction skeleton: one fracked PLB input,
/// two single-policy PLB outputs, no mint, and the transfer-logic
/// script invoked via withdraw-0 to discharge the authorisation
/// requirement (the input's stake credential is that script).
fn valid_unfracking_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [valid_fracked_input()],
    outputs: unfracked_outputs(),
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_logic_global, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }
}

/// Dispatch helper — drives `programmable_logic_global.withdraw` with
/// the `UnfrackingAct` redeemer over a caller-provided transaction.
/// Mirrors the helper shape used in the existing 3rd-party tests.
fn run_unfracking(tx: Transaction) -> Bool {
  programmable_logic_global.programmable_logic_global.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_logic_global,
    tx,
  )
}

// --------------------------------------------------------------- happy paths

// Finding 17: the canonical unfracking case — one multi-policy PLB
// UTxO is broken into one single-policy UTxO per policy. Both new
// UTxOs stay at PLB under the holder's authorised stake credential.
// No mint, no transfer-logic interaction beyond the withdraw-0 that
// authorises the original input.
test unfracking_split_two_policies_into_two_outputs_succeeds() {
  run_unfracking(valid_unfracking_tx())
}

// Finding 17: holders aren't forced into a 1-policy-per-output layout.
// Half of each policy goes to output 1, the other half to output 2.
// The validator only cares that totals at PLB are unchanged and that
// each output's stake credential is authorised.
test unfracking_partial_split_succeeds() {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens(
          [(policy_a, "FOO", 50), (policy_b, "BAR", 50)],
        ),
        fixture.some_output_with_programmable_tokens(
          [(policy_a, "FOO", 50), (policy_b, "BAR", 50)],
        ),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: a degenerate but legal case — one input, one identical
// output. The user is paying fees from a non-PLB fuel input (not
// modelled here) and rebuilding the UTxO. Conservation holds.
test unfracking_identity_reshape_succeeds() {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens(
          [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
        ),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: vkey-authorised holder unfracks their own PLB UTxO.
// The stake credential is a vkey rather than a script, so authorisation
// comes from `extra_signatories` instead of `withdrawals`. The
// transfer_logic withdraw-0 is omitted because nothing in this tx
// relies on the transfer logic — and the validator must not require it.
test unfracking_vkey_authorised_succeeds() {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  let input =
    fixture.some_input_with_programmable_tokens_with(
      vkey_cred,
      [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
      "vkey input",
    )
  let outputs =
    [
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100)],
      ),
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_b, "BAR", 100)],
      ),
    ]
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      inputs: [input],
      outputs: outputs,
      extra_signatories: [second_vkey_pkh],
      withdrawals: [Pair(fixture.credential_validator_logic_global, 0)],
    }
  run_unfracking(tx)
}

// Finding 17 — single-owner invariant. Unfracking is a SAME-OWNER
// restructuring action: tokens crossing between stake credentials is a
// transfer (and must invoke `transfer_logic_script`), not an unfracking.
// Here two PLB UTxOs use DIFFERENT stake credentials (one script-staked,
// one vkey-staked). Even if the holder controls both, the validator must
// reject — otherwise Unfracking would be "transfer-without-transfer-logic"
// between credentials the holder happens to own. The first PLB input
// pins the target stake_cred; the second's mismatched cred triggers
// `expect stake_cred == existing` in `collect_plb_inputs` and the tx
// fails. This `fail` test locks in that boundary.
test unfracking_inputs_with_different_stake_creds_rejected() fail {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  // Input A: default script stake credential
  let input_script =
    fixture.some_input_with_programmable_tokens(
      [(policy_a, "FOO", 100)],
      "script input",
    )
  // Input B: vkey stake credential
  let input_vkey =
    fixture.some_input_with_programmable_tokens_with(
      vkey_cred,
      [(policy_b, "BAR", 100)],
      "vkey input",
    )
  // Outputs swap which cred holds which policy — both creds are
  // authorised so this is legal.
  let outputs =
    [
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100)],
      ),
      fixture.some_output_with_programmable_tokens(
        [(policy_b, "BAR", 100)],
      ),
    ]
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      inputs: [input_script, input_vkey],
      outputs: outputs,
      extra_signatories: [second_vkey_pkh],
      // Script-staked input requires the script's withdraw-0; vkey
      // input is covered by the signatory above.
      withdrawals: [
        Pair(fixture.credential_validator_logic_global, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: an unrelated / unregistered policy that happens to share
// a UTxO with programmable tokens is preserved across the reshape too.
// The validator doesn't consult the registry under Unfracking, so it
// treats the unregistered token the same as the registered ones —
// total at PLB unchanged.
test unfracking_preserves_unregistered_token_at_plb_succeeds() {
  let input =
    fixture.some_input_with_programmable_tokens(
      [
        (policy_a, "FOO", 100),
        (policy_b, "BAR", 100),
        (policy_unrelated, "RAND", 1),
      ],
      "mixed input",
    )
  let outputs =
    [
      fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
      fixture.some_output_with_programmable_tokens(
        [(policy_b, "BAR", 100), (policy_unrelated, "RAND", 1)],
      ),
    ]
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      inputs: [input],
      outputs: outputs,
    }
  run_unfracking(tx)
}

// --------------------------------------------------------------- failure cases
//
// One delta per failure test (CLAUDE.md test conventions). Each test
// builds on `valid_unfracking_tx()` and overrides exactly one field
// — the spec-shaped diff in the body is what tells the reader which
// invariant the test is locking in.

// Finding 17: the destination stake credential must be in the
// authorisation set. ONE delta vs the happy path — second output's
// stake credential is Eve (a vkey the user did NOT sign for). This is
// the core back-door Unfracking has to slam shut, otherwise it becomes
// "transfer-without-transfer-logic" and bypasses the substandard.
test unfracking_output_to_unauthorised_stake_credential_fails() fail {
  let eve_cred = VerificationKey(eve_vkey_pkh)
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
        // ONE delta: stake credential is Eve, not the input's cred.
        fixture.some_output_with_programmable_tokens_with(
          eve_cred,
          [(policy_b, "BAR", 100)],
        ),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: per-policy total at PLB must be conserved. ONE delta
// vs the happy path — output B carries 150 tokens where input held 100.
// (The extra 50 would have had to come from somewhere; the equality
// check catches it without us having to model the missing input.)
test unfracking_output_surplus_fails() fail {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
        // ONE delta: 150 BAR, not 100.
        fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 150)]),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: per-policy total at PLB must be conserved (the other
// direction). ONE delta — output B has only 50 of the 100 BAR; the
// remaining 50 would be leaking somewhere off PLB.
test unfracking_output_shortfall_fails() fail {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
        // ONE delta: 50 BAR, not 100.
        fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 50)]),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: tokens cannot leak to a non-PLB address (proven by the
// conservation rule + ledger value preservation, but worth pinning
// explicitly). ONE delta — output B is at an Eve-payment-credential
// non-PLB address, so 100 BAR is removed from the PLB tally.
test unfracking_token_leak_to_non_plb_output_fails() fail {
  let eve_address =
    Address {
      payment_credential: VerificationKey(eve_vkey_pkh),
      stake_credential: None,
    }
  let leaky_output =
    Output {
      address: eve_address,
      value: from_asset(ada_policy_id, ada_asset_name, 1_000_000)
        |> merge(from_asset(policy_b, "BAR", 100)),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 100)]),
        // ONE delta: B goes to Eve instead of staying at PLB.
        leaky_output,
      ],
    }
  run_unfracking(tx)
}

// Finding 17: script-staked PLB input requires the script's withdraw-0.
// ONE delta — the transfer_logic withdrawal is removed. Authorisation
// scan halts on the first PLB input.
test unfracking_missing_script_authorisation_fails() fail {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      // ONE delta: only the global validator's withdraw-0 remains.
      withdrawals: [Pair(fixture.credential_validator_logic_global, 0)],
    }
  run_unfracking(tx)
}

// Finding 17: vkey-staked PLB input requires the vkey to sign. ONE
// delta vs `unfracking_vkey_authorised_succeeds` — `extra_signatories`
// is empty, so the authorisation check fails on the input.
test unfracking_missing_vkey_signatory_fails() fail {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  let input =
    fixture.some_input_with_programmable_tokens_with(
      vkey_cred,
      [(policy_a, "FOO", 100), (policy_b, "BAR", 100)],
      "vkey input",
    )
  let outputs =
    [
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100)],
      ),
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_b, "BAR", 100)],
      ),
    ]
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      inputs: [input],
      outputs: outputs,
      // ONE delta: no signatory for second_vkey_pkh.
      extra_signatories: [],
      withdrawals: [Pair(fixture.credential_validator_logic_global, 0)],
    }
  run_unfracking(tx)
}

// Finding 17: minting is forbidden during Unfracking. ONE delta — a
// positive mint of policy_a. Without this rule, a holder could
// disguise a mint as an unfracking and skip issuance_mint's
// authorisation checks.
test unfracking_with_mint_fails() fail {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      // ONE delta: non-empty mint.
      mint: from_asset(policy_a, "FOO", 50),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 150)]),
        fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: burning is forbidden during Unfracking. ONE delta — a
// negative mint of policy_a. Same rule as mint, written for
// completeness because burns are the other ledger-level value mutation
// that would otherwise need to be threaded into the conservation
// equality.
test unfracking_with_burn_fails() fail {
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      // ONE delta: negative mint (burn).
      mint: from_asset(policy_a, "FOO", -50),
      outputs: [
        fixture.some_output_with_programmable_tokens([(policy_a, "FOO", 50)]),
        fixture.some_output_with_programmable_tokens([(policy_b, "BAR", 100)]),
      ],
    }
  run_unfracking(tx)
}

// Finding 17: the proof-of-instance for an Unfracking action lives on
// the input authorisation only — transfer_logic must NOT be invoked
// implicitly. This is a sanity check that the happy-path fixture's
// withdrawals are loadbearing for the script-authorisation case, not
// for any (nonexistent) "transfer_logic must always run" rule. ONE
// delta vs `unfracking_vkey_authorised_succeeds` — purely demonstrates
// that the absence of transfer_logic doesn't itself fail when no
// script-staked PLB input demands it.
test unfracking_vkey_path_does_not_require_transfer_logic() {
  let vkey_cred = VerificationKey(second_vkey_pkh)
  let input =
    fixture.some_input_with_programmable_tokens_with(
      vkey_cred,
      [(policy_a, "FOO", 100)],
      "vkey input solo",
    )
  let outputs =
    [
      fixture.some_output_with_programmable_tokens_with(
        vkey_cred,
        [(policy_a, "FOO", 100)],
      ),
    ]
  let tx =
    Transaction {
      ..valid_unfracking_tx(),
      inputs: [input],
      outputs: outputs,
      extra_signatories: [second_vkey_pkh],
      // Only the global validator's withdraw-0; no transfer_logic.
      withdrawals: [Pair(fixture.credential_validator_logic_global, 0)],
    }
  run_unfracking(tx)
}


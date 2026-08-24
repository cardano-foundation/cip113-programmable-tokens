//// Integration tests for the standalone third_party (seize / clawback /
//// freeze) withdraw-0 validator.
////
//// These exercise `third_party.withdraw` with a `ThirdPartyRedeemer` — the
//// same invariants the inline `ThirdPartyAct` arm of the former programmable_logic_global coordinator
//// used to enforce (`validate_3rd_party` in programmable_logic/third_party),
//// now hosted in their own script. The transaction always presents the
//// subject policy's registry node as a reference input and the issuer's
//// third_party_transfer_logic_script withdrawal; the framework validator's
//// own presence is enforced by programmable_logic_base (SpendViaThirdParty),
//// not here.

use aiken/crypto.{ScriptHash, blake2b_256}
use cardano/address.{Address, Credential, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, ada_asset_name, ada_policy_id, from_asset, merge,
}
use cardano/transaction.{
  Datum, DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference,
  Transaction,
}
use programmable_logic/fixture
use registry_node.{RegistryNode, empty_vkey}
use third_party
use types.{ThirdPartyRedeemer}

/// Arbitrary credential representing an ISSUER's third-party transfer logic
/// script (e.g. a seize/freeze substandard) whose withdraw-0 must accompany
/// every third-party action on its policy. Distinct from the framework
/// `third_party` validator's own credential (that one is checked by PLB).
const test_third_party_cred: Credential =
  Script(#"000000000000000000000000000000000000000000000000000003d9")

/// A programmable token policy used across the third-party tests.
const test_third_party_policy: PolicyId =
  #"00000000000000000000000000000000000000000000000000000f00"

/// Build a registry-node reference input whose third_party_transfer_logic_script
/// is set to a real credential (unlike the default fixture which uses Script("")).
fn third_party_registry_node_ref_input(
  key: ByteArray,
  issuer_third_party_cred: Credential,
) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: Script(
          #"00000000000000000000000000000000000000000000000000aabb",
        ),
        stake_credential: None,
      },
      value: from_asset(ada_policy_id, ada_asset_name, 1_000_000)
        |> merge(
            from_asset(fixture.policy_tokens_registry, blake2b_256(key), 1),
          ),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            transfer_logic_script: fixture.credential_transfer_logic,
            third_party_transfer_logic_script: issuer_third_party_cred,
            minting_logic_script: empty_vkey,
            unfracking_logic_script: empty_vkey,
            global_state_cs: "",
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// Run third_party.withdraw with a ThirdPartyRedeemer whose outputs_start_idx
/// is given. Two prog_logic_cred inputs (indices 0 and 1) hold programmable
/// tokens; the outputs remove those tokens and a remaining output at
/// prog_logic_cred receives the seized tokens (balance invariant).
fn validate_third_party_with_outputs(
  outputs: List<Output>,
  outputs_start_idx: Int,
) -> Bool {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
        "third_party_input_a",
      ),
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "third_party_input_b",
      ),
    ],
    outputs,
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    // Only the issuer's third-party logic withdrawal is required by this
    // validator; PLB (not tested here) enforces the framework validator's.
    withdrawals: [Pair(test_third_party_cred, 0)],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

test third_party_act_prog_outputs_first() {
  validate_third_party_with_outputs(
    [
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

test third_party_act_prog_outputs_skipped() {
  validate_third_party_with_outputs(
    [
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_programmable_tokens([]),
    ],
    1,
  )
}

test third_party_act_missing_prog_output() fail {
  validate_third_party_with_outputs(
    [
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

test third_party_act_prog_outputs_out_of_order() fail {
  validate_third_party_with_outputs(
    [
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_programmable_tokens([]),
    ],
    0,
  )
}

// Negative: seized tokens routed to Eve's wallet (NOT at prog_logic_cred).
// The balance invariant rejects this because total output at prog_cred (0)
// is less than total input tokens (42).
test third_party_act_seized_tokens_escape_prog_cred_must_fail() fail {
  let eve_address = Address {
    payment_credential: VerificationKey(
      #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    ),
    stake_credential: None,
  }

  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
        "smuggling_input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([]),
      Output {
        address: eve_address,
        value: from_asset(ada_policy_id, ada_asset_name, 1_000_000)
          |> merge(from_asset(test_third_party_policy, "FOO", 42)),
        datum: NoDatum,
        reference_script: None,
      },
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [Pair(test_third_party_cred, 0)],
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    ThirdPartyRedeemer {
      params_idx: 0,
      registry_node_idx: 1,
      outputs_start_idx: 0,
    },
    fixture.credential_validator_third_party,
    tx,
  )
}

// Canonical happy-path seizure spread base for the Finding 12 tests below.
fn valid_seize_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
        "seize_input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [Pair(test_third_party_cred, 0)],
  }
}

fn run_seize_tx(tx: Transaction) -> Bool {
  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    ThirdPartyRedeemer {
      params_idx: 0,
      registry_node_idx: 1,
      outputs_start_idx: 0,
    },
    fixture.credential_validator_third_party,
    tx,
  )
}

// Positive: seized tokens routed to a new output at prog_logic_cred.
test third_party_act_seized_tokens_to_prog_cred_succeeds() {
  run_seize_tx(valid_seize_tx())
}

// Finding 12: a third-party action cannot CONTAMINATE a paired PLB UTxO that
// didn't already hold the acted-on policy (the paired input holds none of the
// subject policy, the paired output adds 42 FOO). The
// `expect !dict.is_empty(input_tokens_at)` invariant rejects this.
test third_party_act_paired_input_missing_acted_on_policy_fails() fail {
  let tx = Transaction {
    ..valid_seize_tx(),
    inputs: [fixture.some_input_with_programmable_tokens([], "innocent_utxo")],
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
      ),
    ],
  }
  run_seize_tx(tx)
}

// R-03 (re-audit): a degenerate "no-op" third-party action (paired output's
// acted-on amount equals the paired input's) is ACCEPTED — conservation holds,
// no custody is lost; fee-limited off-chain rather than blocked on-chain.
test third_party_act_no_op_seize_succeeds() {
  let tx = Transaction {
    ..valid_seize_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
      ),
    ],
  }
  run_seize_tx(tx)
}

// Positive: partial seizure — seize 40 of 100, leave 60 with the owner.
test third_party_act_partial_seizure_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "partial_seize_input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 60)],
      ),
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 40)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [Pair(test_third_party_cred, 0)],
  }
  run_seize_tx(tx)
}

// Negative: remaining outputs at prog_cred don't have enough seized tokens
// (input 100, paired output 0, remaining only 50 — delta of 50 missing).
test third_party_act_delta_insufficient_remaining_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "insufficient_input",
      ),
    ],
    outputs: [
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 50)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [Pair(test_third_party_cred, 0)],
  }
  run_seize_tx(tx)
}

// ---------------------------------------------------------------------------
// ThirdPartyAct Wipe (Burn) Support Tests
//
// These tests verify that ThirdPartyAct supports burning tokens via tx.mint,
// enabling a compliance "wipe" feature: seize AND burn in one transaction.
// The mint-aware balance invariant adjusts input expectations by tx.mint.
// ---------------------------------------------------------------------------

// Positive: full wipe — seize all 100 FOO and burn all 100.
// Input has 100 FOO, mint has -100 FOO, paired output has 0 FOO.
// Adjusted input = 100 + (-100) = 0, filtered to empty → check trivially passes.
test third_party_act_wipe_full_burn_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "wipe_full_burn_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -100),
    outputs: [
      // Paired output: all FOO removed
      fixture.some_output_with_programmable_tokens([]),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Positive: partial burn — seize all 100 FOO, burn 60, 40 remaining at prog_cred.
// Adjusted input = 100 + (-60) = 40, output has 40 → passes.
test third_party_act_wipe_partial_burn_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "wipe_partial_burn_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -60),
    outputs: [
      // Paired output: all FOO removed from owner
      fixture.some_output_with_programmable_tokens([]),
      // Remaining output: 40 FOO stays at prog_logic_cred
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 40)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Positive: seize + partial burn — seize 80 of 100, burn 50, 30 remaining.
// Owner keeps 20, authority gets 30, 50 burned.
// Adjusted input = 100 + (-50) = 50, output = 20 + 30 = 50 → passes.
test third_party_act_wipe_seize_and_partial_burn() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "wipe_seize_partial_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -50),
    outputs: [
      // Paired output: owner keeps 20 FOO
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 20)],
      ),
      // Remaining output: authority receives 30 seized FOO
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 30)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Negative: burn 30, but remaining output only 50 — need 70.
// Adjusted input = 100 + (-30) = 70, output = 0 + 50 = 50 < 70 → fails.
test third_party_act_wipe_insufficient_after_burn_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "wipe_insufficient_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -30),
    outputs: [
      // Paired output: all FOO removed
      fixture.some_output_with_programmable_tokens([]),
      // Remaining output: only 50 FOO, but adjusted input expects 70
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 50)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Negative: spending and burning some tokens (exact quantities), without executing the 3rd party script.
test third_party_act_unauthorized_burn_compensate_spend() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "programmable tokens",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 50)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [Pair(fixture.credential_validator_transfer, 0)],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Negative: spending and burning some tokens (exact quantities), without providing adequate proof.
test third_party_act_unproven_burn_compensate_spend() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "programmable tokens",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 50)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        "not-the-expected-policy",
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// ---------------------------------------------------------------------------
// ThirdPartyAct Mint Interaction Tests
//
// Verify that minting during a ThirdPartyAct (seizure) behaves correctly for
// all combinations: same-policy mint, other-policy mint (programmable or not),
// and mixed mints. The balance invariant only tracks the seized policy_id;
// other mints are invisible to it. Each layer handles its own authorization:
// - issuance_mint → authorizes minting/burning
// - validate_third_party → tracks balance for the seized policy
// - programmable_logic_base → authorizes spending from prog_cred
// ---------------------------------------------------------------------------

/// An unrelated policy used to test minting of tokens other than the seized policy.
/// From the validator's perspective, programmable vs non-programmable is identical:
/// get_policy_tokens only extracts the seized policy, so this is invisible to the
/// balance invariant regardless. issuance_mint handles programmable mint authorization
/// externally.
const test_unrelated_policy: PolicyId =
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"

// Positive: mint same policy during seizure — adjusted input INCREASES.
// Seize 100 FOO, mint 50 more FOO → adjusted input = 150.
// Output must have >= 150 FOO at prog_cred.
// Not exploitable: issuance_mint forces minted tokens to prog_cred,
// so the minter is just raising the bar for themselves.
test third_party_act_same_policy_mint_during_seizure_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "same_policy_mint_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", 50),
    outputs: [
      // Paired output: all FOO removed from owner
      fixture.some_output_with_programmable_tokens([]),
      // Remaining output: 100 seized + 50 minted = 150 at prog_cred
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 150)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Negative: mint same policy during seizure but insufficient output.
// Seize 100 FOO, mint 50 → adjusted input = 150, but output only has 100.
test third_party_act_same_policy_mint_insufficient_output_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "same_policy_mint_fail_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", 50),
    outputs: [
      // Paired output: all FOO removed
      fixture.some_output_with_programmable_tokens([]),
      // Only 100 FOO, but adjusted input expects 150
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Positive: mint an unrelated policy during seizure.
// Seized policy is test_third_party_policy; the unrelated mint is invisible
// to the balance invariant (get_policy_tokens ignores it).
// Programmable vs non-programmable doesn't matter here — the validator
// doesn't distinguish. issuance_mint handles programmable authorization
// externally; non-programmable tokens have their own minting policy.
test third_party_act_unrelated_policy_mint_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "unrelated_mint_input",
      ),
    ],
    mint: from_asset(test_unrelated_policy, "BAR", 500),
    outputs: [
      // Paired output: all FOO removed
      fixture.some_output_with_programmable_tokens([]),
      // Remaining output: seized FOO stays at prog_cred
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Positive: wipe (burn seized policy) + mint unrelated policy in the same tx.
// This is the realistic compliance scenario: admin burns seized tokens while
// the tx also mints something unrelated (e.g. a receipt NFT).
// Balance invariant sees only the seized policy burn; unrelated mint is invisible.
test third_party_act_wipe_burn_plus_unrelated_mint_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "mixed_mint_input",
      ),
    ],
    mint: from_asset(test_third_party_policy, "FOO", -60)
      |> merge(from_asset(test_unrelated_policy, "RECEIPT", 1)),
    outputs: [
      // Paired output: all FOO removed from owner
      fixture.some_output_with_programmable_tokens([]),
      // Remaining output: 40 FOO stays at prog_cred (100 - 60 burned)
      fixture.some_output_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 40)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }

  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx: 0,
  }

  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// =========================================================================
// Finding 13: reference_script preservation across ThirdPartyAct
//
// `check_seized_tokens` pairs each prog_logic_cred input with the next
// continuing output and asserts address+datum equality. Without an
// equality check on `reference_script`, a third-party-act tx could swap
// a legitimate reference script for a malicious one (or add/remove one)
// while seizing tokens. Post-fix, `output.reference_script ==
// input.reference_script` is enforced per pair.
// =========================================================================

/// Sample reference-script hashes used to exercise the new equality check.
const test_ref_script_hash: ScriptHash =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const test_ref_script_hash_other: ScriptHash =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

/// Spread an existing programmable-tokens input and override its
/// `reference_script` field. Per CLAUDE.md test conventions: one
/// delta from the canonical fixture, made obvious at the call site.
fn input_with_ref_script(
  tokens: List<(PolicyId, AssetName, Int)>,
  label: ByteArray,
  ref_script: Option<ScriptHash>,
) -> Input {
  let base = fixture.some_input_with_programmable_tokens(tokens, label)
  Input {
    ..base,
    output: Output { ..base.output, reference_script: ref_script },
  }
}

/// Spread a paired programmable-tokens output and override its
/// `reference_script` field.
fn output_with_ref_script(
  tokens: List<(PolicyId, AssetName, Int)>,
  ref_script: Option<ScriptHash>,
) -> Output {
  Output {
    ..fixture.some_output_with_programmable_tokens(tokens),
    reference_script: ref_script,
  }
}

/// Variant of `validate_third_party_with_outputs` that also takes
/// custom inputs, so `reference_script` on the inputs can be set
/// per-test. Reuses the same registry-node ref input + withdrawals
/// shape as the existing helper.
fn validate_third_party_with_inputs_and_outputs(
  inputs: List<Input>,
  outputs: List<Output>,
  outputs_start_idx: Int,
) -> Bool {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs,
    outputs,
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      third_party_registry_node_ref_input(
        test_third_party_policy,
        test_third_party_cred,
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(test_third_party_cred, 0),
    ],
  }
  let redeemer = ThirdPartyRedeemer {
    params_idx: 0,
    registry_node_idx: 1,
    outputs_start_idx,
  }
  third_party.third_party.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_third_party,
    tx,
  )
}

// Finding 13 positive: matching `Some(script_hash)` reference scripts
// on input and output pass the new per-pair equality check. Seizure
// still succeeds; only the reference_script invariant is exercised.
test third_party_act_matching_reference_script_preserved() {
  validate_third_party_with_inputs_and_outputs(
    [
      input_with_ref_script(
        [(test_third_party_policy, "FOO", 42)],
        "ref_script_input_a",
        Some(test_ref_script_hash),
      ),
      input_with_ref_script(
        [(test_third_party_policy, "FOO", 100)],
        "ref_script_input_b",
        Some(test_ref_script_hash),
      ),
    ],
    [
      output_with_ref_script([], Some(test_ref_script_hash)),
      output_with_ref_script([], Some(test_ref_script_hash)),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// Finding 13 negative (added): input has no reference_script but the
// continuing output attaches one. Pre-fix this would have passed
// silently — seizure would drop a "free" attestation on the
// continuing UTxO. Post-fix, the per-pair equality rejects.
test third_party_act_reference_script_added_fails() fail {
  validate_third_party_with_inputs_and_outputs(
    [
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 42)],
        "no_ref_script_input_a",
      ),
      fixture.some_input_with_programmable_tokens(
        [(test_third_party_policy, "FOO", 100)],
        "no_ref_script_input_b",
      ),
    ],
    [
      // Attacker attaches a reference script to the first continuing output.
      output_with_ref_script([], Some(test_ref_script_hash)),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// Finding 13 negative (swapped): input and output both carry reference
// scripts, but the output points at a different hash. Catches an
// attacker swapping a legitimate attestation for a misleading one
// during seizure.
test third_party_act_reference_script_swapped_fails() fail {
  validate_third_party_with_inputs_and_outputs(
    [
      input_with_ref_script(
        [(test_third_party_policy, "FOO", 42)],
        "swap_ref_script_input_a",
        Some(test_ref_script_hash),
      ),
      input_with_ref_script(
        [(test_third_party_policy, "FOO", 100)],
        "swap_ref_script_input_b",
        Some(test_ref_script_hash),
      ),
    ],
    [
      // First output swaps to a DIFFERENT reference-script hash.
      output_with_ref_script([], Some(test_ref_script_hash_other)),
      output_with_ref_script([], Some(test_ref_script_hash)),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// ---------------------------------------------------------------------------
// [AL] issue #96: per-pair lovelace must RATCHET (output >= input), not be
// strictly equal. `split_at` runs on the full Value, so the ada entry (empty
// policy id, sorts first) lands in the `before` half and its byte-equality
// forces the paired output to carry EXACTLY the input's lovelace. If a
// protocol-parameter update raises the min-ADA calculation above an existing
// UTxO's lovelace (even by 1), every ThirdPartyAct on that UTxO becomes
// unsatisfiable forever — equality forbids the top-up that would absorb the
// rise.
// ---------------------------------------------------------------------------

/// A foreign programmable policy that sorts BEFORE `test_third_party_policy`,
/// so it lives in the same `before` half as ada — guards that peeling ada off
/// the pair comparison does not weaken the non-acted-on-policy byte-identity.
const test_policy_sorting_before: PolicyId =
  #"00000000000000000000000000000000000000000000000000000e00"

/// Spread a paired programmable-tokens output and add `delta` lovelace on top
/// of the fixture's min-ada value (negative delta = drain).
fn output_with_extra_lovelace(
  tokens: List<(PolicyId, AssetName, Int)>,
  delta: Int,
) -> Output {
  let base = fixture.some_output_with_programmable_tokens(tokens)
  Output {
    ..base,
    value: base.value
      |> merge(from_asset(ada_policy_id, ada_asset_name, delta)),
  }
}

// [AL] issue #96 positive: topping the paired output up by even a couple of
// lovelace must be ACCEPTED — it is exactly the move that absorbs a min-ADA
// parameter rise. Against the pre-fix code (strict before-half equality) this
// test FAILS, proving the report.
test third_party_act_pair_ada_topup_succeeds() {
  validate_third_party_with_outputs(
    [
      // Paired output: identical token set, 2 lovelace MORE than its input.
      output_with_extra_lovelace([], 2),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// [AL] issue #96 negative: the ratchet is one-way. Lovelace is NOT a
// programmable asset — accepting less on the paired output would let the
// admin drain the holder's ada while seizing. output < input must fail.
test third_party_act_pair_ada_drain_fails() fail {
  validate_third_party_with_outputs(
    [
      // Paired output: identical token set, 2 lovelace LESS than its input.
      output_with_extra_lovelace([], -2),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// [AL] issue #96 regression guard: ada shares the `before` half with every
// policy that sorts below the acted-on one. Peeling ada off the comparison
// must NOT loosen the rest of that half — injecting a foreign-policy token
// into the paired output still fails.
test third_party_act_pair_foreign_policy_injection_still_fails() fail {
  validate_third_party_with_outputs(
    [
      // Paired output: a token of a NON-acted-on policy appears from nowhere.
      output_with_extra_lovelace([(test_policy_sorting_before, "BAR", 1)], 0),
      fixture.some_output_with_programmable_tokens([]),
      fixture.some_output_with_seized_tokens(
        [(test_third_party_policy, "FOO", 142)],
      ),
    ],
    0,
  )
}

// ===========================================================================
// Issue #106 — a seizure's DESTINATION outputs must stay seizable in turn
// ===========================================================================
//
// A third-party action creates fresh PLB UTxOs: the destinations the seized
// tokens land in. They are not paired outputs (those are byte-identical to
// their inputs and so inherit their shape), and until now nothing constrained
// them — so an administrator, or a hostile substandard's third-party logic,
// could seize tokens into a UTxO that could never be seized again. Each test
// below is ONE delta from `valid_seize_tx`: the destination output's shape.

/// The seizure destination — `valid_seize_tx`'s second output, the one holding
/// the 42 seized FOO — rebuilt with a caller-chosen shape.
fn seize_with_destination(datum: Datum, ref_script: Option<ScriptHash>) -> Bool {
  let base = fixture.some_output_with_programmable_tokens(
    [(test_third_party_policy, "FOO", 42)],
  )
  let tx = Transaction {
    ..valid_seize_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([]),
      Output { ..base, datum, reference_script: ref_script },
    ],
  }
  run_seize_tx(tx)
}

// A datum HASH on the destination would make the seized UTxO unspendable by
// anyone without the preimage — the vector of issue #106, applied by the
// administrator rather than by the holder.
test third_party_act_destination_datum_hash_fails() fail {
  seize_with_destination(
    DatumHash(
      #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00",
    ),
    None,
  )
}

// A reference script on the destination would bloat every FUTURE seizure of
// that UTxO, which must reproduce it byte-for-byte.
test third_party_act_destination_reference_script_fails() fail {
  seize_with_destination(
    NoDatum,
    Some(#"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"),
  )
}

// The destination keeps its inline stake credential. Without one there is no
// owner `owner.ak` could ever authorise, so the tokens would be permanently
// unspendable. `issuance_mint` skips `no_escape` when it delegates custody to
// this path, so this check is the only thing standing between a mint composed
// with a seize and an unspendable output.
test third_party_act_destination_without_stake_credential_fails() fail {
  let base = fixture.some_output_with_programmable_tokens(
    [(test_third_party_policy, "FOO", 42)],
  )
  let tx = Transaction {
    ..valid_seize_tx(),
    outputs: [
      fixture.some_output_with_programmable_tokens([]),
      Output {
        ..base,
        address: Address { ..base.address, stake_credential: None },
      },
    ],
  }
  run_seize_tx(tx)
}

// Positive control: the ordinary destination shape (inline stake credential,
// no datum, no reference script) still passes — the guard rejects only the
// three shapes above.
test third_party_act_destination_plain_shape_succeeds() {
  seize_with_destination(NoDatum, None)
}

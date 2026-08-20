//// Integration tests for the standalone third_party (seize / clawback /
//// freeze) withdraw-0 validator.
////
//// These exercise `third_party.withdraw` with a `ThirdPartyRedeemer` — the
//// same invariants the inline `ThirdPartyAct` arm of programmable_logic_global
//// used to enforce (`validate_3rd_party` in programmable_logic/third_party),
//// now hosted in their own script. The transaction always presents the
//// subject policy's registry node as a reference input and the issuer's
//// third_party_transfer_logic_script withdrawal; the framework validator's
//// own presence is enforced by programmable_logic_base (SpendViaThirdParty),
//// not here.

use aiken/crypto.{blake2b_256}
use cardano/address.{Address, Credential, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
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

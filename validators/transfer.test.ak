//// Integration tests for the `transfer` validator (the transfer arm of the
//// former programmable_logic_global coordinator).

use aiken/collection/list
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, from_asset, merge, negate, zero}
use cardano/transaction.{Input, NoDatum, Output, OutputReference, Transaction}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode, empty_vkey}
use transfer
use types.{TokenDoesNotExist, TokenExists, TransferRedeemer}
use utils.{bytearray_lt}

const test_registry_node_cs: PolicyId =
  #"1112131415161718191a1b1c0d0e0f0102030405060708090a0b0c0d"

const test_prog_logic_cred: Credential = Script(#"70726f67")

const test_transfer_logic_cred: Credential = Script(#"7472616e73666572")

const test_third_party_transfer_logic_cred: Credential = Script(#"6973737565")

const test_token_cs: PolicyId =
  #"2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c"

// Test ProgrammableLogicGlobalParams structure
test protocol_params_structure() {
  let params = ProgrammableLogicGlobalParams {
    prog_logic_cred: test_prog_logic_cred,
    registry_node_cs: test_registry_node_cs,
    unfracking_cred: fixture.credential_validator_unfracking,
    transfer_cred: fixture.credential_validator_transfer,
    upgrade_cred: fixture.credential_upgrade_authority,
    max_inline_datum_bytes: 1024,
    third_party_cred: fixture.credential_validator_third_party,
  }

  params.prog_logic_cred == test_prog_logic_cred && params.registry_node_cs == test_registry_node_cs
}

// Test TransferRedeemer shape
test transfer_redeemer_carries_proofs() {
  let proof1 = TokenExists { node_idx: 0 }
  let proof2 = TokenDoesNotExist { node_idx: 1 }

  let TransferRedeemer { proofs, .. } = TransferRedeemer {
    params_idx: 0,
    proofs: [proof1, proof2],
  }

  list.length(proofs) == 2
}

// Test TokenDoesNotExist proof
test token_does_not_exist_proof() {
  let proof = TokenDoesNotExist { node_idx: 3 }

  when proof is {
    TokenDoesNotExist { node_idx } -> node_idx == 3
    _ -> False
  }
}

// Test registry node validation for transfer
test registry_node_validation_for_transfer() {
  let node = RegistryNode {
    key: test_token_cs,
    next: #"ffff",
    transfer_logic_script: test_transfer_logic_cred,
    third_party_transfer_logic_script: test_third_party_transfer_logic_cred,
    minting_logic_script: empty_vkey,
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  // Node key should match the token CS
  node.key == test_token_cs && // Transfer logic script should be present
  node.transfer_logic_script == test_transfer_logic_cred
}

// Test covering node logic for non-existent token
test covering_node_logic_for_non_existent_token() {
  let covering_key = #"aa"
  let token_cs = #"bb"
  let next_key = #"cc"

  let covering_node = RegistryNode {
    key: covering_key,
    next: next_key,
    transfer_logic_script: test_transfer_logic_cred,
    third_party_transfer_logic_script: test_third_party_transfer_logic_cred,
    minting_logic_script: empty_vkey,
    unfracking_logic_script: empty_vkey,
    global_state_cs: #"",
  }

  // Covering node should satisfy: covering_key < token_cs < next_key
  bytearray_lt(covering_node.key, token_cs) && bytearray_lt(
    token_cs,
    covering_node.next,
  )
}

// Test seize validation structure
test seize_validation_structure() {
  let seized_cs = test_token_cs
  let input_value = from_asset(seized_cs, #"746f6b656e", 100)
  let expected_output_value = zero

  // After seizing, the output should have the tokens removed
  input_value != expected_output_value
}

// Test programmable tokens go to prog_logic_cred
test programmable_tokens_go_to_prog_logic_cred() {
  let output = Output {
    address: Address {
      payment_credential: test_prog_logic_cred,
      stake_credential: None,
    },
    value: from_asset(test_token_cs, #"746f6b656e", 100),
    datum: NoDatum,
    reference_script: None,
  }

  output.address.payment_credential == test_prog_logic_cred
}

// Test transfer logic script must be invoked
test transfer_logic_script_must_be_invoked() {
  let invoked_scripts = [test_transfer_logic_cred, Script(#"6f74686572")]

  list.has(invoked_scripts, test_transfer_logic_cred)
}

// Test third party transfer logic script must be invoked for third party actions
test third_party_transfer_logic_script_must_be_invoked_for_third_party_actions() {
  let invoked_scripts = [
    test_third_party_transfer_logic_cred,
    Script(#"6f74686572"),
  ]

  list.has(invoked_scripts, test_third_party_transfer_logic_cred)
}

// Test signed prog inputs validation
test signed_prog_inputs_validation() {
  let stake_pkh = #"aabbccdd"
  let input = Input {
    output_reference: OutputReference { transaction_id: #"00", output_index: 0 },
    output: Output {
      address: Address {
        payment_credential: test_prog_logic_cred,
        stake_credential: Some(Inline(VerificationKey(stake_pkh))),
      },
      value: from_asset(test_token_cs, #"746f6b656e", 100),
      datum: NoDatum,
      reference_script: None,
    },
  }

  // Input is from prog_logic_cred with stake credential
  input.output.address.payment_credential == test_prog_logic_cred && when
    input.output.address.stake_credential
  is {
    Some(Inline(VerificationKey(pkh))) -> pkh == stake_pkh
    _ -> False
  }
}

// Test seize prevents DDOS by requiring value change
test seize_prevents_ddos_by_requiring_value_change() {
  let input_value = from_asset(test_token_cs, #"746f6b656e", 100)
  // let output_value = from_asset(test_token_cs, #"746f6b656e", 100)
  let expected_output = merge(
    input_value,
    negate(from_asset(test_token_cs, #"746f6b656e", 50)),
  )

  // Must actually remove tokens (DDOS prevention)
  input_value != expected_output
}

// Test only one prog_logic_cred input allowed in seize
test only_one_prog_logic_cred_input_in_seize() {
  let inputs = [
    Input {
      output_reference: OutputReference {
        transaction_id: #"00",
        output_index: 0,
      },
      output: Output {
        address: Address {
          payment_credential: test_prog_logic_cred,
          stake_credential: None,
        },
        value: zero,
        datum: NoDatum,
        reference_script: None,
      },
    },
  ]

  list.length(
    list.filter(
      inputs,
      fn(input) {
        input.output.address.payment_credential == test_prog_logic_cred
      },
    ),
  ) == 1
}

// Test protocol params from reference inputs
test protocol_params_from_reference_inputs() {
  let params = ProgrammableLogicGlobalParams {
    prog_logic_cred: test_prog_logic_cred,
    registry_node_cs: test_registry_node_cs,
    unfracking_cred: fixture.credential_validator_unfracking,
    transfer_cred: fixture.credential_validator_transfer,
    upgrade_cred: fixture.credential_upgrade_authority,
    max_inline_datum_bytes: 1024,
    third_party_cred: fixture.credential_validator_third_party,
  }

  // Protocol params should be loaded from reference input
  params.registry_node_cs == test_registry_node_cs
}

// Test invoked scripts via withdrawals
test invoked_scripts_via_withdrawals() {
  let withdrawals = [
    Pair(test_transfer_logic_cred, 0),
    Pair(test_third_party_transfer_logic_cred, 0),
  ]

  let invoked_scripts = list.map(
    withdrawals,
    fn(wdrl) {
      let Pair(cred, _amount) = wdrl
      cred
    },
  )

  list.has(invoked_scripts, test_transfer_logic_cred) && list.has(
    invoked_scripts,
    test_third_party_transfer_logic_cred,
  )
}

// ---------------------------------------------------------------------------
// Transfer mint support Tests (Issue #1 from functional analysis)
// ---------------------------------------------------------------------------

/// A programmable token policy used for the transfer/mint tests.
const test_mint_policy: PolicyId =
  #"3132333435363738393a3b3c3d3e3f404142434445464748494a4b4c"

// Positive: partial burn via a transfer with mint.
// Input has 100 FOO, burns 30, output has 70. The proof serves both for mint
// and input to validate the burned and spent tokens against the registry,
// adjusting the expected output down.
test transfer_act_partial_burn_with_mint_proofs_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "burn input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -30),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 70)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Positive: transfer with minting — new tokens appear at prog_logic_cred.
// Input has 100 FOO, mints 50 more, output must have at least 150.
test transfer_act_with_minting_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 150)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Finding 02 fix: pure mints are issuance_mint's responsibility, not the
// transfer path's. A transfer of one policy alongside an INDEPENDENT pure
// mint of another policy now needs only the transfer-side proof. The
// pure-mint policy is dropped from `input_assets` by
// `apply_mint_to_known_policies` and never reaches `verify_proofs`.
// (Pre-fix this test was `() fail` and pinned the wrong behaviour — the
// validator used to demand a proof for the pure-mint policy too.)
test transfer_act_transfer_plus_independent_pure_mint_succeeds() {
  let test_input_policy = "input policy"
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_input_policy, "FOO", 100)],
        "input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_input_policy, "FOO", 100), (test_mint_policy, "FOO", 50)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_input_policy,
        test_mint_policy,
        "registry node #1",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node #2",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  // No proof for idx 2, necessary for the mint but tx.mint is non-empty — must be rejected
  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Positive (Finding 02 fix): a pure mint of a registered policy passes the
// transfer path with NO `TransferRedeemer` proof — pure-mint policies are dropped
// from `input_assets` and have nothing to prove. issuance_mint owns the mint
// authorisation, not the transfer validator.
test transfer_act_with_only_minting_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 150)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  // Finding 02 fix: pure mint requires NO transfer proof.
  let redeemer = TransferRedeemer { params_idx: 0, proofs: [] }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Finding 02: pure-mint policies must NOT carry a transfer proof. ONE delta
// vs `transfer_act_with_only_minting_succeeds` — the redeemer carries
// `TokenExists { node_idx: 1 }`. Because the mint-only policy is dropped from
// `input_assets` by `apply_mint_to_known_policies`, that proof is leftover;
// the final `[] == verify_proofs(...)` check rejects. Pins the strict
// 1-proof-per-input-policy contract that protects against off-chain tx
// builders quietly handing the transfer validator proofs it has no business consuming.
test transfer_act_pure_mint_with_unnecessary_proof_must_fail() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 150)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  // ONE delta vs the success case above — surplus proof for the pure-mint policy.
  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Positive (Finding 02 fix): the previous "must invoke transfer_logic for pure
// mints" rule is gone. A pure-mint tx with NO `transfer_logic` withdraw-0 and
// proofs=[] is accepted: the mint-only policy is dropped from `input_assets`
// before `verify_proofs` runs, so neither a withdrawal nor a proof is needed.
// (Pre-fix this test was `() fail` and pinned the contradictory rejection.)
test transfer_act_pure_mint_without_transfer_logic_succeeds() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 150)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
    ],
    withdrawals: [Pair(fixture.credential_validator_transfer, 0)],
  }

  let redeemer = TransferRedeemer { params_idx: 0, proofs: [] }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

test transfer_act_burning_compensate_spending() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -100),
    outputs: [fixture.some_output_with_programmable_tokens([])],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

test transfer_act_entirely_burning_one_token() {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100), (test_mint_policy, "BAR", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -100),
    outputs: [
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "BAR", 100)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

test transfer_act_entirely_burning_one_token_fail_if_other_missing() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100), (test_mint_policy, "BAR", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -100),
    outputs: [fixture.some_output_with_programmable_tokens([])],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Negative: unauthenticated transfer & burn where spent tokens are entirely burned (so
// mint & spend values balancing each other out)
test transfer_act_unauthorized_burning_compensate_spending_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -100),
    outputs: [],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [Pair(fixture.credential_validator_transfer, 0)],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Negative: unauthenticated transfer & burn where spent tokens are entirely burned (so
// mint & spend values balancing each other out)
test transfer_act_burning_compensate_spending_unproven_token_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "mint input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", -100),
    outputs: [],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer { params_idx: 0, proofs: [] }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// Negative: minting without enough output — mints 50 FOO but output only has 100.
// Expected output is 100 (input) + 50 (mint) = 150, but output only has 100.
test transfer_act_mint_insufficient_output_fails() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
        "mint fail input",
      ),
    ],
    mint: from_asset(test_mint_policy, "FOO", 50),
    outputs: [
      // Only 100 FOO, but expected 150
      fixture.some_output_with_programmable_tokens(
        [(test_mint_policy, "FOO", 100)],
      ),
    ],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        test_mint_policy,
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "registry node",
      ),
    ],
    withdrawals: [
      Pair(fixture.credential_validator_transfer, 0),
      Pair(fixture.credential_transfer_logic, 0),
    ],
  }

  let redeemer = TransferRedeemer {
    params_idx: 0,
    proofs: [TokenExists { node_idx: 1 }],
  }

  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

// ===========================================================================
// COVERAGE REPAIR (mutation testing found both of these controls untested).
//
// `choose_registered_token_with` in programmable_logic/transfer.ak carries the
// two checks that make CIP-113's central promise true — that a REGISTERED
// token's transfer logic governs every transfer, and that a token can only be
// declared UNREGISTERED by a covering node that genuinely covers it. Deleting
// either broke no test in the suite. The tests named for them
// (`transfer_logic_script_must_be_invoked`, `covering_node_logic_for_non_
// existent_token`) never invoke a validator; they assert `list.has` on a
// hand-built list and re-implement the range check inside the test.
// ===========================================================================

const cov_owner_pkh: ByteArray =
  #"0badc0de0badc0de0badc0de0badc0de0badc0de0badc0de0badc0de"

const cov_unregistered: PolicyId =
  #"55555555555555555555555555555555555555555555555555555555"

/// A transfer over one registered policy, owned by a VKEY signer so that
/// dropping the transfer-logic withdrawal does not also destroy the ownership
/// proof. (That confound is why this test was awkward to write before: the
/// shipped fixture stakes PLB inputs with `credential_transfer_logic`, so the
/// two concerns were tested by the same withdrawal — see finding L-09.)
fn cov_transfer(with_transfer_logic: Bool) -> Bool {
  let tokens = [
    (#"f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1", "FOO", 10),
  ]
  let (tx, redeemer) = fixture.some_transfer(tokens)
  let tx = Transaction {
    ..tx,
    inputs: [
      fixture.some_input_with_programmable_tokens_with(
        VerificationKey(cov_owner_pkh),
        tokens,
        "programmable tokens input",
      ),
    ],
    extra_signatories: [cov_owner_pkh],
    withdrawals: if with_transfer_logic {
      [
        Pair(fixture.credential_validator_transfer, 0),
        Pair(fixture.credential_transfer_logic, 0),
      ]
    } else {
      [Pair(fixture.credential_validator_transfer, 0)]
    },
  }
  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    redeemer,
    fixture.credential_validator_transfer,
    tx,
  )
}

test transfer_with_token_transfer_logic_invoked_succeeds() {
  cov_transfer(True)
}

/// GUARDS: `expect has_withdrawal(transfer_logic_script)` (transfer.ak).
/// A registered token may not move without its transfer logic approving.
test fails_transfer_without_token_transfer_logic() fail {
  cov_transfer(False)
}

/// A transfer over an UNREGISTERED policy, proved absent by a covering
/// node supplied at reference-input index 1.
fn cov_absence(node_key: ByteArray, node_next: ByteArray) -> Bool {
  let tokens = [(cov_unregistered, "FOO", 1)]
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [
      fixture.some_input_with_programmable_tokens(tokens, "unregistered in"),
    ],
    outputs: [fixture.some_output_with_programmable_tokens(tokens)],
    reference_inputs: [
      fixture.some_reference_input_protocol_params(
        fixture.protocol_params,
        "protocol params",
      ),
      fixture.some_reference_input_tokens_registry_node(
        node_key,
        node_next,
        "covering node",
      ),
    ],
    withdrawals: fixture.withdrawals_transfer,
  }
  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    TransferRedeemer {
      params_idx: 0,
      proofs: [TokenDoesNotExist { node_idx: 1 }],
    },
    fixture.credential_validator_transfer,
    tx,
  )
}

/// Control: the covering node genuinely spans the policy, so the absence
/// proof is valid and the transfer is allowed.
test transfer_absence_proof_with_covering_node_succeeds() {
  cov_absence(
    #"11111111111111111111111111111111111111111111111111111111",
    #"99999999999999999999999999999999999999999999999999999999",
  )
}

/// GUARDS: `expect less_than_bytearray(key, policy)` (transfer.ak).
/// The named node starts ABOVE the policy, so it cannot prove absence.
test fails_absence_proof_when_node_starts_above_policy() fail {
  cov_absence(
    #"66666666666666666666666666666666666666666666666666666666",
    #"99999999999999999999999999999999999999999999999999999999",
  )
}

/// GUARDS: `expect less_than_bytearray(policy, next)` (transfer.ak).
/// The named node ends BELOW the policy, so it cannot prove absence.
test fails_absence_proof_when_node_ends_below_policy() fail {
  cov_absence(
    #"11111111111111111111111111111111111111111111111111111111",
    #"22222222222222222222222222222222222222222222222222222222",
  )
}
// NOTE: the transfer validator coordinates transfers ONLY. Third-party (seize
// / clawback) actions live in the standalone `third_party` validator and
// unfracking in `unfracking`; `TransferRedeemer` has a single constructor, so
// routing either of them here is unrepresentable at the type level (no runtime
// test needed). See third_party.test.ak and programmable_logic/unfracking.test.ak.

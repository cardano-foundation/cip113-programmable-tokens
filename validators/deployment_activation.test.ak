//// Deployment composition: protocol-params genesis activates the exact
//// upgrade authority it installs.
////
//// These tests drive `protocol_params.mint` and `upgrade_multisig.withdraw`
//// against the SAME transaction. The protocol-params handler proves that the
//// datum names a credential present in `withdrawals`; the authority handler
//// proves that the referenced config exists, decodes, and its approval tree
//// is satisfied. Neither half alone proves the deployment invariant.

use cardano/address.{Address, Credential, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use multisig.{AtLeast, MultisigScript, Signature}
use programmable_logic/params.{ProtocolParams, protocol_params_token}
use protocol_params
use upgrade_multisig.{upgrade_multisig_token}

// ---------------------------------------------------------------------------
// Deployment identities
// ---------------------------------------------------------------------------

const params_seed_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 0,
  }

const upgrade_seed_ref: OutputReference =
  OutputReference {
    transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
    output_index: 0,
  }

const upgrade_config_ref: OutputReference =
  OutputReference {
    transaction_id: #"3333333333333333333333333333333333333333333333333333333333333333",
    output_index: 0,
  }

const params_policy_id: PolicyId =
  #"40404040404040404040404040404040404040404040404040404040"

/// The applied `upgrade_multisig(upgrade_seed_ref)` hash. It is simultaneously
/// the config NFT policy, config payment credential, and withdraw-0 credential.
const upgrade_multisig_hash: ByteArray =
  #"50505050505050505050505050505050505050505050505050505050"

const wrong_authority_hash: ByteArray =
  #"60606060606060606060606060606060606060606060606060606060"

const alice: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const bob: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const carol: ByteArray =
  #"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"

// ---------------------------------------------------------------------------
// Config and protocol-params fixtures
// ---------------------------------------------------------------------------

fn authority_tree() -> MultisigScript {
  AtLeast {
    required: 2,
    scripts: [
      Signature { key_hash: alice },
      Signature { key_hash: bob },
      Signature { key_hash: carol },
    ],
  }
}

fn config_output(datum: Data) -> Output {
  Output {
    address: Address {
      payment_credential: Script(upgrade_multisig_hash),
      stake_credential: None,
    },
    value: assets.zero
      |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
      |> assets.add(upgrade_multisig_hash, upgrade_multisig_token, 1),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn config_reference() -> Input {
  Input {
    output_reference: upgrade_config_ref,
    output: config_output(as_data(authority_tree())),
  }
}

fn params_seed_input() -> Input {
  Input {
    output_reference: params_seed_ref,
    output: Output {
      address: Address {
        payment_credential: VerificationKey(alice),
        stake_credential: None,
      },
      value: assets.from_lovelace(5_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn params_datum(authority: Credential) -> Data {
  as_data(
    ProtocolParams {
      programmable_logic_global_cred: Script(
        #"70707070707070707070707070707070707070707070707070707070",
      ),
      issuance_logic_cred: Script(
        #"71717171717171717171717171717171717171717171717171717171",
      ),
      transfer_cred: Script(
        #"72727272727272727272727272727272727272727272727272727272",
      ),
      third_party_cred: Script(
        #"73737373737373737373737373737373737373737373737373737373",
      ),
      upgrade_cred: authority,
      pending_upgrade_cred: None,
    },
  )
}

fn params_output(authority: Credential) -> Output {
  Output {
    address: Address {
      payment_credential: Script(params_policy_id),
      stake_credential: None,
    },
    value: assets.zero
      |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
      |> assets.add(params_policy_id, protocol_params_token, 1),
    datum: InlineDatum(params_datum(authority)),
    reference_script: None,
  }
}

fn activation_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [params_seed_input()],
    reference_inputs: [config_reference()],
    outputs: [params_output(Script(upgrade_multisig_hash))],
    mint: assets.from_asset(params_policy_id, protocol_params_token, 1),
    withdrawals: [Pair(Script(upgrade_multisig_hash), 0)],
    extra_signatories: [alice, bob],
  }
}

// ---------------------------------------------------------------------------
// Composed calls
// ---------------------------------------------------------------------------

fn call_params_genesis(tx: Transaction) -> Bool {
  protocol_params.protocol_params.mint(
    params_seed_ref,
    Void,
    params_policy_id,
    tx,
  )
}

fn call_upgrade_authority(tx: Transaction) -> Bool {
  upgrade_multisig.upgrade_multisig.withdraw(
    upgrade_seed_ref,
    Void,
    Script(upgrade_multisig_hash),
    tx,
  )
}

fn call_activation(tx: Transaction) -> Bool {
  and {
    call_params_genesis(tx)?,
    call_upgrade_authority(tx)?,
  }
}

// ---------------------------------------------------------------------------
// Activation ceremony
// ---------------------------------------------------------------------------

test deployment_activation_succeeds_at_threshold() {
  call_activation(activation_tx())
}

// The params mint sees the declared withdrawal, but the multisig itself still
// rejects a ceremony that has not proved possession of a threshold of keys.
test deployment_activation_fails_below_threshold() fail {
  call_activation(Transaction { ..activation_tx(), extra_signatories: [alice] })
}

// A withdrawal for the deployed multisig cannot activate a different hash
// written into `ProtocolParams.upgrade_cred`.
test deployment_activation_fails_mismatched_authority_hash() fail {
  call_activation(
    Transaction {
      ..activation_tx(),
      outputs: [params_output(Script(wrong_authority_hash))],
    },
  )
}

// Even a satisfiable multisig is not the declared authority unless its
// withdraw-0 is present in the genesis transaction.
test deployment_activation_fails_missing_withdrawal() fail {
  call_activation(Transaction { ..activation_tx(), withdrawals: [] })
}

// The reference must carry this multisig instance's one-shot config NFT; an
// arbitrary UTxO at the same address is not configuration.
test deployment_activation_fails_wrong_config_nft() fail {
  let wrong_config = Input {
    ..config_reference(),
    output: Output {
      ..config_output(as_data(authority_tree())),
      value: assets.from_lovelace(2_000_000)
        |> assets.add(wrong_authority_hash, upgrade_multisig_token, 1),
    },
  }
  call_activation(
    Transaction { ..activation_tx(), reference_inputs: [wrong_config] },
  )
}

// Finding the NFT is not enough: its inline datum must decode as the approval
// tree that is actually evaluated during activation.
test deployment_activation_fails_malformed_config_datum() fail {
  let malformed = Input {
    ..config_reference(),
    output: config_output(as_data(42)),
  }
  call_activation(
    Transaction { ..activation_tx(), reference_inputs: [malformed] },
  )
}

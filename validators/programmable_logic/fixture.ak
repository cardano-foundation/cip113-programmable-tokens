//// Fixtures, fuzzers and arbitrary data useful to bench and tests the programmable logic validators end to end.

use aiken/collection/dict
use aiken/collection/dict/strategy.{keep_left}
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/fuzz
use cardano/address.{Address, Credential, Inline}
use cardano/assets.{AssetName, PolicyId, Value, ada_asset_name, ada_policy_id}
use cardano/fuzz as cardano
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use registry_node.{RegistryNode, empty_vkey, sentinel_next_key}
use types.{
  ProgrammableLogicGlobalRedeemer, TokenExists, TransferAct, UnfrackingAct,
  UnfrackingRedeemer,
}

/// Some script credential for the transfer logic. Could also be a verification
/// key hash, but the primary use-case is for script.
pub const credential_transfer_logic: Credential =
  Credential.Script(#"00000000000000000000000000000000000000000000000000000b0b")

/// Some script credential for the 3rd-party logic. Could also be a verification
/// key hash, but the primary use-case is for script.
pub const credential_3rd_party_logic: Credential =
  Credential.Script(#"0000000000000000000000000000000000000000000000000000035d")

/// Some script credential for the 3rd-party logic. Could also be a verification
/// key hash, but the primary use-case is for script.
pub const credential_seized_logic: Credential =
  Credential.Script(#"000000000000000000000000000000000000000000000000002e12ed")

/// Arbitrary script hash representing the programmable_logic_base validator.
pub const credential_validator_logic_base: Credential =
  Credential.Script(#"0000000000000000000000000000000000000000000000000000ba5e")

/// Arbitrary script hash representing the programmable_logic_global validator.
pub const credential_validator_logic_global: Credential =
  Credential.Script(#"0000000000000000000000000000000000000000000000000001091c")

/// Arbitrary script credential representing the unfracking
/// validator (Finding 17). Carried by the protocol-params datum
/// (`unfracking_cred`); an UnfrackingAct transaction must carry this
/// script's withdraw-0.
pub const credential_validator_unfracking: Credential =
  Credential.Script(#"00000000000000000000000000000000000000000000000000def17a")

/// Arbitrary script credential representing an ISSUER's unfracking
/// constraint hook (unfracking v2): the credential registered in a
/// policy's `unfracking_logic_script` registry field, whose withdraw-0
/// must accompany every UnfrackingAct on that policy.
pub const credential_unfracking_hook: Credential =
  Credential.Script(#"000000000000000000000000000000000000000000000000000b00c5")

/// Arbitrary script hash representing the protocol params NFT's minting script
pub const policy_protocol_params: PolicyId =
  #"000000000000000000000000000000000000000000000000000005ef"

/// Arbitrary script hash representing the linked-list registry NFT's script
pub const policy_tokens_registry: PolicyId =
  #"000000000000000000000000000000000000000000000000000040de"

/// Typical withdrawals found in a transfer transaction; used to artificially
/// invoke global logic.
pub const withdrawals_transfer: Pairs<Credential, Int> =
  [
    // The artificial withdraw-0 to execute the global logic
    Pair(credential_validator_logic_global, 0),
    // The artificial withdraw-0 to execute the transfer logic
    Pair(credential_transfer_logic, 0),
  ]

/// Typical withdrawals found in a 3rd party transaction; used to artificially
/// invoke global logic.
pub const withdrawals_3rd_party: Pairs<Credential, Int> =
  [
    // The artificial withdraw-0 to execute the global logic
    Pair(credential_validator_logic_global, 0),
    // The artificial withdraw-0 to execute the 3rd party logic
    Pair(credential_3rd_party_logic, 0),
  ]

/// Typical withdrawals found in an unfracking transaction (Finding 17).
/// Three scripts compose: PLG (required by every PLB base spend), the
/// standalone unfracking validator (required by PLG under
/// UnfrackingAct), and the transfer-logic script (authorises the
/// script-staked PLB inputs — same authorisation pattern as TransferAct;
/// a vkey-staked holder signs instead and omits this one).
pub const withdrawals_unfracking: Pairs<Credential, Int> =
  [
    // The artificial withdraw-0 to execute the global logic
    Pair(credential_validator_logic_global, 0),
    // The artificial withdraw-0 to execute the unfracking invariants
    Pair(credential_validator_unfracking, 0),
    // The artificial withdraw-0 authorising the script-staked PLB inputs
    Pair(credential_transfer_logic, 0),
    // The artificial withdraw-0 of the acted-on policy's issuer hook
    // (unfracking v2: the hook is always executed — no script, no party)
    Pair(credential_unfracking_hook, 0),
  ]

/// Parameters for a specific instance of the registry.
pub const protocol_params: ProgrammableLogicGlobalParams =
  ProgrammableLogicGlobalParams {
    registry_node_cs: policy_tokens_registry,
    prog_logic_cred: credential_validator_logic_base,
    unfracking_cred: credential_validator_unfracking,
  }

/// Some input to pay for fuel, deterministically determined by the label.
pub fn some_input_fuel(label: ByteArray) -> Input {
  Input {
    output_reference: generate(cardano.output_reference(), label),
    output: Output {
      address: generate(cardano.address(), label),
      value: min_ada_value,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// An input that spends UTxO locked by the validator logic, parameterized with
/// the transfer logic and holding the given tokens (which may or may not be
/// registered tokens)
pub fn any_input_with_programmable_tokens(
  stake_credential: Credential,
  tokens: List<(PolicyId, AssetName, Int)>,
) -> Fuzzer<Input> {
  let output_reference <- fuzz.map(cardano.output_reference())
  Input {
    output_reference,
    output: Output {
      address: Address {
        payment_credential: credential_validator_logic_base,
        stake_credential: Some(Inline(stake_credential)),
      },
      value: list.foldr(
        tokens,
        min_ada_value,
        fn((policy, asset_name, quantity), assets) {
          assets.add(assets, policy, asset_name, quantity)
        },
      ),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

pub fn some_input_with_programmable_tokens_with(
  stake_credential: Credential,
  tokens: List<(PolicyId, AssetName, Int)>,
  label: ByteArray,
) -> Input {
  generate(any_input_with_programmable_tokens(stake_credential, tokens), label)
}

/// A deterministic version of 'any_input_with_programmable_tokens', which
/// determinism is given by the label.
pub fn some_input_with_programmable_tokens(
  tokens: List<(PolicyId, AssetName, Int)>,
  label: ByteArray,
) -> Input {
  some_input_with_programmable_tokens_with(
    credential_transfer_logic,
    tokens,
    label,
  )
}

/// Some reference inputs holding the given protocol params as inline datum.
/// Identified by a specific NFT from the protocol params policy.
pub fn some_reference_input_protocol_params(
  protocol_params: ProgrammableLogicGlobalParams,
  seed: ByteArray,
) -> Input {
  Input {
    output_reference: generate(cardano.output_reference(), seed),
    output: Output {
      address: address.from_verification_key(
        generate(cardano.verification_key_hash(), seed),
      ),
      value: min_ada_value
        |> assets.add(policy_protocol_params, "ProtocolParams", 1),
      datum: InlineDatum(as_data(protocol_params)),
      reference_script: None,
    },
  }
}

// Some change output
pub fn some_output_change(label: ByteArray) -> Output {
  Output {
    address: generate(cardano.address(), label),
    value: generate(cardano.lovelace(), label),
    datum: NoDatum,
    reference_script: None,
  }
}

pub fn some_output_with_programmable_tokens_with(
  stake_credential: Credential,
  tokens: List<(PolicyId, AssetName, Int)>,
) -> Output {
  Output {
    address: Address {
      payment_credential: credential_validator_logic_base,
      stake_credential: Some(Inline(stake_credential)),
    },
    value: list.foldr(
      tokens,
      min_ada_value,
      fn((policy, asset_name, quantity), assets) {
        assets.add(assets, policy, asset_name, quantity)
      },
    ),
    datum: NoDatum,
    reference_script: None,
  }
}

/// An arbitrary 'programmable' output (i.e. locked by the base logic +
/// transfer logic) containing the given tokens.
pub fn some_output_with_programmable_tokens(
  tokens: List<(PolicyId, AssetName, Int)>,
) -> Output {
  some_output_with_programmable_tokens_with(credential_transfer_logic, tokens)
}

/// An arbitrary seized output (i.e. locked by the base logic +
/// 3rd party logic) containing the given tokens.
pub fn some_output_with_seized_tokens(
  tokens: List<(PolicyId, AssetName, Int)>,
) -> Output {
  Output {
    address: Address {
      payment_credential: credential_validator_logic_base,
      stake_credential: Some(Inline(credential_seized_logic)),
    },
    value: list.foldr(
      tokens,
      min_ada_value,
      fn((policy, asset_name, quantity), assets) {
        assets.add(assets, policy, asset_name, quantity)
      },
    ),
    datum: NoDatum,
    reference_script: None,
  }
}

/// A token registry linked-list node configured with the 'transfer_logic'
pub fn some_reference_input_tokens_registry_node_with(
  transfer_logic_script: Credential,
  third_party_transfer_logic_script: Credential,
  key: ByteArray,
  next: ByteArray,
  label: ByteArray,
) -> Input {
  Input {
    output_reference: generate(cardano.output_reference(), label),
    output: Output {
      address: address.from_verification_key(
        generate(cardano.verification_key_hash(), label),
      ),
      value: min_ada_value
        |> assets.add(policy_tokens_registry, blake2b_256(key), 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next,
            transfer_logic_script,
            third_party_transfer_logic_script,
            // PR-1: not exercised by transfer/3rd-party tests; placeholder.
            minting_logic_script: empty_vkey,
            global_state_cs: "",
            unfracking_logic_script: empty_vkey,
          },
        ),
      ),
      reference_script: None,
    },
  }
}

pub fn some_reference_input_tokens_registry_node(
  key: ByteArray,
  next: ByteArray,
  label: ByteArray,
) -> Input {
  some_reference_input_tokens_registry_node_with(
    credential_transfer_logic,
    credential_3rd_party_logic,
    key,
    next,
    label,
  )
}

/// A baseline transaction for transferring tokens which can be used a
/// placeholder with most field pre-determined.
pub fn some_transfer(
  tokens: List<(PolicyId, AssetName, Int)>,
) -> (Transaction, ProgrammableLogicGlobalRedeemer) {
  // Nub token policies, while preserving their order. This way, we allow for
  // declaring policies in arbitrary order, even if the proofs must be provided
  // in ascending policy order.
  let (node_idxs, policies), _ <- list.foldl2(
    tokens,
    (dict.empty, []),
    2,
    fn((policy, _, _), (idxs, policies), ix, return) {
      let new_idxs = dict.insert_with(idxs, policy, ix, keep_left())
      // If unchanged, it means the policy was already known. No need to increment the index
      if new_idxs == idxs {
        return((idxs, policies), ix)
      } else {
        return((new_idxs, [policy, ..policies]), ix + 1)
      }
    },
  )

  // Create the linked-list registry from the end of the linked-list. Note that
  // we don't have 'gaps' in our linked-list, whereas the protocol should allow
  // for it just fine.
  let first_policy, nodes <- list.foldl2(
    policies,
    #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    [],
    fn(key, next, nodes, return) {
      let node = some_reference_input_tokens_registry_node(key, next, key)
      return(key, [node, ..nodes])
    },
  )

  let nodes = [
    some_reference_input_tokens_registry_node("", first_policy, ""),
    ..nodes
  ]

  (
    Transaction {
      ..transaction.placeholder,
      inputs: [
        some_input_with_programmable_tokens(tokens, "programmable tokens input"),
      ],
      outputs: [some_output_with_programmable_tokens(tokens)],
      reference_inputs: [
        some_reference_input_protocol_params(protocol_params, "protocol params"),
        ..nodes
      ],
      withdrawals: withdrawals_transfer,
    },
    node_idxs
      |> dict.foldr(
          [],
          fn(_, node_idx, proofs) { [TokenExists { node_idx }, ..proofs] },
        )
      |> TransferAct,
  )
}

/// A registry-node reference input for the unfracking (v2) tests and
/// benches: the node's `unfracking_logic_script` is set to
/// `credential_unfracking_hook`, so an action on `key` is permitted
/// exactly when that hook's withdraw-0 is present.
pub fn some_reference_input_unfracking_registry_node(
  key: ByteArray,
  label: ByteArray,
) -> Input {
  Input {
    output_reference: generate(cardano.output_reference(), label),
    output: Output {
      address: address.from_verification_key(
        generate(cardano.verification_key_hash(), label),
      ),
      value: min_ada_value
        |> assets.add(policy_tokens_registry, blake2b_256(key), 1),
      datum: InlineDatum(
        as_data(
          RegistryNode {
            key,
            next: sentinel_next_key,
            transfer_logic_script: credential_transfer_logic,
            third_party_transfer_logic_script: credential_3rd_party_logic,
            minting_logic_script: empty_vkey,
            global_state_cs: "",
            unfracking_logic_script: credential_unfracking_hook,
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// Baseline transaction for an Unfracking action (v2, registry-gated).
/// Single-policy, ThirdPartyAct-shaped: ONE fracked PLB input holding
/// `input_tokens` (which must include the acted-on policy) is paired
/// with a continuing output holding `continuing_tokens` (the untouched
/// non-acted remainder — byte-identity is the validator's per-pair
/// rule), while the acted tokens land in an extra output at the same
/// owner address holding `moved_tokens`.
///
/// Outputs layout: [pair-continuing, extra] with `outputs_start_idx: 0`;
/// reference inputs: [protocol params, acted policy's registry node]
/// with `registry_node_idx: 1`. Withdrawals carry the full v2
/// composition: PLG (base spends), the unfracking validator (PLG's
/// delegation gate), the transfer-logic script (owner authorisation for
/// the script-staked input), and the issuer's unfracking hook.
pub fn some_unfracking(
  acted_policy_key: ByteArray,
  input_tokens: List<(PolicyId, AssetName, Int)>,
  continuing_tokens: List<(PolicyId, AssetName, Int)>,
  moved_tokens: List<(PolicyId, AssetName, Int)>,
) -> (Transaction, ProgrammableLogicGlobalRedeemer, UnfrackingRedeemer) {
  (
    Transaction {
      ..transaction.placeholder,
      inputs: [
        some_input_with_programmable_tokens(input_tokens, "unfracking input"),
      ],
      outputs: [
        some_output_with_programmable_tokens(continuing_tokens),
        some_output_with_programmable_tokens(moved_tokens),
      ],
      reference_inputs: [
        some_reference_input_protocol_params(protocol_params, "protocol params"),
        some_reference_input_unfracking_registry_node(
          acted_policy_key,
          "unfracking registry node",
        ),
      ],
      withdrawals: withdrawals_unfracking,
    },
    UnfrackingAct,
    UnfrackingRedeemer { registry_node_idx: 1, outputs_start_idx: 0 },
  )
}

// --------------------------------------------------------------------- helpers

/// Some value with a non-zero ADA amount. Embodies typical values found on-chain.
pub const min_ada_value: Value =
  assets.zero |> assets.add(ada_policy_id, ada_asset_name, 1000000)

/// Run a 'Fuzzer' in-place, using a label as a seed. This can be used to
/// deterministically produce a single arbitrary value from a known fuzzer.
///
/// Different seeds give different values.
fn generate(fuzzer: Fuzzer<a>, label: ByteArray) -> a {
  expect Some((_, a)) = fuzzer(Seeded { seed: blake2b_256(label), choices: "" })
  a
}

// =============================================================================
// Programmable Logic Global Stake Validator
// =============================================================================
//
// This is the core CIP-0113 validator that coordinates all programmable token
// transfers. It implements the "withdraw-zero" pattern where this stake script
// is invoked via a zero-value withdrawal, giving it visibility into the entire
// transaction for validation.
//
// ## Architecture
//
// The CIP-0113 protocol uses a two-layer validation approach:
//
// 1. **Programmable Logic Base** (spend validator): Locks all programmable
//    token UTxOs and forwards validation to this global validator.
//
// 2. **Programmable Logic Global** (stake validator): Validates the overall
//    transaction, checks registry proofs, and invokes transfer logic scripts.
//
// ## Supported Operations
//
// - **TransferAct**: Standard token transfers between users
// - **ThirdPartyAct**: Administrative operations (seizure, freeze, etc.)
//
// ## Migration Notes
//
// Migrated from SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)
//
// =============================================================================

use aiken/collection/dict.{Dict}
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, Value, ada_policy_id, merge, zero}
use cardano/transaction.{Input, Output, Transaction}
use types.{
  ProgrammableLogicGlobalParams, ProgrammableLogicGlobalRedeemer, RegistryNode,
  RegistryProof, ThirdPartyAct, TokenDoesNotExist, TokenExists, TransferAct,
}
use utils.{
  bytearray_lt, elem_at, expect_inline_datum, expect_value_contains_v3,
  has_currency_symbol, is_script_invoked, is_signed_by,
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Check if a credential is in the withdrawals list (script invocation check).
///
/// This is an optimized direct check that iterates through withdrawals without
/// pre-mapping them. Used to verify that required transfer logic scripts are
/// invoked via the withdraw-zero pattern.
///
/// ## Arguments
///
/// - `withdrawals`: The transaction's withdrawal list
/// - `cred`: The credential to search for
///
/// ## Returns
///
/// `True` if the credential appears in any withdrawal entry.
fn withdrawal_has_cred(
  withdrawals: Pairs<Credential, Int>,
  cred: Credential,
) -> Bool {
  when withdrawals is {
    [] -> False
    [Pair(w_cred, _amount), ..rest] ->
      if w_cred == cred {
        True
      } else {
        withdrawal_has_cred(rest, cred)
      }
  }
}

// =============================================================================
// Main Validator
// =============================================================================

/// The global programmable logic stake validator.
///
/// ## Parameters
///
/// - `protocol_params_cs`: Currency symbol of the protocol parameters NFT.
///   This NFT's datum contains the registry address and programmable logic
///   credential, allowing the validator to locate protocol resources.
///
/// ## Validation Flow
///
/// 1. Locate protocol parameters from reference inputs
/// 2. Extract registry and programmable logic credentials
/// 3. Dispatch to TransferAct or ThirdPartyAct validation
validator programmable_logic_global(protocol_params_cs: PolicyId) {
  withdraw(
    redeemer: ProgrammableLogicGlobalRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting programmable_logic_global validation"

    // Extract protocol parameters from reference inputs
    // The protocol params NFT contains the registry and prog_logic credentials
    let protocol_params_ref <-
      get_protocol_params_ref(protocol_params_cs, self.reference_inputs)

    let protocol_params_utxo = protocol_params_ref.output
    let params_datum = expect_inline_datum(protocol_params_utxo)
    expect params: ProgrammableLogicGlobalParams = params_datum

    let prog_logic_cred = params.prog_logic_cred
    let registry_node_cs = params.registry_node_cs

    // Dispatch based on redeemer type
    // Pass withdrawals directly for inline script invocation checks
    when redeemer is {
      TransferAct { proofs } ->
        validate_transfer(
          self,
          prog_logic_cred,
          registry_node_cs,
          proofs,
          self.withdrawals,
        )

      ThirdPartyAct {
        registry_node_idx,
        input_idxs,
        outputs_start_idx,
        length_input_idxs,
      } ->
        validate_third_party(
          self,
          prog_logic_cred,
          registry_node_cs,
          registry_node_idx,
          input_idxs,
          outputs_start_idx,
          length_input_idxs,
          self.withdrawals,
        )
    }
  }

  else(_) {
    fail
  }
}

/// Find the protocol parameters reference input.
///
/// Searches reference inputs for a UTxO holding the protocol parameters NFT.
/// Uses continuation-passing style for efficient early return.
///
/// ## Arguments
///
/// - `protocol_params_cs`: The protocol params NFT policy ID
/// - `ref_inputs`: List of reference inputs to search
/// - `return`: Continuation function called with the found input
///
/// ## Panics
///
/// Fails with "Protocol parameters reference input not found" if not found.
fn get_protocol_params_ref(
  protocol_params_cs: PolicyId,
  ref_inputs: List<Input>,
  return: fn(Input) -> result,
) -> result {
  when ref_inputs is {
    [] -> fail @"Protocol parameters reference input not found"
    [first_ref, ..rest_refs] ->
      if has_currency_symbol(first_ref.output.value, protocol_params_cs) {
        return(first_ref)
      } else {
        get_protocol_params_ref(protocol_params_cs, rest_refs, return)
      }
  }
}

// =============================================================================
// Transfer Validation
// =============================================================================

/// Validate a standard token transfer action.
///
/// This function validates that all programmable tokens being transferred have
/// their transfer logic scripts properly invoked, and that the outputs contain
/// all the required tokens.
///
/// ## Validation Steps
///
/// 1. Sum all input values from programmable logic addresses (with auth check)
/// 2. For each currency symbol, check registry proofs
/// 3. Invoke transfer logic for registered programmable tokens
/// 4. Verify outputs contain all validated programmable tokens
///
/// ## Arguments
///
/// - `tx`: The transaction being validated
/// - `prog_logic_cred`: The programmable logic base credential
/// - `registry_node_cs`: The registry node NFT policy ID
/// - `proofs`: List of registry proofs for each currency symbol
/// - `withdrawals`: Transaction withdrawals for script invocation checks
///
/// ## Returns
///
/// `True` if the transfer is valid.
fn validate_transfer(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  proofs: List<RegistryProof>,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  // Calculate the total value of programmable tokens being transferred
  // by summing all inputs from the programmable logic credential
  // This also performs authorization checks
  let total_prog_value = get_signed_prog_value(tx, prog_logic_cred)

  // Check transfer logic for each programmable token type
  // Only returns values for tokens that ARE in the registry
  let validated_prog_value =
    check_transfer_and_compute_prog_value(
      total_prog_value,
      registry_node_cs,
      tx.reference_inputs,
      proofs,
      withdrawals,
    )

  // Sum output values at programmable logic addresses
  let output_prog_value =
    list.foldl(
      tx.outputs,
      assets.zero,
      fn(output, acc) {
        if output.address.payment_credential == prog_logic_cred {
          // Must have inline stake credential for programmable addresses
          expect Some(Inline(_stake_cred)) = output.address.stake_credential
          merge(acc, output.value)
        } else {
          acc
        }
      },
    )

  // The output must contain all the validated programmable tokens
  // This ensures no programmable tokens are lost or stolen
  expect_value_contains_v3(output_prog_value, validated_prog_value)
  True
}

// =============================================================================
// Third Party Action Validation
// =============================================================================

/// Validate a third party (administrative) action on multiple UTxOs.
///
/// Third party actions allow administrators (e.g., issuers or regulators) to
/// perform operations like seizure or freeze without owner consent. This is
/// used for compliance and recovery scenarios.
///
/// ## Validation Steps
///
/// 1. Look up the registry node to identify the policy
/// 2. Verify the third party transfer logic script is invoked
/// 3. For each input, verify the corresponding output:
///    - Same address
///    - Same datum
///    - Value with policy tokens removed (seized)
/// 4. Verify all programmable inputs are accounted for
///
/// ## Arguments
///
/// - `tx`: The transaction being validated
/// - `prog_logic_cred`: The programmable logic base credential
/// - `registry_node_cs`: The registry node NFT policy ID
/// - `registry_node_idx`: Index of the registry node in reference inputs
/// - `input_idxs`: List of input indices to process
/// - `outputs_start_idx`: Starting index for corresponding outputs
/// - `length_input_idxs`: Expected length of input_idxs (for validation)
/// - `withdrawals`: Transaction withdrawals for script invocation checks
///
/// ## Returns
///
/// `True` if the third party action is valid.
///
/// ## Migration Notes
///
/// Migrated from Plutarch multi-seize PR #99
fn validate_third_party(
  tx: Transaction,
  prog_logic_cred: Credential,
  registry_node_cs: PolicyId,
  registry_node_idx: Int,
  input_idxs: List<Int>,
  outputs_start_idx: Int,
  length_input_idxs: Int,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  trace @"validate_third_party: processing multiple inputs"

  // Get the registry node for this token policy
  let registry_ref_input = elem_at(tx.reference_inputs, registry_node_idx)
  let registry_datum = expect_inline_datum(registry_ref_input.output)
  expect registry_node: RegistryNode = registry_datum

  // Get the policy ID from the registry
  let policy_id = registry_node.key

  // Process each input-output pair
  // For each input at input_idxs[i], there should be a corresponding output
  // at outputs_start_idx + i
  let input_size =
    list.indexed_foldr(
      input_idxs,
      0,
      fn(idx, input_idx, acc) {
        // Note: Input ordering is implicitly validated because:
        // 1. Currency symbols in Value are ordered lexicographically (Aiken's pairs)
        // 2. Proofs must match currency symbols in order via validate_single_cs
        // 3. If proofs are out of order, the key validation will fail

        // Get the input being processed
        let input = elem_at(tx.inputs, input_idx)

        // Calculate corresponding output index
        let output_idx = outputs_start_idx + idx
        let output = elem_at(tx.outputs, output_idx)

        // Expected output value: input value with policy tokens removed
        let expected_output_dict =
          assets.to_dict(input.output.value) |> dict.delete(policy_id)

        // Must be from prog_logic_cred
        expect input.output.address.payment_credential == prog_logic_cred

        // Validate the output matches expectations:
        // - Same address (tokens stay at same programmable address)
        // - Value with tokens removed (seized by third party)
        // - Same datum (preserves any associated data)
        expect output.address == input.output.address
        expect assets.to_dict(output.value) == expected_output_dict
        expect output.datum == input.output.datum

        // Prevent DDOS: must actually remove some tokens
        // This prevents empty seizure transactions
        expect assets.to_dict(input.output.value) != expected_output_dict
        acc + 1
      },
    )

  // Verify length parameter matches actual list length
  expect input_size == length_input_idxs

  // Verify that ONLY the specified inputs from prog_logic_cred are consumed
  // Count how many inputs from prog_logic_cred are in the transaction
  let prog_input_count =
    list.count(
      tx.inputs,
      fn(input) { input.output.address.payment_credential == prog_logic_cred },
    )

  and {
    // Validate registry node is authentic
    has_currency_symbol(registry_ref_input.output.value, registry_node_cs),
    // The third party transfer logic script must be invoked
    withdrawal_has_cred(withdrawals, registry_node.third_party_transfer_logic_script),
    // Must match the number of inputs we're processing (no extra inputs)
    prog_input_count == length_input_idxs,
  }
}

// =============================================================================
// Authorization
// =============================================================================

/// Get the total value from authorized programmable inputs.
///
/// This function sums the values of all inputs from the programmable logic
/// credential, while verifying that each input is properly authorized.
///
/// ## Authorization Rules
///
/// For each programmable input:
/// - If stake credential is a VerificationKey: transaction must be signed by it
/// - If stake credential is a Script: the script must be invoked via withdrawal
///
/// ## Arguments
///
/// - `tx`: The transaction
/// - `prog_logic_cred`: The programmable logic base credential
///
/// ## Returns
///
/// The sum of all authorized programmable input values.
///
/// ## Panics
///
/// Fails if any programmable input is not properly authorized.
fn get_signed_prog_value(tx: Transaction, prog_logic_cred: Credential) -> Value {
  // Combine authorization check into single fold
  // Uses expect for fail-fast behavior instead of if-then-fail
  list.foldl(
    tx.inputs,
    assets.zero,
    fn(input, acc) {
      if input.output.address.payment_credential == prog_logic_cred {
        // Extract stake credential - must be inline for programmable addresses
        expect Some(Inline(stake_cred)) = input.output.address.stake_credential

        // Authorization check - fail immediately if not authorized
        let is_authorized =
          when stake_cred is {
            VerificationKey(pkh) -> is_signed_by(tx, pkh)
            Script(_hash) -> is_script_invoked(tx, stake_cred)
          }
        expect is_authorized
        merge(acc, input.output.value)
      } else {
        acc
      }
    },
  )
}

// =============================================================================
// Transfer Logic Validation
// =============================================================================

/// Check transfer logic for each currency symbol and compute programmable value.
///
/// This function iterates through all currency symbols in the transaction value
/// and validates each against its registry proof. For registered programmable
/// tokens, it invokes the transfer logic script.
///
/// ## Arguments
///
/// - `value`: The total value being transferred
/// - `registry_node_cs`: The registry node NFT policy ID
/// - `reference_inputs`: Transaction reference inputs (for registry lookups)
/// - `proofs`: List of registry proofs (must match currency symbol order)
/// - `withdrawals`: Transaction withdrawals for script invocation checks
///
/// ## Returns
///
/// The subset of value that consists of registered programmable tokens.
fn check_transfer_and_compute_prog_value(
  value: Value,
  registry_node_cs: PolicyId,
  reference_inputs: List<Input>,
  proofs: List<RegistryProof>,
  withdrawals: Pairs<Credential, Int>,
) -> Value {
  let
    remaining_proofs,
    acc_value,
  <-
    do_check_transfer(
      // Convert value to pairs and remove ADA (not a programmable token)
      value
        |> assets.to_dict
        |> dict.to_pairs
        |> pairs.delete_first(ada_policy_id),
      registry_node_cs,
      reference_inputs,
      withdrawals,
      proofs,
      zero,
    )
  // All proofs must be consumed
  expect [] == remaining_proofs
  acc_value
}

/// Recursive helper for check_transfer_and_compute_prog_value.
///
/// Uses continuation-passing style for tail-call optimization.
fn do_check_transfer(
  my_value: Pairs<PolicyId, Dict<ByteArray, Int>>,
  registry_node_cs: PolicyId,
  reference_inputs: List<Input>,
  withdrawals: Pairs<Credential, Int>,
  proofs: List<RegistryProof>,
  acc: Value,
  return: fn(List<RegistryProof>, Value) -> result,
) -> result {
  when my_value is {
    // Base case: no more currency symbols to check
    [] -> return(proofs, acc)

    // Recursive case: check this currency symbol
    [Pair(cs, tokens), ..rest] ->
      when proofs is {
        [] -> fail @"Not enough proofs for currency symbols"
        [proof, ..rest_proofs] -> {
          // Validate this currency symbol against its proof
          let validated =
            validate_single_cs(
              cs,
              proof,
              reference_inputs,
              registry_node_cs,
              withdrawals,
            )

          // If validated (is a programmable token), add to accumulator
          let new_acc =
            if validated {
              // Add this CS's tokens from the original value to the accumulator
              dict.foldl(
                tokens,
                acc,
                fn(name, amount, inner_acc) { assets.add(inner_acc, cs, name, amount) },
              )
            } else {
              // Not a programmable token, skip it
              acc
            }

          // Continue with remaining currency symbols
          do_check_transfer(
            rest,
            registry_node_cs,
            reference_inputs,
            withdrawals,
            rest_proofs,
            new_acc,
            return,
          )
        }
      }
  }
}

/// Validate a single currency symbol against its registry proof.
///
/// This function checks if a currency symbol is a registered programmable token
/// and, if so, verifies that its transfer logic script is invoked.
///
/// ## Arguments
///
/// - `cs`: The currency symbol to validate
/// - `proof`: The registry proof for this currency symbol
/// - `reference_inputs`: Transaction reference inputs
/// - `registry_node_cs`: The registry node NFT policy ID
/// - `withdrawals`: Transaction withdrawals
///
/// ## Returns
///
/// - `True`: Currency symbol IS a programmable token and transfer logic is invoked
/// - `False`: Currency symbol is NOT a programmable token (proof of non-existence valid)
///
/// ## Panics
///
/// Fails if the proof is invalid (e.g., TokenExists but key doesn't match).
fn validate_single_cs(
  cs: PolicyId,
  proof: RegistryProof,
  reference_inputs: List<Input>,
  registry_node_cs: PolicyId,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  when proof is {
    // Token exists in registry - invoke transfer logic
    TokenExists { node_idx } -> {
      // Get the registry node
      let node_input = elem_at(reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      and {
        // Validate this is a legitimate registry node (has the right NFT)
        has_currency_symbol(node_input.output.value, registry_node_cs),
        // Validate the node's key matches the currency symbol
        node.key == cs,
        // Validate the transfer logic script is invoked
        withdrawal_has_cred(withdrawals, node.transfer_logic_script),
      }
    }

    // Token does NOT exist in registry - verify covering node
    TokenDoesNotExist { node_idx } -> {
      // Get the covering node
      let node_input = elem_at(reference_inputs, node_idx)
      let node_datum = expect_inline_datum(node_input.output)
      expect node: RegistryNode = node_datum

      // Return false (not a programmable token) if:
      // 1. This is a legitimate registry node AND
      // 2. The node covers the currency symbol (key < cs < next)
      !and {
        // Validate this is a legitimate registry node
        has_currency_symbol(node_input.output.value, registry_node_cs),
        // Validate the node covers the currency symbol
        bytearray_lt(node.key, cs),
        bytearray_lt(cs, node.next),
      }
    }
  }
}

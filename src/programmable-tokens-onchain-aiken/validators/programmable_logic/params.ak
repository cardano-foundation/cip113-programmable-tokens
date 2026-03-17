use aiken/builtin.{head_list, tail_list, unconstr_fields}
use assets
use cardano/address.{Credential}
use cardano/assets.{PolicyId} as value
use cardano/transaction.{InlineDatum, Input, Output}

/// Protocol parameters NFT token name
pub const protocol_params_token = "ProtocolParams"

/// Protocol parameters stored on-chain
/// This is referenced by all programmable token transactions
pub type ProgrammableLogicGlobalParams {
  /// Currency symbol of the registry node NFTs
  registry_node_cs: PolicyId,
  /// The programmable logic base credential (payment credential for all programmable token UTxOs)
  prog_logic_cred: Credential,
}

// Extract protocol parameters from reference inputs
pub fn with_programmable_logic_params(
  reference_inputs: List<Input>,
  protocol_params_cs: PolicyId,
  return: fn(PolicyId, Credential) -> result,
) -> result {
  let protocol_params_ref = get_protocol_params_ref(
    protocol_params_cs,
    reference_inputs,
  )

  expect InlineDatum(inline_datum) = protocol_params_ref.output.datum
  let fields = unconstr_fields(inline_datum)
  expect registry_node_cs: PolicyId = head_list(fields)
  let fields = tail_list(fields)
  expect prog_logic_cred: Credential = head_list(fields)

  return(registry_node_cs, prog_logic_cred)
}

fn get_protocol_params_ref(
  protocol_params_cs: PolicyId,
  ref_inputs: List<Input>,
) -> Input {
  let head = head_list(ref_inputs)
  if assets.peek_first(head.output) == protocol_params_cs {
    head
  } else {
    get_protocol_params_ref(protocol_params_cs, tail_list(ref_inputs))
  }
}

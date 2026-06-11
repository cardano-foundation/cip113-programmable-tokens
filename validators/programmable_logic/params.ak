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
  /// Credential of the unfracking withdraw-0 validator (Finding 17).
  /// Appended LAST on purpose: the transfer / third-party hot path reads
  /// only the first two fields, so it pays nothing for this one.
  unfracking_cred: Credential,
}

/// Locate the protocol-params NFT reference input and hand back the raw
/// datum fields. Callers extract only the fields their branch needs via
/// the `*_field` accessors below — cheaper than a full
/// `expect _: ProgrammableLogicGlobalParams` deserialisation, which
/// validates every field on every run.
///
/// Skipping whole-datum validation here is safe for the same reason
/// registry_node.ak skips it for RegistryNode: we only consume this
/// datum, and protocol_params_mint fully deserialises (and thereby
/// shape-checks) it at mint time, so every instance on-chain is
/// well-formed by construction.
pub fn with_protocol_params_fields(
  reference_inputs: List<Input>,
  protocol_params_cs: PolicyId,
  return: fn(List<Data>) -> result,
) -> result {
  let protocol_params_ref = get_protocol_params_ref(
    protocol_params_cs,
    reference_inputs,
  )

  expect InlineDatum(inline_datum) = protocol_params_ref.output.datum
  return(unconstr_fields(inline_datum))
}

/// Field 0: currency symbol of the registry node NFTs.
pub fn registry_node_cs_field(fields: List<Data>) -> PolicyId {
  expect registry_node_cs: PolicyId = head_list(fields)
  registry_node_cs
}

/// Field 1: the programmable logic base (PLB) payment credential.
pub fn prog_logic_cred_field(fields: List<Data>) -> Credential {
  expect prog_logic_cred: Credential = head_list(tail_list(fields))
  prog_logic_cred
}

/// Field 2: the unfracking withdraw-0 credential (Finding 17).
/// Only the UnfrackingAct branch of PLG reads this far into the datum.
pub fn unfracking_cred_field(fields: List<Data>) -> Credential {
  expect unfracking_cred: Credential = head_list(tail_list(tail_list(fields)))
  unfracking_cred
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

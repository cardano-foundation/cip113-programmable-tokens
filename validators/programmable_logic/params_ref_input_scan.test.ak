//// Characterization tests for the protocol-params reference-input lookup.
////
//// `with_protocol_params_fields` no longer SCANS `reference_inputs` for the
//// params NFT. The delegate/PLB redeemers now carry an explicit `params_idx`, and
//// the lookup is a direct `list.at(reference_inputs, params_idx)` followed by
//// an authentication `expect` that the indexed output actually holds the
//// `protocol_params_cs` policy (the params NFT).
////
//// Under the old scan model, an Ada-only reference-script UTxO (Ada +
//// `reference_script`, no tokens — the canonical CIP-33 shape) ordered BEFORE
//// the params NFT would be `peek_first`-probed and abort the script (Finding
//// 082). With the index model that failure is structurally impossible: an
//// input the caller does not point `params_idx` at is never inspected. A
//// token-less reference input at index 0 is simply never touched when the
//// params UTxO is addressed at its real index.
////
//// `..._finds_params_when_indexed_past_adaonly_refscript` pins that the params
//// NFT is found at index 1 even though an Ada-only reference-script input sits
//// at index 0 (that index-0 input is never inspected). `..._fails_index_points_
//// at_adaonly_input` pins that pointing `params_idx` at the token-less input
//// aborts on the NFT-authentication `expect`.

use cardano/address
use cardano/transaction.{Input, NoDatum, Output, OutputReference}
use programmable_logic/fixture
use programmable_logic/params.{
  registry_node_cs_field, with_protocol_params_fields,
}

/// A reference-script UTxO as normally deployed on-chain: Ada only (no tokens)
/// carrying a `reference_script`.
fn ada_only_reference_script_input() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      output_index: 0,
    },
    output: Output {
      address: address.from_script(
        #"0000000000000000000000000000000000000000000000000000ffff",
      ),
      value: fixture.min_ada_value,
      datum: NoDatum,
      reference_script: Some(
        #"0000000000000000000000000000000000000000000000000000ffff",
      ),
    },
  }
}

/// The protocol-params NFT reference input (holds the params datum + NFT).
fn params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    fixture.protocol_params,
    "protocol params",
  )
}

// Finding 082 / issue #103 (FIXED): an Ada-only reference-script input ordered
// before the params NFT no longer aborts anything. The redeemer's `params_idx`
// addresses the params UTxO directly (here index 1); the token-less input at
// index 0 is never inspected, so the 082 abort is structurally impossible.
test params_lookup_finds_params_when_indexed_past_adaonly_refscript() {
  let ref_inputs = [ada_only_reference_script_input(), params_ref_input()]
  let fields <- with_protocol_params_fields(
    ref_inputs,
    fixture.policy_protocol_params,
    1,
  )
  registry_node_cs_field(fields) == fixture.policy_tokens_registry
}

// Pointing `params_idx` at the Ada-only input (index 0) must abort: that output
// does not hold the params policy, so the NFT-authentication `expect` inside
// `with_protocol_params_fields` fails.
test params_lookup_fails_index_points_at_adaonly_input() fail {
  let ref_inputs = [ada_only_reference_script_input(), params_ref_input()]
  let fields <- with_protocol_params_fields(
    ref_inputs,
    fixture.policy_protocol_params,
    0,
  )
  registry_node_cs_field(fields) == fixture.policy_tokens_registry
}

//// Characterization tests for the protocol-params reference-input scan.
////
//// `get_protocol_params_ref` locates the protocol-params UTxO by walking
//// `reference_inputs` and calling `assets.peek_first` on EACH one until a
//// policy id matches `protocol_params_cs`. `peek_first` is
////
////     list.head(list.tail(from_value(self.value))).1st
////
//// which — as its own doc comment states — "fails loudly if the output holds
//// no tokens (beyond Ada)": for an Ada-only value `from_value` yields a single
//// entry, `list.tail` yields `[]`, and `list.head([])` aborts the script.
////
//// A reference-script UTxO is exactly such an output (Ada-only + a
//// `reference_script`, no tokens) and is the canonical way a script is supplied
//// to a transaction (CIP-33) — via `reference_inputs`, whose order in the
//// script context is fixed by `(tx_id, output_index)`, not by the builder. So
//// if such an input is ordered BEFORE the params NFT input, the scan calls
//// `peek_first` on it and aborts.
////
//// The suite previously had NO test constructing a token-less reference input,
//// so this shape was uncovered. Issue #103 replaced the `peek_first` head-read
//// with a direct, total policy lookup (`value.tokens |> dict.is_empty`), so a
//// token-less reference input is now SKIPPED rather than aborted on.
//// `..._finds_params_despite_adaonly_refscript_first` pins that the params NFT
//// is found even when such an input is ordered first; `..._ok_when_params_first`
//// keeps the control (params NFT reached first).

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
// before the params NFT is skipped, and the scan still finds the params NFT.
// Previously `peek_first` aborted on that token-less value; the scan now uses a
// direct, total policy lookup.
test params_scan_finds_params_despite_adaonly_refscript_first() {
  let ref_inputs = [ada_only_reference_script_input(), params_ref_input()]
  let fields <- with_protocol_params_fields(
    ref_inputs,
    fixture.policy_protocol_params,
  )
  registry_node_cs_field(fields) == fixture.policy_tokens_registry
}

// Control: the SAME two inputs with the params NFT reached first — the scan
// matches on the first element and never calls `peek_first` on the Ada-only
// input, so the lookup succeeds.
test params_scan_ok_when_params_input_first() {
  let ref_inputs = [params_ref_input(), ada_only_reference_script_input()]
  let fields <- with_protocol_params_fields(
    ref_inputs,
    fixture.policy_protocol_params,
  )
  registry_node_cs_field(fields) == fixture.policy_tokens_registry
}

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

use cardano/address.{Credential, Script}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}
use programmable_logic/fixture
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, plg_cred_field, with_protocol_params_fields,
}

/// A reference-script UTxO: Ada only (no tokens), carrying a `reference_script`.
///
/// Deliberately LESS realistic than its name suggests: a real CIP-33 reference
/// -script UTxO carries no inline datum, and this one does. The realism was
/// traded for discrimination — see below — and the trade is the point.
///
/// **It carries a well-formed inline params datum on purpose — do not "restore"
/// it to `NoDatum`.** `with_protocol_params_fields` rejects an addressed input
/// on TWO independent grounds, in this order: the params NFT is absent
/// (`params.ak`, the `dict.is_empty` guard) and then the datum is not inline.
/// A fixture missing both is DOUBLY disqualified, and because `test … fail`
/// passes on any abort, such a fixture cannot tell the two guards apart: delete
/// the NFT guard entirely and the InlineDatum guard aborts instead, and the
/// test still passes while asserting nothing about the NFT.
///
/// Giving this output a valid inline datum removes the backstop, so the MISSING
/// NFT is the only thing left that can reject it — which is precisely the
/// property `params_lookup_fails_index_points_at_adaonly_input` claims to pin.
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
      datum: InlineDatum(as_data(fixture.protocol_params)),
      reference_script: Some(
        #"0000000000000000000000000000000000000000000000000000ffff",
      ),
    },
  }
}

/// An attacker-controlled credential, named in every slot of the decoy datum
/// below.
const eve_cred: Credential =
  Script(#"e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4")

/// A reference input an ATTACKER can create at will: no params NFT, but a
/// perfectly well-formed 4-field params datum naming `eve_cred` in every slot.
/// Everything about it is valid except the one thing that cannot be forged.
fn decoy_params_input() -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      output_index: 0,
    },
    output: Output {
      address: address.from_script(
        #"0000000000000000000000000000000000000000000000000000eeee",
      ),
      value: fixture.min_ada_value,
      datum: InlineDatum(
        as_data(
          ProgrammableLogicGlobalParams {
            plg_cred: eve_cred,
            transfer_cred: eve_cred,
            third_party_cred: eve_cred,
            upgrade_cred: eve_cred,
          },
        ),
      ),
      reference_script: None,
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
  plg_cred_field(fields) == fixture.credential_validator_plg
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
  plg_cred_field(fields) == fixture.credential_validator_plg
}

// The params NFT is the ONLY thing authenticating the datum a caller addresses.
// Here the transaction carries no params UTxO at all — just one input an
// attacker can mint for the price of min-ADA, whose datum is a well-formed
// 4-field record naming `eve_cred` in every slot, including `plg_cred`. Nothing
// about the SHAPE is wrong; only the NFT is missing.
//
// This must abort. If it did not, `plg_cred_field` would hand back `eve_cred`
// and — since that is exactly the credential `programmable_logic_base` requires
// a withdraw-0 for — an attacker supplying `withdrawals: [Pair(eve_cred, 0)]`
// would authorise the spend of ANY programmable-token UTxO on the deployment.
//
// The body deliberately returns True on the extracted credential rather than
// asserting a failure: that way, if the NFT guard is ever weakened, this test
// flips from "aborted" to "returned True" and the `fail` marker catches it.
// A body that could also abort for its own reasons would be a backstop, and
// would make this test unable to see the thing it exists to see.
test params_lookup_fails_when_addressed_input_lacks_the_params_nft() fail {
  let fields <- with_protocol_params_fields(
    [decoy_params_input()],
    fixture.policy_protocol_params,
    0,
  )
  plg_cred_field(fields) == eve_cred
}

//// Characterization tests for the reference-input lookups — protocol params
//// AND registry nodes — against the Ada-only reference-script input shape.
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
////
//// The REGISTRY-NODE lookup has the same shape and the same immunity, which
//// until now nothing pinned. `new_registry_node_getter` builds a chain of
//// closures over `reference_inputs`, but the `assets.peek_first` probe lives
//// INSIDE the closure body and only runs for the input whose index the proof
//// actually names — so a token-less reference input at any other position is
//// never probed. The two `registry_node_lookup_*` tests below pin the positive
//// and the negative halves of that.

use aiken/collection/list
use cardano/address
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, NoDatum, Output, OutputReference, Transaction}
use programmable_logic/fixture
use programmable_logic/params.{
  registry_node_cs_field, with_protocol_params_fields,
}
use transfer
use types.{RegistryProof, TokenDoesNotExist, TokenExists, TransferRedeemer}

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

// ---------------------------------------------------------------------------
// Registry-node lookup — the same question, asked of `new_registry_node_getter`
// ---------------------------------------------------------------------------

/// An arbitrary registered policy for the transfer fixture.
const scan_test_policy: PolicyId =
  #"f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

/// Shift every reference-input index the redeemer carries — the params index
/// and each proof's node index — by `by`. Used to slide a whole fixture
/// transaction right when an extra reference input is prepended.
fn shift_ref_indices(redeemer: TransferRedeemer, by: Int) -> TransferRedeemer {
  let TransferRedeemer { params_idx, proofs } = redeemer
  TransferRedeemer {
    params_idx: params_idx + by,
    proofs: list.map(
      proofs,
      fn(proof: RegistryProof) {
        when proof is {
          TokenExists { node_idx } -> TokenExists { node_idx: node_idx + by }
          TokenDoesNotExist { node_idx } ->
            TokenDoesNotExist { node_idx: node_idx + by }
        }
      },
    ),
  }
}

/// A baseline single-policy transfer with an Ada-only reference-script input
/// prepended at index 0, every real reference input therefore sliding to
/// index+1, and the redeemer's indices moved to match — i.e. exactly the
/// transaction shape a deployment with reference scripts produces.
fn transfer_with_adaonly_refscript_first(proof_override: Option<Int>) -> Bool {
  let tokens = [(scan_test_policy, "FOO", 10)]
  let (tx, redeemer) = fixture.some_transfer(tokens)
  let shifted = shift_ref_indices(redeemer, 1)
  let final_redeemer = when proof_override is {
    None -> shifted
    Some(idx) ->
      TransferRedeemer {
        ..shifted,
        proofs: list.map(
          shifted.proofs,
          fn(_proof) { TokenExists { node_idx: idx } },
        ),
      }
  }
  transfer.transfer.withdraw(
    fixture.policy_protocol_params,
    final_redeemer,
    fixture.credential_validator_transfer,
    Transaction {
      ..tx,
      reference_inputs: [
        ada_only_reference_script_input(),
        ..tx.reference_inputs
      ],
    },
  )
}

// Issue #103 regression, registry-node half: an Ada-only reference-script UTxO
// ordered BEFORE the registry nodes does not abort a legitimate transfer. The
// proofs address their nodes directly, so the token-less input at index 0 is
// never probed by `assets.peek_first`.
test registry_node_lookup_survives_adaonly_refscript_ahead_of_nodes() {
  transfer_with_adaonly_refscript_first(None)
}

// The mirror of `params_lookup_fails_index_points_at_adaonly_input`: pointing a
// proof's `node_idx` at the Ada-only input aborts, because `peek_first` needs a
// non-Ada asset to read. ONE delta from the test above — the proof indices.
// Self-invalidating in the same way a wrong `params_idx` is.
test registry_node_lookup_fails_when_proof_points_at_adaonly_input() fail {
  transfer_with_adaonly_refscript_first(Some(0))
}

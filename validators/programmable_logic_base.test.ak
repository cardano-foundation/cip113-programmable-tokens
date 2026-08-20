//// Tests for the programmable_logic_base validator.
//// PLB is parameterized by the protocol-params NFT policy: on every
//// spend it locates the params reference input, reads the CURRENT PLG
//// credential from datum field 3, and requires that credential's
//// withdraw-0. These tests verify both the trampoline check and the
//// datum-driven indirection that makes PLG swappable in place.

use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use programmable_logic_base

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

/// The PLG credential carried by `fixture.protocol_params` (field 3).
const plg_cred: Credential = fixture.credential_validator_logic_global

const other_cred: Credential =
  Script(#"11223344112233441122334411223344112233441122334411223344")

/// A replacement PLG credential, as an upgrade transaction would write
/// into the coordination datum.
const upgraded_plg_cred: Credential =
  Script(#"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd")

/// The protocol-params datum shape BEFORE this refactor appended
/// `prog_logic_global_cred` — used to prove PLB rejects a datum that
/// lacks its field.
type LegacyThreeFieldParams {
  registry_node_cs: PolicyId,
  prog_logic_cred: Credential,
  unfracking_cred: Credential,
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    fixture.protocol_params,
    "protocol params",
  )
}

/// Params reference input whose datum carries `upgraded_plg_cred` in
/// field 3 — the coordination UTxO after an in-place PLG upgrade.
fn upgraded_params_ref_input() -> Input {
  fixture.some_reference_input_protocol_params(
    ProgrammableLogicGlobalParams {
      ..fixture.protocol_params,
      prog_logic_global_cred: upgraded_plg_cred,
    },
    "protocol params",
  )
}

fn valid_plb_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [params_ref_input()],
    withdrawals: [Pair(plg_cred, 0)],
  }
}

fn call_validator(tx: Transaction) -> Bool {
  call_validator_at(tx, 0)
}

/// `call_validator` with an explicit `params_idx` — for tests where the
/// params UTxO is NOT the first reference input.
fn call_validator_at(tx: Transaction, params_idx: Int) -> Bool {
  programmable_logic_base.programmable_logic_base.spend(
    fixture.policy_protocol_params,
    None,
    params_idx,
    Void,
    tx,
  )
}

// ---------------------------------------------------------------------------
// Trampoline check
// ---------------------------------------------------------------------------

// Passes when the PLG credential read from the params datum is in withdrawals
test plb_passes_when_datum_plg_cred_in_withdrawals() {
  call_validator(valid_plb_tx())
}

// Fails when the PLG credential is absent from withdrawals
test plb_fails_when_plg_cred_not_in_withdrawals() fail {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(other_cred, 0)] }
  call_validator(tx)
}

// Fails with empty withdrawals list
test plb_fails_with_empty_withdrawals() fail {
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [] }
  call_validator(tx)
}

// Passes when the PLG credential is among multiple withdrawal entries
test plb_passes_with_multiple_withdrawals() {
  let tx = Transaction {
    ..valid_plb_tx(),
    withdrawals: [
      Pair(other_cred, 0),
      Pair(plg_cred, 0),
      Pair(
        Script(#"99999999999999999999999999999999999999999999999999999999"),
        0,
      ),
    ],
  }
  call_validator(tx)
}

// Fails when credential type differs (VerificationKey vs Script)
test plb_fails_with_wrong_credential_type() fail {
  let vkey_cred: Credential = VerificationKey(
    #"0000000000000000000000000000000000000000000000000001091c",
  )
  let tx = Transaction { ..valid_plb_tx(), withdrawals: [Pair(vkey_cred, 0)] }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// Params-reference-input resolution
// ---------------------------------------------------------------------------

// Passes when the params NFT input is not first among reference inputs
test plb_passes_when_params_ref_not_first() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [
      fixture.some_reference_input_tokens_registry_node(
        "",
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "node",
      ),
      params_ref_input(),
    ],
  }
  // params UTxO is the SECOND reference input here → params_idx = 1
  call_validator_at(tx, 1)
}

// Fails when no reference input carries the params NFT policy
test plb_fails_without_params_reference_input() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [
      fixture.some_reference_input_tokens_registry_node(
        "",
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "node",
      ),
    ],
  }
  call_validator(tx)
}

// Fails when the params datum predates the prog_logic_global_cred field
// (3-field layout): PLB must reject rather than authorise via garbage
test plb_fails_on_legacy_three_field_params_datum() fail {
  let modern = params_ref_input()
  let legacy = Input {
    ..modern,
    output: Output {
      ..modern.output,
      datum: InlineDatum(
        as_data(
          LegacyThreeFieldParams {
            registry_node_cs: fixture.policy_tokens_registry,
            prog_logic_cred: fixture.credential_validator_logic_base,
            unfracking_cred: fixture.credential_validator_unfracking,
          },
        ),
      ),
    },
  }
  let tx = Transaction { ..valid_plb_tx(), reference_inputs: [legacy] }
  call_validator(tx)
}

// ---------------------------------------------------------------------------
// In-place upgradability: the datum drives the authorising credential
// ---------------------------------------------------------------------------

// After an upgrade rewrites field 3, PLB authorises via the NEW credential
test plb_authorises_via_upgraded_plg_cred() {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(upgraded_plg_cred, 0)],
  }
  call_validator(tx)
}

// After an upgrade, the OLD PLG credential no longer authorises a spend.
// Two deltas vs the happy path on purpose: the upgraded datum is the
// setup, the stale withdrawal is the invariant under test (one delta vs
// plb_authorises_via_upgraded_plg_cred).
test plb_rejects_stale_plg_cred_after_upgrade() fail {
  let tx = Transaction {
    ..valid_plb_tx(),
    reference_inputs: [upgraded_params_ref_input()],
    withdrawals: [Pair(plg_cred, 0)],
  }
  call_validator(tx)
}

//// Tests for coordination_spend (in-place upgradability, trampoline 2).
////
//// The happy path is a legitimate upgrade: spend the coordination UTxO,
//// return the params NFT + ADA to the same address, rewrite a MUTABLE datum
//// field (here `transfer_cred` — the transfer-validator swap that is the whole point
//// of the mechanism), and carry the upgrade authority's withdraw-0.
////
//// Each failure test is one delta against `valid_upgrade_tx()`, exercising a
//// single rail: NFT/value continuity, singleton in/out at the address, address
//// preservation, datum well-formedness, the frozen anchors, and authorisation.

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{Value, ada_asset_name, ada_policy_id}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use coordination_spend
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// The coordination address: payment credential = coordination_spend's own
/// script hash (arbitrary here), stake credential fixed.
const coordination_cred: Credential =
  Script(#"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0")

fn coordination_address() -> Address {
  Address {
    payment_credential: coordination_cred,
    stake_credential: Some(
      Inline(
        Script(#"5ada5ada5ada5ada5ada5ada5ada5ada5ada5ada5ada5ada5ada5ada"),
      ),
    ),
  }
}

/// The upgrade authority named by the CURRENT datum's `upgrade_cred`.
const authority_cred: Credential = fixture.credential_upgrade_authority

/// A replacement transfer-validator credential — the mutable field a legitimate upgrade edits.
const new_transfer_cred: Credential =
  Script(#"11111111111111111111111111111111111111111111111111111111")

const own_ref: OutputReference =
  OutputReference {
    transaction_id: #"ababababababababababababababababababababababababababababababab0001",
    output_index: 0,
  }

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The value locked in the coordination UTxO: the one-shot params NFT + min ADA.
fn coordination_value() -> Value {
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
    |> assets.add(fixture.policy_protocol_params, "ProtocolParams", 1)
}

/// Params after a legitimate transfer-validator-swap upgrade: only `transfer_cred`
/// changes; everything else (incl. the frozen anchors) is preserved.
fn upgraded_params() -> ProgrammableLogicGlobalParams {
  ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    transfer_cred: new_transfer_cred,
  }
}

fn coordination_input() -> Input {
  Input {
    output_reference: own_ref,
    output: Output {
      address: coordination_address(),
      value: coordination_value(),
      datum: InlineDatum(as_data(fixture.protocol_params)),
      reference_script: None,
    },
  }
}

/// Continuing coordination output for a given new datum + value + address.
fn continuing_output(
  params: ProgrammableLogicGlobalParams,
  val: Value,
  addr: Address,
) -> Output {
  Output {
    address: addr,
    value: val,
    datum: InlineDatum(as_data(params)),
    reference_script: None,
  }
}

/// Happy-path upgrade transaction.
fn valid_upgrade_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [coordination_input()],
    outputs: [
      continuing_output(
        upgraded_params(),
        coordination_value(),
        coordination_address(),
      ),
    ],
    // The upgrade authority approves via its withdraw-0.
    withdrawals: [Pair(authority_cred, 0)],
  }
}

fn call(tx: Transaction) -> Bool {
  coordination_spend.coordination_spend.spend(
    "nonce",
    Some(fixture.protocol_params),
    Void,
    own_ref,
    tx,
  )
}

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

// A legitimate transfer-validator-swap upgrade: mutable field changes, rails all hold.
test coord_upgrade_succeeds() {
  call(valid_upgrade_tx())
}

// Mutating unfracking_cred (also mutable) is fine.
test coord_upgrade_can_change_unfracking_cred() {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          unfracking_cred: new_transfer_cred,
        },
        coordination_value(),
        coordination_address(),
      ),
    ],
  }
  call(tx)
}

// Handover: rewriting upgrade_cred itself is authorised by the CURRENT
// authority — the sitting authority signs off on its own replacement.
test coord_authority_handover_succeeds() {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          upgrade_cred: new_transfer_cred,
          max_inline_datum_bytes: 1024,
        },
        coordination_value(),
        coordination_address(),
      ),
    ],
  }
  call(tx)
}

// ADA top-up is allowed: the value check ratchets lovelace (output >= input)
// precisely so a min-UTxO parameter rise can never strand the coordination
// UTxO behind an un-toppable strict-equality check.
test coord_ada_topup_succeeds() {
  let topped_up = coordination_value()
    |> assets.add(ada_policy_id, ada_asset_name, 1_000_000)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), topped_up, coordination_address()),
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Authorisation
// ---------------------------------------------------------------------------

// Fails when the current authority's withdraw-0 is absent.
test coord_fails_without_authority_withdrawal() fail {
  let tx = Transaction { ..valid_upgrade_tx(), withdrawals: [] }
  call(tx)
}

// Fails when some OTHER credential's withdraw-0 is present, not the authority's.
test coord_fails_with_wrong_authority() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    withdrawals: [Pair(new_transfer_cred, 0)],
  }
  call(tx)
}

// A handover must be authorised by the OLD authority, not the new one: here only
// the incoming credential signs, which must not suffice.
test coord_handover_needs_current_authority() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          upgrade_cred: new_transfer_cred,
          max_inline_datum_bytes: 1024,
        },
        coordination_value(),
        coordination_address(),
      ),
    ],
    withdrawals: [Pair(new_transfer_cred, 0)],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Frozen anchors
// ---------------------------------------------------------------------------

// Fails if prog_logic_cred (the PLB payment credential = token addresses) changes.
test coord_fails_changing_prog_logic_cred() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          prog_logic_cred: new_transfer_cred,
        },
        coordination_value(),
        coordination_address(),
      ),
    ],
  }
  call(tx)
}

// Fails if registry_node_cs (the registry, out of upgrade scope) changes.
test coord_fails_changing_registry_node_cs() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          registry_node_cs: #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
        },
        coordination_value(),
        coordination_address(),
      ),
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// NFT / value continuity
// ---------------------------------------------------------------------------

// Fails if the NFT is dropped from the continuing output (value not conserved).
test coord_fails_dropping_nft() fail {
  let short_value = assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), short_value, coordination_address()),
    ],
  }
  call(tx)
}

// Fails if ADA is drained from the coordination UTxO (lovelace ratchet:
// output must carry >= the input's ADA).
test coord_fails_draining_ada() fail {
  let drained = assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 1_000_000)
    |> assets.add(fixture.policy_protocol_params, "ProtocolParams", 1)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), drained, coordination_address()),
    ],
  }
  call(tx)
}

// Fails if extra tokens are injected into the coordination UTxO (bloat/grief).
test coord_fails_injecting_tokens() fail {
  let bloated = coordination_value()
    |> assets.add(
        #"cafecafecafecafecafecafecafecafecafecafecafecafecafecafe",
        "junk",
        5,
      )
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), bloated, coordination_address()),
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Placement / singleton
// ---------------------------------------------------------------------------

// Fails if the continuing output is sent to a different address (NFT escapes).
test coord_fails_moving_to_other_address() fail {
  let other = Address {
    payment_credential: Script(
      #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    ),
    stake_credential: None,
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [continuing_output(upgraded_params(), coordination_value(), other)],
  }
  call(tx)
}

// Fails if the continuing output changes the stake credential of the address.
test coord_fails_changing_stake_credential() fail {
  let restaked = Address {
    payment_credential: coordination_cred,
    stake_credential: Some(
      Inline(
        Script(#"9999999999999999999999999999999999999999999999999999999b"),
      ),
    ),
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), coordination_value(), restaked),
    ],
  }
  call(tx)
}

// Fails if two outputs land at the coordination address (NFT split / ambiguity).
test coord_fails_two_continuing_outputs() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        upgraded_params(),
        coordination_value(),
        coordination_address(),
      ),
      continuing_output(
        upgraded_params(),
        assets.zero |> assets.add(ada_policy_id, ada_asset_name, 2_000_000),
        coordination_address(),
      ),
    ],
  }
  call(tx)
}

// Fails if a second input at the coordination address is spent in the same tx.
test coord_fails_two_coordination_inputs() fail {
  let second = Input {
    output_reference: OutputReference {
      transaction_id: #"abababababababababababababababababababababababababababababababffff",
      output_index: 1,
    },
    output: Output {
      address: coordination_address(),
      value: assets.zero |> assets.add(ada_policy_id, ada_asset_name, 2_000_000),
      datum: InlineDatum(as_data(fixture.protocol_params)),
      reference_script: None,
    },
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    inputs: [coordination_input(), second],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Datum well-formedness
// ---------------------------------------------------------------------------

// Fails if the continuing output carries no inline datum (readers would brick).
test coord_fails_missing_inline_datum() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      Output {
        address: coordination_address(),
        value: coordination_value(),
        datum: NoDatum,
        reference_script: None,
      },
    ],
  }
  call(tx)
}

// Fails if a reference script is attached to the continuing coordination UTxO.
test coord_fails_reference_script_attached() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      Output {
        ..continuing_output(
          upgraded_params(),
          coordination_value(),
          coordination_address(),
        ),
        reference_script: Some(
          #"abababababababababababababababababababababababababababab00",
        ),
      },
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Credential well-formedness (NEW-2)
//
// An upgrade may rewrite the mutable credential fields, but not to a value that
// can never be satisfied. A Cardano reward account is a header byte + a 28-byte
// hash, so a credential carrying an empty or wrong-length hash can never appear
// in `tx.withdrawals` — the same ledger impossibility the unfracking hook relies
// on for its default-deny. Writing one here is a ONE-WAY BRICK: an unsatisfiable
// `upgrade_cred` makes this validator's own authority check permanently
// unsatisfiable, with no repair path, and an unsatisfiable
// `transfer_cred` makes every programmable-token UTxO unspendable.
// ---------------------------------------------------------------------------

/// A credential whose hash can never key a reward account.
const unsatisfiable_cred: Credential = VerificationKey(#"")

/// A credential with a hash of the wrong length (4 bytes, not 28).
const short_cred: Credential = Script(#"deadbeef")

/// An upgrade transaction whose continuing datum is `params`.
fn upgrade_tx_with(params: ProgrammableLogicGlobalParams) -> Transaction {
  Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(params, coordination_value(), coordination_address()),
    ],
  }
}

// Reject: the upgrade authority itself is set to an unsatisfiable credential.
// This is the unrecoverable case — no later upgrade could repair it.
test coord_fails_unsatisfiable_upgrade_authority() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        upgrade_cred: unsatisfiable_cred,
        max_inline_datum_bytes: 1024,
      },
    ),
  )
}

// Reject: the transfer validator's credential is set to an unsatisfiable one, which would make
// every PLB spend on the deployment fail immediately.
test coord_fails_unsatisfiable_transfer_cred() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        transfer_cred: unsatisfiable_cred,
      },
    ),
  )
}

// Reject: the unfracking credential is set to an unsatisfiable one.
test coord_fails_unsatisfiable_unfracking_cred() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        unfracking_cred: unsatisfiable_cred,
      },
    ),
  )
}

// Reject: a wrong-length (non-28-byte) hash is refused just as an empty one is.
test coord_fails_wrong_length_credential() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        transfer_cred: short_cred,
      },
    ),
  )
}

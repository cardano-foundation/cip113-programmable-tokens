//// Upgrade tests: the `spend` handler of `protocol_params` (in-place
//// upgradability, trampoline 2).
////
//// The happy path is a legitimate upgrade: spend the protocol-params UTxO,
//// return the params NFT + ADA to the same address, rewrite a MUTABLE datum
//// field (here `transfer_cred` — the transfer-validator swap that is the whole point
//// of the mechanism), and carry the upgrade authority's withdraw-0.
////
//// Each failure test is one delta against `valid_upgrade_tx()`, exercising a
//// single rail: NFT/value continuity, singleton in/out at the address, address
//// preservation, datum well-formedness, credential well-formedness, and
//// authorisation.
////
//// ## Designed out by the four-field params datum
////
//// `ProgrammableLogicGlobalParams` dropped `registry_node_cs` and
//// `prog_logic_cred` when their last on-chain readers went away. FOUR tests
//// went with them. Two of the four lived in THIS file, and a reader who finds
//// two deleted security tests deserves to know which of the two reasons
//// applies to each:
////
////   * `params_spend_fails_changing_prog_logic_cred` (was :234-249) — NOT lost
////     coverage. ELIMINATED STATE SPACE. The field does not exist, so
////     "changing it" is unrepresentable, and a rail forbidding an
////     unrepresentable state is unrepresentable too. A freeze rail replaced by
////     non-existence is stronger over that FIELD: it cannot be edited in
////     place, and no future edit to this validator can get the comparison
////     wrong. It does NOT make the VALUE unreachable — the value is now a
////     compile-time parameter of the delegates, and a dispatch-layer swap
////     installs delegates applied with whatever the upgrade authority chose.
////     That is the same authority in the same transaction, and was equally
////     true before this change.
////   * `params_spend_fails_changing_registry_node_cs` (was :252-267) — same
////     reason, same field-removal, same strengthening.
////
//// The other two were plain construction-site casualties, in
//// `validators/transfer.test.ak`:
////
////   * `protocol_params_structure` (was transfer.test.ak:28-40) — its only two
////     assertions were on `prog_logic_cred` and `registry_node_cs`. With both
////     fields gone the test has no assertion left to make; it was not
////     exercising the `transfer` validator at all.
////   * `protocol_params_from_reference_inputs` (was transfer.test.ak:213-225)
////     — same: one assertion, on `registry_node_cs`.
////
//// What still guards this validator's mutable surface is the four
//// `is_28_byte_credential` rails below, the value-conservation ratchet, the
//// singleton in/out structure, the no-reference-script rail and the
//// `upgrade_cred` trampoline read from the OLD datum.

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{Value, ada_asset_name, ada_policy_id}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use protocol_params

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// The protocol-params address: payment credential = the protocol_params script's own
/// script hash (arbitrary here), stake credential fixed.
const params_utxo_cred: Credential =
  Script(#"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0")

fn params_spend_address() -> Address {
  Address {
    payment_credential: params_utxo_cred,
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

/// The mint handler's one-shot parameter. Never read on the spend path.
const genesis_utxo_ref: OutputReference =
  OutputReference {
    transaction_id: #"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd0000",
    output_index: 0,
  }

const own_ref: OutputReference =
  OutputReference {
    transaction_id: #"ababababababababababababababababababababababababababababababab0001",
    output_index: 0,
  }

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The value locked in the protocol-params UTxO: the one-shot params NFT + min ADA.
fn params_utxo_value() -> Value {
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

fn params_utxo_input() -> Input {
  Input {
    output_reference: own_ref,
    output: Output {
      address: params_spend_address(),
      value: params_utxo_value(),
      datum: InlineDatum(as_data(fixture.protocol_params)),
      reference_script: None,
    },
  }
}

/// Continuing protocol-params output for a given new datum + value + address.
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
    inputs: [params_utxo_input()],
    outputs: [
      continuing_output(
        upgraded_params(),
        params_utxo_value(),
        params_spend_address(),
      ),
    ],
    // The upgrade authority approves via its withdraw-0.
    withdrawals: [Pair(authority_cred, 0)],
  }
}

fn call(tx: Transaction) -> Bool {
  protocol_params.protocol_params.spend(
    // The one-shot parameter belongs to the mint handler; the spend handler
    // carries it unused, which is the price of merging the pair into one hash.
    genesis_utxo_ref,
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
test params_spend_upgrade_succeeds() {
  call(valid_upgrade_tx())
}

// Mutating plg_cred (the dispatcher credential) is the CANONICAL upgrade: it
// re-points every programmable spend at a new dispatch layer without moving
// PLB's hash, and therefore without moving a single token address.
test params_spend_upgrade_can_change_plg_cred() {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          plg_cred: new_transfer_cred,
        },
        params_utxo_value(),
        params_spend_address(),
      ),
    ],
  }
  call(tx)
}

// Handover: rewriting upgrade_cred itself is authorised by the CURRENT
// authority — the sitting authority signs off on its own replacement.
test params_spend_authority_handover_succeeds() {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          upgrade_cred: new_transfer_cred,
        },
        params_utxo_value(),
        params_spend_address(),
      ),
    ],
  }
  call(tx)
}

// ADA top-up is allowed: the value check ratchets lovelace (output >= input)
// precisely so a min-UTxO parameter rise can never strand the protocol-params UTxO
// UTxO behind an un-toppable strict-equality check.
test params_spend_ada_topup_succeeds() {
  let topped_up = params_utxo_value()
    |> assets.add(ada_policy_id, ada_asset_name, 1_000_000)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), topped_up, params_spend_address()),
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Authorisation
// ---------------------------------------------------------------------------

// Fails when the current authority's withdraw-0 is absent.
test params_spend_fails_without_authority_withdrawal() fail {
  let tx = Transaction { ..valid_upgrade_tx(), withdrawals: [] }
  call(tx)
}

// Fails when some OTHER credential's withdraw-0 is present, not the authority's.
test params_spend_fails_with_wrong_authority() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    withdrawals: [Pair(new_transfer_cred, 0)],
  }
  call(tx)
}

// A handover must be authorised by the OLD authority, not the new one: here only
// the incoming credential signs, which must not suffice.
test params_spend_handover_needs_current_authority() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        ProgrammableLogicGlobalParams {
          ..fixture.protocol_params,
          upgrade_cred: new_transfer_cred,
        },
        params_utxo_value(),
        params_spend_address(),
      ),
    ],
    withdrawals: [Pair(new_transfer_cred, 0)],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// NFT / value continuity
// ---------------------------------------------------------------------------

// Fails if the NFT is dropped from the continuing output (value not conserved).
test params_spend_fails_dropping_nft() fail {
  let short_value = assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), short_value, params_spend_address()),
    ],
  }
  call(tx)
}

// Audit-3 finding 01: ADA may now be REDUCED. Non-ADA assets are still
// conserved exactly, so the NFT cannot leave; only the input-relative lovelace
// restriction is gone. The ledger's own min-UTxO rule is the real floor, and
// the only party who can spend this UTxO is the upgrade authority — which is
// already trusted to replace every credential in the datum. The old ratchet
// made over-funding unrecoverable by anyone, forever.
test params_spend_ada_withdrawal_succeeds() {
  let reduced = assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 1_200_000)
    |> assets.add(fixture.policy_protocol_params, "ProtocolParams", 1)
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), reduced, params_spend_address()),
    ],
  }
  call(tx)
}

// Fails if extra tokens are injected into the protocol-params UTxO (bloat/grief).
test params_spend_fails_injecting_tokens() fail {
  let bloated = params_utxo_value()
    |> assets.add(
        #"cafecafecafecafecafecafecafecafecafecafecafecafecafecafe",
        "junk",
        5,
      )
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), bloated, params_spend_address()),
    ],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Placement / singleton
// ---------------------------------------------------------------------------

// Fails if the continuing output is sent to a different address (NFT escapes).
test params_spend_fails_moving_to_other_address() fail {
  let other = Address {
    payment_credential: Script(
      #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    ),
    stake_credential: None,
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [continuing_output(upgraded_params(), params_utxo_value(), other)],
  }
  call(tx)
}

// Fails if the continuing output changes the stake credential of the address.
test params_spend_fails_changing_stake_credential() fail {
  let restaked = Address {
    payment_credential: params_utxo_cred,
    stake_credential: Some(
      Inline(
        Script(#"9999999999999999999999999999999999999999999999999999999b"),
      ),
    ),
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(upgraded_params(), params_utxo_value(), restaked),
    ],
  }
  call(tx)
}

// Fails if two outputs land at the protocol-params address (NFT split / ambiguity).
test params_spend_fails_two_continuing_outputs() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      continuing_output(
        upgraded_params(),
        params_utxo_value(),
        params_spend_address(),
      ),
      continuing_output(
        upgraded_params(),
        assets.zero |> assets.add(ada_policy_id, ada_asset_name, 2_000_000),
        params_spend_address(),
      ),
    ],
  }
  call(tx)
}

// Fails if a second input at the protocol-params address is spent in the same tx.
test params_spend_fails_two_params_utxo_inputs() fail {
  let second = Input {
    output_reference: OutputReference {
      transaction_id: #"abababababababababababababababababababababababababababababababffff",
      output_index: 1,
    },
    output: Output {
      address: params_spend_address(),
      value: assets.zero |> assets.add(ada_policy_id, ada_asset_name, 2_000_000),
      datum: InlineDatum(as_data(fixture.protocol_params)),
      reference_script: None,
    },
  }
  let tx = Transaction {
    ..valid_upgrade_tx(),
    inputs: [params_utxo_input(), second],
  }
  call(tx)
}

// ---------------------------------------------------------------------------
// Datum well-formedness
// ---------------------------------------------------------------------------

// Fails if the continuing output carries no inline datum (readers would brick).
test params_spend_fails_missing_inline_datum() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      Output {
        address: params_spend_address(),
        value: params_utxo_value(),
        datum: NoDatum,
        reference_script: None,
      },
    ],
  }
  call(tx)
}

// Fails if a reference script is attached to the continuing protocol-params UTxO.
test params_spend_fails_reference_script_attached() fail {
  let tx = Transaction {
    ..valid_upgrade_tx(),
    outputs: [
      Output {
        ..continuing_output(
          upgraded_params(),
          params_utxo_value(),
          params_spend_address(),
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
      continuing_output(params, params_utxo_value(), params_spend_address()),
    ],
  }
}

// Reject: the upgrade authority itself is set to an unsatisfiable credential.
// This is the unrecoverable case — no later upgrade could repair it.
test params_spend_fails_unsatisfiable_upgrade_authority() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        upgrade_cred: unsatisfiable_cred,
      },
    ),
  )
}

// Reject: the transfer validator's credential is set to an unsatisfiable one, which would make
// every PLB spend on the deployment fail immediately.
test params_spend_fails_unsatisfiable_transfer_cred() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        transfer_cred: unsatisfiable_cred,
      },
    ),
  )
}

// Reject: the DISPATCHER credential is set to an unsatisfiable one. This is the
// widest brick this validator can prevent — an unsatisfiable plg_cred makes
// every programmable token UTxO on the deployment permanently unspendable,
// because PLB requires exactly this credential's withdraw-0 on every input.
test params_spend_fails_unsatisfiable_plg_cred() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        plg_cred: unsatisfiable_cred,
      },
    ),
  )
}

// Reject: a wrong-length (non-28-byte) hash is refused just as an empty one is.
test params_spend_fails_wrong_length_credential() fail {
  call(
    upgrade_tx_with(
      ProgrammableLogicGlobalParams {
        ..fixture.protocol_params,
        transfer_cred: short_cred,
      },
    ),
  )
}

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
//// What still guards this validator's mutable surface is the five
//// `is_28_byte_credential` rails below (one per credential, nominee included),
//// exact non-ADA conservation (lovelace is free since #118), the singleton
//// in/out structure, the no-reference-script rail and the three-arm
//// authorisation read from the OLD datum (#125).

use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{Value, ada_asset_name, ada_policy_id}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use programmable_logic/fixture
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use protocol_params
use types.{
  NominateAuthority, PromoteAuthority, ProtocolParamsRedeemer, ProtocolUpgrade,
}

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

/// The credential the sitting authority nominates as its successor. Distinct
/// from `new_transfer_cred` so a test can never pass by aliasing the two.
const nominee_cred: Credential =
  Script(#"22222222222222222222222222222222222222222222222222222222")

/// A second candidate, for the "someone other than the nominee tries to
/// activate" case.
const impostor_cred: Credential =
  Script(#"33333333333333333333333333333333333333333333333333333333")

/// Params with a handover IN FLIGHT: nominated, not yet activated.
fn params_in_flight() -> ProgrammableLogicGlobalParams {
  ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    pending_upgrade_cred: Some(nominee_cred),
  }
}

/// Params after a completed handover: the nominee is the authority and the
/// nomination is cleared. Every other field is untouched — that is the rail.
fn params_promoted() -> ProgrammableLogicGlobalParams {
  ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    upgrade_cred: nominee_cred,
    pending_upgrade_cred: None,
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

/// The params UTxO carrying an arbitrary old datum — needed by every test
/// that starts from a handover already in flight.
fn params_utxo_input_with(old: ProgrammableLogicGlobalParams) -> Input {
  Input {
    output_reference: own_ref,
    output: Output {
      address: params_spend_address(),
      value: params_utxo_value(),
      datum: InlineDatum(as_data(old)),
      reference_script: None,
    },
  }
}

/// Spend a params UTxO whose CURRENT datum is `old`, producing `new`, with
/// `withdrawals` present. The single shape every two-phase test is built from.
fn handover_tx(
  old: ProgrammableLogicGlobalParams,
  new: ProgrammableLogicGlobalParams,
  withdrawals: Pairs<Credential, Int>,
) -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [params_utxo_input_with(old)],
    outputs: [
      continuing_output(new, params_utxo_value(), params_spend_address()),
    ],
    withdrawals,
  }
}

/// Spend a params UTxO whose CURRENT datum is `old`, under the DECLARED
/// action, with `tx`. Reads as: call, under this action, from this state.
fn call_from(
  redeemer: ProtocolParamsRedeemer,
  old: ProgrammableLogicGlobalParams,
  tx: Transaction,
) -> Bool {
  protocol_params.protocol_params.spend(
    genesis_utxo_ref,
    Some(old),
    redeemer,
    own_ref,
    tx,
  )
}

/// The structural rails (value, address, singleton in/out, datum shape) are
/// action-agnostic, so they are all exercised under `ProtocolUpgrade` — the
/// arm an ordinary upgrade uses.
fn call(tx: Transaction) -> Bool {
  protocol_params.protocol_params.spend(
    // The one-shot parameter belongs to the mint handler; the spend handler
    // carries it unused, which is the price of merging the pair into one hash.
    genesis_utxo_ref,
    Some(fixture.protocol_params),
    ProtocolUpgrade,
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

// Issue #125: **BEHAVIOUR CHANGE.** This was
// `params_spend_authority_handover_succeeds`, and it PASSED: the sitting
// authority could rewrite `upgrade_cred` in one step, with nothing checked
// about the incoming credential but its length. That is the brick this issue
// is about — a hash for a script nobody deployed becomes the only credential
// able to authorise the next spend, and there is no repair path.
//
// The capability is not removed, it is split: see
// `params_spend_nomination_succeeds` and `params_spend_promotion_succeeds`
// below, which together do what this test used to do in one transaction.
test params_spend_fails_direct_authority_rewrite() fail {
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

// ADA top-up is allowed: lovelace is unconstrained relative to the input
// (audit-3 finding 01, #118), so a min-UTxO parameter rise can never strand
// the protocol-params UTxO. Non-ADA assets are still conserved exactly.
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

// An incoming credential cannot install itself under an ORDINARY upgrade: it
// presents its own withdraw-0 and writes itself in as the authority, but
// `ProtocolUpgrade` is authorised by the sitting credential and refuses to
// move `upgrade_cred` at all. The same attempt declared as `PromoteAuthority`
// is covered by `params_spend_fails_promotion_declared_without_nomination`.
test params_spend_fails_self_installation_under_ordinary_upgrade() fail {
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

/// An ada-only UTxO someone parked at the protocol-params address. Anyone can
/// create one at any time; it carries no NFT and whatever datum its sender
/// chose.
fn junk_at_params_address() -> Input {
  Input {
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
}

// Double satisfaction, the genuine half: spending the params UTxO together with
// junk parked at its address is fine FOR THE GENUINE INPUT'S RUN — its
// continuing output matches its own non-ADA value. There is no "exactly one
// input at this address" rail, and this test is what says so on purpose.
test params_spend_genuine_run_passes_alongside_junk_input() {
  call(
    Transaction {
      ..valid_upgrade_tx(),
      inputs: [params_utxo_input(), junk_at_params_address()],
    },
  )
}

// Double satisfaction, the half that matters: the JUNK input's run of this
// validator, in that same transaction, fails — the one continuing output
// carries the NFT and the junk input does not, so exact non-ADA conservation
// rejects it. That is what makes the input-count rail redundant: the value
// rail already fails any transaction that spends two UTxOs at this address,
// because at most one of them can hold the one-shot NFT.
test params_spend_fails_junk_run_alongside_genuine() fail {
  let junk = junk_at_params_address()
  protocol_params.protocol_params.spend(
    genesis_utxo_ref,
    Some(fixture.protocol_params),
    ProtocolUpgrade,
    junk.output_reference,
    Transaction { ..valid_upgrade_tx(), inputs: [params_utxo_input(), junk] },
  )
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

// Reject: the upgrade authority itself is set to an unsatisfiable credential
// — the unrecoverable case, since no later upgrade could repair it.
//
// Since #125 this fails on the DIRECT-REWRITE ban, not on the length rail:
// `ProtocolUpgrade` refuses to move `upgrade_cred` at all, whatever the value.
// The length rail on `upgrade_cred` is reachable only at genesis
// (`genesis_fails_wrong_length_upgrade_cred`), because the one path that can
// change it — promotion — requires the nominee's withdrawal, and the ledger
// admits only a real 28-byte credential there. Mutation-verified 2026-09-08:
// neutering that rail kills the genesis test alone. Kept because the shape —
// writing an authority nobody can satisfy — is the threat this file exists to
// document, and this is where a reader looks for it.
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

// ---------------------------------------------------------------------------
// Issue #125 — two-phase authority handover
// ---------------------------------------------------------------------------
//
// Phase 1 (NOMINATE) is an ordinary upgrade by the sitting authority: it
// writes `pending_upgrade_cred` and nothing takes effect. Phase 2 (PROMOTE)
// is the nominee presenting its own withdraw-0, which is the evidence that it
// exists, runs and consents. Between the two the sitting authority may revoke.
//
// The co-signature form first drafted for #125 — require the incoming
// credential's withdrawal in the SAME transaction as the rewrite — was
// rejected because it restricts the successor to parties that can be
// scheduled into someone else's transaction, which excludes a governance
// action and any slowly-assembled quorum. The tests below are what replaces
// it: `params_spend_promotion_succeeds` carries ONLY the nominee's
// withdrawal, which is the whole point.

// Phase 1: nominate. `upgrade_cred` does not move, so nothing has changed hands.
test params_spend_nomination_succeeds() {
  call_from(
    NominateAuthority,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      params_in_flight(),
      [Pair(authority_cred, 0)],
    ),
  )
}

// **BEHAVIOUR CHANGE, deliberate.** Under the three-action redeemer a
// nomination may NOT ride along with a parameter change: `NominateAuthority`
// freezes every field but the nomination. An earlier draft of this branch
// allowed it (`params_spend_nomination_alongside_upgrade_succeeds`, which
// passed) because the two routes were inferred rather than declared.
//
// The cost is one extra transaction on the rarest path in the protocol. What
// it buys is that a handover always BEGINS as its own transaction, visible as
// such to anyone watching the chain, instead of being reachable inside
// something that presents itself as a routine parameter change.
test params_spend_fails_nomination_carrying_an_upgrade() fail {
  let nominated_and_upgraded = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    transfer_cred: new_transfer_cred,
    pending_upgrade_cred: Some(nominee_cred),
  }
  call_from(
    NominateAuthority,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      nominated_and_upgraded,
      [Pair(authority_cred, 0)],
    ),
  )
}

// The mirror: an ordinary upgrade may not begin a handover either. Together
// with the test above, this is what makes the declared action a RAIL rather
// than a label — neither arm can do the other's job.
test params_spend_fails_upgrade_carrying_a_nomination() fail {
  let upgraded_and_nominated = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    transfer_cred: new_transfer_cred,
    pending_upgrade_cred: Some(nominee_cred),
  }
  call_from(
    ProtocolUpgrade,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      upgraded_and_nominated,
      [Pair(authority_cred, 0)],
    ),
  )
}

// A nomination may not move the authority: that is what phase 2 is for.
test params_spend_fails_nomination_moving_the_authority() fail {
  let nominated_and_promoted = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    upgrade_cred: nominee_cred,
    pending_upgrade_cred: Some(nominee_cred),
  }
  call_from(
    NominateAuthority,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      nominated_and_promoted,
      [Pair(authority_cred, 0)],
    ),
  )
}

// Declaring `PromoteAuthority` with no nomination standing aborts on the
// `expect Some(nominee)`: there is nothing to promote, and the arm never
// falls back to the sitting authority.
test params_spend_fails_promotion_declared_without_nomination() fail {
  call_from(
    PromoteAuthority,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      params_promoted(),
      [Pair(nominee_cred, 0)],
    ),
  )
}

// Revocation: the sitting authority clears a nomination it regrets. Also an
// ordinary upgrade — this is the repair path the one-step rewrite never had.
test params_spend_revocation_succeeds() {
  call_from(
    NominateAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      fixture.protocol_params,
      [Pair(authority_cred, 0)],
    ),
  )
}

// Re-nomination: replacing one nominee with another needs no revoke first.
test params_spend_renomination_succeeds() {
  let renominated = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    pending_upgrade_cred: Some(impostor_cred),
  }
  call_from(
    NominateAuthority,
    params_in_flight(),
    handover_tx(params_in_flight(), renominated, [Pair(authority_cred, 0)]),
  )
}

// Phase 2: the nominee activates ITSELF, carrying only its own withdrawal.
// The outgoing authority is absent from this transaction entirely — that is
// the property the co-signature design could not offer, and the reason a
// governance action can be a successor.
test params_spend_promotion_succeeds() {
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(params_in_flight(), params_promoted(), [Pair(nominee_cred, 0)]),
  )
}

// The cooperative case still works: both authorities present is a superset of
// what promotion requires, and adding a withdrawal never removes a constraint.
test params_spend_promotion_with_both_withdrawals_succeeds() {
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      params_promoted(),
      [Pair(authority_cred, 0), Pair(nominee_cred, 0)],
    ),
  )
}

// The sitting authority cannot complete the handover on the nominee's behalf:
// route 1 refuses to move `upgrade_cred` at all, and route 2 needs a
// withdrawal only the nominee can produce. Without this the two-phase split
// would be theatre — the sitting authority could nominate and promote in two
// transactions it fully controls, and the nominee would still never have
// proved anything.
test params_spend_fails_promotion_without_nominee_withdrawal() fail {
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      params_promoted(),
      [Pair(authority_cred, 0)],
    ),
  )
}

// Only the NOMINATED credential may activate. Here a third party presents its
// own withdrawal and writes itself in as the authority.
test params_spend_fails_promotion_by_non_nominee() fail {
  let impostor_promoted = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    upgrade_cred: impostor_cred,
    pending_upgrade_cred: None,
  }
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(params_in_flight(), impostor_promoted, [Pair(impostor_cred, 0)]),
  )
}

// Promotion is PURE: the nominee may not change anything else on its way in.
// `plg_cred` is the sharpest case — it re-points every programmable spend on
// the deployment, and this is exactly the transaction the sitting authority
// would be racing to revoke.
test params_spend_fails_promotion_changing_plg_cred() fail {
  let promoted_and_upgraded = ProgrammableLogicGlobalParams {
    ..params_promoted(),
    plg_cred: new_transfer_cred,
  }
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      promoted_and_upgraded,
      [Pair(nominee_cred, 0)],
    ),
  )
}

// A promotion must CLEAR the nomination. Leaving it set would keep a live
// second route open against the new authority, which nobody nominated.
test params_spend_fails_promotion_leaving_nomination_set() fail {
  let promoted_but_still_pending = ProgrammableLogicGlobalParams {
    ..params_promoted(),
    pending_upgrade_cred: Some(nominee_cred),
  }
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      promoted_but_still_pending,
      [Pair(nominee_cred, 0)],
    ),
  )
}

// The 28-byte rail reaches the nomination too, one phase before it could
// matter: a wrong-length nominee is refused at nomination time rather than
// becoming a nominee that can never produce a withdrawal.
test params_spend_fails_wrong_length_pending_cred() fail {
  let bad_nomination = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    pending_upgrade_cred: Some(short_cred),
  }
  call_from(
    NominateAuthority,
    fixture.protocol_params,
    handover_tx(
      fixture.protocol_params,
      bad_nomination,
      [Pair(authority_cred, 0)],
    ),
  )
}

// The nominee may not install a DIFFERENT successor than the one nominated.
// Isolates the promotion's record-equality rail: the nominee's withdrawal is
// present, so the transaction gets past the withdrawal check and dies on the
// datum comparison alone.
test params_spend_fails_promotion_installing_other_credential() fail {
  let wrong_successor = ProgrammableLogicGlobalParams {
    ..fixture.protocol_params,
    upgrade_cred: impostor_cred,
    pending_upgrade_cred: None,
  }
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(params_in_flight(), wrong_successor, [Pair(nominee_cred, 0)]),
  )
}

// The nominee may not smuggle an ordinary parameter change into its own
// promotion. `transfer_cred` is the everyday upgrade field, so this is the
// shape a nominee would actually reach for; it must cost a second transaction
// under the sitting-authority route, after the handover has completed.
test params_spend_fails_promotion_changing_transfer_cred() fail {
  let promoted_and_upgraded = ProgrammableLogicGlobalParams {
    ..params_promoted(),
    transfer_cred: new_transfer_cred,
  }
  call_from(
    PromoteAuthority,
    params_in_flight(),
    handover_tx(
      params_in_flight(),
      promoted_and_upgraded,
      [Pair(nominee_cred, 0)],
    ),
  )
}

//// Tests for `issuance_mint` — the PERMANENT half of issuance (#129).
////
//// The policy checks two things and nothing else: the token's own minting
//// logic ran, and the protocol's `issuance_logic` ran AND named this policy
//// as a key of its redeemer. Every rule about registry proofs, custody and
//// output shape is exercised in `issuance_logic.test.ak`; here the question
//// is only whether the permanent policy binds to the right script and the
//// right key, and refuses everything that is not that.

use aiken/collection/list
use cardano/address.{Address, Credential, Script}
use cardano/assets.{PolicyId, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
}
use issuance_mint
use programmable_logic/params.{ProgrammableLogicGlobalParams}
use types.{IssuanceRedeemer, MintingRegistryProof, RefInput}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ml_cred: Credential =
  Script(#"11111111111111111111111111111111111111111111111111111111")

const params_policy: PolicyId =
  #"22222222222222222222222222222222222222222222222222222222"

const own_policy: PolicyId =
  #"33333333333333333333333333333333333333333333333333333333"

const other_policy: PolicyId =
  #"44444444444444444444444444444444444444444444444444444444"

/// The LIVE issuance-logic credential, as named by the params datum.
const logic_hash: ByteArray =
  #"15501550155015501550155015501550155015501550155015501550"

const logic_cred: Credential = Script(logic_hash)

/// A previous issuance-logic script, no longer named by the datum.
const stale_logic_cred: Credential =
  Script(#"01d001d001d001d001d001d001d001d001d001d001d001d001d001d0")

const placeholder: Credential =
  Script(#"99999999999999999999999999999999999999999999999999999999")

const token_name: ByteArray = #"746f6b656e"

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn oref(i: Int) -> OutputReference {
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
    output_index: i,
  }
}

/// The protocol-params UTxO: params NFT + a datum whose field 5 names the
/// live issuance-logic credential. Every other field is a placeholder; the
/// permanent policy reads field 5 alone.
fn params_ref_input() -> Input {
  Input {
    output_reference: oref(0),
    output: Output {
      address: Address {
        payment_credential: placeholder,
        stake_credential: None,
      },
      value: assets.from_lovelace(2_000_000)
        |> assets.add(params_policy, "ProtocolParams", 1),
      datum: InlineDatum(
        as_data(
          ProgrammableLogicGlobalParams {
            plg_cred: placeholder,
            transfer_cred: placeholder,
            third_party_cred: placeholder,
            upgrade_cred: placeholder,
            pending_upgrade_cred: None,
            issuance_logic_cred: logic_cred,
          },
        ),
      ),
      reference_script: None,
    },
  }
}

/// A reference input that is not the params UTxO.
fn junk_ref_input() -> Input {
  Input {
    output_reference: oref(7),
    output: Output {
      address: Address {
        payment_credential: placeholder,
        stake_credential: None,
      },
      value: assets.from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// `issuance_logic`'s redeemer: a map policy -> proof. The proofs are opaque
/// to the permanent policy; `RefInput(0)` is a placeholder.
fn coverage(policies: List<PolicyId>) -> Data {
  let entries: Pairs<PolicyId, MintingRegistryProof> = list.map(
    policies,
    fn(p) { Pair(p, RefInput(0)) },
  )
  as_data(entries)
}

/// A transaction in which both withdraw-0s ran and the logic covered us.
fn valid_tx() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    reference_inputs: [params_ref_input()],
    mint: from_asset(own_policy, token_name, 100),
    withdrawals: [Pair(ml_cred, 0), Pair(logic_cred, 0)],
    redeemers: [Pair(Withdraw(logic_cred), coverage([own_policy]))],
  }
}

fn call_at(params_idx: Int, tx: Transaction) -> Bool {
  issuance_mint.issuance_mint.mint(
    ml_cred,
    params_policy,
    IssuanceRedeemer { params_idx },
    own_policy,
    tx,
  )
}

fn call(tx: Transaction) -> Bool {
  call_at(0, tx)
}

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

test mint_valid() {
  call(valid_tx())
}

// The permanent policy does not look at the sign of the mint; burning takes
// the same two proofs.
test burn_valid() {
  call(
    Transaction { ..valid_tx(), mint: from_asset(own_policy, token_name, -40) },
  )
}

// The logic's map may name several policies; ours only has to be among them.
test covered_among_other_policies() {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [
        Pair(Withdraw(logic_cred), coverage([other_policy, own_policy])),
      ],
    },
  )
}

// `params_idx` is an index hint, not a scan: the params UTxO may sit anywhere
// among the reference inputs as long as the hint points at it.
test params_hint_at_second_position() {
  call_at(
    1,
    Transaction {
      ..valid_tx(),
      reference_inputs: [junk_ref_input(), params_ref_input()],
    },
  )
}

// Other redeemers in the transaction — the issuer's own withdraw-0, say — are
// walked past, not mistaken for the coverage map.
test other_redeemers_are_skipped() {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [
        Pair(Withdraw(ml_cred), as_data(Void)),
        Pair(Withdraw(logic_cred), coverage([own_policy])),
      ],
    },
  )
}

// ---------------------------------------------------------------------------
// The two proofs
// ---------------------------------------------------------------------------

// Proof of instance: the token's own minting logic must run.
test fails_minting_logic_not_invoked() fail {
  call(Transaction { ..valid_tx(), withdrawals: [Pair(logic_cred, 0)] })
}

// The protocol's issuance logic must run: no redeemer under its credential.
test fails_issuance_logic_not_invoked() fail {
  call(Transaction { ..valid_tx(), redeemers: [] })
}

// The logic ran but did not name us: its map covers another policy only.
test fails_not_covered() fail {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [Pair(Withdraw(logic_cred), coverage([other_policy]))],
    },
  )
}

test fails_empty_coverage() fail {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [Pair(Withdraw(logic_cred), coverage([]))],
    },
  )
}

// THE upgrade property (#129): the credential that counts is the one the
// params datum names NOW. A previous issuance-logic script still running —
// with a redeemer that covers us — no longer proves anything.
test fails_stale_issuance_logic() fail {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [Pair(Withdraw(stale_logic_cred), coverage([own_policy]))],
    },
  )
}

// The frozen interface: the logic's redeemer must decode as a map keyed by
// policy id. Anything else aborts at the decode.
test fails_malformed_coverage() fail {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [Pair(Withdraw(logic_cred), as_data(42))],
    },
  )
}

// A coverage claim under the MINT purpose is not the logic's redeemer.
test fails_coverage_under_wrong_purpose() fail {
  call(
    Transaction {
      ..valid_tx(),
      redeemers: [Pair(transaction.Mint(own_policy), coverage([own_policy]))],
    },
  )
}

// ---------------------------------------------------------------------------
// Locating the params UTxO
// ---------------------------------------------------------------------------

// The hint points at a reference input without the params NFT.
test fails_wrong_params_hint() fail {
  call_at(
    0,
    Transaction {
      ..valid_tx(),
      reference_inputs: [junk_ref_input(), params_ref_input()],
    },
  )
}

test fails_params_ref_input_missing() fail {
  call(Transaction { ..valid_tx(), reference_inputs: [] })
}

// A datum that names a different live credential than the one that ran.
test fails_datum_names_other_logic() fail {
  let renamed = Input {
    ..params_ref_input(),
    output: Output {
      ..params_ref_input().output,
      datum: InlineDatum(
        as_data(
          ProgrammableLogicGlobalParams {
            plg_cred: placeholder,
            transfer_cred: placeholder,
            third_party_cred: placeholder,
            upgrade_cred: placeholder,
            pending_upgrade_cred: None,
            issuance_logic_cred: stale_logic_cred,
          },
        ),
      ),
    },
  }
  call(Transaction { ..valid_tx(), reference_inputs: [renamed] })
}

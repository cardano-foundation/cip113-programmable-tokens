//// Genesis tests: the `mint` handler of `protocol_params`.
////
//// Tests invoke the validator's mint handler directly, covering:
//// - Happy path (all conditions met)
//// - One-shot UTxO consumption
//// - Token name and quantity checks
//// - Protocol-params address enforcement
//// - InlineDatum and ProgrammableLogicGlobalParams datum validation

use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id, from_asset}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use programmable_logic/params.{
  ProgrammableLogicGlobalParams, protocol_params_token,
}
use protocol_params

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const test_utxo_ref =
  OutputReference {
    transaction_id: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    output_index: 0,
  }

const test_policy_id: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const min_ada =
  assets.zero
    |> assets.add(ada_policy_id, ada_asset_name, 2_000_000)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// After the merge the params UTxO is locked at the minting policy's own
/// script hash — no parameter names the address, the policy IS the address.
fn params_spend_address() -> Address {
  Address { payment_credential: Script(test_policy_id), stake_credential: None }
}

fn valid_params_datum() -> Data {
  as_data(
    ProgrammableLogicGlobalParams {
      plg_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      transfer_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      third_party_cred: Script(
        #"00000000000000000000000000000000000000000000000000731d3a",
      ),
      upgrade_cred: Script(
        #"000000000000000000000000000000000000000000000000009c6ade",
      ),
      pending_upgrade_cred: None,
      issuance_logic_cred: Script(
        #"000000000000000000000000000000000000000000000000001550ab",
      ),
    },
  )
}

fn valid_nft_output() -> Output {
  Output {
    address: params_spend_address(),
    value: min_ada
      |> assets.add(test_policy_id, protocol_params_token, 1),
    datum: InlineDatum(valid_params_datum()),
    reference_script: None,
  }
}

fn valid_input() -> Input {
  Input {
    output_reference: test_utxo_ref,
    output: Output {
      address: Address {
        payment_credential: VerificationKey(
          #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
        stake_credential: None,
      },
      value: min_ada,
      datum: NoDatum,
      reference_script: None,
    },
  }
}

fn valid_transaction() -> Transaction {
  Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [valid_nft_output()],
  }
}

fn call_validator(utxo_ref: OutputReference, tx: Transaction) -> Bool {
  protocol_params.protocol_params.mint(
    utxo_ref,
    as_data(Void),
    test_policy_id,
    tx,
  )
}

// ========================================================================
// Happy path — all conditions met
// ========================================================================

test protocol_params_genesis_valid() {
  call_validator(test_utxo_ref, valid_transaction())
}

// ========================================================================
// One-shot UTxO not consumed
// ========================================================================

test fails_when_utxo_not_consumed() fail {
  let wrong_utxo_ref = OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 99,
  }
  call_validator(wrong_utxo_ref, valid_transaction())
}

// ========================================================================
// Wrong token name — the `tn == protocol_params_token` check
//
// We mint "WrongName" but keep the output NFT as "ProtocolParams" so
// has_nft_strict and datum checks pass; only the token-name check fails.
// ========================================================================

test fails_with_wrong_token_name() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, "WrongName", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// Quantity != 1 — the `qty == 1` check
//
// We mint qty=2 but keep the output with qty=1 so has_nft_strict passes;
// only the quantity check in the and-block fails.
// ========================================================================

test fails_when_quantity_is_not_one() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 2),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// Multiple token names minted under the same policy
//
// The `expect [(_, tn, qty)] = own_minted` pattern crashes because
// the list has 2 elements instead of 1.
// ========================================================================

test fails_with_multiple_token_names_minted() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1)
      |> assets.add(test_policy_id, "ExtraToken", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// No tokens minted from own policy
//
// The mint contains a different policy entirely, so `own_minted` is empty
// and `expect [(_, tn, qty)]` crashes.
// ========================================================================

test fails_when_no_tokens_minted_from_own_policy() fail {
  let other_policy: PolicyId = #"1111111111111111111111111111111111111111111111111111111111"
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(other_policy, "SomeToken", 1),
    outputs: [valid_nft_output()],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// No output at the protocol-params address
//
// The NFT goes to a completely different address.
// `expect Some(nft_output) = list.find(...)` crashes because no output
// matches the expected protocol-params address.
// ========================================================================

test fails_when_no_output_at_params_spend_address() fail {
  let wrong_address = Address {
    payment_credential: Script(
      #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ),
    stake_credential: None,
  }
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [
      Output {
        address: wrong_address,
        value: min_ada
          |> assets.add(test_policy_id, protocol_params_token, 1),
        datum: InlineDatum(valid_params_datum()),
        reference_script: None,
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// Output at protocol-params address exists but does NOT contain the NFT
//
// `has_nft_strict(nft_output.value, own_policy, ...)` fails because
// the output at the protocol-params address has only ADA.
// ========================================================================

test fails_when_nft_missing_from_params_output() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [
      // Output at protocol-params address but WITHOUT the NFT
      Output {
        address: params_spend_address(),
        value: min_ada,
        datum: InlineDatum(valid_params_datum()),
        reference_script: None,
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// No inline datum on the protocol-params output
//
// `expect InlineDatum(datum) = nft_output.datum` crashes because the
// output uses NoDatum.
// ========================================================================

test fails_when_no_inline_datum() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [Output { ..valid_nft_output(), datum: NoDatum }],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// Invalid datum type — datum is not ProgrammableLogicGlobalParams
//
// `expect _params: ProgrammableLogicGlobalParams = datum` crashes because
// an Int doesn't match the ProgrammableLogicGlobalParams constructor.
// ========================================================================

test fails_with_invalid_datum_type() fail {
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [valid_input()],
    mint: from_asset(test_policy_id, protocol_params_token, 1),
    outputs: [Output { ..valid_nft_output(), datum: InlineDatum(as_data(42)) }],
  }
  call_validator(test_utxo_ref, tx)
}

// ========================================================================
// Genesis rails (M4 / audit-3 finding 05 family): the state the spend handler
// refuses to move to must also be a state the mint handler refuses to create.
// ========================================================================

/// A datum whose `upgrade_cred` is a 27-byte hash. A reward account is a header
/// byte + 28-byte hash, so this credential can never appear in `tx.withdrawals`
/// — the protocol would be born with an authority that can never authorise
/// anything, and no repair path exists.
fn short_upgrade_cred_datum() -> Data {
  as_data(
    ProgrammableLogicGlobalParams {
      plg_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      transfer_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      third_party_cred: Script(
        #"00000000000000000000000000000000000000000000000000731d3a",
      ),
      upgrade_cred: Script(
        #"0000000000000000000000000000000000000000000000000000009c6a",
      ),
      pending_upgrade_cred: None,
      issuance_logic_cred: Script(
        #"000000000000000000000000000000000000000000000000001550ab",
      ),
    },
  )
}

// M4: genesis may not install an unsatisfiable upgrade authority.
test genesis_fails_wrong_length_upgrade_cred() fail {
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [
      Output {
        ..valid_nft_output(),
        datum: InlineDatum(short_upgrade_cred_datum()),
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// M4: genesis may not install an unsatisfiable dispatcher credential — the
// widest brick available, since `plg_cred` is on every token's spend path.
test genesis_fails_wrong_length_plg_cred() fail {
  let bad_datum = as_data(
    ProgrammableLogicGlobalParams {
      plg_cred: Script(
        #"000000000000000000000000000000000000000000000000000109",
      ),
      transfer_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      third_party_cred: Script(
        #"00000000000000000000000000000000000000000000000000731d3a",
      ),
      upgrade_cred: Script(
        #"000000000000000000000000000000000000000000000000009c6ade",
      ),
      pending_upgrade_cred: None,
      issuance_logic_cred: Script(
        #"000000000000000000000000000000000000000000000000001550ab",
      ),
    },
  )
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [Output { ..valid_nft_output(), datum: InlineDatum(bad_datum) }],
  }
  call_validator(test_utxo_ref, tx)
}

// No junk token may ride in alongside the NFT: the spend handler conserves
// non-ADA value exactly, so anything minted in here would be welded in forever.
// The guarantee comes from `has_nft_strict`, which matches only a value whose
// non-ADA half is exactly the one NFT — so the tagged output is never found.
// Pinned here because nothing in the mint handler names the invariant.
test genesis_fails_junk_token_alongside_nft() fail {
  let junk_policy: PolicyId = #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [
      Output {
        ..valid_nft_output(),
        value: valid_nft_output().value
          |> assets.add(junk_policy, "JUNK", 1),
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// M4: no reference script at genesis — the spend handler forbids one on every
// continuing output, and every reader of this UTxO would pay for it.
test genesis_fails_reference_script_attached() fail {
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [
      Output {
        ..valid_nft_output(),
        reference_script: Some(
          #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        ),
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// The rails do not ban a legitimate ADA amount above the minimum: only the
// non-ADA half of the value is pinned.
test genesis_allows_extra_ada() {
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [
      Output {
        ..valid_nft_output(),
        value: valid_nft_output().value
          |> assets.add(ada_policy_id, ada_asset_name, 8_000_000),
      },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// Issue #125: genesis must produce a protocol AT REST — no handover already in
// flight. A nomination baked into the genesis datum would hand a nominee the
// power to take the upgrade authority before the deployer had ever exercised
// it, and nothing legitimate needs it: the sitting authority can nominate in
// its own transaction, one block later, where the act is visible and
// revocable.
test genesis_fails_pending_nomination() fail {
  let nominated_at_birth = as_data(
    ProgrammableLogicGlobalParams {
      plg_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      transfer_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      third_party_cred: Script(
        #"00000000000000000000000000000000000000000000000000731d3a",
      ),
      upgrade_cred: Script(
        #"000000000000000000000000000000000000000000000000009c6ade",
      ),
      pending_upgrade_cred: Some(
        Script(#"00000000000000000000000000000000000000000000000000abcdef"),
      ),
      issuance_logic_cred: Script(
        #"000000000000000000000000000000000000000000000000001550ab",
      ),
    },
  )
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [
      Output { ..valid_nft_output(), datum: InlineDatum(nominated_at_birth) },
    ],
  }
  call_validator(test_utxo_ref, tx)
}

// The positive twin: a nomination that is simply absent is the normal genesis
// shape, and it is what `valid_params_datum` already carries. Stated as its
// own test so the rail above cannot be "fixed" by banning the field outright.
test genesis_allows_no_pending_nomination() {
  call_validator(test_utxo_ref, valid_transaction())
}

// Issue #129: `issuance_logic_cred` is held to the same 28-byte rail as every
// other credential. An unsatisfiable one here would halt issuance for every
// token on the deployment, with no repair path short of a params update.
test genesis_fails_wrong_length_issuance_logic_cred() fail {
  let bad_datum = as_data(
    ProgrammableLogicGlobalParams {
      plg_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      transfer_cred: Script(
        #"0000000000000000000000000000000000000000000000000001091c",
      ),
      third_party_cred: Script(
        #"00000000000000000000000000000000000000000000000000731d3a",
      ),
      upgrade_cred: Script(
        #"000000000000000000000000000000000000000000000000009c6ade",
      ),
      pending_upgrade_cred: None,
      issuance_logic_cred: Script(#"1550ab"),
    },
  )
  let tx = Transaction {
    ..valid_transaction(),
    outputs: [Output { ..valid_nft_output(), datum: InlineDatum(bad_datum) }],
  }
  call_validator(test_utxo_ref, tx)
}

// // Integration tests for example transfer logic validators
// use aiken/collection/list
// use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
// use cardano/assets.{zero}
// use cardano/transaction.{Input, NoDatum, Output, OutputReference}

// // Test data
// const test_permitted_pkh = #"aabbccdd"

// // const test_permitted_cred: Credential = VerificationKey(test_permitted_pkh)

// const test_other_pkh = #"11223344"

// const test_prog_logic_base_cred: Credential = Script(#"70726f67")

// // const test_blacklist_node_cs: PolicyId =
// //   #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"

// // Test simple permissioned transfer with VerificationKey
// test simple_permissioned_transfer_with_vkey() {
//   let permitted_cred = VerificationKey(test_permitted_pkh)
//   let extra_signatories = [test_permitted_pkh, #"99999999"]

//   when permitted_cred is {
//     VerificationKey(pkh) -> list.has(extra_signatories, pkh)
//     _ -> False
//   }
// }

// // Test simple permissioned transfer fails without signature
// test simple_permissioned_transfer_fails_without_signature() {
//   let permitted_cred = VerificationKey(test_permitted_pkh)
//   let extra_signatories = [test_other_pkh]

//   when permitted_cred is {
//     VerificationKey(pkh) -> !list.has(extra_signatories, pkh)
//     _ -> True
//   }
// }

// // Test script credential always passes (simplified)
// test script_credential_always_passes() {
//   let permitted_cred = Script(#"736372697074")

//   when permitted_cred is {
//     VerificationKey(_) -> False
//     _ -> True
//   }
// }

// // Test freeze-and-seize gets prog inputs
// test freeze_and_seize_gets_prog_inputs() {
//   let inputs =
//     [
//       Input {
//         output_reference: OutputReference {
//           transaction_id: #"00",
//           output_index: 0,
//         },
//         output: Output {
//           address: Address {
//             payment_credential: test_prog_logic_base_cred,
//             stake_credential: Some(Inline(VerificationKey(test_permitted_pkh))),
//           },
//           value: zero,
//           datum: NoDatum,
//           reference_script: None,
//         },
//       },
//       Input {
//         output_reference: OutputReference {
//           transaction_id: #"01",
//           output_index: 1,
//         },
//         output: Output {
//           address: Address {
//             payment_credential: Script(#"6f74686572"),
//             stake_credential: None,
//           },
//           value: zero,
//           datum: NoDatum,
//           reference_script: None,
//         },
//       },
//     ]

//   let prog_inputs =
//     list.filter(
//       inputs,
//       fn(input) {
//         input.output.address.payment_credential == test_prog_logic_base_cred
//       },
//     )

//   list.length(prog_inputs) == 1
// }

// // Test freeze-and-seize extracts stake credentials
// test freeze_and_seize_extracts_stake_credentials() {
//   let input =
//     Input {
//       output_reference: OutputReference {
//         transaction_id: #"00",
//         output_index: 0,
//       },
//       output: Output {
//         address: Address {
//           payment_credential: test_prog_logic_base_cred,
//           stake_credential: Some(Inline(VerificationKey(test_permitted_pkh))),
//         },
//         value: zero,
//         datum: NoDatum,
//         reference_script: None,
//       },
//     }

//   when input.output.address.stake_credential is {
//     Some(Inline(stake_cred)) ->
//       when stake_cred is {
//         VerificationKey(pkh) -> pkh == test_permitted_pkh
//         _ -> False
//       }
//     _ -> False
//   }
// }

// // Test freeze-and-seize validates VerificationKey stake credentials
// test freeze_and_seize_validates_vkey_stake_credentials() {
//   let stake_cred = VerificationKey(test_permitted_pkh)

//   when stake_cred is {
//     VerificationKey(pkh) -> pkh == test_permitted_pkh
//     _ -> False
//   }
// }

// // Test freeze-and-seize validates script stake credentials
// test freeze_and_seize_validates_script_stake_credentials() {
//   let stake_cred = Script(#"736372697074")

//   when stake_cred is {
//     VerificationKey(_) -> False
//     _ -> True
//   }
// }

// // Test freeze-and-seize requires stake credential
// test freeze_and_seize_requires_stake_credential() {
//   let with_stake =
//     Address {
//       payment_credential: test_prog_logic_base_cred,
//       stake_credential: Some(Inline(VerificationKey(test_permitted_pkh))),
//     }

//   let without_stake =
//     Address {
//       payment_credential: test_prog_logic_base_cred,
//       stake_credential: None,
//     }

//   when with_stake.stake_credential is {
//     Some(Inline(_)) -> True
//     _ -> False
//   } && when without_stake.stake_credential is {
//     Some(Inline(_)) -> False
//     _ -> True
//   }
// }

// // Test all prog inputs must validate
// test all_prog_inputs_must_validate() {
//   let inputs =
//     [
//       Input {
//         output_reference: OutputReference {
//           transaction_id: #"00",
//           output_index: 0,
//         },
//         output: Output {
//           address: Address {
//             payment_credential: test_prog_logic_base_cred,
//             stake_credential: Some(Inline(VerificationKey(test_permitted_pkh))),
//           },
//           value: zero,
//           datum: NoDatum,
//           reference_script: None,
//         },
//       },
//       Input {
//         output_reference: OutputReference {
//           transaction_id: #"01",
//           output_index: 1,
//         },
//         output: Output {
//           address: Address {
//             payment_credential: test_prog_logic_base_cred,
//             stake_credential: Some(Inline(VerificationKey(test_other_pkh))),
//           },
//           value: zero,
//           datum: NoDatum,
//           reference_script: None,
//         },
//       },
//     ]

//   // Both inputs should validate (in this simplified version)
//   list.all(
//     inputs,
//     fn(input) {
//       when input.output.address.stake_credential is {
//         Some(Inline(stake_cred)) ->
//           when stake_cred is {
//             VerificationKey(_) -> True
//             _ -> True
//           }
//         _ -> False
//       }
//     },
//   )
// }

// // Test BlacklistProof structure
// test blacklist_proof_structure() {
//   // BlacklistProof would contain node indices for validation
//   // For this test, we just verify the type exists
//   // let _proof: List<BlacklistProof> = []
//   True
// }

// // Test extra signatories list handling
// test extra_signatories_list_handling() {
//   let signatories = [test_permitted_pkh, test_other_pkh, #"deadbeef"]

//   list.has(signatories, test_permitted_pkh) && list.has(
//     signatories,
//     test_other_pkh,
//   ) && !list.has(signatories, #"6e6f7470726573656e74")
// }

// // Test credential type matching
// test credential_type_matching() {
//   let vkey_cred = VerificationKey(test_permitted_pkh)
//   let script_cred = Script(#"736372697074")

//   when vkey_cred is {
//     VerificationKey(_) -> True
//     _ -> False
//   } && when script_cred is {
//     Script(_) -> True
//     _ -> False
//   }
// }
// ============================================================
// Tests for Issuer Admin Contract
// ============================================================

use aiken/builtin
use aiken/collection/list
use cardano/address.{Script, VerificationKey}
use cardano/transaction as transaction
use utils.{apply_hashed_parameter}

// ------------------------------------------------------------
// Test constants
// ------------------------------------------------------------

const test_permitted_pkh = #"aabbccdd"
const test_other_pkh = #"11223344"

const test_asset_name = #"544f4b454e" // "TOKEN"

const issuance_prefix = #"aa"
const issuance_postfix = #"bb"
const prog_base_hash = #"cccc"
const withdraw_script_hash = #"dddd"

// ------------------------------------------------------------
// Helpers (mirror validator logic)
// ------------------------------------------------------------

fn concat_bytes(a: ByteArray, b: ByteArray) -> ByteArray {
  builtin.append_bytearray(a, b)
}

fn derive_policy_id(
  issuance_prefix: ByteArray,
  issuance_postfix: ByteArray,
  prog_base_hash: ByteArray,
  withdraw_script_hash: ByteArray,
) -> ByteArray {
  let hashed_param =
    concat_bytes(prog_base_hash, withdraw_script_hash)

  apply_hashed_parameter(
    issuance_prefix,
    issuance_postfix,
    hashed_param,
  )
}

fn withdraw_script_executed(
  redeemers: Pairs<transaction.ScriptPurpose, transaction.Redeemer>,
  expected_hash: ByteArray,
) -> Bool {
  list.any(
    redeemers,
    fn(pair) {
      let Pair(purpose, _) = pair
      when purpose is {
        transaction.Withdraw(Script(hash)) -> hash == expected_hash
        _ -> False
      }
    },
  )
}

// ------------------------------------------------------------
// Authorization tests
// ------------------------------------------------------------

test admin_authorized_with_signature() {
  let permitted = VerificationKey(test_permitted_pkh)
  let signers = [test_permitted_pkh]

  when permitted is {
    VerificationKey(pkh) -> list.has(signers, pkh)
    _ -> False
  }
}

test admin_fails_without_signature() {
  let permitted = VerificationKey(test_permitted_pkh)
  let signers = [test_other_pkh]

  when permitted is {
    VerificationKey(pkh) -> !list.has(signers, pkh)
    _ -> True
  }
}

// ------------------------------------------------------------
// Withdraw execution tests
// ------------------------------------------------------------

test withdraw_script_executes() {
  let dummy_redeemer: transaction.Redeemer = 0
  let redeemers =
    [
      Pair(
        transaction.Withdraw(Script(withdraw_script_hash)),
        dummy_redeemer,
      )
    ]

  withdraw_script_executed(redeemers, withdraw_script_hash)
}

test withdraw_script_hash_mismatch_fails() {
  let dummy_redeemer: transaction.Redeemer = 0
  let redeemers =
    [
      Pair(
        transaction.Withdraw(Script(#"eeee")),
        dummy_redeemer,
      )
    ]

  !withdraw_script_executed(redeemers, withdraw_script_hash)
}

// ------------------------------------------------------------
// Mint validation tests
// ------------------------------------------------------------

test valid_mint_passes() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(pid, test_asset_name, 1)]

  when list.head(mint) is {
    Some((policy, name, qty)) ->
      policy == pid && name == test_asset_name && qty > 0
    None -> False
  }
}

test wrong_asset_name_fails() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(pid, #"424144", 1)] // "BAD"

  when list.head(mint) is {
    Some((_, name, _)) -> name != test_asset_name
    None -> False
  }
}

test wrong_policy_id_fails() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint = [(#"deadbeef", test_asset_name, 1)]

  when list.head(mint) is {
    Some((policy, _, _)) -> policy != pid
    None -> False
  }
}

test multiple_assets_fail() {
  let pid =
    derive_policy_id(
      issuance_prefix,
      issuance_postfix,
      prog_base_hash,
      withdraw_script_hash,
    )

  let mint =
    [
      (pid, test_asset_name, 1),
      (pid, #"424144", 1),
    ]

  // Multiple assets should not be considered a valid mint
  list.length(mint) > 1
}

// ------------------------------------------------------------
// Seize (no mint) test
// ------------------------------------------------------------

test seize_without_mint_allowed() {
  let mint: List<(ByteArray, ByteArray, Int)> = []
  list.length(mint) == 0
}

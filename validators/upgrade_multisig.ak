//// The upgrade authority — a native-script-shaped multisig held in a config UTxO.
////
//// This is the credential `protocol_params` names in `upgrade_cred`: the party
//// whose withdraw-0 authorises a protocol upgrade (trampoline 2). Its ONLY job
//// is that authorisation decision; every structural rail of an upgrade lives
//// in `protocol_params`, and this script checks nothing about the upgrade.
////
//// ## What replaced what
////
//// The previous reference authority was a flat M-of-N over compile-time
//// parameters. That had two costs (audit-3 finding 05, MINR-054/057):
////
////   * the parameters were unguarded — a duplicated signer halved the
////     threshold, a threshold of 0 authorised everything, a threshold above
////     the signer count could never be met — and there was nowhere to guard
////     them, because a parameter is written by nobody on-chain;
////   * every signer rotation was a new applied script, and so a new credential,
////     and so a full `upgrade_cred` handover — two transactions since #125.
////
//// Both go away by moving the configuration into a DATUM this script owns:
////
////   * `mint` creates the config UTxO once, holding the one-shot config NFT
////     and a `MultisigScript` tree (`lib/multisig.ak`, Sundae's native-script
////     ADT) that must be `well_formed`;
////   * `spend` updates the tree: the OLD tree must be satisfied, the NEW one
////     must be well-formed, the NFT continues at this address. Rotation is
////     now a config update, and `upgrade_cred` never moves for it;
////   * `withdraw` is the trampoline target: find the config NFT among the
////     reference inputs, decode the tree, and ask whether the transaction
////     satisfies it — signatories, validity range and withdrawals all count,
////     so `AtLeast`, `After` and `Script` leaves each mean what they say.
////
//// One script, three handlers, one hash: the NFT policy, the config address's
//// payment credential and the withdraw-0 credential in `upgrade_cred` are all
//// the same value, by construction (the #117 / #118 pattern).
////
//// ## What the tree buys
////
//// Any combination rather than flat M-of-N; `After` for approve-now-execute-
//// later; and the `Script` leaf, which composes with ANY other withdraw-0
//// script — a cold-recovery branch, or whatever governance-shaped authority
//// the ecosystem eventually offers, plugs in as one leaf with no change here.
////
//// ## Two limits, deliberately
////
////   * The config UTxO cannot be spent and referenced in one transaction, so a
////     config update and a protocol upgrade are two transactions. Reading the
////     tree from inputs as well would buy that back at the cost of a second
////     code path; both are rare, so simplicity wins.
////   * The tree is read on every upgrade, so its evaluation cost is bounded by
////     `multisig.max_size`, enforced when the tree is WRITTEN — an authority
////     cannot configure itself into a tree it can no longer afford to run.

use aiken/collection/list
use assets.{has_policy_nft_strictly} as my_assets
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}
use multisig.{MultisigScript, satisfied, well_formed}
use utils.{has_currency_symbol}

/// Token name of the one-shot config NFT.
pub const upgrade_multisig_token: ByteArray = "UpgradeMultisig"

/// The datum rail: inline, and decodes as a tree. Shared by all three handlers.
fn output_tree(output: Output) -> MultisigScript {
  expect InlineDatum(datum) = output.datum
  expect tree: MultisigScript = datum
  tree
}

validator upgrade_multisig(utxo_ref: OutputReference) {
  mint(_redeemer: Data, own_policy: PolicyId, self: Transaction) {
    trace @"Starting upgrade_multisig mint validation"

    // One-shot: the named UTxO must be consumed, so this policy mints once and
    // every deployment gets a distinct credential.
    list.expect_any(
      self.inputs,
      fn(input) { input.output_reference == utxo_ref },
    )

    // Exactly one token minted, with the config name, under this policy.
    expect
      has_policy_nft_strictly(self.mint, own_policy, upgrade_multisig_token)

    // `has_nft_strict` is strict about the whole value: an output bundling any
    // other asset with the config NFT is simply not found.
    let nft_output = list.expect_find(
      self.outputs,
      fn(output) {
        assets.has_nft_strict(output.value, own_policy, upgrade_multisig_token)
      },
    )

    and {
      // Born well-formed — the same rail every later update satisfies.
      well_formed(output_tree(nft_output))?,
      // Paid for by every upgrade that references this UTxO otherwise.
      (nft_output.reference_script == None)?,
      // Locked at THIS script, wearing its spending hat.
      (nft_output.address == address.from_script(own_policy))?,
    }
  }

  spend(
    datum: Option<MultisigScript>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    trace @"Starting upgrade_multisig spend validation"

    // The tree being replaced is the one that must approve its replacement.
    expect Some(old_tree) = datum

    // Own input + own address. Every structural check keys on this input so
    // junk UTxOs parked at the address cannot interfere.
    let own_input = list.expect_find(
      self.inputs,
      fn(i) { i.output_reference == own_ref },
    )
    let own_address = own_input.output.address

    // One continuing output at this address. There is deliberately no
    // matching rail on INPUTS: a second UTxO at the address cannot carry the
    // one-shot NFT, so its non-ADA value cannot equal the continuing output's,
    // and its own run of this validator fails the transaction. Proven by
    // `update_fails_junk_run_alongside_genuine`.
    expect [cont] = list.filter(
      self.outputs,
      fn(o) { o.address == own_address },
    )

    expect (cont.reference_script == None)?

    // Non-ADA value exactly conserved — the NFT continues, nothing joins it.
    // Lovelace is unconstrained, for the reasons given on `protocol_params`.
    expect assets.expect_match_assets(cont.value, own_input.output.value)?

    // The replacement tree is held to the same standard as the first one.
    expect well_formed(output_tree(cont))?

    // Authorisation: the CURRENT tree, against the whole transaction.
    satisfied(
      old_tree,
      self.extra_signatories,
      self.validity_range,
      self.withdrawals,
    )?
  }

  withdraw(_redeemer: Data, account: Credential, self: Transaction) {
    trace @"Starting upgrade_multisig authorisation"

    // The reward account IS this script; its hash is the config NFT's policy.
    expect Script(own_hash) = account

    // The config UTxO, by its one-shot NFT. Policy presence suffices: the
    // mint handler mints exactly one token, so any UTxO carrying it is the
    // genuine config.
    let config = list.expect_find(
      self.reference_inputs,
      fn(i) { has_currency_symbol(i.output.value, own_hash) },
    )

    satisfied(
      output_tree(config.output),
      self.extra_signatories,
      self.validity_range,
      self.withdrawals,
    )?
  }

  // A withdraw-0 credential must be registered before it can withdraw. In the
  // era after Conway the legacy no-witness registration is withdrawn, so a
  // script without this handler can never be registered again — and the old
  // reference authority lacked it (MINR-057). Registration only; nothing else
  // is ever needed and nothing else is allowed.
  publish(_r: Data, c: Certificate, _s: Transaction) {
    when c is {
      RegisterCredential { .. } -> True
      _ -> False
    }
  }

  else(_) {
    fail
  }
}

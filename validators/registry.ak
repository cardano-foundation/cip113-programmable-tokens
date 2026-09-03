//// The token registry — one script, two purposes.
////
//// The registry is a linked list of `RegistryNode` UTxOs, one per registered
//// programmable token policy. `mint` governs the list's *structure* (Init
//// creates the origin node, Insert splices a new node in); `spend` governs
//// what may happen to a node UTxO once it exists (it is either the
//// covering-node spend of an Insert, or an in-place update of the node's
//// mutable fields).
////
//// Merging them into ONE multi-purpose validator collapses two hashes into
//// one: every handler of a `validator` block shares a single script hash, so
//// the registry node NFT policy id (this script as a minting policy) and the
//// registry node address's payment credential (this script as a spending
//// validator) are now THE SAME VALUE, by construction rather than by
//// deployment discipline.
////
//// Two parameters disappear as a direct consequence:
////
////   * `registry_spend_cred` — Init used to be told, as a compile-time
////     parameter, which address the origin node must be locked at. It now
////     names itself: `Script(policy_id)`.
////   * `protocol_params_cs` — the spend handler used to scan
////     `reference_inputs` for the protocol-params UTxO purely to read
////     `registry_node_cs` out of its datum. It now reads that policy off its
////     own input's payment credential. The registry therefore no longer
////     depends on the protocol-params chain at all, and no longer pays for a
////     reference-input scan, an inline-datum extraction and a whole-record
////     deserialisation on every node spend.

use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs as std_pairs
use cardano/address.{Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction, find_input}
use linked_list.{
  is_field_updated_registry_node, is_inserted_directory_node,
  is_updated_directory_node, validate_directory_init,
  validate_directory_node_output, validate_mint,
}
use pairs
use registry_node.{RegistryNode}
use types.{IssuanceCborHex, RegistryInit, RegistryInsert, RegistryRedeemer}
use utils.{
  expect_inline_datum, has_currency_symbol, is_programmable_token_id_valid,
  mint_has_policy,
}

validator registry(utxo_ref: OutputReference, issuance_cbor_hex_cs: PolicyId) {
  mint(redeemer: RegistryRedeemer, policy_id: PolicyId, self: Transaction) {
    trace @"Starting registry mint validation"
    when redeemer is {
      RegistryInit -> {
        // Ensure this is a one-shot minting policy by checking that utxo_ref is spent
        let Void = list.expect_any(
          self.inputs,
          fn(input) { input.output_reference == utxo_ref },
        )

        // Initialize the registry with an empty origin node.
        //
        // The origin node's address is `Script(policy_id)` — this very script,
        // wearing its spending hat. No parameter is needed to say so: the mint
        // and spend handlers share one hash, so the policy minting the node NFT
        // IS the credential that must lock it.
        validate_directory_init(
          self.outputs,
          self.mint,
          policy_id,
          Script(policy_id),
        )
      }
      RegistryInsert { key, minting_logic_script } -> {
        // Find the issuance CBOR hex reference input
        let issuance_ref_input = list.expect_find(
          self.reference_inputs,
          fn(input) {
            has_currency_symbol(input.output.value, issuance_cbor_hex_cs)
          },
        )

        // Extract the IssuanceCborHex datum
        let issuance_datum = expect_inline_datum(issuance_ref_input.output)
        expect issuance_cbor: IssuanceCborHex = issuance_datum

        // Cryptographic binding (mode-independent): the key being inserted
        // must be the policy id derived from the issuance template
        // parameterised with `minting_logic_script`. The `hashed_param`
        // for the derivation is the inner 28-byte hash of the credential,
        // extracted inside the helper.
        expect
          is_programmable_token_id_valid(
            key,
            issuance_cbor.prefix_cbor_hex,
            issuance_cbor.postfix_cbor_hex,
            minting_logic_script,
          )

        // Substandard authorises this registration. The substandard's
        // withdraw-0 logic must appear in tx.withdrawals. This is the
        // "proof of instance" check — replacing the old indirect proof of
        // "tokens are being minted" which transitively required
        // issuance_mint (and hence minting_logic_script) to run. Required
        // explicitly here because a registration may carry no first mint,
        // in which case issuance_mint is never invoked.
        //
        // Whether a first mint of `key` occurs in the same tx is NOT
        // checked here: if it does, issuance_mint validates it as usual.
        expect pairs.has_key_or_fail(self.withdrawals, minting_logic_script)

        // Must mint exactly one node token with the new key
        expect validate_mint(self.mint, policy_id) == key

        // There must be exactly one node input (the covering node).
        // No explicit address check needed: any registry-NFT-bearing UTxO is
        // at the registry node address by induction (Init binds the origin's
        // address, every Insert binds its new outputs' addresses, and this
        // validator's spend handler is the sole script that can spend those
        // UTxOs).
        expect [covering_input] = list.filter(
          self.inputs,
          fn(input) { has_currency_symbol(input.output.value, policy_id) },
        )

        let covering_datum = expect_inline_datum(covering_input.output)
        expect covering_node: RegistryNode = covering_datum

        // Filter the two registry-node outputs and classify them. The destructure
        // enforces exactly two such outputs. The strict ordering invariant
        // (covering_node.key < key, asserted below) means no single output can satisfy
        // both the inserted and the updated-covering shape, so identifying which is
        // which by a single `is_inserted_directory_node` check is unambiguous.
        expect [out1,
              out2] = list.filter(
          self.outputs,
          fn(o) { has_currency_symbol(o.value, policy_id) },
        )

        let node1 = validate_directory_node_output(
          out1,
          policy_id,
          covering_input.output.address,
        )
        let node2 = validate_directory_node_output(
          out2,
          policy_id,
          covering_input.output.address,
        )

        let updated = if is_inserted_directory_node(
          node1,
          key,
          covering_node.next,
          minting_logic_script,
        ) {
          node2
        } else {
          expect
            is_inserted_directory_node(
              node2,
              key,
              covering_node.next,
              minting_logic_script,
            )
          node1
        }
        // node2 inserted ⇒ node1 is the updated covering
        is_updated_directory_node(updated, covering_node, key)
      }
    }
  }

  spend(
    datum: Option<RegistryNode>,
    _redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    trace @"Starting registry spend validation"

    // Spending a registry node is a lifecycle action, never an issuance: its
    // own programmable token (`key`) must not be minted/burned in the same tx.
    // Hoisted above the `when` so it covers BOTH the update (None) and the
    // insert covering-node spend (Some) — this handler is the sole spender
    // of every node, so this is the only place the check is needed.
    expect Some(spent_node) = datum
    expect !mint_has_policy(self.mint, spent_node.key)

    // The registry node NFT policy is this script's own hash, read off the
    // UTxO being spent. Both bindings below are TOTAL, not checks: the ledger
    // only invokes this handler for a UTxO that (a) exists among `self.inputs`
    // at `own_ref` and (b) is locked by a script address whose payment
    // credential is this very script. Neither can be made to fail by a
    // transaction author, so neither is a guard — do not add a redundant
    // equality check here, and do not write a test asserting that either one
    // bites.
    expect Some(own_input) = find_input(self.inputs, own_ref)
    expect Script(registry_node_cs) = own_input.output.address.payment_credential

    when
      assets.to_dict(self.mint)
        |> dict.get(registry_node_cs)
    is {
      // A registry node NFT is minted → we are the covering-node spend of an
      // insert; the `mint` handler validates the linked-list structure.
      Some(minted_assets) -> {
        expect [Pair(_, amount)] = dict.to_pairs(minted_assets)
        amount > 0
      }
      // No registry node NFT minted → in-place update of this node.
      None -> {
        expect [cont] = list.filter(
          self.outputs,
          fn(o) { has_currency_symbol(o.value, registry_node_cs) },
        )
        let new_node = validate_directory_node_output(
          cont,
          registry_node_cs,
          own_input.output.address,
        )
        and {
          is_field_updated_registry_node(new_node, spent_node),
          when spent_node.minting_logic_script is {
            Script(_) ->
              std_pairs.has_key(
                self.withdrawals,
                spent_node.minting_logic_script,
              )
            VerificationKey(_) -> False
          },
        }
      }
    }
  }

  else(_) {
    fail
  }
}

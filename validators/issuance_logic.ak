//// The replaceable half of issuance (issue #129, audit-3 finding 07).
////
//// A token's policy id is the hash of its applied `issuance_mint` script, so
//// whatever that script hard-codes, every token minted under it obeys for as
//// long as it exists. Until #129 it hard-coded a great deal: the current
//// `TransferRedeemer` / `ThirdPartyRedeemer` shapes (to prove a delegate
//// covered its registry node), the current `RegistryNode` shape, and the
//// current custody and PLB output-shape rules. Any protocol upgrade that
//// changed one of those either broke minting and burning for every existing
//// token, or — worse — kept decoding while the field it keyed on no longer
//// meant "custody was checked".
////
//// Everything that may change now lives HERE, behind a credential the
//// protocol-params datum names (`issuance_logic_cred`, field 5). The permanent
//// policy requires this script's withdraw-0 and checks that its own policy
//// id is a KEY of this script's redeemer; it never decodes anything else. So
//// the rules every token obeys are upgraded by rewriting one datum field,
//// and no policy id ever moves.
////
//// The trust this adds is nothing new. The upgrade authority could already
//// drain every token by installing a permissive dispatcher in `plg_cred`;
//// installing a permissive script here is the same authority, the same act.
////
//// Runs ONCE per transaction (withdraw-0), for every policy in its redeemer.
//// The redeemer is a map policy -> registry proof; a policy that is issued
//// but absent from the map fails in its own permanent policy, so this script
//// need not inspect `tx.mint` at all.

use aiken/builtin.{unconstr_fields}
use aiken/collection/list
use assets as prog_assets
use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Input, Output, ScriptPurpose, Transaction, Withdraw}
use programmable_logic/params
use registry_node.{RegistryNode}
use types.{
  IssuanceLogicRedeemer, MintingRegistryProof, OutputIndex, RefInput,
  RegistryProof, ThirdPartyRedeemer, TokenExists, TransferRedeemer,
}
use utils.{expect_inline_datum, has_currency_symbol}

validator issuance_logic(
  // Programmable Token Script Hash — the custody address every issued token
  // must land at.
  programmable_logic_base: Credential,
  // Registry Node Currency Symbol — authenticates registry proofs.
  registry_node_cs: PolicyId,
  // One-shot protocol-params NFT policy. Locates the protocol-params UTxO
  // among `reference_inputs` inside the `RefInput` delegation branch, to read
  // the LIVE delegate credentials (`transfer_cred`, `third_party_cred`).
  params_policy: PolicyId,
  // Inline-datum size bound for PLB outputs that carry the minted policy
  // (issue #106, vector 3). The same parameter `transfer`, `third_party` and
  // `unfracking` take, and it MUST be deployed with the same value: each
  // script bounds only the outputs it creates, and a datum born under a laxer
  // bound than the one `transfer` or `third_party` must later carry it under
  // is a frozen, unseizable UTxO. Nothing on-chain can compare the four
  // values — correctness here is by composition, at deployment.
  max_inline_datum_bytes: Int,
) {
  withdraw(
    redeemer: IssuanceLogicRedeemer,
    _account: Credential,
    self: Transaction,
  ) {
    trace @"Starting issuance_logic validation"
    list.all(
      redeemer,
      fn(entry) {
        let Pair(own_policy, proof) = entry
        valid_issuance(
          self,
          proof,
          own_policy,
          programmable_logic_base,
          registry_node_cs,
          params_policy,
          max_inline_datum_bytes,
        )?
      },
    )
  }

  // Registration only: this credential must be registered before it can
  // withdraw, and after Conway that needs the script's consent. Nothing else
  // is allowed — deregistering it would halt issuance for every token.
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

/// The per-policy rule set, unchanged from the pre-#129 `issuance_mint`
/// except for taking `own_policy` as an argument instead of receiving it as
/// the mint purpose. The registry proof determines WHO enforces custody:
///
///   OutputIndex → the policy's registry node appears as an OUTPUT of this
///     tx (freshly minted, OR re-emitted by a node update/insert). No
///     delegate sees this node, so custody is enforced here.
///
///   RefInput { index } → the node is a reference input, and a delegate
///     validator MAY enforce custody instead — but only when ITS redeemer
///     names the SAME registry node `index` points at. `verify_registry_node`
///     has already bound that index to `own_policy`, so comparing indices
///     suffices. Two delegates can cover:
///       * `transfer` → its `TransferRedeemer.proofs` contains
///         `TokenExists { node_idx: index }`
///       * `third_party` → its `ThirdPartyRedeemer.registry_node_idx == index`
///     (`unfracking` never mints, so it can never cover a mint.)
///     If a delegate covers → delegate; otherwise enforce custody here.
///
/// Closes Finding 04 / re-audit R-04: this precise check trusts a delegate
/// only for the specific node the proof named, and `no_escape` catches any
/// token this policy issues that the delegate did not see.
fn valid_issuance(
  self: Transaction,
  proof: MintingRegistryProof,
  own_policy: PolicyId,
  programmable_logic_base: Credential,
  registry_node_cs: PolicyId,
  params_policy: PolicyId,
  max_inline_datum_bytes: Int,
) -> Bool {
  let custody_ok = fn() {
    no_escape(
      self.outputs,
      programmable_logic_base,
      own_policy,
      max_inline_datum_bytes,
    )
  }
  when proof is {
    OutputIndex { index } -> {
      // The node is an OUTPUT here: a first mint, a covering node re-emitted
      // by an insert, or an in-place update. In the last two the policy is
      // ALREADY registered and pre-existing supply may be spent from a PLB
      // input, so an output-only quantity check could be masked. `no_escape`
      // sidesteps the case analysis: nothing minted can leave the PLB
      // regardless of how the node got here.
      let output = list.expect_at(self.outputs, index)
      expect verify_registry_node(output, registry_node_cs, own_policy)
      custody_ok()?
    }
    RefInput { index } -> {
      let ref_input = list.expect_at(self.reference_inputs, index)
      expect
        verify_registry_node(ref_input.output, registry_node_cs, own_policy)
      or {
        delegate_covers_own_registry_node(
          self.redeemers,
          self.reference_inputs,
          params_policy,
          index,
        ),
        custody_ok()?,
      }
    }
  }
}

/// Custody check (re-audit R-04): NO token of `own_policy` may sit at a
/// non-PLB output. Combined with ledger value-conservation this pins every
/// minted unit at the PLB — a freshly minted token cannot escape to a
/// non-programmable address, and pre-existing PLB supply cannot mask an escape
/// (the failure mode of the earlier check, which compared the absolute PLB
/// output total to the mint delta and could be satisfied by preserved supply).
///
/// Every PLB output must additionally carry an inline stake credential (so
/// ownership is well-defined). Inputs need no scan: any `own_policy` spent
/// must reappear at a PLB output or be burned, both of which this output-only
/// rule already forces through value-conservation.
///
/// Deliberately NOT enforced here: a ledger-impossible over-burn (burning more
/// than exists) — value-conservation makes the ledger reject that anyway.
fn no_escape(
  outputs: List<Output>,
  programmable_logic_base: Credential,
  own_policy: PolicyId,
  max_inline_datum_bytes: Int,
) -> Bool {
  list.all(
    outputs,
    fn(output) {
      if output.address.payment_credential == programmable_logic_base {
        expect Some(Inline(_stake_cred)) = output.address.stake_credential
        // A programmable-token UTxO must stay seizable: no datum hash
        // (unspendable without the preimage), no reference script (bloats the
        // mandatory seizure continuing-output) — and, where THIS policy is
        // present, an inline datum no larger than the bound, so the UTxO a
        // mint creates can be carried by every script that may have to carry
        // it later. PLB outputs that do not carry this policy get the shape
        // check only: their datum is some other script's responsibility, and
        // `serialise_data` is the one expensive step here.
        if has_currency_symbol(output.value, own_policy) {
          prog_assets.is_seizable_output_shape_bounded(
            output,
            max_inline_datum_bytes,
          )
        } else {
          prog_assets.is_seizable_output_shape(output)
        }
      } else {
        !has_currency_symbol(output.value, own_policy)
      }
    },
  )
}

fn verify_registry_node(
  output: Output,
  registry_node_cs: PolicyId,
  own_policy: PolicyId,
) -> Bool {
  // Strict: registry NFT's asset name MUST equal own_policy. This binds the
  // NFT identity to the datum key and removes implicit trust on the linked-list
  // invariant (asset_name == datum.key) enforced elsewhere.
  //
  // No need to compare `registry.minting_logic_script` against the validator's
  // `minting_logic_cred` parameter here. `registry_mint` already enforces that
  // the registered credential's inner hash is the one the policy id was
  // derived from (via `is_programmable_token_id_valid`). Since this
  // validator's `minting_logic_cred` parameter is also baked into the policy
  // id at compile time, collision-resistance of blake2b_224 implies the two
  // credentials must match. Checking again here would be redundant.
  expect assets.has_nft_strict(output.value, registry_node_cs, own_policy)?
  let registry_datum = expect_inline_datum(output)
  expect registry: RegistryNode = registry_datum
  registry.key == own_policy
}

/// True iff a delegate validator's currently-running redeemer names the
/// same registry node (by index) that our `RefInput { index }` already bound
/// to `own_policy`. If so, that delegate will validate `own_policy`'s mint
/// custody at runtime and issuance_mint can safely delegate.
///
/// The delegates' credentials are NOT parameters: they are the LIVE ones read
/// from the protocol-params UTxO's datum (`transfer_cred`, field 1;
/// `third_party_cred`, field 2), so delegation trust tracks in-place
/// upgrades — a retired credential can no longer act as a mint-custody
/// delegate.
///
/// We only need to compare indices — `own_registry_node_idx` is the index
/// from issuance_mint's RefInput redeemer, which `verify_registry_node`
/// has already shown to correspond to `own_policy`. So "same index" ⇒
/// "same policy" without re-extracting any key.
///
/// Every `None` case — no protocol-params UTxO among the reference inputs,
/// neither delegate invoked, or a delegate's redeemer naming a different
/// registry node — returns False, falling back to local custody. The
/// protocol-params locate is deliberately non-failing (`list.find` +
/// `has_nft_strict`) so non-delegating RefInput mints need no protocol-params
/// ref input.
fn delegate_covers_own_registry_node(
  redeemers: Pairs<ScriptPurpose, Data>,
  reference_inputs: List<Input>,
  params_policy: PolicyId,
  own_registry_node_idx: Int,
) -> Bool {
  when
    list.find(
      reference_inputs,
      fn(ref_input) {
        assets.has_nft_strict(
          ref_input.output.value,
          params_policy,
          params.protocol_params_token,
        )
      },
    )
  is {
    None -> False
    Some(params_ref) -> {
      let fields = unconstr_fields(expect_inline_datum(params_ref.output))
      or {
        // (a) the `transfer` validator validates our node's custody: its
        // proof walk resolves our node and `validate_transfer` contains the
        // minted supply at PLB.
        when
          find_transfer_redeemer(redeemers, params.transfer_cred_field(fields))
        is {
          None -> False
          Some(transfer_redeemer) ->
            transfer_scope_covers(transfer_redeemer, own_registry_node_idx)
        },
        // (b) the `third_party` (seize) validator does: its conservation check
        // (validate_3rd_party) covers minted subject-policy tokens, so trusting
        // it for custody is sound (Finding 04 precise delegation preserved).
        third_party_covers_own_registry_node(
          redeemers,
          params.third_party_cred_field(fields),
          own_registry_node_idx,
        ),
      }
    }
  }
}

/// Does the `third_party` (seize) validator's redeemer name the SAME
/// registry node our `RefInput { index }` did? Its `registry_node_idx` IS the
/// subject policy's node (single-policy), so "same index" ⇒ "same policy" —
/// the same reasoning as `transfer_scope_covers`.
/// None (third_party not invoked, or its redeemer names a different node) ⇒
/// no delegation, so custody falls back to local `no_escape`.
fn third_party_covers_own_registry_node(
  redeemers: Pairs<ScriptPurpose, Data>,
  third_party_cred: Credential,
  own_registry_node_idx: Int,
) -> Bool {
  when find_tp_redeemer(redeemers, third_party_cred) is {
    None -> False
    Some(ThirdPartyRedeemer { registry_node_idx, .. }) ->
      registry_node_idx == own_registry_node_idx
  }
}

/// Find the `third_party` validator's Withdraw redeemer in `tx.redeemers` and
/// decode it. Mirrors `find_transfer_redeemer`; returns None when the
/// third_party validator isn't invoked.
fn find_tp_redeemer(
  redeemers: Pairs<ScriptPurpose, Data>,
  cred: Credential,
) -> Option<ThirdPartyRedeemer> {
  when redeemers is {
    [] -> None
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == cred {
            expect tp: ThirdPartyRedeemer = data
            Some(tp)
          } else {
            find_tp_redeemer(tail, cred)
          }
        _ -> find_tp_redeemer(tail, cred)
      }
  }
}

/// Find the `transfer` validator's Withdraw redeemer in `tx.redeemers` and
/// decode it. Linear in `|redeemers|`. Returns None when the transfer
/// validator isn't invoked.
fn find_transfer_redeemer(
  redeemers: Pairs<ScriptPurpose, Data>,
  cred: Credential,
) -> Option<TransferRedeemer> {
  when redeemers is {
    [] -> None
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == cred {
            expect transfer_redeemer: TransferRedeemer = data
            Some(transfer_redeemer)
          } else {
            find_transfer_redeemer(tail, cred)
          }
        _ -> find_transfer_redeemer(tail, cred)
      }
  }
}

/// Scope check: does the given transfer redeemer name the SAME registry node
/// our `RefInput { index }` did? `proofs` must contain
/// `TokenExists { node_idx }` with `node_idx == own_registry_node_idx`. The
/// transfer validator's `verify_proofs` walks `proofs` in lockstep with
/// `input_assets`; if any input asset's policy lines up with this proof, it
/// resolves our index and validates against it. If positions don't line up,
/// it aborts and the tx fails — no escape path.
///
/// The `unfracking` validator is deliberately NOT a delegate: unfracking is
/// value-preserving, same-owner PLB restructuring with NO mint, so it never
/// validates an issuance's custody and cannot cover one (Finding 04 precise
/// delegation).
fn transfer_scope_covers(
  transfer_redeemer: TransferRedeemer,
  own_registry_node_idx: Int,
) -> Bool {
  let TransferRedeemer { proofs } = transfer_redeemer
  let expected_proof = TokenExists(own_registry_node_idx)
  list.any(proofs, fn(proof: RegistryProof) { expected_proof == proof })
}
